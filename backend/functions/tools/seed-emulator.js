/* eslint-disable no-console */
/**
 * Fills the LOCAL Firebase emulators with demo data. Refuses to run against a real project.
 *
 *   firebase emulators:start --project demo-saibaan      (in one terminal)
 *   node tools/seed-emulator.js                          (from backend/functions)
 *
 * All demo accounts use the password Demo@12345.
 */
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");

const PROJECT_ID = "demo-saibaan";
const PASSWORD = "Demo@12345";
const DEMO_DEVICE_ID = "demo-device-0001"; // matches Env.demoDeviceId in the app
const OFFSET_MS = 5 * 60 * 60 * 1000; // Asia/Karachi

initializeApp({ projectId: PROJECT_ID });
const auth = getAuth();
const db = getFirestore();

const dateKeyOf = (ms) => new Date(ms + OFFSET_MS).toISOString().slice(0, 10);
/** Epoch ms for a wall-clock time in Pakistan, `daysAgo` days before today. */
function pkt(daysAgo, hour, minute = 0) {
  const todayKey = dateKeyOf(Date.now());
  const d = new Date(`${todayKey}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - daysAgo);
  return d.getTime() + (hour * 60 + minute) * 60_000 - OFFSET_MS;
}

const SITES = [
  { id: "site-head-office", name: "Head Office", address: "Main Boulevard, Lahore", latitude: 31.5204, longitude: 74.3587, radiusM: 200 },
  { id: "site-field-kasur", name: "Field Site — Kasur", address: "Kasur project area", latitude: 31.1167, longitude: 74.45, radiusM: 500 },
  { id: "site-field-sheikhupura", name: "Field Site — Sheikhupura", address: "Sheikhupura project area", latitude: 31.7131, longitude: 73.9783, radiusM: 500 },
];
const DEPARTMENTS = [
  { id: "dept-field", name: "Field Operations" },
  { id: "dept-admin", name: "Administration" },
  { id: "dept-hr", name: "Human Resources" },
];
const USERS = [
  { key: "admin", name: "Ayesha Admin", role: "admin", phone: "923000000001", dept: "dept-admin", code: "SDO-001", designation: "System Administrator", sites: ["site-head-office"] },
  { key: "hr", name: "Hina HR", role: "hr", phone: "923000000002", dept: "dept-hr", code: "SDO-002", designation: "HR Officer", sites: ["site-head-office"] },
  { key: "manager", name: "Usman Manager", role: "manager", phone: "923000000003", dept: "dept-field", code: "SDO-003", designation: "Project Manager", sites: ["site-head-office", "site-field-kasur"] },
  { key: "supervisor", name: "Saad Supervisor", role: "supervisor", phone: "923000000004", dept: "dept-field", code: "SDO-004", designation: "Field Supervisor", sites: ["site-field-kasur", "site-field-sheikhupura"], manager: "manager" },
  { key: "employee", name: "Bilal Employee", role: "employee", phone: "923000000005", dept: "dept-field", code: "SDO-101", designation: "Field Officer", sites: ["site-field-kasur", "site-head-office"], manager: "manager", supervisor: "supervisor" },
  { key: "employee2", name: "Fatima Employee", role: "employee", phone: "923000000006", dept: "dept-field", code: "SDO-102", designation: "Social Mobilizer", sites: ["site-field-sheikhupura"], manager: "manager", supervisor: "supervisor" },
];

async function upsertAuthUser(email, displayName) {
  try {
    const u = await auth.getUserByEmail(email);
    await auth.updateUser(u.uid, { password: PASSWORD, displayName, disabled: false });
    return u.uid;
  } catch {
    const u = await auth.createUser({ email, password: PASSWORD, displayName });
    return u.uid;
  }
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Emulator host not set");
  const batch = db.batch();
  const now = FieldValue.serverTimestamp();

  // Policy: biometric fallback and gallery photos ON so the demo works in a browser.
  batch.set(db.doc("config/policy"), {
    leave: { requiredApprovals: 2, adminCanApproveAlone: true, rejectionBlocks: true, adminCanOverrideRejection: true, maxAttachments: 3 },
    attendance: { maxAccuracyM: 100, lateSyncMinutes: 15, clockSkewToleranceMinutes: 5, allowWithoutBiometric: true, correctionRoles: ["hr", "admin"] },
    tracking: { intervalSeconds: 60, distanceFilterM: 0, locationRetentionDays: 90 },
    photos: { allowGallery: true },
    sites: { defaultRadiusM: 200 },
  });
  for (const s of SITES) {
    const { id, ...data } = s;
    batch.set(db.doc(`sites/${id}`), { ...data, isActive: true, createdAt: now, updatedAt: now });
  }
  for (const d of DEPARTMENTS) batch.set(db.doc(`departments/${d.id}`), { name: d.name, isActive: true, createdAt: now });

  // Accounts
  const uid = {};
  for (const u of USERS) {
    const email = `${u.key}@saibaan.demo`;
    uid[u.key] = await upsertAuthUser(email, u.name);
    await auth.setCustomUserClaims(uid[u.key], { role: u.role, status: "active" });
  }
  for (const u of USERS) {
    const email = `${u.key}@saibaan.demo`;
    batch.set(db.doc(`users/${uid[u.key]}`), {
      uid: uid[u.key], displayName: u.name, email, authEmail: email, phone: u.phone, photoPath: null,
      role: u.role, accountStatus: "active",
      activeDeviceId: DEMO_DEVICE_ID, activeDeviceModel: "Demo device", pendingDeviceId: null, pendingDeviceModel: null,
      employeeCode: u.code, designation: u.designation, departmentId: u.dept,
      managerUid: u.manager ? uid[u.manager] : null, supervisorUid: u.supervisor ? uid[u.supervisor] : null,
      assignedSiteIds: u.sites, reviewComment: null, requestedAt: now, createdAt: now, updatedAt: now,
    });
    batch.set(db.doc(`phoneIndex/${u.phone}`), { uid: uid[u.key], authEmail: email });
  }

  // A registration waiting for approval
  const pendingUid = await upsertAuthUser("newjoiner@saibaan.demo", "Zain New Joiner");
  await auth.setCustomUserClaims(pendingUid, { status: "pending" });
  batch.set(db.doc(`users/${pendingUid}`), {
    uid: pendingUid, displayName: "Zain New Joiner", email: "newjoiner@saibaan.demo", authEmail: "newjoiner@saibaan.demo",
    phone: "923000000099", photoPath: null, role: "employee", accountStatus: "pending",
    activeDeviceId: null, activeDeviceModel: null, pendingDeviceId: DEMO_DEVICE_ID, pendingDeviceModel: "Demo device",
    employeeCode: null, designation: null, departmentId: null, managerUid: null, supervisorUid: null,
    assignedSiteIds: [], reviewComment: null, requestedAt: now, createdAt: now, updatedAt: now,
  });
  batch.set(db.doc("phoneIndex/923000000099"), { uid: pendingUid, authEmail: "newjoiner@saibaan.demo" });

  // Attendance history for the two field employees (last 6 days, excluding today)
  const viewers = [uid.manager, uid.supervisor];
  const kasur = SITES[1];
  for (const key of ["employee", "employee2"]) {
    for (let daysAgo = 1; daysAgo <= 6; daysAgo++) {
      const inMs = pkt(daysAgo, 9, (daysAgo * 7) % 25);
      const outMs = pkt(daysAgo, 17, (daysAgo * 11) % 40);
      const dateKey = dateKeyOf(inMs);
      const flagged = key === "employee" && daysAgo === 2;
      const missing = key === "employee2" && daysAgo === 3;
      const flags = flagged ? ["outside_geofence"] : missing ? ["missing_checkout"] : [];
      const inId = `seed-${key}-${dateKey}-in`;
      batch.set(db.doc(`attendanceEvents/${inId}`), {
        uid: uid[key], employeeName: USERS.find((u) => u.key === key).name, type: "check_in", dateKey,
        deviceTime: Timestamp.fromMillis(inMs), serverReceivedAt: Timestamp.fromMillis(inMs + 4000),
        latitude: flagged ? kasur.latitude + 0.02 : kasur.latitude, longitude: kasur.longitude, accuracyM: 12, isMocked: false,
        siteId: kasur.id, siteName: kasur.name, distanceM: flagged ? 2224 : 18, insideGeofence: !flagged,
        biometricPassed: true, deviceId: DEMO_DEVICE_ID, flags: flagged ? ["outside_geofence"] : [], applied: true,
        reviewStatus: flagged ? "pending" : "none", managerUid: uid.manager, viewerUids: viewers,
      });
      batch.set(db.doc(`attendanceDays/${uid[key]}_${dateKey}`), {
        uid: uid[key], employeeName: USERS.find((u) => u.key === key).name, dateKey, viewerUids: viewers,
        checkInAt: Timestamp.fromMillis(inMs), checkInEventId: inId,
        ...(missing ? {} : { checkOutAt: Timestamp.fromMillis(outMs), workedMinutes: Math.round((outMs - inMs) / 60000) }),
        siteId: kasur.id, siteName: kasur.name,
        status: missing ? "missing_checkout" : "completed", flags, needsReview: flags.length > 0, updatedAt: now,
      });
    }
  }

  // Last known locations
  batch.set(db.doc(`liveLocations/${uid.employee}`), {
    uid: uid.employee, employeeName: "Bilal Employee", isTracking: false, sessionDateKey: dateKeyOf(pkt(1, 9)),
    latitude: kasur.latitude + 0.0004, longitude: kasur.longitude - 0.0003, accuracyM: 9,
    capturedAt: Timestamp.fromMillis(pkt(1, 17)), receivedAt: Timestamp.fromMillis(pkt(1, 17)),
    siteId: kasur.id, siteName: kasur.name, insideGeofence: true, viewerUids: viewers, updatedAt: now,
  });

  // Leave requests
  batch.set(db.doc("leaveRequests/seed-leave-1"), {
    uid: uid.employee2, employeeName: "Fatima Employee", leaveType: "sick",
    startDate: dateKeyOf(pkt(-2, 9)), endDate: dateKeyOf(pkt(-3, 9)), days: 2, halfDayPeriod: null,
    reason: "Fever, doctor advised two days of rest.", attachmentPaths: [], status: "pending",
    decisions: [], managerUid: uid.manager, viewerUids: [uid.manager], createdAt: now, updatedAt: now,
  });
  batch.set(db.doc("leaveRequests/seed-leave-2"), {
    uid: uid.employee, employeeName: "Bilal Employee", leaveType: "half_day",
    startDate: dateKeyOf(pkt(5, 9)), endDate: dateKeyOf(pkt(5, 9)), days: 0.5, halfDayPeriod: "second_half",
    reason: "Family commitment in the afternoon.", attachmentPaths: [], status: "approved",
    decisions: [
      { role: "manager", uid: uid.manager, name: "Usman Manager", decision: "approve", comment: null, at: Timestamp.fromMillis(pkt(6, 11)) },
      { role: "hr", uid: uid.hr, name: "Hina HR", decision: "approve", comment: "Approved.", at: Timestamp.fromMillis(pkt(6, 14)) },
    ],
    managerUid: uid.manager, viewerUids: [uid.manager], createdAt: Timestamp.fromMillis(pkt(6, 10)), updatedAt: now,
  });

  // Notifications
  for (const [to, title, body, type] of [
    [uid.manager, "Leave request", "Fatima Employee: Sick leave, 2 days.", "leave_submitted"],
    [uid.hr, "New registration", "Zain New Joiner is waiting for account approval.", "registration_pending"],
    [uid.admin, "New registration", "Zain New Joiner is waiting for account approval.", "registration_pending"],
    [uid.employee, "Leave approved", "Half-day leave was approved.", "leave_decision"],
  ]) {
    batch.set(db.collection("notifications").doc(), { recipientUid: to, title, body, type, data: {}, read: false, createdAt: now });
  }
  batch.set(db.collection("auditLogs").doc(), {
    actorUid: "seed", actorName: "Seed script", action: "demo.seeded", targetType: "project", targetId: PROJECT_ID, metadata: {}, createdAt: now,
  });

  await batch.commit();
  console.log("\nDemo data loaded. Sign in with any of these (password Demo@12345):");
  for (const u of USERS) console.log(`  ${u.role.padEnd(10)} ${u.key}@saibaan.demo   or phone 0${u.phone.slice(2)}`);
  console.log("  pending    newjoiner@saibaan.demo  (awaiting approval)");
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
