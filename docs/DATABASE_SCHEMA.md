# Firestore schema

All business writes go through Cloud Functions (`backend/functions/src`). Clients only read, except marking their own notifications as read. Timestamps are Firestore `Timestamp`s unless noted; `dateKey` is `YYYY-MM-DD` in organization time (Asia/Karachi, UTC+5).

`viewerUids` = `[managerUid, supervisorUid]` of the employee, denormalized at write time so rules and queries can scope team access.

| Collection | Key fields |
|---|---|
| `users/{uid}` | displayName, email, authEmail, phone (normalized digits), photoPath, role (`employee`/`supervisor`/`manager`/`hr`/`admin`), accountStatus (`pending`/`active`/`rejected`/`disabled`), activeDeviceId/Model, pendingDeviceId/Model, employeeCode, designation, departmentId, managerUid, supervisorUid, assignedSiteIds[], reviewComment, requestedAt, createdAt, updatedAt |
| `phoneIndex/{phone}` | uid, authEmail — backend only; enforces unique phone and phone login |
| `fcmTokens/{uid}` | tokens[] (max 5) — backend only |
| `deviceRequests/{id}` | uid, employeeName, deviceId, deviceModel, previousDeviceId, reason, status, reviewedBy, comment, createdAt |
| `sites/{siteId}` | name, address, latitude, longitude, radiusM, isActive |
| `departments/{id}` | name, isActive |
| `config/policy` | leave / attendance / tracking / photos / sites sections (see `logic/policyModel.ts`) |
| `attendanceEvents/{eventId}` | uid, type (`check_in`/`check_out`), dateKey, deviceTime, serverReceivedAt, latitude, longitude, accuracyM, isMocked, siteId, distanceM, insideGeofence, biometricPassed, deviceId, flags[], applied, reviewStatus (`none`/`pending`/`accepted`/`rejected`), managerUid, viewerUids |
| `attendanceDays/{uid}_{dateKey}` | uid, employeeName, dateKey, checkInAt, checkOutAt, check*EventId, siteId, status (`checked_in`/`completed`/`incomplete`/`missing_checkout`), workedMinutes, flags[], needsReview, corrected, corrections[], viewerUids |
| `liveLocations/{uid}` | latest latitude/longitude/accuracyM, capturedAt (device), receivedAt (server), isTracking, insideGeofence, siteId, viewerUids |
| `locationPoints/{pointId}` | uid, dateKey, latitude, longitude, accuracyM, capturedAt, receivedAt, viewerUids — purged after `tracking.locationRetentionDays` |
| `fieldPhotos/{photoId}` | uid, siteId, storagePath, caption, source (`camera`/`gallery`), metadataVerified, capturedAt, uploadedAt, latitude, longitude, viewerUids |
| `leaveRequests/{id}` | uid, leaveType (`sick`/`emergency`/`half_day`/`other`), startDate, endDate, days, halfDayPeriod, reason, attachmentPaths[], status, decisions[] {role, uid, name, decision, comment, at}, managerUid, viewerUids |
| `notifications/{id}` | recipientUid, title, body, type, data, read, createdAt |
| `auditLogs/{id}` | actorUid, actorName, action, targetType, targetId, metadata, createdAt |

Event and location point IDs are generated on the phone (UUID), so retries after offline periods are idempotent.

## Storage paths
- `employee-photos/{uid}/profile.jpg`
- `field-photos/{uid}/{photoId}.jpg`
- `leave-attachments/{uid}/{fileId}.{ext}` (images or PDF)
