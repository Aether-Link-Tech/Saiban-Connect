# Proposed Firestore schema

| Collection | Key fields |
|---|---|
| `users/{uid}` | displayName, email, phone, role, accountStatus, createdAt |
| `employees/{uid}` | employeeCode, departmentId, designation, photoPath, assignedSiteIds, managerUid, supervisorUid |
| `deviceRegistrations/{deviceId}` | uid, platform, status, approvedBy, approvedAt |
| `sites/{siteId}` | name, address, latitude, longitude, geofenceRadiusM, isActive |
| `attendanceEvents/{eventId}` | uid, eventType, deviceTime, serverReceivedAt, latitude, longitude, siteId, biometricPassed, reviewFlags |
| `attendanceDays/{uid_date}` | uid, dateKey, checkInEventId, checkOutEventId, status |
| `locationPoints/{pointId}` | uid, sessionId, latitude, longitude, accuracyM, capturedAt, receivedAt |
| `fieldPhotos/{photoId}` | uid, siteId, storagePath, caption, capturedAt, uploadedAt, location |
| `leaveRequests/{requestId}` | uid, leaveType, startDate, endDate, reason, attachmentPaths, approvalSteps, status |
| `notifications/{id}` | recipientUid, title, body, type, readAt, createdAt |
| `departments/{id}` | name, isActive |
| `auditLogs/{id}` | actorUid, action, targetType, targetId, createdAt, metadata |

Use stable IDs and server timestamps. Do not trust client-written roles or approval states. Use pagination/subcollections for high-volume GPS records. Define retention before production.
