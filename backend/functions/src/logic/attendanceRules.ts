import type { AttendanceType } from "../core/types";
import type { Policy } from "./policyModel";

export interface AttendanceEvalInput {
  type: AttendanceType;
  deviceTimeMs: number;
  serverTimeMs: number;
  hasCoords: boolean;
  accuracyM: number | null;
  isMocked: boolean;
  biometricPassed: boolean;
  hasAssignedSites: boolean;
  /** Nearest assigned site, when coordinates and sites are available. */
  nearest: { distanceM: number; radiusM: number } | null;
  /** Current day record, if one exists. */
  day: { checkInAtMs: number | null; checkOutAtMs: number | null } | null;
}

export interface AttendanceEvalResult {
  flags: string[];
  /** Whether the event updates the attendance day (false for duplicates). */
  apply: boolean;
  /** Non-null when the event must not be recorded at all. */
  rejectReason: string | null;
}

/**
 * Validates one attendance event against the attendance policy. Anything unusual is
 * recorded but flagged for review (proposal §4.3, §4.4, §12); only events
 * without the required biometric confirmation are rejected outright.
 */
export function evaluateAttendanceEvent(
  i: AttendanceEvalInput,
  p: Policy["attendance"],
): AttendanceEvalResult {
  const flags: string[] = [];

  if (!i.biometricPassed) {
    if (!p.allowWithoutBiometric) {
      return { flags, apply: false, rejectReason: "Biometric confirmation is required." };
    }
    flags.push("no_biometric");
  }

  if (i.deviceTimeMs > i.serverTimeMs + p.clockSkewToleranceMinutes * 60_000) {
    flags.push("device_time_ahead");
  }
  if (i.serverTimeMs - i.deviceTimeMs > p.lateSyncMinutes * 60_000) {
    flags.push("late_sync");
  }

  if (!i.hasCoords) {
    flags.push("no_gps");
  } else {
    if (i.accuracyM === null || i.accuracyM > p.maxAccuracyM) flags.push("low_accuracy");
    if (i.isMocked) flags.push("mock_location");
    if (!i.hasAssignedSites) flags.push("no_assigned_site");
    else if (i.nearest && i.nearest.distanceM > i.nearest.radiusM) flags.push("outside_geofence");
  }

  let apply = true;
  const checkInAtMs = i.day?.checkInAtMs ?? null;
  const checkOutAtMs = i.day?.checkOutAtMs ?? null;
  if (i.type === "check_in") {
    if (checkInAtMs !== null) {
      flags.push("duplicate_check_in");
      apply = false;
    }
  } else {
    if (checkOutAtMs !== null) {
      flags.push("duplicate_check_out");
      apply = false;
    } else if (checkInAtMs === null) {
      flags.push("check_out_without_check_in");
    } else if (i.deviceTimeMs < checkInAtMs) {
      flags.push("check_out_before_check_in");
      apply = false;
    }
  }

  return { flags, apply, rejectReason: null };
}
