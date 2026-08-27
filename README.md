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

## Current product scope

The Flutter UI currently includes:

- real account registration, login, secure Session storage, and cold-start recovery;
- three-step patient onboarding;
- dashboard and medication three-state interactions;
- medication management and reminder screens;
- menstrual-cycle calendar and weight trends;
- visit records and source traceability;
- upload, OCR review, draft confirmation, and medication reconciliation;
- report generation and three-layer report navigation;
- doctor KYC, signature, and test-chain certification states;
- patient profile and authorization entry points.

The non-authentication Flutter feature screens still use local demo data and are
the next frontend integration work. FastAPI now implements the contracted P0
patient, tracking, document, OCR, reconciliation, report snapshot, and PDF APIs.
OCR defaults to an explicitly labelled local mock adapter; production Qwen use
requires server-only credentials. Identity-provider and blockchain behavior is
outside the P0 backend boundary.

## Quality checks

Run the same core checks used by GitHub Actions:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

## Frontend/backend integration

- Human-readable task and field guide:
  [`docs/frontend-backend-integration.md`](docs/frontend-backend-integration.md)
- Machine-readable API contract:
  [`contracts/openapi/pomi-api-v1.yaml`](contracts/openapi/pomi-api-v1.yaml)

See `THIRD_PARTY_NOTICES.md` for UI dependency licenses.
