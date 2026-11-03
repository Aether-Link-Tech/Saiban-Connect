import { db } from "./firebase";
import { mergePolicy, Policy } from "../logic/policyModel";

export const POLICY_DOC = "config/policy";

/**
 * Loads the organization policy (config/policy) merged over defaults.
 * Not cached: functions run on many instances, and admin changes must apply
 * immediately everywhere. It costs one document read per call.
 */
export async function loadPolicy(): Promise<Policy> {
  const snap = await db.doc(POLICY_DOC).get();
  return mergePolicy(snap.data());
}
