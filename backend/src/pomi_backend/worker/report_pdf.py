"""Recoverable worker for deterministic, snapshot-only report PDF generation."""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import socket
import time
import uuid
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.db.models import ReportFile, ReportSnapshot
from pomi_backend.db.models.auth import utc_now
from pomi_backend.repositories import ReportFileRepository
from pomi_backend.services.report_pdf_renderer import render_report_pdf

logger = logging.getLogger("pomi.report_pdf.worker")


class ReportPdfWorker:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        *,
        storage_root: Path,
        worker_id: str,
        lease_seconds: int = 180,
    ) -> None:
        self.session_factory = session_factory
        self.storage_root = storage_root
        self.worker_id = worker_id
        self.lease_seconds = lease_seconds

    def run_once(self) -> bool:
        with self.session_factory() as session:
            task = ReportFileRepository(session).claim(
                worker_id=self.worker_id,
                now=utc_now(),
                lease_seconds=self.lease_seconds,
            )
            file_id = task.id if task is not None else None
        if file_id is None:
            return False
        self._process(file_id)
        return True

    def _process(self, file_id: str) -> None:
        with self.session_factory() as session:
            report_file = session.get(ReportFile, file_id)
            if not self._owns_lease(report_file):
                return
            report = session.get(ReportSnapshot, report_file.report_id)
            if (
                report is None
                or report.report_status != "succeeded"
                or report.snapshot_json is None
                or report.snapshot_hash is None
                or report.snapshot_hash != report_file.snapshot_hash
                or _snapshot_hash(report.snapshot_json) != report_file.snapshot_hash
            ):
                self._fail(session, report_file, "The immutable report snapshot is unavailable.")
                return
            # This is intentionally the only value passed into the renderer. No current health
            # table or #26 certification data is queried or substituted here.
            frozen_snapshot = json.loads(_stable_json(report.snapshot_json))

        try:
            pdf_bytes = render_report_pdf(frozen_snapshot)
            if not pdf_bytes.startswith(b"%PDF-"):
                raise ValueError("renderer returned a non-PDF payload")
            digest = hashlib.sha256(pdf_bytes).hexdigest()
            relative = (
                Path("report-pdfs")
                / report.patient_id
                / report.id
                / f"{file_id}-{report_file.template_version}.pdf"
            )
            final_path = self._store_atomically(relative, pdf_bytes, file_id)
        except Exception:
            # Never log renderer exception text: it could contain snapshot field values.
            logger.error("file_id=%s status=failed code=REPORT_PDF_RENDER_FAILED", file_id)
            with self.session_factory() as session:
                current = session.get(ReportFile, file_id)
                if self._owns_lease(current):
                    self._fail(session, current, "PDF generation failed. Retry the task.")
            return

        with self.session_factory() as session:
            current = session.get(ReportFile, file_id)
            if not self._owns_lease(current):
                return
            now = utc_now()
            current.storage_path = relative.as_posix()
            current.file_hash = digest
            current.file_size_bytes = len(pdf_bytes)
            current.generation_status = "succeeded"
            current.generated_at = now
            current.failure_reason = None
            current.lease_owner = None
            current.lease_expires_at = None
            current.updated_at = now
            session.commit()
        logger.info(
            "file_id=%s report_id=%s status=succeeded bytes=%s path_scope=private",
            file_id,
            report.id,
            final_path.stat().st_size,
        )

    def _store_atomically(self, relative: Path, data: bytes, file_id: str) -> Path:
        root = self.storage_root.resolve()
        final_path = (root / relative).resolve()
        if root not in final_path.parents:
            raise ValueError("report PDF path escaped private storage")
        temporary_root = root / ".tmp"
        temporary_root.mkdir(parents=True, exist_ok=True)
        temporary = temporary_root / f"{file_id}-{uuid.uuid4().hex}.pdf"
        try:
            with temporary.open("wb") as destination:
                destination.write(data)
                destination.flush()
                os.fsync(destination.fileno())
            final_path.parent.mkdir(parents=True, exist_ok=True)
            os.replace(temporary, final_path)
            return final_path
        finally:
            temporary.unlink(missing_ok=True)

    def _fail(self, session: Session, report_file: ReportFile, reason: str) -> None:
        now = utc_now()
        report_file.generation_status = "failed"
        report_file.failure_reason = reason[:500]
        report_file.lease_owner = None
        report_file.lease_expires_at = None
        report_file.updated_at = now
        session.commit()

    def _owns_lease(self, report_file: ReportFile | None) -> bool:
        return bool(
            report_file is not None
            and report_file.generation_status == "processing"
            and report_file.lease_owner == self.worker_id
        )


def _stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _snapshot_hash(value: Any) -> str:
    return hashlib.sha256(_stable_json(value).encode()).hexdigest()


def build_worker(settings: Settings | None = None) -> ReportPdfWorker:
    active = settings or Settings.from_env()
    engine = build_engine(active.database_url)
    worker_id = f"{socket.gethostname()}-{uuid.uuid4().hex[:8]}"
    return ReportPdfWorker(
        build_session_factory(engine),
        storage_root=active.storage_root,
        worker_id=worker_id,
        lease_seconds=active.report_pdf_lease_seconds,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the POMI report PDF worker")
    parser.add_argument("--once", action="store_true", help="Process at most one task")
    parser.add_argument("--poll-seconds", type=float, default=1.0)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    worker = build_worker()
    if args.once:
        worker.run_once()
        return
    while True:
        if not worker.run_once():
            time.sleep(max(args.poll_seconds, 0.1))


if __name__ == "__main__":
    main()
