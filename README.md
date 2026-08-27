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

## Local Web Preview with smoke data

The local Preview uses an in-memory smoke API. It does not start, proxy to, or
depend on a backend service. Login, registration, onboarding, and the main app
can therefore be reviewed without network access.

```bash
flutter build web \
  --dart-define=POMI_SMOKE_MODE=true
python3 tools/web_preview_proxy.py --root build/web
```

Open `http://127.0.0.1:3001`. Smoke data is reset when the Preview is rebuilt or
the browser app is reloaded. Omit `POMI_SMOKE_MODE` in Android and production
builds so they continue to use the configured real API.

## Quality checks

Run the same core checks used by GitHub Actions:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```
