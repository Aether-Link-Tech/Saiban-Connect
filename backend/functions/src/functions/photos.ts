import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireActive, viewerUidsFor } from "../core/context";
import { bucket, db } from "../core/firebase";
import { nearestSite } from "../core/geo";
import { loadPolicy } from "../core/policy";
import { asObject, bad, oneOf, optNumber, optString, reqId, reqNumber, reqString } from "../core/validate";
import { loadSites } from "./sites";

/**
 * Links an uploaded site photograph (already in Cloud Storage under
 * field-photos/{uid}/) to the employee and site records.
 */
export const registerFieldPhoto = onCall(async (req) => {
  const caller = await requireActive(req);
  const policy = await loadPolicy();
  const d = asObject(req.data);
  const photoId = reqId(d.photoId, "Photo ID");
  const storagePath = reqString(d.storagePath, "Storage path", 300);
  const pathPattern = new RegExp(`^field-photos/${caller.uid}/${photoId}\\.(jpg|jpeg|png|webp)$`);
  if (!pathPattern.test(storagePath)) bad("Invalid photo path.");
  const source = oneOf(d.source, "Source", ["camera", "gallery"] as const);
  if (source === "gallery" && !policy.photos.allowGallery) {
    throw new HttpsError("failed-precondition", "Site photos must be taken with the in-app camera.");
  }
  const caption = optString(d.caption, "Caption", 300);
  const capturedAt = reqNumber(d.capturedAt, "Capture time", Date.UTC(2024, 0, 1), Date.now() + 86_400_000);
  const latitude = optNumber(d.latitude, "Latitude", -90, 90);
  const longitude = optNumber(d.longitude, "Longitude", -180, 180);
  const accuracyM = optNumber(d.accuracyM, "Accuracy", 0, 1_000_000);
  const requestedSiteId = optString(d.siteId, "Site", 64);

  const [exists] = await bucket().file(storagePath).exists();
  if (!exists) bad("Photo upload not found. Please upload again.");

  const sites = await loadSites(caller.profile.assignedSiteIds);
  let site = requestedSiteId ? sites.find((s) => s.id === requestedSiteId) ?? null : null;
  if (requestedSiteId && !site) bad("You are not assigned to the selected site.");
  const near = latitude !== null && longitude !== null ? nearestSite(latitude, longitude, sites) : null;
  if (!site && near?.inside) site = near.site;

  const ref = db.doc(`fieldPhotos/${photoId}`);
  if ((await ref.get()).exists) return { ok: true, photoId };
  await ref.set({
    uid: caller.uid,
    employeeName: caller.name,
    siteId: site?.id ?? null,
    siteName: site?.name ?? null,
    storagePath,
    caption,
    source,
    // Camera captures are timestamped by the app; gallery metadata cannot be verified.
    metadataVerified: source === "camera",
    capturedAt: Timestamp.fromMillis(capturedAt),
    uploadedAt: FieldValue.serverTimestamp(),
    latitude,
    longitude,
    accuracyM,
    viewerUids: viewerUidsFor(caller.profile),
  });
  return { ok: true, photoId };
});
