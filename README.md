# PMOS ENclaire App

PMOS ENclaire mobile application built with Flutter for iOS and Android.

The Flutter client and Supabase backend assets live in this repository. See
[`docs/architecture.md`](docs/architecture.md) for directory boundaries and
security rules.

## Repository layout

- `lib/`: Flutter application code
- `test/`: Flutter unit and widget tests
- `android/` and `ios/`: native host projects
- `supabase/`: database migrations and server-side Edge Functions
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

## Quality checks

Run the same core checks used by GitHub Actions:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```
