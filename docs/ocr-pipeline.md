# OCR task pipeline

## API contract

Every endpoint requires the current Bearer session and returns only the current
patient's tasks. A missing or foreign task, document, or revision returns `404`.

- `POST /api/ocr/tasks` accepts `document_id` and explicit
  `document_revision_id`. It returns `201`; `reused=true` means the
  UID/file-hash/material/prompt/model key already has a task, so the model is not
  called twice.
- `GET /api/ocr/tasks/{task_id}` returns `queued`, `processing`,
  `pending_confirmation`, `confirmed`, `failed`, or `timed_out`, safe error data,
  and the provider attempt history.
- `GET /api/ocr/tasks/{task_id}/result` returns the protected raw provider response,
  validated draft, field-level evidence, and the exact private source revision. It returns
  `409 OCR_RESULT_NOT_READY` before a result exists.
- `POST /api/ocr/tasks/{task_id}/confirm` currently accepts laboratory reports.
  It revalidates edited P0 fields, dates, units, reference ranges, and saves the
  field decisions plus formal observations atomically. An identical replay returns
  the same observation IDs; a different replay is rejected.
- `GET /api/lab-observations` and `GET /api/lab-observations/{id}` expose only the
  current patient's confirmed, revision-traceable observations.
- `POST /api/ocr/tasks/{task_id}/retry` is allowed only for `failed` or
  `timed_out`. It creates one linked manual attempt and returns the same child on
  repeated clicks.

The upload must contain recorded external-processing consent. The worker never writes
drafts into formal tables. Only an explicit successful user confirmation can write a
`lab_observation`.

## Worker and retry rules

FastAPI never uses request-local background work for OCR. `pomi-ocr-worker` claims
one due task with an expiring SQLite lease, loads the explicit immutable revision,
calls an `OCRProvider`, validates the material-specific JSON Schema, applies only
deterministic whitespace cleaning, and persists the result and field evidence in one
transaction.

The four draft schemas use the field sets in the integration contract. Every returned
evidence path must resolve to one actual draft leaf, have the same parsed value, be
unique, and collectively cover all draft leaves. One-page PDFs are rendered to an
image inside the Worker before Qwen3-VL Chat Completions is called; PDF bytes are not
sent through an image URL.

Network, timeout, rate-limit, and temporary provider failures receive at most two
automatic retries. Schema or response-format failures receive at most one. File and
unsupported-format errors do not retry. A lease that expired before the provider call
can be reclaimed. If the worker died while a provider call was in flight, its outcome
is unknowable, so the task becomes `timed_out` instead of duplicating disclosure.

Qwen3-VL is configured only with server environment variables. Provider responses
are persisted in protected storage but never emitted to ordinary logs.
The API key lives only in `/etc/pomi/pomi-ocr.env`; the Worker refuses to start when
the key is absent or when the lease is shorter than the request timeout plus its
safety margin.

## Flutter lifecycle

After upload, Flutter creates a task using the returned document revision. It polls
every two seconds only while the app is resumed and the state is `queued` or
`processing`. Polling stops in the background and resumes immediately in the
foreground. Terminal failures expose manual retry; `pending_confirmation` opens the
matching material confirmation entry without saving formal medical data.

The UI distinguishes file, network, timeout, provider-unavailable,
response-format, and unknown errors.

The laboratory editor shows the original image/PDF revision, confidence and source
evidence beside editable name, value, unit, range, and date fields. Client validation
mirrors the server's P0/unit/date hints, while the server remains authoritative.
Submission failures keep every controller alive for retry. Success replaces the editor
with a summary of the confirmed formal observations and manual-review mapping flags.

## Deterministic laboratory rules

The controlled alias dictionary maps only exact normalized aliases; an unknown name is
never fuzzy-bound to another metric. Numeric values use decimal parsing. Units pass an
explicit whitelist and metric-compatible conversions. Reference bounds are parsed from
closed ranges or one-sided inequalities, converted with the value, and used to compute
`low/normal/high/unknown`; provider abnormal labels are ignored. Trend dates choose
sample, exam, report, then visit date and retain the selected source. Missing optional
dates and ranges remain explicit nulls.
