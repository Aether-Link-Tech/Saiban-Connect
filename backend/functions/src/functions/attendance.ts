import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { audit } from "../core/audit";
import { Caller, isHrOrAdmin, requireActive, viewerUidsFor } from "../core/context";
import { db } from "../core/firebase";
import { GeoSite, nearestSite } from "../core/geo";
import { notifyUsers } from "../core/notify";
import { loadPolicy } from "../core/policy";
import { addDays, dateKeyOf } from "../core/time";
import { ATTENDANCE_TYPES, DECISIONS } from "../core/types";
import {
  asObject, bad, oneOf, optBool, optNumber, optString, reqBool, reqDateKey, reqId, reqNumber, reqString,
} from "../core/validate";
import { evaluateAttendanceEvent } from "../logic/attendanceRules";
import { Policy } from "../logic/policyModel";
import { loadSites } from "./sites";

const MAX_EVENTS_PER_CALL = 50;
const EARLIEST_ACCEPTED_MS = Date.UTC(2024, 0, 1);

export function requireApprovedDevice(caller: Caller, deviceId: string): void {
  if (caller.profile.activeDeviceId !== deviceId) {
    throw new HttpsError("failed-precondition", "This phone is not the approved device for your account.", {
      reason: "device_not_approved",
    });
  }
}

function tsMs(v: unknown): number | null {
  return v instanceof Timestamp ? v.toMillis() : null;
}

interface EventResult {
  eventId: string;
  status: "accepted" | "flagged" | "already_synced" | "rejected";
  flags?: string[];
  reason?: string;
}

async function processEvent(
  caller: Caller,
  raw: unknown,
  sites: GeoSite[],
  policy: Policy,
  deviceId: string,
  serverMs: number,
): Promise<EventResult> {
  let eventId = "unknown";
  try {
    const e = asObject(raw);
    eventId = reqId(e.eventId, "Event ID");
    const type = oneOf(e.type, "Event type", ATTENDANCE_TYPES);
    const deviceTime = reqNumber(e.deviceTime, "Device time", EARLIEST_ACCEPTED_MS, serverMs + 86_400_000);
    const latitude = optNumber(e.latitude, "Latitude", -90, 90);
    const longitude = optNumber(e.longitude, "Longitude", -180, 180);
    const accuracyM = optNumber(e.accuracyM, "Accuracy", 0, 1_000_000);
    const biometricPassed = reqBool(e.biometricPassed, "Biometric result");
    const isMocked = optBool(e.isMocked, "Mock location") ?? false;
    const hasCoords = latitude !== null && longitude !== null;

    const dateKey = dateKeyOf(deviceTime);
    const near = hasCoords ? nearestSite(latitude, longitude, sites) : null;
    const eventRef = db.doc(`attendanceEvents/${eventId}`);
    const dayRef = db.doc(`attendanceDays/${caller.uid}_${dateKey}`);
    const viewerUids = viewerUidsFor(caller.profile);

    const result = await db.runTransaction<EventResult>(async (tx) => {
      const [evSnap, daySnap] = await Promise.all([tx.get(eventRef), tx.get(dayRef)]);
      if (evSnap.exists) {
        if (evSnap.get("uid") !== caller.uid) return { eventId, status: "rejected", reason: "Event ID conflict." };
        return { eventId, status: "already_synced", flags: evSnap.get("flags") ?? [] };
      }
      const day = daySnap.data();
      const ev = evaluateAttendanceEvent(
        {
          type,
          deviceTimeMs: deviceTime,
          serverTimeMs: serverMs,
          hasCoords,
          accuracyM,
          isMocked,
          biometricPassed,
          hasAssignedSites: sites.length > 0,
          nearest: near ? { distanceM: near.distanceM, radiusM: near.site.radiusM } : null,
          day: day ? { checkInAtMs: tsMs(day.checkInAt), checkOutAtMs: tsMs(day.checkOutAt) } : null,
        },
        policy.attendance,
      );
      if (ev.rejectReason) return { eventId, status: "rejected", reason: ev.rejectReason };

      const deviceTs = Timestamp.fromMillis(deviceTime);
      tx.set(eventRef, {
        uid: caller.uid,
        employeeName: caller.name,
        type,
        dateKey,
        deviceTime: deviceTs,
        serverReceivedAt: FieldValue.serverTimestamp(),
        latitude,
        longitude,
        accuracyM,
        isMocked,
        siteId: near?.site.id ?? null,
        siteName: near?.site.name ?? null,
        distanceM: near ? Math.round(near.distanceM) : null,
        insideGeofence: near?.inside ?? null,
        biometricPassed,
        deviceId,
        flags: ev.flags,
        applied: ev.apply,
        reviewStatus: ev.flags.length ? "pending" : "none",
        managerUid: caller.profile.managerUid ?? null,
        viewerUids,
      });

      const common = {
        uid: caller.uid,
        employeeName: caller.name,
        dateKey,
        viewerUids,
        updatedAt: FieldValue.serverTimestamp(),
        ...(ev.flags.length ? { flags: FieldValue.arrayUnion(...ev.flags), needsReview: true } : {}),
      };
      if (ev.apply && type === "check_in") {
        tx.set(dayRef, {
          ...common,
          checkInAt: deviceTs,
          checkInEventId: eventId,
          siteId: near?.site.id ?? null,
          siteName: near?.site.name ?? null,
          status: "checked_in",
        }, { merge: true });
      } else if (ev.apply && type === "check_out") {
        const inMs = day ? tsMs(day.checkInAt) : null;
        tx.set(dayRef, {
          ...common,
          checkOutAt: deviceTs,
          checkOutEventId: eventId,
          status: inMs === null ? "incomplete" : "completed",
          workedMinutes: inMs === null ? null : Math.max(0, Math.round((deviceTime - inMs) / 60_000)),
        }, { merge: true });
      } else if (daySnap.exists && ev.flags.length) {
        tx.set(dayRef, common, { merge: true });
      }

      if (ev.apply) {
        const liveRef = db.doc(`liveLocations/${caller.uid}`);
        tx.set(liveRef, {
          uid: caller.uid,
          employeeName: caller.name,
          isTracking: type === "check_in",
          sessionDateKey: dateKey,
          viewerUids,
          updatedAt: FieldValue.serverTimestamp(),
          ...(hasCoords ? {
            latitude, longitude, accuracyM,
            capturedAt: deviceTs,
            receivedAt: FieldValue.serverTimestamp(),
            siteId: near?.site.id ?? null,
            siteName: near?.site.name ?? null,
            insideGeofence: near?.inside ?? null,
          } : {}),
        }, { merge: true });
      }
      return { eventId, status: ev.flags.length ? "flagged" : "accepted", flags: ev.flags };
    });

    if (result.status === "flagged" && result.flags?.includes("outside_geofence") && type === "check_in") {
      await notifyUsers(viewerUidsFor(caller.profile), {
        title: "Check-in outside site",
        body: `${caller.name} checked in ${near ? `${Math.round(near.distanceM)} m from ${near.site.name}` : "away from an assigned site"}.`,
        type: "attendance_flag",
        data: { eventId },
      });
    }
    return result;
  } catch (e) {
    if (e instanceof HttpsError && e.code === "invalid-argument") {
      return { eventId, status: "rejected", reason: e.message };
    }
    logger.error("Attendance event failed", { eventId, error: String(e) });
    throw e;
  }
}

