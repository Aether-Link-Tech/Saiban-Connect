import assert from "node:assert/strict";
import { test } from "node:test";
import { AttendanceEvalInput, evaluateAttendanceEvent } from "../logic/attendanceRules";
import { DEFAULT_POLICY } from "../logic/policyModel";

const p = DEFAULT_POLICY.attendance;
const now = Date.UTC(2026, 10, 3, 5, 0);
const base: AttendanceEvalInput = {
  type: "check_in",
  deviceTimeMs: now,
  serverTimeMs: now,
  hasCoords: true,
  accuracyM: 15,
  isMocked: false,
  biometricPassed: true,
  hasAssignedSites: true,
  nearest: { distanceM: 50, radiusM: 200 },
  day: null,
};

test("clean check-in is applied without flags", () => {
  assert.deepEqual(evaluateAttendanceEvent(base, p), { flags: [], apply: true, rejectReason: null });
});

test("missing biometric is rejected unless policy allows it", () => {
  assert.ok(evaluateAttendanceEvent({ ...base, biometricPassed: false }, p).rejectReason);
  const r = evaluateAttendanceEvent({ ...base, biometricPassed: false }, { ...p, allowWithoutBiometric: true });
  assert.equal(r.rejectReason, null);
  assert.ok(r.flags.includes("no_biometric"));
});

test("location problems are flagged", () => {
  assert.ok(evaluateAttendanceEvent({ ...base, nearest: { distanceM: 900, radiusM: 200 } }, p).flags.includes("outside_geofence"));
  assert.ok(evaluateAttendanceEvent({ ...base, accuracyM: 500 }, p).flags.includes("low_accuracy"));
  assert.ok(evaluateAttendanceEvent({ ...base, hasCoords: false, accuracyM: null, nearest: null }, p).flags.includes("no_gps"));
  assert.ok(evaluateAttendanceEvent({ ...base, isMocked: true }, p).flags.includes("mock_location"));
  assert.ok(evaluateAttendanceEvent({ ...base, hasAssignedSites: false, nearest: null }, p).flags.includes("no_assigned_site"));
});

test("time anomalies are flagged", () => {
  assert.ok(evaluateAttendanceEvent({ ...base, deviceTimeMs: now - 60 * 60_000 }, p).flags.includes("late_sync"));
  assert.ok(evaluateAttendanceEvent({ ...base, deviceTimeMs: now + 30 * 60_000 }, p).flags.includes("device_time_ahead"));
});

test("second check-in is a duplicate and not applied", () => {
  const r = evaluateAttendanceEvent({ ...base, day: { checkInAtMs: now - 1000, checkOutAtMs: null } }, p);
  assert.equal(r.apply, false);
  assert.ok(r.flags.includes("duplicate_check_in"));
});

test("check-out rules", () => {
  const out = { ...base, type: "check_out" as const };
  assert.equal(evaluateAttendanceEvent({ ...out, day: { checkInAtMs: now - 3_600_000, checkOutAtMs: null } }, p).apply, true);
  assert.ok(evaluateAttendanceEvent({ ...out, day: null }, p).flags.includes("check_out_without_check_in"));
  const dup = evaluateAttendanceEvent({ ...out, day: { checkInAtMs: now - 10, checkOutAtMs: now - 5 } }, p);
  assert.equal(dup.apply, false);
  const before = evaluateAttendanceEvent({ ...out, day: { checkInAtMs: now + 10, checkOutAtMs: null } }, p);
  assert.equal(before.apply, false);
  assert.ok(before.flags.includes("check_out_before_check_in"));
});
