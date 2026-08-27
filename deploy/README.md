# Pomi lightweight-server deployment

This runbook targets Ubuntu with 2 CPU cores, 2 GB memory, and a 40 GB system
disk. It deploys one FastAPI process behind Nginx at
`api.healy1012-ops.top`. Run commands from a reviewed release checkout; do not
copy uncommitted files to the server.

Install the small set of operating-system dependencies first:

```bash
sudo apt-get update
sudo apt-get install nginx python3-venv sqlite3 util-linux logrotate certbot python3-certbot-nginx
```

## Directory and permission model

| Path | Purpose | Owner and mode |
| --- | --- | --- |
| `/opt/pomi/releases/<commit>` | immutable application release | `root:root`, not writable by service |
| `/opt/pomi/current` | symlink to active release | `root:root` |
| `/etc/pomi/pomi.env` | runtime configuration and secrets | `root:root`, `0600` |
| `/etc/pomi/pomi-ocr.env` | Worker-only OCR API key | `root:root`, `0600` |
| `/var/lib/pomi/pomi.db` | SQLite database | `pomi:pomi`, `0600` |
| `/var/lib/pomi/storage` | private document storage root | `pomi:pomi`, `0700` |
| `/var/lib/pomi/uploads` | private uploaded files | `pomi:pomi`, `0700` |
| `/var/lib/pomi/reports` | generated reports | `pomi:pomi`, `0700` |
| `/var/lib/pomi/storage/report-pdfs` | private generated report PDFs | `pomi:pomi`, `0700` |
| `/var/log/pomi` | FastAPI logs | `pomi:pomi`, `0750` |
| `/var/backups/pomi` | SQLite backups | `pomi:pomi`, `0700` |

Create the unprivileged service account and state directories:

```bash
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin pomi
sudo install -d -o root -g root -m 0755 /opt/pomi/releases /etc/pomi
sudo install -d -o pomi -g pomi -m 0700 /var/lib/pomi /var/lib/pomi/storage /var/lib/pomi/uploads /var/lib/pomi/reports /var/backups/pomi
sudo install -d -o pomi -g pomi -m 0750 /var/log/pomi
```

Copy `deploy/systemd/pomi.env.example` to `/etc/pomi/pomi.env` and
`deploy/systemd/pomi-ocr.env.example` to `/etc/pomi/pomi-ocr.env`, then review
them and enforce ownership and mode. Put the OCR API key only in the second file;
do not put initial or reset passwords in either persistent file.

```bash
sudo chown root:root /etc/pomi/pomi.env
sudo chmod 0600 /etc/pomi/pomi.env
sudo chown root:root /etc/pomi/pomi-ocr.env
sudo chmod 0600 /etc/pomi/pomi-ocr.env
```

## First deployment

For a release stored at `/opt/pomi/releases/<commit>`:

```bash
cd /opt/pomi/releases/<commit>/backend
python3 -m venv .venv
.venv/bin/python -m pip install .
sudo -u pomi install -m 0600 /dev/null /var/lib/pomi/pomi.db
sudo -u pomi env POMI_DATABASE_URL=sqlite:////var/lib/pomi/pomi.db .venv/bin/python -m alembic upgrade head
sudo ln -sfn /opt/pomi/releases/<commit> /opt/pomi/current
```

Install Nginx, systemd, backup, and logrotate files using their directory
README instructions. Validate before starting:

```bash
sudo cp /opt/pomi/current/deploy/logrotate/pomi /etc/logrotate.d/pomi
sudo chown root:root /etc/logrotate.d/pomi
sudo chmod 0644 /etc/logrotate.d/pomi
sudo nginx -t
sudo systemd-analyze verify /etc/systemd/system/pomi-api.service /etc/systemd/system/pomi-ocr-worker.service /etc/systemd/system/pomi-report-pdf-worker.service /etc/systemd/system/pomi-backup.service /etc/systemd/system/pomi-backup.timer
sudo logrotate --debug /etc/logrotate.d/pomi
sudo systemctl daemon-reload
sudo systemctl enable --now pomi-api.service pomi-ocr-worker.service pomi-report-pdf-worker.service pomi-backup.timer
curl --fail --silent https://api.healy1012-ops.top/health/ready
```

