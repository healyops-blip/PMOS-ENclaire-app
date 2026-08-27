# Backend

This directory contains the FastAPI service, SQLite migrations, OCR worker, and
backend tests described by the Pomi technical plan.

Runtime databases, uploads, reports, logs, backups, and secrets are not committed.
Use environment variables for production configuration and external API keys.

Before backend implementation, use these two documents as the contract:

- [`../docs/frontend-backend-integration.md`](../docs/frontend-backend-integration.md)
- [`../contracts/openapi/pomi-api-v1.yaml`](../contracts/openapi/pomi-api-v1.yaml)

Implement Router, Pydantic Schema, Service, and Repository separately. SQLite is
the P0 formal data source; uploaded originals and generated PDFs stay in a private
server directory. OCR and PDF work must be claimed by the single-process worker,
not FastAPI `BackgroundTasks`.
