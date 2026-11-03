# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project
SAIBAAN Connect — Android-first Flutter app for SAIBAAN Development Organization (client) built by Aether Link. Employee attendance with device biometrics, GPS/geofence field tracking, offline attendance sync, site photos, leave approvals, push notifications and role-based administration for five roles: Employee, Supervisor, Manager, HR, Administrator.

The signed scope is the proposal (PKR 150,000, Android only). Out of scope unless a change request is approved: iOS release, web admin dashboard, payroll, biometric hardware, central face/fingerprint database, paid map services, SMS/OTP.

## Layout
- `mobile/` — Flutter app (Dart, Riverpod, sqflite, Firebase SDKs)
  - `lib/core/` constants, theme, providers, utils, errors
  - `lib/domain/entities/` models parsed from Firestore
  - `lib/data/` `FunctionsApi` (callable wrapper) and `LocalDb` (SQLite offline queue)
  - `lib/shared/services/` biometric, location, tracking, sync, push, device identity
  - `lib/features/<feature>/presentation/` screens and widgets
- `backend/functions/` — Cloud Functions (TypeScript, Node 20, region `asia-south1`)
  - `src/core/` Firebase init, auth/caller checks, validation, notify, audit, policy loader
  - `src/logic/` **pure** business rules (no Firebase imports) — unit tested in `src/test/`
  - `src/functions/` callable and scheduled functions, exported from `src/index.ts`
- `backend/firestore.rules`, `backend/storage.rules`, `backend/firestore.indexes.json`
- `docs/` architecture, schema, workflows, policy decisions, security checklist

## Commands
```bash
# Everything locally (emulators + demo data + app in Chrome) — no cloud project needed
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1          # add -Test for e2e, -NoApp for backend only
#   Emulator UI http://localhost:4000 · demo logins <role>@saibaan.demo / Demo@12345
#   App: flutter run -d chrome --web-port 8686 --dart-define=USE_EMULATOR=true
cd backend/functions && node tools/e2e-emulator.js   # end-to-end tests (needs fresh emulators + seed)

# Backend
cd backend/functions && npm install
npm test            # tsc + node:test on lib/test
npm run build
firebase emulators:start          # from repo root
npm run bootstrap-admin -- <email> <projectId>   # promote the first administrator

# Mobile
cd mobile && flutter pub get
flutter analyze && flutter test
flutter run
```
First-time Android setup: see `scripts/setup_android.ps1` (runs `flutter create` for platform files, raises minSdk, then `flutterfire configure`).

## Architecture rules
- **The backend is authoritative.** Clients never write business collections; every change goes through a callable function that validates input, checks the caller's role from `users/{uid}` (not just token claims), writes an audit log and sends notifications. Firestore rules allow reads only (plus `notifications.read`).
- Role/status are mirrored to custom claims (`role`, `status`) for security rules. Set claims **before** updating the profile document so the app never sees a status its token lacks; the app refreshes its ID token when they differ.
- Team scoping uses `viewerUids` (`[managerUid, supervisorUid]`) denormalized onto attendance, location, photo and leave records. Queries by managers/supervisors must include `where('viewerUids', arrayContains: uid)` or rules reject them; HR/Admin queries need no filter. Add composite indexes to `firestore.indexes.json` for new query shapes.
- Day keys are `YYYY-MM-DD` in organization time, UTC+5 (`dateKeyOf` in backend, `orgDateKey` in app). Keep both in sync.
- Callable region `asia-south1` must match `AppConstants.functionsRegion`.
- Attendance/location events get UUIDs on the phone and are queued in SQLite; sync is idempotent by ID. Device time and server receipt time are stored separately.
- One approved device per employee (`users.activeDeviceId`); attendance and location calls from any other device are refused.
- Biometrics: use the OS prompt via `local_auth` only. Never store biometric data.
- Location tracking runs only between check-in and check-out (foreground service notification on Android).

## Policies not yet confirmed by the client (proposal §11)
Implemented as configurable defaults in `config/policy` (`backend/functions/src/logic/policyModel.ts`, editable in-app by Admin → Policy settings). Do not hard-code these elsewhere:
leave approval rule, GPS interval, geofence default radius, gallery vs camera photos, biometric fallback, correction roles, location retention. Shifts, working days, holidays, grace periods and late/absence rules are **not implemented** pending client decisions.

## Local / emulator mode
- `--dart-define=USE_EMULATOR=true` (`lib/core/config/env.dart`) points the app at the emulators (project `demo-saibaan`), disables push, and uses the fixed device ID `demo-device-0001` that the seed script approves.
- Web is supported only for local demos: `LocalDb` falls back to in-memory, biometrics report unavailable (seeded policy allows the fallback), uploads use bytes (no `dart:io`).
- Widget tests render real screens per role with `fake_cloud_firestore` via `firestoreOverride` and provider overrides (`test/screens_test.dart`).

## Conventions
- TypeScript strict; validate all callable input with helpers in `core/validate.ts`; throw `HttpsError` with user-readable messages.
- Put decision logic in `src/logic/` and cover it with tests.
- Dart: `flutter_lints`; user-facing errors via `friendlyError()`.
- Commit messages: imperative summary line, body explaining what/why.
- Never commit `google-services.json`, `firebase_options.dart` with production keys, service-account JSON, keystores, `.env` files or real employee data.
