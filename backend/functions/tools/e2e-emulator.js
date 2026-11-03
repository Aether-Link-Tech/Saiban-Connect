/* eslint-disable no-console */
/**
 * End-to-end test against the LOCAL emulators (project demo-saibaan), acting like the
 * mobile app: signs in as each role, calls the callable functions over HTTP, uploads
 * files to the Storage emulator and checks Firestore security rules.
 *
 *   firebase emulators:start --project demo-saibaan
 *   node tools/seed-emulator.js && node tools/e2e-emulator.js     (from backend/functions)
 */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const PROJECT = "demo-saibaan";
const REGION = "asia-south1";
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FUNCS = `http://127.0.0.1:5001/${PROJECT}/${REGION}`;
const FS = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const STORAGE = "http://127.0.0.1:9199";
const BUCKET = `${PROJECT}.appspot.com`;
const PASSWORD = "Demo@12345";
const DEMO_DEVICE = "demo-device-0001";
const KASUR = { latitude: 31.1167, longitude: 74.45 };
const OFFSET = 5 * 3600_000;
const dateKeyOf = (ms) => new Date(ms + OFFSET).toISOString().slice(0, 10);
const futureKey = (days) => dateKeyOf(Date.now() + days * 86_400_000);
const uuid = () => crypto.randomUUID();

