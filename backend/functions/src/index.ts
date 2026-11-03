import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

export const healthCheck = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  return { ok: true, service: "saibaan-connect", uid: request.auth.uid };
});

// Call this helper only after a trusted function has validated actor permissions.
export async function writeAuditLog(
  actorUid: string, action: string, targetType: string, targetId: string
): Promise<void> {
  await db.collection("auditLogs").add({
    actorUid, action, targetType, targetId,
    createdAt: FieldValue.serverTimestamp()
  });
}
