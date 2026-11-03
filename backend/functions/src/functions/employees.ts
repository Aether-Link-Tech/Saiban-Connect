import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive, viewerUidsFor } from "../core/context";
import { adminAuth, db } from "../core/firebase";
import { notifyUsers } from "../core/notify";
import { asObject, oneOf, reqString } from "../core/validate";
import { parseAssignment } from "./assignment";

/**
 * HR/Admin update employee details and assignments. Role and account status
 * changes are Administrator-only.
 */
export const updateEmployee = onCall(async (req) => {
  const caller = await requireActive(req, ["hr", "admin"]);
  const d = asObject(req.data);
  const uid = reqString(d.uid, "User", 128);

  const ref = db.doc(`users/${uid}`);
  const user = (await ref.get()).data();
  if (!user) throw new HttpsError("not-found", "Employee not found.");
  if (user.accountStatus !== "active" && user.accountStatus !== "disabled") {
    throw new HttpsError("failed-precondition", "Review the registration before editing this account.");
  }
  if (caller.role !== "admin" && (user.role === "hr" || user.role === "admin")) {
    throw new HttpsError("permission-denied", "Only an administrator can edit HR or Administrator accounts.");
  }
  if (caller.role !== "admin" && (d.role !== undefined || d.accountStatus !== undefined)) {
    throw new HttpsError("permission-denied", "Only an administrator can change roles or account status.");
  }

  const changes = await parseAssignment(d, caller, uid);
  const accountStatus = d.accountStatus === undefined ? undefined : oneOf(d.accountStatus, "Account status", ["active", "disabled"] as const);

  if (uid === caller.uid && ((changes.role && changes.role !== "admin") || accountStatus === "disabled")) {
    throw new HttpsError("failed-precondition", "You cannot remove your own administrator access.");
  }

  const newRole = changes.role ?? user.role;
  const newStatus = accountStatus ?? user.accountStatus;
  if (newRole !== user.role || newStatus !== user.accountStatus) {
    await adminAuth.setCustomUserClaims(uid, { role: newRole, status: newStatus });
    if (newStatus !== user.accountStatus) {
      await adminAuth.updateUser(uid, { disabled: newStatus === "disabled" });
      if (newStatus === "disabled") await adminAuth.revokeRefreshTokens(uid);
    }
  }

  await ref.update({
    ...changes,
    ...(accountStatus ? { accountStatus } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Keep live-location visibility in step with the new manager/supervisor.
  if (changes.managerUid !== undefined || changes.supervisorUid !== undefined) {
    const merged = { ...user, ...changes };
    const live = db.doc(`liveLocations/${uid}`);
    if ((await live.get()).exists) await live.update({ viewerUids: viewerUidsFor(merged) });
  }

  await audit(caller, "employee.updated", "user", uid, { ...changes, ...(accountStatus ? { accountStatus } : {}) });
  if (newRole !== user.role) {
    await notifyUsers([uid], {
      title: "Role updated",
      body: `Your role is now ${newRole}. Reopen the app to see your new options.`,
      type: "role_changed",
    });
  }
  return { ok: true };
});
