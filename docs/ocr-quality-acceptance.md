# OCR release-quality acceptance

## What is automated in this repository

- The deterministic dataset contains 40 synthetic PNGs, ten per material type,
  with SHA-256 and field-level P0/P1/P2 ground truth.
- The evaluator validates the active material JSON Schema, reports priority
  accuracy, critical errors, per-type success/error distributions, and genuine
  model P50/P95. It requires all 40 real-model records before a gate can pass.
- Exact fallback matching uses the immutable revision SHA-256, user-selected
  material type, and `pomi-demo-fallback-v1`. Only network, timeout, or provider
  unavailability failures are eligible. A refusal leaves the original failed
  task unchanged.
- Accepted fallback creates the same editable OCR result used by the normal
  confirmation flows. Task, every confirmation page, and material detail stay
  visibly labelled as demo fallback.
  The audit stores trigger reason, version, selector, timestamp, and confirmer.
- Backend tests cover wrong hash/type/version, ineligible errors, cross-UID
  access, explicit decline, duplicate acceptance, schema gates, and fallback
  exclusion. Flutter tests cover the explicit dialog and persistent badge.

Run locally:

```powershell
$env:PYTHONPATH = (Resolve-Path backend/src).Path
python -m pytest backend/tests -W error -q
python backend/scripts/run_ocr_quality_evaluation.py `
  --dataset backend/evaluation/ocr_quality/dataset.json `
  --predictions backend/evaluation/ocr_quality/offline-perfect-predictions.json `
  --output runtime/ocr-quality-offline.json `
  --enforce
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

The offline-perfect run validates only the scoring machinery. It must never be
reported as Qwen3-VL accuracy or model latency.

## Release gates

The real `--run-qwen` record must contain all 40 samples and pass: Schema 100%,
P0 >= 95%, P1 >= 90%, P2 >= 80%, and zero critical errors in drug name, dose,
frequency, test name, numeric value, or unit. Fallback records are excluded from
accuracy, success, and latency. Archive the model, prompt/schema versions,
execution time, dataset manifest hash, and generated JSON report.

Operational aggregation is available without loading file bytes, OCR text, or
medical field values:

```powershell
python backend/scripts/ocr_operational_metrics.py
```

It reports success rate, real-model P50/P95, backlog, expired-lease anomalies,
status counts, and error categories; fallback tasks are separately counted and
excluded from real-model metrics.

## Android golden paths (external execution required)

For every material type, record manual type selection; camera, gallery, and
single-page PDF upload; first external-processing consent; queue/processing;
background/resume; original comparison; edits; confirmation; formal-data query;
and revision/source trace. The order path additionally records old/new medicine
comparison, every user decision, version replacement, and event history. Never
auto-stop an existing medicine merely because it is absent from a new order.

Repeat with timeout, invalid Schema response, worker restart before and during a
provider call, duplicate taps, manual retry, weak network, and idempotency. Verify
an arbitrary file and every hash/type/version mismatch cannot use fallback; an
eligible synthetic file still requires confirmation. Under a second UID, verify
document, file stream, task, draft, confirmation, and formal records all return
not found or forbidden.

Current honest status:

- Real Qwen3-VL 40-sample evaluation: **NOT RUN** (server key and authorized
  evaluation window required).
- Android emulator golden paths: **NOT RUN**.
- Physical Android device golden paths: **NOT RUN**.

Copy and complete the JSON templates under
`backend/evaluation/ocr_quality/records/`. A release reviewer must reject any
record that omits device identity, app commit/APK hash, evidence paths, model and
prompt/schema versions, or execution time.

## Privacy boundary

Only synthetic materials are authorized here. The Qwen key remains in a
server-side environment variable. Logs and acceptance evidence must not contain
passwords, sessions, Authorization headers, file bodies, OCR full text, model
requests/responses, or medical values. Before any real patient material is used,
complete a separate privacy/consent review covering vendor retention, data
residency, access, deletion, and the application's retention policy.
