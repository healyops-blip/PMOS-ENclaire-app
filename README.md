# PMOS ENclaire App

PMOS ENclaire mobile application built with Flutter for iOS and Android, with a
FastAPI and SQLite backend in the same repository. See
[`docs/architecture.md`](docs/architecture.md) for directory boundaries and
security rules.

## Repository layout

- `lib/`: Flutter application code
- `test/`: Flutter unit and widget tests
- `android/` and `ios/`: native host projects
- `backend/`: FastAPI API, SQLite migrations, and the OCR worker
- `contracts/`: OpenAPI and JSON Schema contracts shared across components
- `deploy/`: Nginx and systemd deployment assets
- `docs/`: architecture, API, privacy, and technical decisions
- `.github/workflows/`: required CI and security checks

## Requirements

- Flutter 3.47.1 (stable)
- Dart 3.13.1
- VS Code with the recommended Flutter and Dart extensions
- Xcode for iOS development
- Android SDK for Android development

## Get started

```bash
flutter pub get
flutter run
```

## UI demo scope

The current Flutter UI uses local demo data and includes:

- fixed new/existing demo-account routes;
- three-step patient onboarding;
- dashboard and medication three-state interactions;
- medication management and reminder screens;
- menstrual-cycle calendar with add, edit, completion, deletion, and trend states;
- visit records and source traceability;
- upload, OCR review, draft confirmation, and medication reconciliation;
- report generation and three-layer report navigation;
- doctor KYC, signature, and test-chain certification states;
- patient profile and authorization entry points.

The cycle screen now has a repository boundary and the authenticated FastAPI cycle
history API is implemented; the demo shell injects local cycle data until Flutter
authentication owns a live Session. Other Flutter screens still use local demo
data. Real OCR, identity providers, blockchain nodes, and PDF export remain
unimplemented.

## Quality checks

Run the same core checks used by GitHub Actions:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```

## Frontend/backend integration

- Human-readable task and field guide:
  [`docs/frontend-backend-integration.md`](docs/frontend-backend-integration.md)
- Machine-readable API contract:
  [`contracts/openapi/pomi-api-v1.yaml`](contracts/openapi/pomi-api-v1.yaml)

See `THIRD_PARTY_NOTICES.md` for UI dependency licenses.
