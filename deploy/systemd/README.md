# systemd deployment

- `pomi-api.service` starts one Uvicorn worker on `127.0.0.1:8010` and restarts it after
  failures. One worker is intentional while authentication rate limits are kept
  in process memory.
- `pomi-backup.service` creates a consistent SQLite backup.
- `pomi-backup.timer` runs the backup daily and catches missed runs after boot.
- `pomi-ocr-worker.service` runs exactly one independently restartable lease-based OCR worker.
- `pomi.env.example` documents shared non-secret production settings.
- `pomi-ocr.env.example` documents the Worker-only secret file.

Install units after creating the directories and environment file described in
`deploy/README.md`:

```bash
sudo cp /opt/pomi/current/deploy/systemd/pomi-api.service /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-backup.service /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-backup.timer /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-ocr-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pomi-api.service pomi-backup.timer
# Run this only after /etc/pomi/pomi-ocr.env contains the real API key.
sudo systemctl enable --now pomi-ocr-worker.service
```

The real `/etc/pomi/pomi.env` and `/etc/pomi/pomi-ocr.env` must be owned by root
with mode `0600`. Never add initial passwords, reset passwords, or external API
keys to an example file. Put `POMI_OCR_API_KEY` only in `pomi-ocr.env`; the API and
Worker may share SQLite and private storage, but only the Worker receives the key.
Do not enable the Worker until that key is configured: it intentionally refuses to
start instead of claiming tasks that cannot be processed.
