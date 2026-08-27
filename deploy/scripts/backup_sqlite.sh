#!/usr/bin/env bash
set -euo pipefail
umask 0077

database_path="${POMI_SQLITE_PATH:-/var/lib/pomi/pomi.db}"
backup_directory="${POMI_BACKUP_DIR:-/var/backups/pomi}"
retention_days="${POMI_BACKUP_RETENTION_DAYS:-14}"

if [[ ! "$database_path" =~ ^/[A-Za-z0-9._/-]+$ || "$database_path" == "/" ]]; then
    echo "POMI_SQLITE_PATH must be a safe absolute path" >&2
    exit 2
fi
if [[ ! "$backup_directory" =~ ^/[A-Za-z0-9._/-]+$ || "$backup_directory" == "/" ]]; then
    echo "POMI_BACKUP_DIR must be a safe absolute path" >&2
    exit 2
fi
if [[ ! "$retention_days" =~ ^[0-9]+$ ]]; then
    echo "POMI_BACKUP_RETENTION_DAYS must be a non-negative integer" >&2
    exit 2
fi
if [[ ! -f "$database_path" ]]; then
    echo "SQLite database does not exist: $database_path" >&2
    exit 3
fi

install -d -m 0700 "$backup_directory"
exec 9>"$backup_directory/.backup.lock"
flock -n 9 || exit 0

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
temporary_path="$backup_directory/.pomi-$timestamp.sqlite3.tmp"
final_path="$backup_directory/pomi-$timestamp.sqlite3"
trap 'rm -f "$temporary_path"' EXIT

sqlite3 "$database_path" ".timeout 5000" ".backup '$temporary_path'"
integrity_result="$(sqlite3 "$temporary_path" 'PRAGMA integrity_check;')"
if [[ "$integrity_result" != "ok" ]]; then
    echo "Backup integrity check failed" >&2
    exit 4
fi

chmod 0600 "$temporary_path"
mv "$temporary_path" "$final_path"
sha256sum "$final_path" >"$final_path.sha256"
chmod 0600 "$final_path.sha256"

find "$backup_directory" -maxdepth 1 -type f \
    \( -name 'pomi-*.sqlite3' -o -name 'pomi-*.sqlite3.sha256' \) \
    -mtime "+$retention_days" -delete

echo "SQLite backup completed: $final_path"
