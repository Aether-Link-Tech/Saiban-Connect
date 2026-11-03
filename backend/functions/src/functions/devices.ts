import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive } from "../core/context";
import { db } from "../core/firebase";
import { activeUidsWithRoles, notifyUsers } from "../core/notify";
import { DECISIONS } from "../core/types";
import { asObject, oneOf, optString, reqId, reqString } from "../core/validate";

/** Employee asks to move their account to a new phone (one registered device per employee). */
export const requestDeviceChange = onCall(async (req) => {
  const caller = await requireActive(req);
  const d = asObject(req.data);
  const deviceId = reqId(d.deviceId, "Device ID");
  const deviceModel = optString(d.deviceModel, "Device model", 120) ?? "Unknown device";
  const reason = optString(d.reason, "Reason", 300);
  if (caller.profile.activeDeviceId === deviceId) return { ok: true, status: "already_active" };

  const existing = await db
    .collection("deviceRequests")
    .where("uid", "==", caller.uid)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  const payload = {
    uid: caller.uid,
    employeeName: caller.name,
    deviceId,
    deviceModel,
    reason,
    previousDeviceId: caller.profile.activeDeviceId ?? null,
    previousDeviceModel: caller.profile.activeDeviceModel ?? null,
    status: "pending",
    updatedAt: FieldValue.serverTimestamp(),
  };
  let requestId: string;
  if (!existing.empty) {
    requestId = existing.docs[0].id;
    await existing.docs[0].ref.update(payload);
  } else {
    const ref = await db.collection("deviceRequests").add({ ...payload, createdAt: FieldValue.serverTimestamp() });
    requestId = ref.id;
  }

  await audit(caller, "device.change_requested", "deviceRequest", requestId, { deviceModel });
  await notifyUsers(await activeUidsWithRoles(["hr", "admin"]), {
    title: "Device change request",
    body: `${caller.name} wants to use a new phone (${deviceModel}).`,
    type: "device_request",
    data: { requestId },
  });
  return { ok: true, status: "pending", requestId };
});

export const reviewDeviceChange = onCall(async (req) => {
  const caller = await requireActive(req, ["hr", "admin"]);
  const d = asObject(req.data);
  const requestId = reqString(d.requestId, "Request", 128);
  const decision = oneOf(d.decision, "Decision", DECISIONS);
  const comment = optString(d.comment, "Comment", 300);

  const reqRef = db.doc(`deviceRequests/${requestId}`);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    const r = snap.data();
    if (!r) throw new HttpsError("not-found", "Request not found.");
    if (r.status !== "pending") throw new HttpsError("failed-precondition", "This request was already reviewed.");
    const status = decision === "approve" ? "approved" : "rejected";
    tx.update(reqRef, {
      status,
      comment,
      reviewedBy: caller.uid,
      reviewedByName: caller.name,
      reviewedAt: FieldValue.serverTimestamp(),
    });
    if (decision === "approve") {
      // The previous phone is revoked by replacement: attendance calls from it fail the device check.
      tx.update(db.doc(`users/${r.uid}`), {
        activeDeviceId: r.deviceId,
        activeDeviceModel: r.deviceModel,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { uid: r.uid as string, status, deviceModel: r.deviceModel as string };
  });

  await audit(caller, `device.change_${result.status}`, "deviceRequest", requestId, { uid: result.uid, comment });
  await notifyUsers([result.uid], {
    title: result.status === "approved" ? "New phone approved" : "Device change rejected",
    body:
      result.status === "approved"
        ? `You can now mark attendance from ${result.deviceModel}.`
        : comment ?? "Your device change request was not approved.",
    type: "device_request_decision",
  });
  return { ok: true, status: result.status };
});
