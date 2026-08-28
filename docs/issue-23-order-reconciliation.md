# Issue 23: medical-order confirmation and reconciliation

## Flutter confirmation contract

Read `validated_draft.orders` and show the original `source_text` next
to editable `drug_name`, `specification`, `dosage_value`, `dosage_unit`,
`frequency`, `duration`, `route`, `instruction`, and `prescribed_at`. Every item is
checked separately. Submit stays disabled while any drug name, positive dose,
unit, frequency, date, or raw source text is missing. Keep local edits after an
API failure.

```json
POST /api/ocr/tasks/{task_id}/confirm
{"result_id":"ocr-result-uuid","expected_revision_id":"document-revision-uuid","items":[{"source_index":0,"confirmed":true,"source_text":"Metformin 500 mg twice daily","drug_name":"Metformin","specification":"500 mg","dosage_value":500,"dosage_unit":"mg","frequency":"twice daily","duration":"30 days","route":"oral","instruction":"after meals","prescribed_at":"2026-08-27","explicitly_stopped":false}]}
```

The response has `items` containing the persisted formal orders, `reused`, and
`p0_evaluation` for drug-name/dose/frequency safety-critical field accuracy.
Unknown drug aliases have `standard_drug_id: null` and `review_required: true`.

## Reconciliation contract

Create with `{"ocr_task_id":"..."}`. Each response item contains
`old_medication`, `new_medical_order`, `match_basis`, and one of six suggestions:
`unchanged`, `adjusted`, `added`, `stopped`, `uncertain`, or `manual_review`.

```json
PUT /api/medication-reconciliations/{id}
{"decisions":[{"item_id":"...","decision":"accept"}]}
```

Allowed decisions are `accept`, `keep_current`, and `reject`. Flutter collects a
decision for every item before PUT. An accepted `stopped` item also needs
`stop_date` and `stop_source`. A `manual_review` item cannot be automatically
accepted. An `uncertain` item never stops a medication; it records no change.

All endpoints are scoped to the authenticated UID. Confirmation is idempotent by
OCR task/result item. Reconciliation creation is idempotent by patient/task, and
execution returns the existing executed result only when the retry payload is identical;
a different replay receives `409`. Accepted medication
changes and their events commit in a single database transaction.