Confirm the public certificate and renewal path without printing secrets:

```bash
openssl s_client -connect api.healy1012-ops.top:443 -servername api.healy1012-ops.top </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
sudo certbot renew --dry-run
```

Initialize the two product accounts interactively so passwords are hidden and
do not enter shell history:

```bash
cd /opt/pomi/current/backend
sudo -u pomi /opt/pomi/current/backend/.venv/bin/pomi-admin seed-accounts
```

The command is idempotent. It creates `first-time-user` with
`onboarding_completed=false` and `returning-user` with
`onboarding_completed=true`. Product-provided simulated health data can later
reference the returning account UID.

## Local administrator password reset

There is no HTTP reset endpoint and no universal password. Run this only on the
server; the new password is entered without terminal echo:

```bash
sudo -u pomi /opt/pomi/current/backend/.venv/bin/pomi-admin reset-password ACCOUNT_NAME
```

The password update and revocation of every active Session for that account are
committed together.

## Upgrade

1. Put the reviewed commit in a new `/opt/pomi/releases/<commit>` directory.
2. Create its virtual environment and install the backend.
3. Run `sudo systemctl start pomi-backup.service` and verify success.
4. Stop `pomi-ocr-worker.service` and `pomi-report-pdf-worker.service` before migrating if installed.
5. Run Alembic from the new release against `/var/lib/pomi/pomi.db`.
6. Atomically update `/opt/pomi/current` to the new release.
7. Run `sudo systemctl restart pomi-api.service pomi-ocr-worker.service pomi-report-pdf-worker.service`.
8. Verify `/health/ready`, then run the smoke test as the service user. It asks
   for both initial-account passwords without terminal echo:

   ```bash
   sudo -u pomi /opt/pomi/current/backend/.venv/bin/python /opt/pomi/current/deploy/scripts/auth_smoke.py
   ```

9. Keep the previous release until the observation window ends.

## Rollback and database restore

If the schema remains backward-compatible, point `/opt/pomi/current` to the
previous release and restart `pomi-api.service`. Do not run an Alembic downgrade
on production without reviewing its data-loss behavior.

To restore SQLite after a confirmed database failure:

1. Stop `pomi-api.service` and any worker that writes the database.
2. From `/var/backups/pomi`, verify the selected backup with
   `sha256sum --check pomi-<timestamp>.sqlite3.sha256` and
   `sqlite3 pomi-<timestamp>.sqlite3 'PRAGMA integrity_check;'`.
3. Move the damaged database and its `-wal`/`-shm` files to an incident folder.
4. Copy the verified backup to `/var/lib/pomi/pomi.db` with owner `pomi:pomi`
   and mode `0600`.
5. Start the service and verify `/health/ready` and the authentication smoke test.

Never overwrite the only copy of a damaged database; preserve it for analysis.

## Reboot persistence acceptance

After the first deployment or a unit-file change, perform one controlled server
reboot and retain the command output in the release record:

```bash
sudo reboot
```

After reconnecting, verify that both units were enabled and recovered without a
manual start:

```bash
systemctl is-enabled pomi-api.service pomi-ocr-worker.service pomi-report-pdf-worker.service pomi-backup.timer
systemctl is-active pomi-api.service pomi-ocr-worker.service pomi-report-pdf-worker.service pomi-backup.timer
curl --fail --silent https://api.healy1012-ops.top/health/ready
sudo -u pomi /opt/pomi/current/backend/.venv/bin/python /opt/pomi/current/deploy/scripts/auth_smoke.py
```

## Troubleshooting

```bash
sudo systemctl status pomi-api.service
sudo journalctl -u pomi-api.service --since '30 minutes ago'
sudo tail -n 200 /var/log/pomi/api-error.log
sudo nginx -t
sudo tail -n 200 /var/log/nginx/pomi-api-error.log
sudo -u pomi sqlite3 /var/lib/pomi/pomi.db 'PRAGMA integrity_check;'
sudo systemctl list-timers pomi-backup.timer
sudo systemctl start pomi-backup.service
```

Do not print `/etc/pomi/pomi.env`, Authorization headers, passwords, or Session
credentials while troubleshooting.
