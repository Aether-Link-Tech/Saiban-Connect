/* eslint-disable no-console */
/**
 * One-time setup: promotes an existing Firebase Auth account to Administrator.
 *
 * 1. Register the first admin's account in the app (or create it in the Firebase console).
 * 2. Authenticate the Admin SDK, e.g.:
 *      gcloud auth application-default login
 *    or set GOOGLE_APPLICATION_CREDENTIALS to a service-account key kept OUTSIDE the repo.
 * 3. Run from backend/functions:
 *      npm run bootstrap-admin -- admin@example.org <projectId>
 */
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

async function main() {
  const [email, projectId] = process.argv.slice(2);
  if (!email || !projectId) {
    console.error("Usage: npm run bootstrap-admin -- <email> <projectId>");
    process.exit(1);
  }
  initializeApp({ credential: applicationDefault(), projectId });
  const auth = getAuth();
  const db = getFirestore();
  const user = await auth.getUserByEmail(email);

  await auth.setCustomUserClaims(user.uid, { role: "admin", status: "active" });
  const ref = db.doc(`users/${user.uid}`);
  const existing = await ref.get();
  await ref.set(
    {
      uid: user.uid,
      displayName: existing.get("displayName") || user.displayName || email,
      email,
      authEmail: email,
      role: "admin",
      accountStatus: "active",
      activeDeviceId: existing.get("activeDeviceId") || existing.get("pendingDeviceId") || null,
      activeDeviceModel: existing.get("activeDeviceModel") || existing.get("pendingDeviceModel") || null,
      pendingDeviceId: null,
      pendingDeviceModel: null,
      assignedSiteIds: existing.get("assignedSiteIds") || [],
      managerUid: existing.get("managerUid") || null,
      supervisorUid: existing.get("supervisorUid") || null,
      updatedAt: FieldValue.serverTimestamp(),
      ...(existing.exists ? {} : { createdAt: FieldValue.serverTimestamp(), phone: null, photoPath: null }),
    },
    { merge: true },
  );
  await db.collection("auditLogs").add({
    actorUid: "bootstrap-script",
    action: "admin.bootstrapped",
    targetType: "user",
    targetId: user.uid,
    metadata: { email },
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(`${email} (${user.uid}) is now an active Administrator. Sign out and back in on the phone.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
