"""Patient-scoped PDF metadata and SQLite-safe recoverable task claiming."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import and_, or_, select, update
from sqlalchemy.orm import Session

from pomi_backend.db.models import ReportFile, ReportSnapshot


class ReportFileRepository:
    def __init__(self, session: Session, patient_id: str | None = None) -> None:
        self.session = session
        self.patient_id = patient_id

    def _owned_report_ids(self):
        statement = select(ReportSnapshot.id)
        if self.patient_id is not None:
            statement = statement.where(ReportSnapshot.patient_id == self.patient_id)
        return statement

    def get(self, file_id: str) -> ReportFile | None:
        return self.session.scalar(
            select(ReportFile).where(
                ReportFile.id == file_id,
                ReportFile.report_id.in_(self._owned_report_ids()),
            )
        )

    def for_report(self, report_id: str, *, template_version: str) -> ReportFile | None:
        return self.session.scalar(
            select(ReportFile)
            .where(
                ReportFile.report_id == report_id,
                ReportFile.template_version == template_version,
                ReportFile.report_id.in_(self._owned_report_ids()),
            )
            .order_by(ReportFile.created_at.desc(), ReportFile.id.desc())
            .limit(1)
        )

    def by_idempotency_key(self, key: str) -> ReportFile | None:
        return self.session.scalar(
            select(ReportFile).where(
                ReportFile.idempotency_key == key,
                ReportFile.report_id.in_(self._owned_report_ids()),
            )
        )

    def add(self, report_file: ReportFile) -> ReportFile:
        report = self.session.scalar(
            select(ReportSnapshot).where(
                ReportSnapshot.id == report_file.report_id,
                ReportSnapshot.id.in_(self._owned_report_ids()),
                ReportSnapshot.report_status == "succeeded",
            )
        )
        if report is None:
            raise ValueError("report file is outside repository scope")
        self.session.add(report_file)
        self.session.flush()
        return report_file

    def retry(self, report_file: ReportFile, *, now: datetime) -> None:
        if self.get(report_file.id) is None:
            raise ValueError("report file is outside repository scope")
        if report_file.generation_status not in {"failed", "succeeded"}:
            return
        report_file.generation_status = "queued"
        report_file.available_at = now
        report_file.failure_reason = None
        report_file.lease_owner = None
        report_file.lease_expires_at = None
        if report_file.file_hash is not None:
            report_file.storage_path = None
            report_file.file_hash = None
            report_file.file_size_bytes = None
            report_file.generated_at = None
        report_file.updated_at = now
        self.session.flush()

    def claim(self, *, worker_id: str, now: datetime, lease_seconds: int) -> ReportFile | None:
        """Claim queued work or a processing task whose deterministic render lease expired."""

        claimable = or_(
            ReportFile.generation_status == "queued",
            and_(
                ReportFile.generation_status == "processing",
                ReportFile.lease_expires_at <= now,
            ),
        )
        candidate_id = self.session.scalar(
            select(ReportFile.id)
            .where(ReportFile.available_at <= now, claimable)
            .order_by(ReportFile.created_at, ReportFile.id)
            .limit(1)
        )
        if candidate_id is None:
            return None
        lease_until = now + timedelta(seconds=lease_seconds)
        claimed = self.session.execute(
            update(ReportFile)
            .where(ReportFile.id == candidate_id, ReportFile.available_at <= now, claimable)
            .values(
                generation_status="processing",
                attempt_count=ReportFile.attempt_count + 1,
                lease_owner=worker_id,
                lease_expires_at=lease_until,
                started_at=now,
                failure_reason=None,
                updated_at=now,
            )
        )
        if claimed.rowcount != 1:
            self.session.rollback()
            return None
        self.session.commit()
        return self.session.get(ReportFile, candidate_id)
