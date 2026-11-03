import { FieldValue } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { requireActive } from "../core/context";
import { db } from "../core/firebase";
import { loadPolicy, POLICY_DOC } from "../core/policy";
import { asObject } from "../core/validate";
import { mergePolicy } from "../logic/policyModel";

/** Administrator updates organization policy. Partial input is merged over the current policy. */
export const updatePolicy = onCall(async (req) => {
  const caller = await requireActive(req, ["admin"]);
  const input = asObject(asObject(req.data).policy);
  const current = await loadPolicy();
  const combined: Record<string, unknown> = { ...current };
  for (const [section, values] of Object.entries(input)) {
    if (values && typeof values === "object" && section in current) {
      combined[section] = { ...(current as unknown as Record<string, object>)[section], ...(values as object) };
    }
  }
  const next = mergePolicy(combined);
  await db.doc(POLICY_DOC).set({ ...next, updatedAt: FieldValue.serverTimestamp(), updatedBy: caller.uid });
  await audit(caller, "policy.updated", "config", "policy", { before: current, after: next });
  return { ok: true, policy: next };
});
