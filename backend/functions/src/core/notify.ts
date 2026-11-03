import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { db, messaging } from "./firebase";
import { Role } from "./types";

export interface NotificationInput {
  title: string;
  body: string;
  type: string;
  data?: Record<string, string>;
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Stores an in-app notification for each recipient and sends a push message to
 * their registered devices. Failures are logged and never fail the calling action.
 */
export async function notifyUsers(uids: Array<string | null | undefined>, n: NotificationInput): Promise<void> {
  const recipients = [...new Set(uids.filter((u): u is string => typeof u === "string" && u.length > 0))];
  if (recipients.length === 0) return;
  try {
    for (const group of chunk(recipients, 400)) {
      const batch = db.batch();
      for (const uid of group) {
        batch.set(db.collection("notifications").doc(), {
          recipientUid: uid,
          title: n.title,
          body: n.body,
          type: n.type,
          data: n.data ?? {},
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    const tokenSnaps = await db.getAll(...recipients.map((uid) => db.doc(`fcmTokens/${uid}`)));
    const targets: Array<{ uid: string; token: string }> = [];
    for (const s of tokenSnaps) {
      const tokens = s.get("tokens");
      if (Array.isArray(tokens)) {
        for (const t of tokens) if (typeof t === "string") targets.push({ uid: s.id, token: t });
      }
    }
    for (const group of chunk(targets, 500)) {
      const res = await messaging.sendEachForMulticast({
        tokens: group.map((t) => t.token),
        notification: { title: n.title, body: n.body },
        data: { type: n.type, ...(n.data ?? {}) },
        android: { priority: "high" },
      });
      const stale = res.responses
        .map((r, i) => ({ r, t: group[i] }))
        .filter(
          ({ r }) =>
            !r.success &&
            (r.error?.code === "messaging/registration-token-not-registered" ||
              r.error?.code === "messaging/invalid-registration-token"),
        );
      for (const { t } of stale) {
        await db.doc(`fcmTokens/${t.uid}`).update({ tokens: FieldValue.arrayRemove(t.token) });
      }
    }
  } catch (e) {
    logger.error("Notification delivery failed", { type: n.type, error: String(e) });
  }
}

export async function activeUidsWithRoles(roles: Role[]): Promise<string[]> {
  const snap = await db
    .collection("users")
    .where("accountStatus", "==", "active")
    .where("role", "in", roles)
    .get();
  return snap.docs.map((d) => d.id);
}
