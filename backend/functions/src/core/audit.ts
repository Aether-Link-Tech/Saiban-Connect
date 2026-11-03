import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { db } from "./firebase";

export interface Actor {
  uid: string;
  name?: string;
}

/** Records an administrative or approval action. Call only after permissions were checked. */
export async function audit(
  actor: Actor,
  action: string,
  targetType: string,
  targetId: string,
  metadata: Record<string, unknown> = {},
): Promise<void> {
  try {
    await db.collection("auditLogs").add({
      actorUid: actor.uid,
      actorName: actor.name ?? null,
      action,
      targetType,
      targetId,
      metadata,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.error("Failed to write audit log", { action, targetId, error: String(e) });
  }
}
