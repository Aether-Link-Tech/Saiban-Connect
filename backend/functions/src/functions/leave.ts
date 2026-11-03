import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive } from "../core/context";
import { bucket, db } from "../core/firebase";
import { activeUidsWithRoles, notifyUsers } from "../core/notify";
import { loadPolicy } from "../core/policy";
import { daysInclusive } from "../core/time";
import { DECISIONS, LEAVE_TYPES } from "../core/types";
import { asObject, bad, oneOf, optString, reqDateKey, reqString, stringArray } from "../core/validate";
import { canReview, evaluateLeave, LeaveStatus, ReviewerRole } from "../logic/leaveWorkflow";

const LEAVE_LABELS: Record<string, string> = {
  sick: "Sick",
  emergency: "Emergency",
  half_day: "Half-day",
  other: "Other",
};

export const submitLeaveRequest = onCall(async (req) => {
  const caller = await requireActive(req);
  const policy = await loadPolicy();
  const d = asObject(req.data);
  const leaveType = oneOf(d.leaveType, "Leave type", LEAVE_TYPES);
  const startDate = reqDateKey(d.startDate, "Start date");
  const endDate = leaveType === "half_day" ? startDate : reqDateKey(d.endDate, "End date");
  if (endDate < startDate) bad("End date must be on or after the start date.");
  if (daysInclusive(startDate, endDate) > 60) bad("A single request can cover at most 60 days.");
  const halfDayPeriod = leaveType === "half_day" ? oneOf(d.halfDayPeriod, "Half-day period", ["first_half", "second_half"] as const) : null;
  const reason = reqString(d.reason, "Reason", 1000, 3);
  const attachmentPaths = stringArray(d.attachmentPaths, "Attachments", policy.leave.maxAttachments);
  for (const p of attachmentPaths) {
    if (!p.startsWith(`leave-attachments/${caller.uid}/`)) bad("Invalid attachment path.");
    const [exists] = await bucket().file(p).exists();
    if (!exists) bad("An attachment upload was not found. Please attach it again.");
  }

  const mine = await db.collection("leaveRequests").where("uid", "==", caller.uid).get();
  const overlap = mine.docs.find((doc) => {
    const r = doc.data();
    return (r.status === "pending" || r.status === "approved") && r.startDate <= endDate && r.endDate >= startDate;
  });
  if (overlap) throw new HttpsError("already-exists", "You already have a leave request covering these dates.");

  const managerUid: string | null = caller.profile.managerUid ?? null;
  const ref = await db.collection("leaveRequests").add({
    uid: caller.uid,
    employeeName: caller.name,
    leaveType,
    startDate,
    endDate,
    days: leaveType === "half_day" ? 0.5 : daysInclusive(startDate, endDate),
    halfDayPeriod,
    reason,
    attachmentPaths,
    status: "pending",
    decisions: [],
    managerUid,
    viewerUids: managerUid ? [managerUid] : [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await audit(caller, "leave.submitted", "leaveRequest", ref.id, { leaveType, startDate, endDate });
  const reviewers = [managerUid, ...(await activeUidsWithRoles(["hr", "admin"]))].filter((u) => u !== caller.uid);
  await notifyUsers(reviewers, {
    title: "Leave request",
    body: `${caller.name}: ${LEAVE_LABELS[leaveType]} leave, ${startDate}${endDate !== startDate ? ` to ${endDate}` : ""}.`,
    type: "leave_submitted",
    data: { requestId: ref.id },
  });
  return { ok: true, requestId: ref.id };
});

export const cancelLeaveRequest = onCall(async (req) => {
  const caller = await requireActive(req);
  const d = asObject(req.data);
  const requestId = reqString(d.requestId, "Request", 128);
  const ref = db.doc(`leaveRequests/${requestId}`);
  await db.runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data();
    if (!r || r.uid !== caller.uid) throw new HttpsError("not-found", "Leave request not found.");
    if (r.status !== "pending") throw new HttpsError("failed-precondition", "Only pending requests can be cancelled.");
    tx.update(ref, { status: "cancelled", updatedAt: FieldValue.serverTimestamp(), finalizedAt: FieldValue.serverTimestamp() });
  });
  await audit(caller, "leave.cancelled", "leaveRequest", requestId);
  return { ok: true };
});

/**
 * Manager (of the employee), HR or Administrator record a decision.
 * The outcome is computed by evaluateLeave() using the configured policy.
 */
export const reviewLeaveRequest = onCall(async (req) => {
  const caller = await requireActive(req, ["manager", "hr", "admin"]);
  const policy = await loadPolicy();
  const d = asObject(req.data);
  const requestId = reqString(d.requestId, "Request", 128);
  const decision = oneOf(d.decision, "Decision", DECISIONS);
  const comment = optString(d.comment, "Comment", 1000);
  if (decision === "reject" && !comment) bad("Please give a reason for the rejection.");

  const ref = db.doc(`leaveRequests/${requestId}`);
  const outcome = await db.runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data();
    if (!r) throw new HttpsError("not-found", "Leave request not found.");
    if (r.uid === caller.uid) throw new HttpsError("permission-denied", "You cannot review your own leave request.");

    let reviewerRole: ReviewerRole | null = null;
    if (caller.role === "admin") reviewerRole = "admin";
    else if (caller.role === "hr") reviewerRole = "hr";
    else if (caller.role === "manager" && r.managerUid === caller.uid) reviewerRole = "manager";
    if (!reviewerRole) throw new HttpsError("permission-denied", "You can only review leave for your own team.");

    const previous = r.status as LeaveStatus;
    if (!canReview(previous, reviewerRole, policy.leave)) {
      throw new HttpsError("failed-precondition", "This request is no longer open for review.");
    }
    const entry = {
      role: reviewerRole,
      uid: caller.uid,
      name: caller.name,
      decision,
      comment,
      at: Timestamp.now(),
    };
    const decisions = [...(Array.isArray(r.decisions) ? r.decisions : []), entry];
    const status = evaluateLeave(
      decisions.map((x) => ({ role: x.role, decision: x.decision, at: x.at instanceof Timestamp ? x.at.toMillis() : 0 })),
      policy.leave,
      r.managerUid ? 3 : 2,
    );
    tx.update(ref, {
      decisions,
      status,
      updatedAt: FieldValue.serverTimestamp(),
      ...(status !== "pending" ? { finalizedAt: FieldValue.serverTimestamp(), finalizedBy: caller.uid } : {}),
    });
    return { previous, status, r, reviewerRole };
  });

  const { r, status, previous, reviewerRole } = outcome;
  await audit(caller, `leave.${decision}`, "leaveRequest", requestId, { reviewerRole, comment, status, previous });

  const label = `${LEAVE_LABELS[r.leaveType] ?? "Leave"} leave (${r.startDate}${r.endDate !== r.startDate ? ` to ${r.endDate}` : ""})`;
  if (status !== previous) {
    await notifyUsers([r.uid], {
      title: status === "approved" ? "Leave approved" : status === "rejected" ? "Leave rejected" : "Leave updated",
      body: `${label} was ${status}${comment ? `: ${comment}` : "."}`,
      type: "leave_decision",
      data: { requestId },
    });
  } else {
    await notifyUsers([r.uid], {
      title: "Leave review in progress",
      body: `${caller.name} (${reviewerRole}) ${decision === "approve" ? "approved" : "rejected"} your ${label}. Awaiting further review.`,
      type: "leave_progress",
      data: { requestId },
    });
  }
  return { ok: true, status };
});
