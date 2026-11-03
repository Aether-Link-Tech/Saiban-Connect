# Project tree

```text
saibaan_connect_project/
├── mobile/                         Flutter app
│   ├── lib/
│   │   ├── core/                   theme, routing, constants, errors
│   │   ├── data/                   Firebase + SQLite data sources/repositories
│   │   ├── domain/                 entities, contracts, use cases
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── onboarding/
│   │   │   ├── dashboard/
│   │   │   ├── attendance/
│   │   │   ├── field_tracking/
│   │   │   ├── sites/
│   │   │   ├── photos/
│   │   │   ├── leave/
│   │   │   ├── notifications/
│   │   │   ├── employees/
│   │   │   ├── reports/
│   │   │   └── administration/
│   │   └── shared/
│   ├── assets/{images,icons}/
│   ├── test/
│   ├── integration_test/
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
├── backend/
│   ├── functions/src/              trusted TypeScript business logic
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── storage.rules
├── docs/
├── scripts/
├── .github/workflows/
├── firebase.json
└── README.md
```
