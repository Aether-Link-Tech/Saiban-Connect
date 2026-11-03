import { FieldValue } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive } from "../core/context";
import { db } from "../core/firebase";
import { GeoSite } from "../core/geo";
import { loadPolicy } from "../core/policy";
import { asObject, optBool, optId, optNumber, optString, reqNumber, reqString } from "../core/validate";

/** Loads the active sites among the given IDs. */
export async function loadSites(ids: unknown): Promise<GeoSite[]> {
  if (!Array.isArray(ids) || ids.length === 0) return [];
  const refs = ids.filter((x): x is string => typeof x === "string").map((id) => db.doc(`sites/${id}`));
  if (refs.length === 0) return [];
  const snaps = await db.getAll(...refs);
  return snaps
    .filter((s) => s.exists && s.get("isActive") !== false)
    .map((s) => ({
      id: s.id,
      name: String(s.get("name") ?? ""),
      latitude: Number(s.get("latitude")),
      longitude: Number(s.get("longitude")),
      radiusM: Number(s.get("radiusM")),
    }));
}

/** Administrator creates or updates an authorized work location and its geofence. */
export const upsertSite = onCall(async (req) => {
  const caller = await requireActive(req, ["admin"]);
  const d = asObject(req.data);
  const policy = await loadPolicy();
  const siteId = optId(d.siteId, "Site");
  const data = {
    name: reqString(d.name, "Site name", 100, 2),
    address: optString(d.address, "Address", 300),
    latitude: reqNumber(d.latitude, "Latitude", -90, 90),
    longitude: reqNumber(d.longitude, "Longitude", -180, 180),
    radiusM: optNumber(d.radiusM, "Geofence radius", 20, 5000) ?? policy.sites.defaultRadiusM,
    isActive: optBool(d.isActive, "Active") ?? true,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: caller.uid,
  };
  const ref = siteId ? db.doc(`sites/${siteId}`) : db.collection("sites").doc();
  if (siteId) await ref.set(data, { merge: true });
  else await ref.set({ ...data, createdAt: FieldValue.serverTimestamp(), createdBy: caller.uid });
  const { updatedAt: _ignored, ...auditData } = data;
  await audit(caller, siteId ? "site.updated" : "site.created", "site", ref.id, auditData);
  return { ok: true, siteId: ref.id };
});

export const upsertDepartment = onCall(async (req) => {
  const caller = await requireActive(req, ["admin"]);
  const d = asObject(req.data);
  const id = optId(d.departmentId, "Department");
  const data = {
    name: reqString(d.name, "Department name", 100, 2),
    isActive: optBool(d.isActive, "Active") ?? true,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const ref = id ? db.doc(`departments/${id}`) : db.collection("departments").doc();
  await ref.set(id ? data : { ...data, createdAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(caller, id ? "department.updated" : "department.created", "department", ref.id, { name: data.name, isActive: data.isActive });
  return { ok: true, departmentId: ref.id };
});
