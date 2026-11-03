import type { Decision } from "../core/types";
import type { Policy } from "./policyModel";

export type ReviewerRole = "manager" | "hr" | "admin";
export type LeaveStatus = "pending" | "approved" | "rejected" | "cancelled";

export interface LeaveDecisionInput {
  role: ReviewerRole;
  decision: Decision;
  /** epoch ms */
  at: number;
}

/**
 * Evaluates a leave request from its reviewer decisions.
 *
 * Approval route (proposal §4.6 / §11): Manager, HR and Administrator review in
 * parallel. Each reviewer slot keeps only its latest decision.
 *  - Administrator rejection rejects.
 *  - Administrator approval approves when `adminCanApproveAlone`, unless another
 *    reviewer rejected and rejections block without admin override.
 *  - Otherwise a Manager/HR rejection rejects when `rejectionBlocks`.
 *  - `requiredApprovals` distinct approvals approve.
 *  - If the remaining reviewers can no longer reach the required count, the request is rejected.
 *
 * @param availableReviewers number of reviewer slots that can act (3, or 2 when the employee has no manager).
 */
export function evaluateLeave(
  decisions: LeaveDecisionInput[],
  policy: Policy["leave"],
  availableReviewers = 3,
): LeaveStatus {
  const latest = new Map<ReviewerRole, LeaveDecisionInput>();
  for (const d of [...decisions].sort((a, b) => a.at - b.at)) latest.set(d.role, d);

  const admin = latest.get("admin");
  const others = [...latest.values()].filter((d) => d.role !== "admin");
  const otherRejected = others.some((d) => d.decision === "reject");

  if (admin) {
    if (admin.decision === "reject") return "rejected";
    if (policy.adminCanApproveAlone) {
      if (otherRejected && policy.rejectionBlocks && !policy.adminCanOverrideRejection) return "rejected";
      return "approved";
    }
  }

  if (otherRejected && policy.rejectionBlocks) return "rejected";

  const approvals = [...latest.values()].filter((d) => d.decision === "approve").length;
  const required = Math.min(policy.requiredApprovals, availableReviewers);
  if (approvals >= required) return "approved";

  const undecided = Math.max(0, availableReviewers - latest.size);
  if (approvals + undecided < required) return "rejected";
  return "pending";
}

/** Whether a reviewer in the given slot may record a decision on a request in this status. */
export function canReview(status: LeaveStatus, role: ReviewerRole, policy: Policy["leave"]): boolean {
  if (status === "pending") return true;
  return (
    status === "rejected" &&
    role === "admin" &&
    policy.adminCanApproveAlone &&
    policy.adminCanOverrideRejection
  );
}
