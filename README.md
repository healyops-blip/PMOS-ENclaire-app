# PMOS ENclaire App

PMOS ENclaire mobile application built with Flutter for iOS and Android, with a
FastAPI and SQLite backend in the same repository. See
[`docs/architecture.md`](docs/architecture.md) for directory boundaries and
security rules, and [`docs/ui-guidelines.md`](docs/ui-guidelines.md) for Flutter
visual and layout rules.

## POMI

把散落的检查单、用药与周期记录，整理成患者和医生都能直接查看的健康报告。
POMI 结合 AI 资料识别、可追溯的数据汇总和趋势展示，帮助用户准备每一次复诊。

<p align="center">
  <img src="docs/images/pomi-landing-page.png" alt="POMI 产品首页" width="100%" />
</p>

<p align="center">
  <img src="docs/images/pomi-app-dashboard.png" alt="POMI 移动端首页与用药看板" width="46%" />
  <img src="docs/images/pomi-fpg-trend.png" alt="POMI 空腹血糖趋势界面" width="46%" />
</p>

核心体验包括：拍照或上传医疗资料、OCR 后确认入库、指标趋势追踪、用药记录，以及可分享的医生版就诊报告。

## Repository layout

- `lib/`: Flutter application code
- `test/`: Flutter unit and widget tests
- `android/` and `ios/`: native host projects
- `backend/`: FastAPI API, SQLite migrations, and the OCR worker
- `contracts/`: OpenAPI and JSON Schema contracts shared across components
- `deploy/`: Nginx and systemd deployment assets
- `docs/`: architecture, API, UI, privacy, and technical decisions
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
