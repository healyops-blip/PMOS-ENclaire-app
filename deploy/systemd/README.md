# systemd deployment

- `pomi-api.service` starts one Uvicorn worker on `127.0.0.1:8010` and restarts it after
  failures. One worker is intentional while authentication rate limits are kept
  in process memory.
- `pomi-backup.service` creates a consistent SQLite backup.
- `pomi-backup.timer` runs the backup daily and catches missed runs after boot.
- `pomi-ocr-worker.service` runs exactly one independently restartable lease-based OCR worker.
- `pomi-report-pdf-worker.service` runs the recoverable, network-isolated static PDF worker.
- `pomi.env.example` documents non-secret production settings.

Install units after creating the directories and environment file described in
`deploy/README.md`:

```bash
sudo cp /opt/pomi/current/deploy/systemd/pomi-api.service /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-backup.service /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-backup.timer /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-ocr-worker.service /etc/systemd/system/
sudo cp /opt/pomi/current/deploy/systemd/pomi-report-pdf-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pomi-api.service pomi-ocr-worker.service pomi-report-pdf-worker.service pomi-backup.timer
```

The real `/etc/pomi/pomi.env` must be owned by root with mode `0600`. Never add
initial passwords, reset passwords, or external API keys to the example file.
Set `POMI_OCR_API_KEY` only in that root-owned file. The API and Worker may share
SQLite and private storage, but only the Worker receives and uses the key.
