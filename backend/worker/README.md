# OCR worker

The single-process worker claims queued OCR jobs from SQLite and calls the
server-side document-understanding integration. External API credentials must be
provided through environment variables.

# Report PDF worker

`pomi-report-pdf-worker` claims private `report_file` tasks using recoverable
SQLite leases. It verifies the immutable snapshot hash, renders with the CJK
font bundled in the wheel, and atomically writes under `POMI_STORAGE_ROOT`.
It has no network dependency and must not log report or patient field values.

Run one task locally:

```bash
pomi-report-pdf-worker --once
```
