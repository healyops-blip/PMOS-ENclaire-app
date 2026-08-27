# Backend

This directory contains the FastAPI service, SQLite migrations, OCR worker, and
backend tests described by the Pomi technical plan.

Runtime databases, uploads, reports, logs, backups, and secrets are not committed.
Use environment variables for production configuration and external API keys.

## API contracts

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
pomi-admin reset-password ACCOUNT_NAME
```

`seed-accounts` idempotently creates `first-time-user` and `returning-user`.
`seed-health` keeps the first-time user's health records empty and idempotently
adds synthetic medications, events, daily statuses, cycles, and weights for the
returning user. Run it only after `seed-accounts`.
`reset-password` changes the hash and revokes every active Session for the
account. Neither operation is exposed as an HTTP endpoint.

## Remaining P0 backend rules

Implement Router, Pydantic Schema, Service, and Repository separately. SQLite is
the P0 formal data source; uploaded originals and generated PDFs stay in a private
server directory. OCR and PDF work must be claimed by the single-process worker,
not FastAPI `BackgroundTasks`.
