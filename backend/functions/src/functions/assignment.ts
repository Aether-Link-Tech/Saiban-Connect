import { HttpsError } from "firebase-functions/v2/https";
import { Caller } from "../core/context";
import { db } from "../core/firebase";
import { ROLES, Role } from "../core/types";
import { bad, oneOf, optString, stringArray } from "../core/validate";

export interface AssignmentChanges {
  role?: Role;
  employeeCode?: string | null;
  designation?: string | null;
  departmentId?: string | null;
  managerUid?: string | null;
  supervisorUid?: string | null;
  assignedSiteIds?: string[];
}

async function requireUserWithRole(uid: string, allowed: Role[], label: string): Promise<void> {
  const snap = await db.doc(`users/${uid}`).get();
  const d = snap.data();
  if (!d || d.accountStatus !== "active" || !allowed.includes(d.role)) {
    bad(`${label} must be an active user with role: ${allowed.join(", ")}.`);
  }
}

/**
 * Parses organizational assignment fields shared by registration approval and
 * employee updates. Only fields present in the input are returned.
 */
export async function parseAssignment(
  d: Record<string, unknown>,
  caller: Caller,
  targetUid: string,
): Promise<AssignmentChanges> {
  const out: AssignmentChanges = {};

  if (d.role !== undefined) {
    const role = oneOf(d.role, "Role", ROLES);
    if (caller.role !== "admin" && (role === "hr" || role === "admin")) {
      throw new HttpsError("permission-denied", "Only an administrator can assign HR or Administrator roles.");
    }
    out.role = role;
  }
  if (d.employeeCode !== undefined) out.employeeCode = optString(d.employeeCode, "Employee code", 40);
  if (d.designation !== undefined) out.designation = optString(d.designation, "Designation", 100);

  if (d.departmentId !== undefined) {
    const id = optString(d.departmentId, "Department", 64);
    if (id) {
      const dep = await db.doc(`departments/${id}`).get();
      if (!dep.exists) bad("Department not found.");
    }
    out.departmentId = id;
  }
  if (d.managerUid !== undefined) {
    const id = optString(d.managerUid, "Manager", 128);
    if (id === targetUid) bad("An employee cannot be their own manager.");
    if (id) await requireUserWithRole(id, ["manager", "hr", "admin"], "Manager");
    out.managerUid = id;
  }
  if (d.supervisorUid !== undefined) {
    const id = optString(d.supervisorUid, "Supervisor", 128);
    if (id === targetUid) bad("An employee cannot be their own supervisor.");
    if (id) await requireUserWithRole(id, ["supervisor", "manager"], "Supervisor");
    out.supervisorUid = id;
  }
  if (d.assignedSiteIds !== undefined) {
    const ids = stringArray(d.assignedSiteIds, "Sites", 50, 64);
    if (ids.length) {
      const snaps = await db.getAll(...ids.map((id) => db.doc(`sites/${id}`)));
      const missing = snaps.filter((s) => !s.exists).map((s) => s.id);
      if (missing.length) bad(`Unknown site(s): ${missing.join(", ")}.`);
    }
    out.assignedSiteIds = ids;
  }
  return out;
}