/**
 * Receives queued check-in/check-out events from the phone (live or after being
 * offline). Idempotent per event ID; keeps device time and server receipt time separately.
 */
export const syncAttendanceEvents = onCall(async (req) => {
  const caller = await requireActive(req);
  const d = asObject(req.data);
  const deviceId = reqId(d.deviceId, "Device ID");
  requireApprovedDevice(caller, deviceId);
  if (!Array.isArray(d.events) || d.events.length === 0) bad("No attendance events supplied.");
  if (d.events.length > MAX_EVENTS_PER_CALL) bad(`At most ${MAX_EVENTS_PER_CALL} events per request.`);

  const policy = await loadPolicy();
  const sites = await loadSites(caller.profile.assignedSiteIds);
  const serverMs = Date.now();
  const sorted = [...d.events].sort((a, b) => Number(a?.deviceTime ?? 0) - Number(b?.deviceTime ?? 0));
  const results: EventResult[] = [];
  for (const raw of sorted) results.push(await processEvent(caller, raw, sites, policy, deviceId, serverMs));
  return { results };
});

/** HR/Admin (or the employee's manager) accept or reject a flagged attendance event. */
export const reviewAttendanceEvent = onCall(async (req) => {
  const caller = await requireActive(req, ["manager", "hr", "admin"]);
  const d = asObject(req.data);
  const eventId = reqId(d.eventId, "Event");
  const decision = oneOf(d.decision, "Decision", DECISIONS);
  const comment = optString(d.comment, "Comment", 500);

  const ref = db.doc(`attendanceEvents/${eventId}`);
  const ev = (await ref.get()).data();
  if (!ev) throw new HttpsError("not-found", "Attendance event not found.");
  if (!isHrOrAdmin(caller.role) && ev.managerUid !== caller.uid) {
    throw new HttpsError("permission-denied", "You can only review your own team's attendance.");
  }
  if (ev.uid === caller.uid) throw new HttpsError("permission-denied", "You cannot review your own attendance.");
  if (ev.reviewStatus !== "pending") throw new HttpsError("failed-precondition", "This event is not awaiting review.");

  const reviewStatus = decision === "approve" ? "accepted" : "rejected";
  await ref.update({
    reviewStatus,
    reviewComment: comment,
    reviewedBy: caller.uid,
    reviewedByName: caller.name,
    reviewedAt: FieldValue.serverTimestamp(),
  });
  if (reviewStatus === "rejected") {
    await db.doc(`attendanceDays/${ev.uid}_${ev.dateKey}`).set(
      { flags: FieldValue.arrayUnion(`${ev.type}_rejected_by_review`), needsReview: true },
      { merge: true },
    );
  }
  await audit(caller, `attendance.event_${reviewStatus}`, "attendanceEvent", eventId, { uid: ev.uid, comment });
  await notifyUsers([ev.uid], {
    title: reviewStatus === "accepted" ? "Attendance accepted" : "Attendance rejected",
    body: `Your ${ev.type === "check_in" ? "check-in" : "check-out"} on ${ev.dateKey} was ${reviewStatus}${comment ? `: ${comment}` : "."}`,
    type: "attendance_review",
  });
  return { ok: true };
});

