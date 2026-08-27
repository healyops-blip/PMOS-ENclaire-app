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

- `POST /api/auth/register` creates an account but does not automatically log in.
- `POST /api/auth/login` returns an opaque `session_id` once.
- `GET /api/auth/me` requires `Authorization: Bearer <session_id>`.

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