// ---------------- helpers ----------------
async function json(res) {
  const text = await res.text();
  try { return JSON.parse(text); } catch { return { raw: text }; }
}
async function signIn(email, password = PASSWORD) {
  const r = await fetch(`${AUTH}/accounts:signInWithPassword?key=demo`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const b = await json(r);
  if (!r.ok) throw Object.assign(new Error(`signIn ${email}: ${b.error?.message}`), { code: b.error?.message });
  return { token: b.idToken, uid: b.localId, email };
}
async function signUp(email) {
  const r = await fetch(`${AUTH}/accounts:signUp?key=demo`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
  });
  const b = await json(r);
  if (!r.ok) throw new Error(`signUp: ${b.error?.message}`);
  return { token: b.idToken, uid: b.localId, email };
}
/** Calls a callable function. Returns result, or throws an error with .status (e.g. PERMISSION_DENIED). */
async function call(name, data, who) {
  const r = await fetch(`${FUNCS}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(who ? { authorization: `Bearer ${who.token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  const b = await json(r);
  if (b.error) throw Object.assign(new Error(`${name}: ${b.error.status} ${b.error.message}`), { status: b.error.status });
  if (!r.ok) throw new Error(`${name}: HTTP ${r.status} ${JSON.stringify(b)}`);
  return b.result;
}
async function expectError(promise, status) {
  try {
    await promise;
  } catch (e) {
    if (status && e.status !== status) throw new Error(`expected ${status}, got ${e.status}: ${e.message}`);
    return e;
  }
  throw new Error(`expected error ${status ?? ""} but call succeeded`);
}
/** Firestore REST read as a user (rules enforced) or as admin ("owner", rules bypassed). */
async function fsGet(path, who) {
  const r = await fetch(`${FS}/${path}`, { headers: { authorization: `Bearer ${who === "owner" ? "owner" : who.token}` } });
  return { status: r.status, body: await json(r) };
}
async function fsQuery(collection, filters, who) {
  const where = filters.length === 1 ? { fieldFilter: filters[0] } : { compositeFilter: { op: "AND", filters: filters.map((f) => ({ fieldFilter: f })) } };
  const r = await fetch(`${FS}:runQuery`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${who === "owner" ? "owner" : who.token}` },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], where } }),
  });
  return { status: r.status, body: await json(r) };
}
async function fsPatch(path, fields, mask, who) {
  const qs = mask.map((m) => `updateMask.fieldPaths=${m}`).join("&");
  const r = await fetch(`${FS}/${path}?${qs}`, {
    method: "PATCH",
    headers: { "content-type": "application/json", authorization: `Bearer ${who.token}` },
    body: JSON.stringify({ fields }),
  });
  return r.status;
}
const eq = (field, v) => ({ field: { fieldPath: field }, op: "EQUAL", value: typeof v === "boolean" ? { booleanValue: v } : { stringValue: v } });
const val = (doc, field) => {
  const f = doc.fields?.[field];
  if (!f) return undefined;
  return f.stringValue ?? f.booleanValue ?? (f.integerValue !== undefined ? Number(f.integerValue) : undefined) ?? f.doubleValue ?? f.timestampValue ?? (f.nullValue === null ? null : f);
};
async function upload(path, who, contentType = "image/jpeg") {
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 0xff, 0xd9]);
  const r = await fetch(`${STORAGE}/v0/b/${BUCKET}/o?name=${encodeURIComponent(path)}`, {
    method: "POST", headers: { "content-type": contentType, authorization: `Bearer ${who.token}` }, body: bytes,
  });
  return r.status;
}
const att = (type, deviceTime, extra = {}) => ({
  eventId: uuid(), type, deviceTime, latitude: KASUR.latitude + 0.0002, longitude: KASUR.longitude, accuracyM: 10,
  biometricPassed: true, isMocked: false, ...extra,
});

// ---------------- harness ----------------
const results = [];
async function test(name, fn) {
  try {
    await fn();
    results.push([true, name]);
    console.log(`  ✔ ${name}`);
  } catch (e) {
    results.push([false, name, e]);
    console.log(`  ✖ ${name}\n      ${e.message}`);
  }
}

async function main() {
  const S = {};
  for (const k of ["admin", "hr", "manager", "supervisor", "employee", "employee2"]) S[k] = await signIn(`${k}@saibaan.demo`);
  const testEmail = `e2e-${Date.now()}@saibaan.demo`;
  const testPhone = `0301${String(Date.now()).slice(-7)}`;
  let T; // the newly registered test user

  console.log("\nAuthentication & registration");
  await test("phone login resolves the sign-in email", async () => {
    const r = await call("resolveLoginEmail", { phone: "0300-0000005" });
    assert.equal(r.email, "employee@saibaan.demo");
  });
  await test("unknown phone is rejected", () => expectError(call("resolveLoginEmail", { phone: "03119999999" }), "NOT_FOUND"));
  await test("new employee registers with profile photo (pending)", async () => {
    T = await signUp(testEmail);
    assert.equal(await upload(`employee-photos/${T.uid}/profile.jpg`, T), 200);
    await call("submitRegistration", {
      displayName: "E2E Tester", phone: testPhone, email: testEmail,
      photoPath: `employee-photos/${T.uid}/profile.jpg`, deviceId: "e2e-device-aaaa", deviceModel: "Test Phone",
    }, T);
    const own = await fsGet(`users/${T.uid}`, T);
    assert.equal(own.status, 200);
    assert.equal(val(own.body, "accountStatus"), "pending");
  });
  await test("duplicate phone number is refused", async () => {
    const other = await signUp(`dup-${Date.now()}@saibaan.demo`);
    await expectError(call("submitRegistration", { displayName: "Dup", phone: testPhone, deviceId: "dup-device-1" }, other), "ALREADY_EXISTS");
  });
  await test("pending user cannot use the app (sites hidden, attendance refused)", async () => {
    T = await signIn(testEmail);
    assert.equal((await fsGet("sites/site-head-office", T)).status, 403);
    await expectError(call("syncAttendanceEvents", { deviceId: "e2e-device-aaaa", events: [att("check_in", Date.now())] }, T), "PERMISSION_DENIED");
  });
  await test("HR cannot grant the Administrator role", () =>
    expectError(call("reviewRegistration", { uid: T.uid, decision: "approve", role: "admin" }, S.hr), "PERMISSION_DENIED"));
  await test("employee cannot approve registrations", () =>
    expectError(call("reviewRegistration", { uid: T.uid, decision: "approve" }, S.employee), "PERMISSION_DENIED"));
  await test("HR approves registration with role, manager and sites", async () => {
    await call("reviewRegistration", {
      uid: T.uid, decision: "approve", role: "employee", employeeCode: "SDO-E2E", designation: "Tester",
      departmentId: "dept-field", managerUid: S.manager.uid, supervisorUid: S.supervisor.uid,
      assignedSiteIds: ["site-field-kasur"],
    }, S.hr);
    T = await signIn(testEmail); // fresh token with role claims
    const u = await fsGet(`users/${T.uid}`, T);
    assert.equal(val(u.body, "accountStatus"), "active");
    assert.equal(val(u.body, "activeDeviceId"), "e2e-device-aaaa");
    assert.equal((await fsGet("sites/site-head-office", T)).status, 200);
  });

  console.log("\nAttendance, geofence & offline sync");
  const inTime = Date.now() - 10 * 60_000; // recent, so it isn't flagged as a late sync
  const checkIn = att("check_in", inTime);
  const dayPath = `attendanceDays/${S.employee.uid}_${dateKeyOf(inTime)}`;
  await test("check-in inside the geofence is accepted", async () => {
    const r = await call("syncAttendanceEvents", { deviceId: DEMO_DEVICE, events: [checkIn] }, S.employee);
    assert.equal(r.results[0].status, "accepted", JSON.stringify(r.results[0]));
    const day = await fsGet(dayPath, S.employee);
    assert.equal(val(day.body, "status"), "checked_in");
    assert.equal(val(day.body, "siteName"), "Field Site — Kasur");
  });
  await test("re-sending the same event is idempotent (offline retry)", async () => {
    const r = await call("syncAttendanceEvents", { deviceId: DEMO_DEVICE, events: [checkIn] }, S.employee);
    assert.equal(r.results[0].status, "already_synced");
  });
  await test("second check-in the same day is flagged as duplicate", async () => {
    const r = await call("syncAttendanceEvents", { deviceId: DEMO_DEVICE, events: [att("check_in", inTime + 60_000)] }, S.employee);
    assert.ok(r.results[0].flags.includes("duplicate_check_in"));
  });
  await test("attendance from an unapproved phone is refused", () =>
    expectError(call("syncAttendanceEvents", { deviceId: "some-other-phone", events: [att("check_out", Date.now())] }, S.employee), "FAILED_PRECONDITION"));
  await test("location points update the live location", async () => {
    const t = Date.now() - 60_000;
    const r = await call("uploadLocationPoints", {
      deviceId: DEMO_DEVICE,
      points: [
        { id: uuid(), latitude: KASUR.latitude, longitude: KASUR.longitude, accuracyM: 8, capturedAt: t - 300_000 },
        { id: uuid(), latitude: KASUR.latitude + 0.0001, longitude: KASUR.longitude, accuracyM: 7, capturedAt: t },
      ],
    }, S.employee);
    assert.equal(r.stored, 2);
    const live = await fsGet(`liveLocations/${S.employee.uid}`, S.manager);
    assert.equal(live.status, 200);
    assert.equal(val(live.body, "isTracking"), true);
    assert.equal(val(live.body, "insideGeofence"), true);
  });
  await test("check-out completes the day with worked time", async () => {
    const r = await call("syncAttendanceEvents", { deviceId: DEMO_DEVICE, events: [att("check_out", Date.now() - 60_000)] }, S.employee);
    assert.equal(r.results[0].status, "accepted", JSON.stringify(r.results[0]));
    const day = await fsGet(dayPath, S.employee);
    assert.equal(val(day.body, "status"), "completed");
    assert.ok(val(day.body, "workedMinutes") >= 8);
    const live = await fsGet(`liveLocations/${S.employee.uid}`, S.employee);
    assert.equal(val(live.body, "isTracking"), false);
  });
  await test("offline check-in far from site, no biometric, synced late is flagged", async () => {
    const late = Date.now() - 3 * 3600_000;
    const r = await call("syncAttendanceEvents", {
      deviceId: DEMO_DEVICE,
      events: [att("check_in", late, { latitude: 31.3, longitude: 74.6, accuracyM: 350, biometricPassed: false })],
    }, S.employee2);
    const flags = r.results[0].flags;
    for (const f of ["outside_geofence", "late_sync", "low_accuracy", "no_biometric"]) assert.ok(flags.includes(f), `missing ${f}: ${flags}`);
  });
  await test("manager is notified of the outside-site check-in", async () => {
    const q = await fsQuery("notifications", [eq("recipientUid", S.manager.uid), eq("type", "attendance_flag")], S.manager);
    assert.equal(q.status, 200);
    assert.ok(q.body.filter((x) => x.document).length >= 1);
  });
  await test("biometric is required when policy disallows fallback", async () => {
    await call("updatePolicy", { policy: { attendance: { allowWithoutBiometric: false } } }, S.admin);
    try {
      const r = await call("syncAttendanceEvents", { deviceId: DEMO_DEVICE, events: [att("check_in", Date.now(), { biometricPassed: false })] }, S.manager);
      assert.equal(r.results[0].status, "rejected");
    } finally {
      await call("updatePolicy", { policy: { attendance: { allowWithoutBiometric: true } } }, S.admin);
    }
  });
  await test("manager reviews (accepts) a flagged event of their team", async () => {
    await call("reviewAttendanceEvent", { eventId: `seed-employee-${dateKeyOf(Date.now() - 2 * 86_400_000)}-in`, decision: "approve" }, S.manager);
  });
  await test("supervisor cannot review attendance", () =>
    expectError(call("reviewAttendanceEvent", { eventId: "seed-employee-x-in", decision: "approve" }, S.supervisor), "PERMISSION_DENIED"));
  await test("HR corrects a missed check-out; employee cannot", async () => {
    const key = dateKeyOf(Date.now() - 3 * 86_400_000);
    const out = new Date(`${key}T17:30:00Z`).getTime() - OFFSET;
    await expectError(call("correctAttendance", { uid: S.employee2.uid, dateKey: key, checkOutAt: out, reason: "Forgot" }, S.employee), "PERMISSION_DENIED");
    await call("correctAttendance", { uid: S.employee2.uid, dateKey: key, checkOutAt: out, reason: "Phone battery died" }, S.hr);
    const day = await fsGet(`attendanceDays/${S.employee2.uid}_${key}`, "owner");
    assert.equal(val(day.body, "status"), "completed");
    assert.equal(val(day.body, "corrected"), true);
  });

  console.log("\nSite photos");
  await test("photo upload is linked to employee and site", async () => {
    const id = uuid();
    const path = `field-photos/${S.employee.uid}/${id}.jpg`;
    assert.equal(await upload(path, S.employee), 200);
    await call("registerFieldPhoto", {
      photoId: id, storagePath: path, source: "camera", capturedAt: Date.now(),
      latitude: KASUR.latitude, longitude: KASUR.longitude, caption: "E2E site photo",
    }, S.employee);
    const p = await fsGet(`fieldPhotos/${id}`, S.supervisor);
    assert.equal(p.status, 200);
    assert.equal(val(p.body, "siteName"), "Field Site — Kasur");
  });
  await test("cannot register someone else's photo path", async () => {
    const id = uuid();
    await expectError(call("registerFieldPhoto", {
      photoId: id, storagePath: `field-photos/${S.employee2.uid}/${id}.jpg`, source: "camera", capturedAt: Date.now(),
    }, S.employee), "INVALID_ARGUMENT");
  });
  await test("storage rules block uploading into another user's folder", async () => {
    assert.equal(await upload(`field-photos/${S.employee2.uid}/${uuid()}.jpg`, S.employee), 403);
  });

  console.log("\nLeave workflow");
  let leaveA;
  let leaveB;
  await test("employee submits leave with an attachment", async () => {
    const att1 = `leave-attachments/${S.employee.uid}/${uuid()}.pdf`;
    assert.equal(await upload(att1, S.employee, "application/pdf"), 200);
    const r = await call("submitLeaveRequest", {
      leaveType: "sick", startDate: futureKey(20), endDate: futureKey(21), reason: "Medical appointment", attachmentPaths: [att1],
    }, S.employee);
    leaveA = r.requestId;
  });
  await test("overlapping leave is refused", () =>
    expectError(call("submitLeaveRequest", { leaveType: "other", startDate: futureKey(21), endDate: futureKey(22), reason: "Overlap" }, S.employee), "ALREADY_EXISTS"));
  await test("employee cannot review own leave; supervisor cannot review", async () => {
    await expectError(call("reviewLeaveRequest", { requestId: leaveA, decision: "approve" }, S.employee), "PERMISSION_DENIED");
    await expectError(call("reviewLeaveRequest", { requestId: leaveA, decision: "approve" }, S.supervisor), "PERMISSION_DENIED");
  });
  await test("Manager + HR approvals approve the request (2 of 3)", async () => {
    let r = await call("reviewLeaveRequest", { requestId: leaveA, decision: "approve" }, S.manager);
    assert.equal(r.status, "pending");
    r = await call("reviewLeaveRequest", { requestId: leaveA, decision: "approve", comment: "OK" }, S.hr);
    assert.equal(r.status, "approved");
  });
  await test("one rejection rejects; Administrator can override", async () => {
    const r0 = await call("submitLeaveRequest", { leaveType: "half_day", startDate: futureKey(30), halfDayPeriod: "first_half", reason: "Bank work" }, S.employee);
    leaveB = r0.requestId;
    await expectError(call("reviewLeaveRequest", { requestId: leaveB, decision: "reject" }, S.manager), "INVALID_ARGUMENT"); // reason required
    let r = await call("reviewLeaveRequest", { requestId: leaveB, decision: "reject", comment: "Busy week" }, S.manager);
    assert.equal(r.status, "rejected");
    await expectError(call("reviewLeaveRequest", { requestId: leaveB, decision: "approve" }, S.hr), "FAILED_PRECONDITION");
    r = await call("reviewLeaveRequest", { requestId: leaveB, decision: "approve", comment: "Override" }, S.admin);
    assert.equal(r.status, "approved");
  });
  await test("employee can withdraw a pending request", async () => {
    const r = await call("submitLeaveRequest", { leaveType: "emergency", startDate: futureKey(40), endDate: futureKey(40), reason: "Test" }, S.employee);
    await call("cancelLeaveRequest", { requestId: r.requestId }, S.employee);
    const d = await fsGet(`leaveRequests/${r.requestId}`, S.employee);
    assert.equal(val(d.body, "status"), "cancelled");
  });
  await test("employee is notified of the leave decision", async () => {
    const q = await fsQuery("notifications", [eq("recipientUid", S.employee.uid), eq("type", "leave_decision")], S.employee);
    assert.ok(q.body.filter((x) => x.document).length >= 1);
  });

  console.log("\nDevice change (one phone per employee)");
  await test("employee requests a new phone; HR approves; old phone is revoked", async () => {
    const r = await call("requestDeviceChange", { deviceId: "e2e-device-bbbb", deviceModel: "New Test Phone", reason: "Upgraded" }, T);
    assert.equal(r.status, "pending");
    await call("reviewDeviceChange", { requestId: r.requestId, decision: "approve" }, S.hr);
    await expectError(call("syncAttendanceEvents", { deviceId: "e2e-device-aaaa", events: [att("check_in", Date.now())] }, T), "FAILED_PRECONDITION");
    const ok = await call("syncAttendanceEvents", { deviceId: "e2e-device-bbbb", events: [att("check_in", Date.now())] }, T);
    assert.equal(ok.results[0].status, "accepted");
  });

  console.log("\nAdministration & policy");
  await test("admin creates a site and department; HR cannot", async () => {
    const s = await call("upsertSite", { name: "E2E Site", latitude: 31.5, longitude: 74.3, radiusM: 150 }, S.admin);
    assert.ok(s.siteId);
    await expectError(call("upsertSite", { name: "Nope", latitude: 1, longitude: 1 }, S.hr), "PERMISSION_DENIED");
    const d = await call("upsertDepartment", { name: "E2E Department" }, S.admin);
    assert.ok(d.departmentId);
  });
  await test("policy update is clamped to safe ranges; HR cannot change policy", async () => {
    const r = await call("updatePolicy", { policy: { tracking: { intervalSeconds: 5 } } }, S.admin);
    assert.equal(r.policy.tracking.intervalSeconds, 30);
    await call("updatePolicy", { policy: { tracking: { intervalSeconds: 60 } } }, S.admin);
    await expectError(call("updatePolicy", { policy: {} }, S.hr), "PERMISSION_DENIED");
  });
  await test("admin cannot remove own admin access", () =>
    expectError(call("updateEmployee", { uid: S.admin.uid, role: "employee" }, S.admin), "FAILED_PRECONDITION"));
  await test("admin disables an account; it can no longer sign in", async () => {
    await call("updateEmployee", { uid: T.uid, accountStatus: "disabled" }, S.admin);
    const e = await expectError(signIn(testEmail));
    assert.equal(e.code, "USER_DISABLED");
  });
  await test("audit log records actions (HR can read, employee cannot)", async () => {
    const q = await fsQuery("auditLogs", [eq("action", "leave.approve")], S.hr);
    assert.equal(q.status, 200);
    assert.ok(q.body.filter((x) => x.document).length >= 1);
    assert.equal((await fsQuery("auditLogs", [eq("action", "leave.approve")], S.employee)).status, 403);
  });

  console.log("\nSecurity rules (data visibility)");
  await test("employee cannot read another employee's profile", async () => {
    assert.equal((await fsGet(`users/${S.employee2.uid}`, S.employee)).status, 403);
  });
  await test("manager can read team profiles", async () => {
    assert.equal((await fsGet(`users/${S.employee.uid}`, S.manager)).status, 200);
  });
  await test("employee cannot list others' attendance", async () => {
    assert.equal((await fsQuery("attendanceDays", [eq("uid", S.employee2.uid)], S.employee)).status, 403);
  });
  await test("supervisor lists team attendance only with the viewer filter", async () => {
    const ok = await fsQuery("attendanceDays", [{ field: { fieldPath: "viewerUids" }, op: "ARRAY_CONTAINS", value: { stringValue: S.supervisor.uid } }], S.supervisor);
    assert.equal(ok.status, 200);
    assert.equal((await fsQuery("attendanceDays", [eq("uid", S.employee.uid)], S.supervisor)).status, 403);
  });
  await test("clients cannot write business data directly", async () => {
    const status = await fsPatch(`attendanceDays/${S.employee.uid}_2099-01-01`, { status: { stringValue: "completed" } }, ["status"], S.employee);
    assert.equal(status, 403);
  });
  await test("user can mark own notification read, but not change its text", async () => {
    const q = await fsQuery("notifications", [eq("recipientUid", S.employee.uid)], S.employee);
    const doc = q.body.find((x) => x.document).document;
    const path = doc.name.split("/documents/")[1];
    assert.equal(await fsPatch(path, { read: { booleanValue: true } }, ["read"], S.employee), 200);
    assert.equal(await fsPatch(path, { title: { stringValue: "hacked" } }, ["title"], S.employee), 403);
  });
  await test("phone index and push tokens are hidden from clients", async () => {
    assert.equal((await fsGet("phoneIndex/923000000001", S.admin)).status, 403);
    assert.equal((await fsGet(`fcmTokens/${S.admin.uid}`, S.admin)).status, 403);
  });

  const failed = results.filter((r) => !r[0]);
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
