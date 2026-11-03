# SAIBAAN Connect

Employee attendance and field management app for **SAIBAAN Development Organization**. It's an Android-first Flutter app with a Firebase backend.

| Area | Implementation |
|---|---|
| Registration & login | Self-registration with profile photo, HR/Admin approval, email **or phone** + password, one approved phone per employee with device-change approval |
| Biometric attendance | OS fingerprint/face prompt at check-in and check-out; one check-in/out per day; GPS, site and sync status recorded |
| GPS & geofences | Admin-managed sites with radius; tracking only between check-in and check-out (foreground service); live location with last-update time for assigned managers |
| Offline | SQLite queue for attendance and location; automatic sync; device time kept separate from server time; anomalies flagged for review |
| Site photos | Camera (gallery optional by policy) to Cloud Storage, linked to employee/site with time and location |
| Leave | Sick / Emergency / Half-day / Other, attachments, Manager + HR + Admin review with configurable approval rule |
| Notifications | FCM push and in-app inbox for registration, device, leave and attendance events |
| Administration | Employees, roles, departments, managers/supervisors, sites, policy settings, attendance corrections, flagged-record review, audit log |

## Repository
- `mobile/`: Flutter app
- `backend/functions/`: Cloud Functions (TypeScript), all trusted business logic
- `backend/*.rules`, `backend/firestore.indexes.json`: security rules and indexes
- `docs/`: architecture, schema, workflows, policies, security checklist
- `scripts/setup_android.ps1`: one-time Android/Firebase setup

## Run everything locally (no cloud account needed)
Requires Node.js, Java 21, Firebase CLI and Flutter.
```
powershell -ExecutionPolicy Bypass -File scripts/start-local.ps1
```
This starts the Firebase emulators, loads demo data and opens the app in Chrome (http://localhost:8686). The emulator dashboard is at http://localhost:4000.

| Login | Role |
|---|---|
| admin@saibaan.demo | Administrator |
| hr@saibaan.demo | HR |
| manager@saibaan.demo | Manager |
| supervisor@saibaan.demo | Supervisor |
| employee@saibaan.demo / employee2@saibaan.demo | Employee |
| newjoiner@saibaan.demo | Pending registration |

All demo accounts use the password `Demo@12345`. You can also sign in with a phone number, e.g. `03000000005`. In the browser, fingerprint and camera are replaced by fallbacks, and push notifications only work on a real phone.

Tests: `npm test` (backend unit tests), `node tools/e2e-emulator.js` (43 end-to-end checks against the emulators), and `flutter test` (18 app tests, including every role's main screens).

## Setup
1. Install Flutter (stable), Android Studio, Node.js 20, Firebase CLI and FlutterFire CLI.
2. Create a Firebase project (Blaze plan, required for Cloud Functions). Enable Email/Password authentication, Firestore, Storage and Cloud Messaging.
3. `powershell -File scripts/setup_android.ps1 -FirebaseProject <project-id>`
4. Deploy the backend:
   ```bash
   cd backend/functions && npm install && npm test
   firebase deploy --only functions,firestore,storage
   ```
5. Register the first administrator in the app, then promote that account:
   `npm run bootstrap-admin -- admin@example.org <project-id>` (from `backend/functions`).
6. As admin, add sites and departments, then approve employee registrations.

For local development, run `firebase emulators:start`.

## Before production
- Confirm the operational policies in `docs/ATTENDANCE_POLICY.md` and `docs/APPROVAL_WORKFLOWS.md` with SAIBAAN, then set them in **Admin → Policy settings**.
- Enable Firebase App Check, test on the agreed Android devices (including battery-optimisation behaviour), and complete the privacy review in `docs/SECURITY_AND_PRIVACY.md`.

Never commit service-account JSON, signing keys, `google-services.json`, `.env` files or real employee data.
