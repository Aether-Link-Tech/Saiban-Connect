import { ROLES, Role } from "../core/types";

/**
 * Operational policy. Every value here corresponds to a decision listed in
 * proposal §11 ("Important Policies to Confirm Before Development"). Defaults are
 * placeholders until the client confirms them in writing; an administrator can
 * change them in the app (stored at config/policy).
 */
export interface Policy {
  leave: {
    /** Number of distinct reviewer approvals (Manager / HR / Admin) that approve a request. */
    requiredApprovals: number;
    /** Administrator approval alone approves the request. */
    adminCanApproveAlone: boolean;
    /** A single rejection by Manager or HR rejects the request. */
    rejectionBlocks: boolean;
    /** Administrator may approve a request that another reviewer rejected. */
    adminCanOverrideRejection: boolean;
    maxAttachments: number;
  };
  attendance: {
    /** GPS readings with worse accuracy than this are flagged. */
    maxAccuracyM: number;
    /** Events received this long after the device time are flagged as late sync. */
    lateSyncMinutes: number;
    /** Device time this far ahead of server time is flagged. */
    clockSkewToleranceMinutes: number;
    /** Allow attendance on phones without enrolled biometrics (flagged for review). */
    allowWithoutBiometric: boolean;
    /** Roles allowed to correct attendance records. */
    correctionRoles: Role[];
  };
  tracking: {
    intervalSeconds: number;
    distanceFilterM: number;
    locationRetentionDays: number;
  };
  photos: {
    allowGallery: boolean;
  };
  sites: {
    defaultRadiusM: number;
  };
}

export const DEFAULT_POLICY: Policy = {
  leave: {
    requiredApprovals: 2,
    adminCanApproveAlone: true,
    rejectionBlocks: true,
    adminCanOverrideRejection: true,
    maxAttachments: 3,
  },
  attendance: {
    maxAccuracyM: 100,
    lateSyncMinutes: 15,
    clockSkewToleranceMinutes: 5,
    allowWithoutBiometric: false,
    correctionRoles: ["hr", "admin"],
  },
  tracking: {
    intervalSeconds: 300,
    distanceFilterM: 0,
    locationRetentionDays: 90,
  },
  photos: {
    allowGallery: false,
  },
  sites: {
    defaultRadiusM: 200,
  },
};

const RANGES: Record<string, [number, number]> = {
  "leave.requiredApprovals": [1, 3],
  "leave.maxAttachments": [0, 5],
  "attendance.maxAccuracyM": [10, 5000],
  "attendance.lateSyncMinutes": [1, 10080],
  "attendance.clockSkewToleranceMinutes": [1, 1440],
  "tracking.intervalSeconds": [30, 3600],
  "tracking.distanceFilterM": [0, 1000],
  "tracking.locationRetentionDays": [7, 3650],
  "sites.defaultRadiusM": [20, 5000],
};

function clamp(path: string, n: number): number {
  const r = RANGES[path];
  if (!r) return n;
  return Math.min(r[1], Math.max(r[0], Math.round(n)));
}

/**
 * Builds a complete, range-checked policy from untrusted input. Unknown keys are
 * dropped; wrong types fall back to the default value.
 */
export function mergePolicy(raw: unknown, base: Policy = DEFAULT_POLICY): Policy {
  const src = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const out: Record<string, Record<string, unknown>> = {};
  for (const [section, defaults] of Object.entries(base)) {
    const rawSection = (src[section] && typeof src[section] === "object" ? src[section] : {}) as Record<string, unknown>;
    out[section] = {};
    for (const [key, def] of Object.entries(defaults as Record<string, unknown>)) {
      const v = rawSection[key];
      const path = `${section}.${key}`;
      if (Array.isArray(def)) {
        out[section][key] = Array.isArray(v)
          ? [...new Set(v.filter((x): x is Role => typeof x === "string" && (ROLES as readonly string[]).includes(x)))]
          : [...def];
      } else if (typeof def === "number") {
        out[section][key] = typeof v === "number" && Number.isFinite(v) ? clamp(path, v) : def;
      } else if (typeof def === "boolean") {
        out[section][key] = typeof v === "boolean" ? v : def;
      } else {
        out[section][key] = def;
      }
    }
  }
  const policy = out as unknown as Policy;
  // Administrators must always be able to correct attendance.
  if (!policy.attendance.correctionRoles.includes("admin")) policy.attendance.correctionRoles.push("admin");
  return policy;
}