/** Corrects a missed or wrong check-in/check-out. Allowed roles come from policy (default HR, Admin). */
export const correctAttendance = onCall(async (req) => {
  const caller = await requireActive(req);
  const policy = await loadPolicy();
  if (!policy.attendance.correctionRoles.includes(caller.role)) {
    throw new HttpsError("permission-denied", "Your role cannot correct attendance.");
  }
  const d = asObject(req.data);
  const uid = reqString(d.uid, "Employee", 128);
  const dateKey = reqDateKey(d.dateKey, "Date");
  const checkInAt = optNumber(d.checkInAt, "Check-in time", EARLIEST_ACCEPTED_MS);
  const checkOutAt = optNumber(d.checkOutAt, "Check-out time", EARLIEST_ACCEPTED_MS);
  const reason = reqString(d.reason, "Reason", 500, 3);
  if (checkInAt === null && checkOutAt === null) bad("Enter a check-in or check-out time.");
  if (uid === caller.uid && caller.role !== "admin") throw new HttpsError("permission-denied", "You cannot correct your own attendance.");
  if (checkInAt !== null && dateKeyOf(checkInAt) !== dateKey) bad("Check-in time must be on the selected date.");
  if (checkOutAt !== null && dateKeyOf(checkOutAt) !== dateKey && dateKeyOf(checkOutAt) !== addDays(dateKey, 1)) {
    bad("Check-out time must be on the selected date or the following morning.");
  }

  const employee = (await db.doc(`users/${uid}`).get()).data();
  if (!employee) throw new HttpsError("not-found", "Employee not found.");

  const dayRef = db.doc(`attendanceDays/${uid}_${dateKey}`);
  await db.runTransaction(async (tx) => {
    const day = (await tx.get(dayRef)).data();
    const prevIn = day ? tsMs(day.checkInAt) : null;
    const prevOut = day ? tsMs(day.checkOutAt) : null;
    const inMs = checkInAt ?? prevIn;
    const outMs = checkOutAt ?? prevOut;
    if (inMs !== null && outMs !== null && outMs < inMs) bad("Check-out must be after check-in.");
    tx.set(dayRef, {
      uid,
      employeeName: employee.displayName ?? "",
      dateKey,
      viewerUids: viewerUidsFor(employee),
      ...(checkInAt !== null ? { checkInAt: Timestamp.fromMillis(checkInAt) } : {}),
      ...(checkOutAt !== null ? { checkOutAt: Timestamp.fromMillis(checkOutAt) } : {}),
      status: inMs !== null && outMs !== null ? "completed" : inMs !== null ? "checked_in" : "incomplete",
      workedMinutes: inMs !== null && outMs !== null ? Math.round((outMs - inMs) / 60_000) : null,
      corrected: true,
      needsReview: false,
      corrections: FieldValue.arrayUnion({
        by: caller.uid,
        byName: caller.name,
        at: Timestamp.now(),
        reason,
        previousCheckInAt: prevIn === null ? null : Timestamp.fromMillis(prevIn),
        previousCheckOutAt: prevOut === null ? null : Timestamp.fromMillis(prevOut),
      }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  await audit(caller, "attendance.corrected", "attendanceDay", `${uid}_${dateKey}`, { checkInAt, checkOutAt, reason });
  await notifyUsers([uid], {
    title: "Attendance corrected",
    body: `Your attendance for ${dateKey} was corrected by ${caller.name}: ${reason}`,
    type: "attendance_corrected",
  });
  return { ok: true };
});
