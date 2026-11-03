import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { requireActive, viewerUidsFor } from "../core/context";
import { db } from "../core/firebase";
import { nearestSite } from "../core/geo";
import { dateKeyOf } from "../core/time";
import { asObject, bad, optNumber, reqId, reqNumber } from "../core/validate";
import { requireApprovedDevice } from "./attendance";
import { loadSites } from "./sites";

const MAX_POINTS = 400;

/**
 * Receives location samples recorded while the employee is checked in (queued on the
 * phone when offline). Updates liveLocations/{uid} with the newest sample so
 * management sees the last received position and its timestamp.
 */
export const uploadLocationPoints = onCall(async (req) => {
  const caller = await requireActive(req);
  const d = asObject(req.data);
  const deviceId = reqId(d.deviceId, "Device ID");
  requireApprovedDevice(caller, deviceId);
  if (!Array.isArray(d.points) || d.points.length === 0) bad("No location points supplied.");
  if (d.points.length > MAX_POINTS) bad(`At most ${MAX_POINTS} points per request.`);

  const now = Date.now();
  const viewerUids = viewerUidsFor(caller.profile);
  const points = d.points.map((raw, i) => {
    const p = asObject(raw);
    return {
      id: reqId(p.id, `Point ${i} ID`),
      latitude: reqNumber(p.latitude, "Latitude", -90, 90),
      longitude: reqNumber(p.longitude, "Longitude", -180, 180),
      accuracyM: optNumber(p.accuracyM, "Accuracy", 0, 1_000_000),
      capturedAt: reqNumber(p.capturedAt, "Captured time", Date.UTC(2024, 0, 1), now + 86_400_000),
    };
  });

  const batch = db.batch();
  for (const p of points) {
    batch.set(db.doc(`locationPoints/${p.id}`), {
      uid: caller.uid,
      dateKey: dateKeyOf(p.capturedAt),
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyM: p.accuracyM,
      capturedAt: Timestamp.fromMillis(p.capturedAt),
      receivedAt: FieldValue.serverTimestamp(),
      viewerUids,
    });
  }
  await batch.commit();

  const newest = points.reduce((a, b) => (b.capturedAt > a.capturedAt ? b : a));
  const liveRef = db.doc(`liveLocations/${caller.uid}`);
  const sites = await loadSites(caller.profile.assignedSiteIds);
  const near = nearestSite(newest.latitude, newest.longitude, sites);
  await db.runTransaction(async (tx) => {
    const live = (await tx.get(liveRef)).data();
    const prev = live?.capturedAt instanceof Timestamp ? live.capturedAt.toMillis() : 0;
    if (newest.capturedAt <= prev) return;
    tx.set(liveRef, {
      uid: caller.uid,
      employeeName: caller.name,
      latitude: newest.latitude,
      longitude: newest.longitude,
      accuracyM: newest.accuracyM,
      capturedAt: Timestamp.fromMillis(newest.capturedAt),
      receivedAt: FieldValue.serverTimestamp(),
      siteId: near?.site.id ?? null,
      siteName: near?.site.name ?? null,
      insideGeofence: near?.inside ?? null,
      viewerUids,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { ok: true, stored: points.length };
});
