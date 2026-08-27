# Backend

This directory contains the FastAPI service, SQLite migrations, OCR worker, and
backend tests described by the Pomi technical plan.

Runtime databases, uploads, reports, logs, backups, and secrets are not committed.
Use environment variables for production configuration and external API keys.

## API contracts

- 认证接口与 Session 约定：
  [`../docs/backend-api.md`](../docs/backend-api.md)
- 全部 P0 前后端分工与字段说明：
  [`../docs/frontend-backend-integration.md`](../docs/frontend-backend-integration.md)
- 全部 P0 机器可读契约：
  [`../contracts/openapi/pomi-api-v1.yaml`](../contracts/openapi/pomi-api-v1.yaml)

业务接口使用 `success/data/request_id/error` 信封；现有认证接口继续保持直接
响应兼容。接口路径、方法和参数以总 OpenAPI、运行代码及测试共同约束。

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

在另一个终端启动可恢复的 OCR/PDF 队列：

```bash
cd backend
pomi-worker
```

本地默认 `POMI_OCR_MODE=mock`。接入 Qwen 时，仅在后端服务器配置
`POMI_OCR_MODE=qwen`、`POMI_QWEN_API_URL`、`POMI_QWEN_API_KEY` 和
`POMI_QWEN_MODEL`。原件与 PDF 保存在 `POMI_STORAGE_ROOT` 下，不作为静态目录公开。

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
pomi-admin reset-password ACCOUNT_NAME
```

`seed-accounts` idempotently creates `first-time-user` and `returning-user`.
`reset-password` changes the hash and revokes every active Session for the
account. Neither operation is exposed as an HTTP endpoint.

## Implemented P0 modules

- 患者引导/画像、Dashboard、不可覆盖的用药事件、每日三状态、经期和体重；
- 私有医疗材料、不可变修订和鉴权文件流；
- 可恢复 OCR 任务、Draft 2020-12 Schema 校验、字段确认与正式记录入库；
- 用药对账、确定性规则审计接口、患者自述、不可变报告快照、来源追溯与 PDF。

SQLite 是 P0 正式数据源。OCR 与 PDF 必须由单进程 `pomi-worker` 领取，不能使用
FastAPI `BackgroundTasks`。
