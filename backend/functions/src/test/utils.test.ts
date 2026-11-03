import assert from "node:assert/strict";
import { test } from "node:test";
import { distanceM, nearestSite } from "../core/geo";
import { addDays, dateKeyOf, daysInclusive, isValidDateKey } from "../core/time";
import { isSyntheticEmail, normalizePhone, syntheticEmailFor } from "../logic/phone";
import { DEFAULT_POLICY, mergePolicy } from "../logic/policyModel";

test("normalizePhone handles Pakistani formats", () => {
  assert.equal(normalizePhone("0300-1234567"), "923001234567");
  assert.equal(normalizePhone("+92 300 1234567"), "923001234567");
  assert.equal(normalizePhone("3001234567"), "923001234567");
  assert.equal(normalizePhone("0092 300 1234567"), "923001234567");
  assert.equal(normalizePhone("12345"), null);
});

test("synthetic emails round-trip", () => {
  const e = syntheticEmailFor("923001234567");
  assert.ok(isSyntheticEmail(e));
  assert.ok(!isSyntheticEmail("someone@example.com"));
});

test("dateKeyOf uses Pakistan time", () => {
  // 20:00 UTC on 2 Nov is 01:00 on 3 Nov in Karachi.
  assert.equal(dateKeyOf(Date.UTC(2026, 10, 2, 20, 0)), "2026-11-03");
  assert.equal(dateKeyOf(Date.UTC(2026, 10, 2, 18, 59)), "2026-11-02");
});

test("date key helpers", () => {
  assert.ok(isValidDateKey("2026-02-28"));
  assert.ok(!isValidDateKey("2026-02-30"));
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
  assert.equal(daysInclusive("2026-11-01", "2026-11-03"), 3);
});

test("distance and nearest site", () => {
  const d = distanceM(31.5204, 74.3587, 31.5294, 74.3587); // ~1 km north
  assert.ok(d > 990 && d < 1010, `distance was ${d}`);
  const sites = [
    { id: "a", name: "A", latitude: 31.5204, longitude: 74.3587, radiusM: 100 },
    { id: "b", name: "B", latitude: 31.6, longitude: 74.4, radiusM: 100 },
  ];
  const n = nearestSite(31.5205, 74.3588, sites);
  assert.equal(n?.site.id, "a");
  assert.equal(n?.inside, true);
});

test("mergePolicy validates and clamps", () => {
  assert.deepEqual(mergePolicy(undefined), DEFAULT_POLICY);
  const p = mergePolicy({
    leave: { requiredApprovals: 9, rejectionBlocks: "yes" },
    tracking: { intervalSeconds: 5 },
    attendance: { correctionRoles: ["hr", "bogus"] },
    unknown: { x: 1 },
  });
  assert.equal(p.leave.requiredApprovals, 3);
  assert.equal(p.leave.rejectionBlocks, DEFAULT_POLICY.leave.rejectionBlocks);
  assert.equal(p.tracking.intervalSeconds, 30);
  assert.deepEqual(p.attendance.correctionRoles, ["hr", "admin"]);
  assert.ok(!("unknown" in p));
});
