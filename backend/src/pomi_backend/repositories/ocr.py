"""Persistence and SQLite-safe lease claiming for OCR tasks."""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import and_, or_, select, update
from sqlalchemy.orm import Session

from pomi_backend.db.models.ocr import OCRFieldResult, OCRResult, OCRTask


class OCRRepository:
    def __init__(self, session: Session, patient_id: str | None = None) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, task_id: str) -> OCRTask | None:
        statement = select(OCRTask).where(OCRTask.id == task_id)
        if self.patient_id is not None:
            statement = statement.where(OCRTask.patient_id == self.patient_id)
        return self.session.scalar(statement)

    def by_deduplication_key(self, key: str) -> OCRTask | None:
        statement = select(OCRTask).where(OCRTask.deduplication_key == key)
        if self.patient_id is not None:
            statement = statement.where(OCRTask.patient_id == self.patient_id)
        return self.session.scalar(statement)

    def retry_for(self, task_id: str) -> OCRTask | None:
        statement = select(OCRTask).where(OCRTask.parent_task_id == task_id)
        if self.patient_id is not None:
            statement = statement.where(OCRTask.patient_id == self.patient_id)
        return self.session.scalar(statement)

    def result(self, task_id: str) -> OCRResult | None:
        task = self.get(task_id)
        if task is None:
            return None
        return self.session.scalar(select(OCRResult).where(OCRResult.task_id == task.id))

    def fields(self, result_id: str) -> list[OCRFieldResult]:
        return list(
            self.session.scalars(
                select(OCRFieldResult)
                .where(OCRFieldResult.result_id == result_id)
                .order_by(OCRFieldResult.field_path)
            )
        )

    def add_task(self, task: OCRTask) -> None:
        if self.patient_id is not None and task.patient_id != self.patient_id:
            raise ValueError("task does not match repository scope")
        self.session.add(task)
        self.session.flush()

    def claim(self, *, worker_id: str, now: datetime, lease_seconds: int) -> OCRTask | None:
        """Atomically claim one due task; compatible with multiple SQLite processes."""

        candidate_id = self.session.scalar(
            select(OCRTask.id)
            .where(
                OCRTask.available_at <= now,
                or_(
                    OCRTask.status == "queued",
                    and_(
                        OCRTask.status == "processing",
                        OCRTask.lease_expires_at <= now,
                        OCRTask.provider_call_started_at.is_(None),
                    ),
                ),
            )
            .order_by(OCRTask.created_at, OCRTask.id)
            .limit(1)
        )
        if candidate_id is None:
            return None
        lease_until = now + timedelta(seconds=lease_seconds)
        claimed = self.session.execute(
            update(OCRTask)
            .where(
                OCRTask.id == candidate_id,
                OCRTask.available_at <= now,
                or_(
                    OCRTask.status == "queued",
                    and_(
                        OCRTask.status == "processing",
                        OCRTask.lease_expires_at <= now,
                        OCRTask.provider_call_started_at.is_(None),
                    ),
                ),
            )
            .values(
                status="processing",
                lease_owner=worker_id,
                lease_expires_at=lease_until,
                started_at=now,
                updated_at=now,
            )
        )
        if claimed.rowcount != 1:
            self.session.rollback()
            return None
        self.session.commit()
        return self.session.get(OCRTask, candidate_id)

    def expire_ambiguous_calls(self, *, now: datetime) -> int:
        """Never replay a provider request whose completion is unknowable after a crash."""

        expired = list(
            self.session.scalars(
                select(OCRTask).where(
                    OCRTask.status == "processing",
                    OCRTask.lease_expires_at <= now,
                    OCRTask.provider_call_started_at.is_not(None),
                )
            )
        )
        for task in expired:
            task.status = "timed_out"
            task.error_category = "timeout"
            task.error_code = "OCR_PROVIDER_OUTCOME_UNKNOWN"
            task.error_message = "Worker stopped while the provider request was in flight."
            task.finished_at = now
            task.lease_owner = None
            task.lease_expires_at = None
            task.updated_at = now
        if expired:
            self.session.commit()
        return len(expired)
