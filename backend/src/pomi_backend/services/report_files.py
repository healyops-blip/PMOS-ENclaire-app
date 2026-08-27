"""Authenticated orchestration for private report PDF artifacts."""

from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.api.business import BusinessError
from pomi_backend.db.models import ReportFile, UserAccount
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories import (
    PatientRepository,
    ReportFileRepository,
    ReportSnapshotRepository,
)
from pomi_backend.services.document_storage import private_path

PDF_TEMPLATE_VERSION = "report-pdf-v1"


def pdf_idempotency_key(report_id: str, snapshot_hash: str, template_version: str) -> str:
    value = f"{report_id}\0{snapshot_hash}\0{template_version}".encode()
    return hashlib.sha256(value).hexdigest()


def report_file_data(report_file: ReportFile) -> dict[str, object | None]:
    succeeded = report_file.generation_status == "succeeded"
    return {
        "report_id": report_file.report_id,
        "file_id": report_file.id,
        "generation_status": report_file.generation_status,
        "template_version": report_file.template_version,
        "attempt_count": report_file.attempt_count,
        "file_name": f"pomi-report-{report_file.report_id}.pdf" if succeeded else None,
        "mime_type": "application/pdf" if succeeded else None,
        "file_size_bytes": report_file.file_size_bytes if succeeded else None,
        "file_hash": report_file.file_hash if succeeded else None,
        "generated_at": (
            report_file.generated_at.isoformat() if report_file.generated_at else None
        ),
        # Downloads always use the authenticated fixed endpoint. Never expose storage paths or URLs.
        "download_url": None,
        "download_expires_at": None,
        "failure_reason": report_file.failure_reason,
    }


class ReportFileService:
    def __init__(
        self,
        session: Session,
        account: UserAccount,
        storage_root: Path,
    ) -> None:
        self.session = session
        self.account = account
        self.storage_root = storage_root
        profile = PatientRepository(session).get_or_create(account.uid)
        self.reports = ReportSnapshotRepository(session, profile.patient_id)
        self.files = ReportFileRepository(session, profile.patient_id)

    def create_or_retry(self, report_id: str) -> tuple[ReportFile, bool]:
        report = self._successful_report(report_id)
        if report.snapshot_hash is None or report.snapshot_json is None:
            raise BusinessError(
                "REPORT_SNAPSHOT_UNAVAILABLE",
                "The immutable report snapshot is unavailable.",
                409,
            )
        key = pdf_idempotency_key(report.id, report.snapshot_hash, PDF_TEMPLATE_VERSION)
        existing = self.files.by_idempotency_key(key)
        if existing is not None:
            invalid_success = (
                existing.generation_status == "succeeded"
                and self._verified_private_file(existing) is None
            )
            if existing.generation_status == "failed" or invalid_success:
                self.files.retry(existing, now=datetime.now(UTC))
                self.session.commit()
                self.session.refresh(existing)
            return existing, False

        report_file = ReportFile(
            id=new_uuid(),
            report_id=report.id,
            file_type="pdf",
            template_version=PDF_TEMPLATE_VERSION,
            snapshot_hash=report.snapshot_hash,
            idempotency_key=key,
            generation_status="queued",
        )
        try:
            self.files.add(report_file)
            self.session.commit()
            self.session.refresh(report_file)
            return report_file, True
        except IntegrityError:
            self.session.rollback()
            existing = self.files.by_idempotency_key(key)
            if existing is None:
                raise
            return existing, False

    def status(self, report_id: str) -> ReportFile:
        self._successful_report(report_id)
        report_file = self.files.for_report(report_id, template_version=PDF_TEMPLATE_VERSION)
        if report_file is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "The report PDF task was not found.", 404)
        return report_file

    def download(self, report_id: str) -> tuple[ReportFile, Path]:
        report_file = self.status(report_id)
        if report_file.generation_status != "succeeded" or report_file.storage_path is None:
            raise BusinessError(
                "REPORT_PDF_NOT_READY",
                "The report PDF is not ready for download.",
                409,
                details={"generation_status": report_file.generation_status},
            )
        path = self._verified_private_file(report_file)
        if path is None:
            raise BusinessError(
                "REPORT_PDF_FILE_UNAVAILABLE",
                "The generated report PDF is unavailable. Retry generation.",
                409,
            )
        return report_file, path

    def _verified_private_file(self, report_file: ReportFile) -> Path | None:
        if (
            report_file.storage_path is None
            or report_file.file_size_bytes is None
            or report_file.file_hash is None
        ):
            return None
        try:
            path = private_path(self.storage_root, report_file.storage_path)
        except BusinessError:
            return None
        digest = hashlib.sha256()
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
        if (
            path.stat().st_size != report_file.file_size_bytes
            or digest.hexdigest() != report_file.file_hash
        ):
            return None
        return path

    def _successful_report(self, report_id: str):
        report = self.reports.get(report_id)
        if report is None:
            raise BusinessError("RESOURCE_NOT_FOUND", "The report was not found.", 404)
        if report.report_status != "succeeded":
            raise BusinessError(
                "REPORT_NOT_READY", "Only a successful immutable report can be exported.", 409
            )
        return report
