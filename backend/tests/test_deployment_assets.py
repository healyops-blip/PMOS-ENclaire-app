from __future__ import annotations

import hashlib
import re
from importlib.resources import files
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def read(relative_path: str) -> str:
    return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")


def test_systemd_service_is_loopback_only_and_hardened() -> None:
    service = read("deploy/systemd/pomi-api.service")
    assert "--host 127.0.0.1" in service
    assert "--port 8010" in service
    assert "--workers 1" in service
    assert "--reload" not in service
    assert "--forwarded-allow-ips=127.0.0.1" in service
    assert "Restart=on-failure" in service
    assert "NoNewPrivileges=true" in service
    assert "ProtectSystem=strict" in service
    assert "EnvironmentFile=/etc/pomi/pomi.env" in service

    worker = read("deploy/systemd/pomi-ocr-worker.service")
    assert "pomi-ocr-worker --poll-seconds 1" in worker
    assert "NoNewPrivileges=true" in worker
    assert "ProtectSystem=strict" in worker
    assert "EnvironmentFile=/etc/pomi/pomi.env" in worker
    assert "EnvironmentFile=/etc/pomi/pomi-ocr.env" in worker
    assert "--workers" not in worker

    api = read("deploy/systemd/pomi-api.service")
    assert "pomi-ocr.env" not in api

    pdf_worker = read("deploy/systemd/pomi-report-pdf-worker.service")
    assert "pomi-report-pdf-worker --poll-seconds 1" in pdf_worker
    assert "NoNewPrivileges=true" in pdf_worker
    assert "ProtectSystem=strict" in pdf_worker
    assert "EnvironmentFile=/etc/pomi/pomi.env" in pdf_worker
    assert "RestrictAddressFamilies=AF_UNIX" in pdf_worker
    systemd_readme = read("deploy/systemd/README.md")
    assert systemd_readme.count("pomi-report-pdf-worker.service") >= 3


def test_nginx_has_tls_limits_and_local_upstream() -> None:
    nginx = read("deploy/nginx/pomi-api.conf")
    bootstrap = read("deploy/nginx/pomi-api-http.conf")
    assert "server 127.0.0.1:8010" in nginx
    assert "api.healy1012-ops.top" in nginx
    assert "ssl_certificate /etc/letsencrypt/" in nginx
    assert "ssl_protocols TLSv1.2 TLSv1.3" in nginx
    assert "client_max_body_size" in nginx
    assert "limit_req zone=pomi_auth" in nginx
    assert "proxy_set_header X-Forwarded-Proto https" in nginx
    assert "Strict-Transport-Security" in nginx
    assert nginx.count("proxy_hide_header Server") == 3
    assert "ssl_certificate" not in bootstrap
    assert "root /var/www/certbot" in bootstrap
    assert "proxy_pass http://127.0.0.1:8010" in bootstrap


def test_environment_example_and_repository_contain_no_seed_passwords() -> None:
    environment_example = read("deploy/systemd/pomi.env.example")
    ocr_environment_example = read("deploy/systemd/pomi-ocr.env.example")
    assert "PASSWORD=" not in environment_example
    assert "SECRET=" not in environment_example
    assert "POMI_OCR_API_KEY=" not in environment_example
    assert "POMI_OCR_API_KEY=" in ocr_environment_example

    tracked_text = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in REPOSITORY_ROOT.rglob("*")
        if path.is_file()
        and path.resolve() != Path(__file__).resolve()
        and ".git" not in path.parts
        and ".venv" not in path.parts
        and path.suffix in {".py", ".md", ".yml", ".yaml", ".example", ".service"}
    )
    assert not re.search(r"POMI_(FIRST_TIME|RETURNING)_ACCOUNT_PASSWORD=\S+", tracked_text)
    assert not re.search(r"POMI_RESET_PASSWORD=\S+", tracked_text)


def test_report_pdf_font_and_license_are_packaged_deployment_assets() -> None:
    package = files("pomi_backend")
    font = package.joinpath("assets/fonts/wqy-microhei.ttc")
    license_file = package.joinpath("assets/fonts/LICENSE_Apache2.txt")
    origin = package.joinpath("assets/fonts/FONT_ORIGIN.md")
    assert font.is_file()
    assert 4_000_000 < font.stat().st_size < 10_000_000
    font_hash = hashlib.sha256(font.read_bytes()).hexdigest()
    assert "Apache License" in license_file.read_text(encoding="utf-8")
    origin_text = origin.read_text(encoding="utf-8")
    assert "WenQuanYi Micro Hei" in origin_text
    assert font_hash == "e4bca8df123ce01b104780f576ea1a58b9a5ff1662a91124b6d3180cb6c88212"
    assert font_hash in origin_text

    project = read("backend/pyproject.toml")
    for name in ("wqy-microhei.ttc", "LICENSE_Apache2.txt", "FONT_ORIGIN.md"):
        assert project.count(name) >= 2


def test_backup_logrotate_and_runbook_are_present() -> None:
    backup = read("deploy/scripts/backup_sqlite.sh")
    smoke = read("deploy/scripts/auth_smoke.py")
    logrotate = read("deploy/logrotate/pomi")
    runbook = read("deploy/README.md")
    assert "PRAGMA integrity_check" in backup
    assert ".backup" in backup
    assert "flock" in backup
    assert "-mtime" in backup
    assert "umask 0077" in backup
    assert "reset-password" in smoke
    assert "POMI_FIRST_TIME_ACCOUNT_PASSWORD" in smoke
    assert "POMI_RETURNING_ACCOUNT_PASSWORD" in smoke
    assert "onboarding_completed" in smoke
    assert "rotate 14" in logrotate
    for section in ("## Upgrade", "## Rollback", "## Troubleshooting"):
        assert section in runbook
