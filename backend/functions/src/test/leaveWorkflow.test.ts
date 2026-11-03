import assert from "node:assert/strict";
import { test } from "node:test";
import { canReview, evaluateLeave, LeaveDecisionInput } from "../logic/leaveWorkflow";
import { DEFAULT_POLICY } from "../logic/policyModel";

const p = DEFAULT_POLICY.leave;
const d = (role: LeaveDecisionInput["role"], decision: LeaveDecisionInput["decision"], at = 1): LeaveDecisionInput => ({ role, decision, at });

test("no decisions is pending", () => {
  assert.equal(evaluateLeave([], p), "pending");
});

test("one approval is pending, two approvals approve", () => {
  assert.equal(evaluateLeave([d("manager", "approve")], p), "pending");
  assert.equal(evaluateLeave([d("manager", "approve"), d("hr", "approve", 2)], p), "approved");
});

test("administrator can approve alone", () => {
  assert.equal(evaluateLeave([d("admin", "approve")], p), "approved");
  assert.equal(evaluateLeave([d("admin", "approve")], { ...p, adminCanApproveAlone: false }), "pending");
});

test("a manager or HR rejection blocks by default", () => {
  assert.equal(evaluateLeave([d("manager", "approve"), d("hr", "reject", 2)], p), "rejected");
});

test("administrator overrides a rejection only when allowed", () => {
  const decisions = [d("hr", "reject"), d("admin", "approve", 2)];
  assert.equal(evaluateLeave(decisions, p), "approved");
  assert.equal(evaluateLeave(decisions, { ...p, adminCanOverrideRejection: false }), "rejected");
});

test("administrator rejection rejects", () => {
  assert.equal(evaluateLeave([d("manager", "approve"), d("admin", "reject", 2)], p), "rejected");
});

test("without blocking rejections, becomes rejected only when approvals are unreachable", () => {
  const nb = { ...p, rejectionBlocks: false };
  assert.equal(evaluateLeave([d("manager", "reject")], nb), "pending");
  assert.equal(evaluateLeave([d("manager", "reject"), d("hr", "reject", 2)], nb), "rejected");
  assert.equal(evaluateLeave([d("manager", "reject"), d("hr", "approve", 2), d("admin", "approve", 3)], nb), "approved");
});

test("latest decision per reviewer slot wins", () => {
  assert.equal(evaluateLeave([d("hr", "reject", 1), d("hr", "approve", 2), d("manager", "approve", 3)], p), "approved");
});

test("employee without a manager needs HR and admin when two approvals are required", () => {
  const strict = { ...p, adminCanApproveAlone: false };
  assert.equal(evaluateLeave([d("hr", "approve")], strict, 2), "pending");
  assert.equal(evaluateLeave([d("hr", "approve"), d("admin", "approve", 2)], strict, 2), "approved");
});

test("canReview allows admin override on rejected requests", () => {
  assert.equal(canReview("pending", "manager", p), true);
  assert.equal(canReview("rejected", "hr", p), false);
  assert.equal(canReview("rejected", "admin", p), true);
  assert.equal(canReview("approved", "admin", p), false);
});
