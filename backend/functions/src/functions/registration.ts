import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive, requireAuth } from "../core/context";
import { adminAuth, db } from "../core/firebase";
import { activeUidsWithRoles, notifyUsers } from "../core/notify";
import { DECISIONS } from "../core/types";
import { asObject, bad, oneOf, optString, reqId, reqString } from "../core/validate";
import { isSyntheticEmail, normalizePhone } from "../logic/phone";
import { parseAssignment } from "./assignment";

/**
 * Step 2 of self-registration (step 1 is creating the Firebase Auth account on the
 * phone). Creates the pending profile; HR/Admin must approve before the account works.
 */
export const submitRegistration = onCall(async (req) => {
  const uid = requireAuth(req);
  const authEmail = req.auth?.token.email;
  if (!authEmail) bad("Your sign-in account has no email address.");

  const d = asObject(req.data);
  const displayName = reqString(d.displayName, "Full name", 100, 2);
  const phone = normalizePhone(reqString(d.phone, "Phone number", 25));
  if (!phone) bad("Enter a valid phone number.");
  const contactEmail = optString(d.email, "Email", 200)?.toLowerCase() ?? null;
  const photoPath = optString(d.photoPath, "Profile photo", 300);
  if (photoPath && !photoPath.startsWith(`employee-photos/${uid}/`)) bad("Invalid profile photo path.");
  const deviceId = reqId(d.deviceId, "Device ID");
  const deviceModel = optString(d.deviceModel, "Device model", 120) ?? "Unknown device";

  const userRef = db.doc(`users/${uid}`);
  const phoneRef = db.doc(`phoneIndex/${phone}`);
  const resubmission = await db.runTransaction(async (tx) => {
    const [user, phoneDoc] = await Promise.all([tx.get(userRef), tx.get(phoneRef)]);
    const existing = user.data();
    if (existing && existing.accountStatus !== "rejected") {
      throw new HttpsError("already-exists", "A registration has already been submitted for this account.");
    }
    if (phoneDoc.exists && phoneDoc.get("uid") !== uid) {
      throw new HttpsError("already-exists", "This phone number is already registered.");
    }
    if (existing?.phone && existing.phone !== phone) tx.delete(db.doc(`phoneIndex/${existing.phone}`));
    tx.set(phoneRef, { uid, authEmail });
    tx.set(userRef, {
      uid,
      displayName,
      email: contactEmail ?? (isSyntheticEmail(authEmail) ? null : authEmail.toLowerCase()),
      authEmail,
      phone,
      photoPath,
      role: "employee",
      accountStatus: "pending",
      pendingDeviceId: deviceId,
      pendingDeviceModel: deviceModel,
      activeDeviceId: null,
      activeDeviceModel: null,
      employeeCode: null,
      designation: null,
      departmentId: null,
      managerUid: null,
      supervisorUid: null,
      assignedSiteIds: [],
      reviewComment: null,
      requestedAt: FieldValue.serverTimestamp(),
      createdAt: existing?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return existing !== undefined;
  });

  await adminAuth.setCustomUserClaims(uid, { status: "pending" });
  await audit({ uid, name: displayName }, resubmission ? "registration.resubmitted" : "registration.submitted", "user", uid);
  await notifyUsers(await activeUidsWithRoles(["hr", "admin"]), {
    title: "New registration",
    body: `${displayName} is waiting for account approval.`,
    type: "registration_pending",
    data: { uid },
  });
  return { ok: true };
});

/**
 * Maps a phone number to the sign-in email so employees can log in with phone + password.
 * Note: this reveals whether a phone number is registered. Enable Firebase App Check
 * in production to limit automated enumeration.
 */
export const resolveLoginEmail = onCall(async (req) => {
  const d = asObject(req.data);
  const phone = normalizePhone(reqString(d.phone, "Phone number", 25));
  if (!phone) bad("Enter a valid phone number.");
  const snap = await db.doc(`phoneIndex/${phone}`).get();
  if (!snap.exists) throw new HttpsError("not-found", "No account found for this phone number.");
  return { email: snap.get("authEmail") as string };
});

/** HR/Admin approve or reject a pending registration, assigning role and organization details. */
export const reviewRegistration = onCall(async (req) => {
  const caller = await requireActive(req, ["hr", "admin"]);
  const d = asObject(req.data);
  const uid = reqString(d.uid, "User", 128);
  const decision = oneOf(d.decision, "Decision", DECISIONS);
  const comment = optString(d.comment, "Comment", 500);

  const ref = db.doc(`users/${uid}`);
  const snap = await ref.get();
  const user = snap.data();
  if (!user) throw new HttpsError("not-found", "Registration not found.");
  if (user.accountStatus !== "pending") throw new HttpsError("failed-precondition", "This registration was already reviewed.");

  if (decision === "reject") {
    if (!comment) bad("Please give a reason for rejecting the registration.");
    // Claims are updated before the profile so the app never sees a status its token lacks.
    await adminAuth.setCustomUserClaims(uid, { status: "rejected" });
    await ref.update({
      accountStatus: "rejected",
      reviewComment: comment,
      reviewedBy: caller.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await audit(caller, "registration.rejected", "user", uid, { comment });
    await notifyUsers([uid], {
      title: "Registration not approved",
      body: comment,
      type: "registration_rejected",
    });
    return { ok: true, status: "rejected" };
  }

  const changes = await parseAssignment(d, caller, uid);
  const role = changes.role ?? "employee";
  await adminAuth.setCustomUserClaims(uid, { role, status: "active" });
  await ref.update({
    ...changes,
    role,
    accountStatus: "active",
    activeDeviceId: user.pendingDeviceId ?? null,
    activeDeviceModel: user.pendingDeviceModel ?? null,
    pendingDeviceId: null,
    pendingDeviceModel: null,
    reviewComment: comment,
    reviewedBy: caller.uid,
    reviewedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(caller, "registration.approved", "user", uid, { ...changes, role });
  await notifyUsers([uid], {
    title: "Account approved",
    body: "Your SAIBAAN Connect account is active. You can now sign in and mark attendance.",
    type: "registration_approved",
  });
  return { ok: true, status: "active" };
});
