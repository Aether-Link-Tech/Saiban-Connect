import { FieldValue } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { requireAuth } from "../core/context";
import { db } from "../core/firebase";
import { asObject, reqString } from "../core/validate";

const MAX_TOKENS_PER_USER = 5;

/** Stores the phone's FCM token. Tokens are not readable by clients. */
export const registerFcmToken = onCall(async (req) => {
  const uid = requireAuth(req);
  const token = reqString(asObject(req.data).token, "Token", 4096);
  const ref = db.doc(`fcmTokens/${uid}`);
  await db.runTransaction(async (tx) => {
    const existing = (await tx.get(ref)).get("tokens");
    const list = (Array.isArray(existing) ? existing : []).filter((t: unknown) => t !== token);
    list.push(token);
    tx.set(ref, { tokens: list.slice(-MAX_TOKENS_PER_USER), updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
});

export const unregisterFcmToken = onCall(async (req) => {
  const uid = requireAuth(req);
  const token = reqString(asObject(req.data).token, "Token", 4096);
  await db.doc(`fcmTokens/${uid}`).set({ tokens: FieldValue.arrayRemove(token) }, { merge: true });
  return { ok: true };
});
