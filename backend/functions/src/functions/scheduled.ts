import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "../core/firebase";
import { notifyUsers } from "../core/notify";
import { loadPolicy } from "../core/policy";
import { dateKeyOf, ORG_TIME_ZONE } from "../core/time";

/** End of day: flag employees who checked in but never checked out. */
export const markMissingCheckouts = onSchedule({ schedule: "55 23 * * *", timeZone: ORG_TIME_ZONE }, async () => {
  const today = dateKeyOf(Date.now());
  const open = await db
    .collection("attendanceDays")
    .where("dateKey", "==", today)
    .where("status", "==", "checked_in")
    .get();
  for (const doc of open.docs) {
    const day = doc.data();
    await doc.ref.update({
      status: "missing_checkout",
      flags: FieldValue.arrayUnion("missing_checkout"),
      needsReview: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await notifyUsers([day.uid], {
      title: "Check-out missing",
      body: `You did not check out on ${today}. Check out now if you are still working, or ask HR to correct it.`,
      type: "missing_checkout",
    });
  }
  logger.info("Missing check-outs flagged", { count: open.size, dateKey: today });
});

/** Deletes location history older than the configured retention period. */
export const purgeLocationHistory = onSchedule({ schedule: "30 2 * * *", timeZone: ORG_TIME_ZONE }, async () => {
  const policy = await loadPolicy();
  const cutoff = Timestamp.fromMillis(Date.now() - policy.tracking.locationRetentionDays * 86_400_000);
  let deleted = 0;
  for (let round = 0; round < 40; round++) {
    const snap = await db.collection("locationPoints").where("capturedAt", "<", cutoff).limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
  }
  logger.info("Location history purged", { deleted, retentionDays: policy.tracking.locationRetentionDays });
});
