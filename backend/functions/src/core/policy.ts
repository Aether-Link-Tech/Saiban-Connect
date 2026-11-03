import { db } from "./firebase";
import { mergePolicy, Policy } from "../logic/policyModel";

export const POLICY_DOC = "config/policy";

let cached: { at: number; policy: Policy } | null = null;
const CACHE_MS = 60_000;

/** Loads the organization policy (config/policy) merged over defaults. Cached per instance for 60 s. */
export async function loadPolicy(force = false): Promise<Policy> {
  if (!force && cached && Date.now() - cached.at < CACHE_MS) return cached.policy;
  const snap = await db.doc(POLICY_DOC).get();
  const policy = mergePolicy(snap.data());
  cached = { at: Date.now(), policy };
  return policy;
}

export function invalidatePolicyCache(): void {
  cached = null;
}
