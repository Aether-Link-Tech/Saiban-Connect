# Architecture

Flutter mobile client → Firebase Authentication → Firestore / Storage → Cloud Functions → FCM.

SQLite stores offline attendance events and queued location samples. A sync service uploads them when connectivity returns. The server is authoritative for roles, approvals and audit logs.

## Frontend layers
- Presentation: screens, widgets, navigation and state.
- Domain: entities, repository contracts and use cases.
- Data: Firebase adapters, SQLite adapters and repositories.
- Core/shared: theme, permissions, logging, errors and reusable widgets.

## Backend responsibilities
Registration and device approvals; attendance validation and idempotent sync; leave workflow evaluation; role/site assignment; audit logs; notification delivery.

## Important constraints
Use OS biometric APIs; never store fingerprint/face templates. Offline device timestamps and GPS are not tamper-proof. Show stale location with its last-updated time, not as live. Background location requires permissions, disclosure, battery testing and store-policy review.
