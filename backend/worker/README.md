# OCR worker

The single-process worker claims queued OCR jobs from SQLite and calls the
server-side document-understanding integration. External API credentials must be
provided through environment variables.
