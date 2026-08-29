#!/usr/bin/env bash
# Dev server entry for Kimi Work preview: forwards CLI host/port args
# to Flutter's web-server and points the app at the local FastAPI backend.
set -euo pipefail

HOST="0.0.0.0"
PORT="7100"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host|--hostname)
      HOST="$2"; shift 2 ;;
    --host=*|--hostname=*)
      HOST="${1#*=}"; shift ;;
    --port)
      PORT="$2"; shift 2 ;;
    --port=*)
      PORT="${1#*=}"; shift ;;
    *)
      shift ;;
  esac
done

cd "$(dirname "$0")/.."

exec flutter run -d web-server \
  --web-hostname "$HOST" \
  --web-port "$PORT" \
  --dart-define=POMI_API_BASE_URL=http://localhost:8000/api
