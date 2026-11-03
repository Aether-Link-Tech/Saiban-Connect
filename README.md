# SAIBAAN Connect — Project Scaffold

Android-first Flutter application for SAIBAAN Development Organization.

**Stack:** Flutter/Dart, Firebase Authentication, Cloud Firestore, Cloud Storage, Cloud Functions (TypeScript), Firebase Cloud Messaging, SQLite offline queue.

This archive is a structured starter scaffold, not a finished production application. Configure Firebase, implement the TODO workflows, test on target devices, and complete security/privacy review before deployment.

## Setup
1. Install Flutter stable, Node.js LTS and Firebase CLI.
2. In `mobile/`, run `flutter pub get`.
3. Run `flutterfire configure` and generate platform Firebase options.
4. In `backend/functions/`, run `npm install`.
5. Review `docs/` and complete the unresolved business rules before coding.
6. Run Firebase emulators with `firebase emulators:start`.

Never commit service-account JSON, signing keys, production `.env` files or real employee data.
