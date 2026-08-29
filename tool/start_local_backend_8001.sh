#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR/backend"

# Keep the provider credential in process memory only. If it is not already
# exported by the caller, read it without echoing or writing it to disk.
if [[ -z "${POMI_OCR_API_KEY:-}" ]]; then
  read -r -s -p "POMI_OCR_API_KEY: " POMI_OCR_API_KEY
  printf '\n' >&2
  export POMI_OCR_API_KEY
fi

export POMI_OCR_API_BASE_URL="${POMI_OCR_API_BASE_URL:-https://api.openai-next.com/v1}"
export POMI_OCR_MODEL="${POMI_OCR_MODEL:-doubao-seed-2-0-mini-260215}"

exec .venv/bin/uvicorn pomi_backend.main:app \
  --host 127.0.0.1 \
  --port 8001
