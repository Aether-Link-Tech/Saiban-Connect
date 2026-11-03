import type { DocumentData } from "firebase-admin/firestore";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { db } from "./firebase";
import { Role } from "./types";

export interface Caller {
  uid: string;
  role: Role;
  name: string;
  profile: DocumentData;
}

export function requireAuth(req: CallableRequest<unknown>): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in.");
  return req.auth.uid;
}

/**
 * Loads the caller's profile and checks the account is active. The Firestore
 * profile (not the token claims) is the source of truth for role and status, so a
 * disabled account is blocked immediately rather than when its token expires.
 */
export async function requireActive(req: CallableRequest<unknown>, roles?: readonly Role[]): Promise<Caller> {
  const uid = requireAuth(req);
  const snap = await db.doc(`users/${uid}`).get();
  const profile = snap.data();
  if (!profile) throw new HttpsError("permission-denied", "Your account registration was not found.");
  if (profile.accountStatus !== "active") throw new HttpsError("permission-denied", "Your account is not active.");
  const role = profile.role as Role;
  if (roles && !roles.includes(role)) {
    throw new HttpsError("permission-denied", "Your role does not allow this action.");
  }
  return { uid, role, name: String(profile.displayName ?? ""), profile };
}

/** Users who may view this employee's operational data (attendance, location, photos). */
export function viewerUidsFor(profile: DocumentData | undefined): string[] {
  const ids = [profile?.managerUid, profile?.supervisorUid].filter(
    (x): x is string => typeof x === "string" && x.length > 0,
  );
  return [...new Set(ids)];
}

export function isHrOrAdmin(role: Role): boolean {
  return role === "hr" || role === "admin";
}
