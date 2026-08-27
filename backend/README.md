# Backend

This directory contains the FastAPI service, SQLite migrations, OCR worker, and
backend tests described by the Pomi technical plan.

Runtime databases, uploads, reports, logs, backups, and secrets are not committed.
Use environment variables for production configuration and external API keys.

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

完整的中文请求字段、响应示例、错误码和 Flutter 联调说明见
[`docs/backend-api.md`](../docs/backend-api.md)。

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
pomi-admin reset-password ACCOUNT_NAME
```

`seed-accounts` idempotently creates `first-time-user` and `returning-user`.
`reset-password` changes the hash and revokes every active Session for the
account. Neither operation is exposed as an HTTP endpoint.
