# Backend

This directory contains the FastAPI service, SQLite migrations, OCR worker, and
backend tests described by the Pomi technical plan.

Runtime databases, uploads, reports, logs, backups, and secrets are not committed.
Use environment variables for production configuration and external API keys.

## API contracts

- OCR task, Worker, retry, and Flutter polling contract:
  [`../docs/ocr-pipeline.md`](../docs/ocr-pipeline.md)

- 已经实现并通过测试的认证接口：
  [`../docs/backend-api.md`](../docs/backend-api.md)
- 全部 P0 前后端分工与字段说明：
  [`../docs/frontend-backend-integration.md`](../docs/frontend-backend-integration.md)
- 全部 P0 机器可读契约：
  [`../contracts/openapi/pomi-api-v1.yaml`](../contracts/openapi/pomi-api-v1.yaml)

已实现接口以运行代码、测试和 `docs/backend-api.md` 为准；扩展总契约时不得
改变现有认证字段。尚未实现的模块根据总 OpenAPI 开发，并在同一 PR 更新
Pydantic Schema、Flutter DTO 和契约测试。

## Local setup

Python 3.12 or newer is required.

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m alembic upgrade head
pytest
ruff check .
uvicorn pomi_backend.main:app --reload
```

The default database path is `backend/runtime/pomi.db`. Set
`POMI_DATABASE_URL` to use another SQLite path or a PostgreSQL connection later.

## OCR worker

FastAPI creates and reads OCR tasks but never executes model calls inside a request.
Run `pomi-ocr-worker` as a separate single-process service. It claims work through
expiring SQLite leases and can resume a task whose worker stopped before the provider
call. If a worker stops while a provider request is in flight, the task becomes
`timed_out` instead of silently resending protected medical data.

Qwen3-VL configuration is server-only: `POMI_OCR_API_KEY`, `POMI_OCR_API_BASE_URL`,
`POMI_OCR_MODEL`, `POMI_OCR_TIMEOUT_SECONDS`, and `POMI_OCR_LEASE_SECONDS`. Never put
the key in Flutter, a database row, logs, or source control. The Worker refuses to
start until the API key is set and the lease is at least 30 seconds longer than the
provider timeout.
After loading the key from a local secret source (without placing it in shell history),
run `pomi-ocr-worker --once` for one local claim or omit `--once` for the polling loop.

## Current authentication persistence

- `user_account` uses an internal numeric key and exposes a separate UUID `uid`.
- `user_session` references the account `uid` and stores only `session_hash`.
- SQLite foreign keys are enabled for every application connection.
- All schema changes are versioned under `migrations/`.

## Authentication API

- `POST /api/auth/register` creates an account but does not automatically log in.
- `POST /api/auth/login` returns an opaque `session_id` once.
- `GET /api/auth/me` requires `Authorization: Bearer <session_id>`.
- `POST /api/auth/logout` revokes the supplied Session and is idempotent.
- `GET /health/live` checks the API process; `GET /health/ready` also checks SQLite.

The server stores only Argon2 password hashes and SHA-256 Session credential
hashes. Interactive API docs are available locally and disabled when
`POMI_ENVIRONMENT=production`.

Authentication tuning is configured through environment variables:

- `POMI_SESSION_TTL_SECONDS`
- `POMI_ARGON2_TIME_COST`
- `POMI_ARGON2_MEMORY_COST_KIB`
- `POMI_ARGON2_PARALLELISM`
- `POMI_AUTH_RATE_LIMIT_ATTEMPTS`
- `POMI_AUTH_RATE_LIMIT_WINDOW_SECONDS`

## Server-local account administration

Run migrations before the administrative commands. Passwords are read without
terminal echo unless the corresponding one-shot environment variable is set.

```bash
pomi-admin seed-accounts
pomi-admin seed-health
pomi-admin purge-documents
pomi-admin reset-password ACCOUNT_NAME
```

`seed-accounts` idempotently creates `first-time-user` and `returning-user`.
`seed-health` keeps the first-time user's health records empty and idempotently
adds synthetic medications, events, daily statuses, cycles, and weights for the
returning user. Run it only after `seed-accounts`.
`purge-documents` removes expired physical files for soft-deleted documents after
the seven-day retention period; immutable report references must be registered by
the report module before enabling its scheduled timer.
`reset-password` changes the hash and revokes every active Session for the
account. Neither operation is exposed as an HTTP endpoint.

## Medication API

- `GET /api/medication-catalog` returns the versioned, authenticated Pomi static
  candidate library. `q` searches names and aliases and `category` filters it.
  Candidates are for recognition/display only; they never create a regimen or
  reminder by themselves.
- `GET/POST /api/medications` reads grouped current medications or creates one.
- A manually created medication may include `standard_drug_id` from the catalog;
  a user-defined medication leaves it null. Both cases are persisted in the
  patient-owned `medication` table, separate from `medication_catalog`.
- `PUT /api/medications/{id}` adjusts, pauses, resumes, or stops a medication.
- Dose/frequency adjustments create a new row linked by `replaces_medication_id`.
- `GET /api/medications/{id}/events` returns the immutable cross-version timeline.
- `PUT /api/medications/{id}/daily-status` accepts the server business date and
  the preceding six natural days. Earlier history is read-only and future dates
  are rejected with stable business error codes.
- Repeating an identical daily-state `PUT` preserves its operation timestamp;
  changing it records the latest UTC operation time and acting account UID.
- `GET /api/medication-daily` dynamically returns `unrecorded` without storing it
  and marks every item with the server-derived `editable` flag.
- Daily writes return `month_summary`, `business_date`, and `editable_from` so the
  app can refresh Dashboard totals without inferring the server timezone.

The server business date uses `POMI_BUSINESS_TIMEZONE` (`Asia/Singapore` by
default). Daily totals exclude future dates and derive expected days from every
start, pause, resume, adjustment, and stop boundary.

## Medical-order confirmation and reconciliation

- Qwen3-VL produces one `medical_order` draft containing `order_text` and a
  `medications` array. Each item keeps drug name, specification, single dose,
  unit, frequency, course, route, instructions, source text, and explicit-stop
  evidence separate.
- `POST /api/ocr/tasks/{task_id}/confirm` requires every extracted item with
  `confirmed: true`. Missing drug name, positive dose, unit, frequency, date, or
  raw source text rejects the whole request. Repeating a successful confirmation
  returns the same `medical_order` rows.
- Standard drug IDs use the exact controlled alias table in
  `services/orders.py`. Unknown names stay `review_required`; no fuzzy or model
  guess is persisted.
- `POST /api/medication-reconciliations` accepts `ocr_task_id` and applies rule
  version `pomi-med-reconcile-v1`. Suggestions are `unchanged`, `adjusted`,
  `added`, `stopped`, `uncertain`, or `manual_review`.
- `GET/PUT /api/medication-reconciliations/{id}` are patient scoped. PUT requires
  one decision for every item and applies accepted changes in one transaction.
  Omitted old drugs are always `uncertain` and never automatically stopped.
  Explicit stopping additionally requires a date and source.

## Remaining P0 backend rules

Implement Router, Pydantic Schema, Service, and Repository separately. SQLite is
the P0 formal data source; uploaded originals and generated PDFs stay in a private
server directory. OCR and PDF work must be claimed by the single-process worker,
not FastAPI `BackgroundTasks`.
