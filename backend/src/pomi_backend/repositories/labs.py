"""Patient-scoped persistence for confirmed laboratory observations."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models.health import PatientProfile
from pomi_backend.db.models.labs import LabObservation
from pomi_backend.db.models.ocr import OCRResult, OCRTask


class LabObservationRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def add(self, observation: LabObservation) -> LabObservation:
        if observation.patient_id != self.patient_id:
            raise ValueError("observation does not match repository scope")
        lineage = self.session.execute(
            select(
                OCRTask.patient_id,
                OCRTask.document_id,
                OCRTask.document_revision_id,
                PatientProfile.account_uid,
            )
            .join(OCRResult, OCRResult.task_id == OCRTask.id)
            .join(PatientProfile, PatientProfile.patient_id == OCRTask.patient_id)
            .where(OCRResult.id == observation.ocr_result_id)
        ).one_or_none()
        if lineage != (
            observation.patient_id,
            observation.document_id,
            observation.document_revision_id,
            observation.confirmed_by_uid,
        ):
            raise ValueError("observation lineage does not match its OCR result")
        self.session.add(observation)
        self.session.flush()
        return observation

    def get(self, observation_id: str) -> LabObservation | None:
        return self.session.scalar(
            select(LabObservation).where(
                LabObservation.id == observation_id,
                LabObservation.patient_id == self.patient_id,
            )
        )

    def for_result(self, ocr_result_id: str) -> list[LabObservation]:
        return list(
            self.session.scalars(
                select(LabObservation)
                .where(
                    LabObservation.patient_id == self.patient_id,
                    LabObservation.ocr_result_id == ocr_result_id,
                )
                .order_by(LabObservation.item_index)
            )
        )

    def list(self) -> list[LabObservation]:
        return list(
            self.session.scalars(
                select(LabObservation)
                .where(LabObservation.patient_id == self.patient_id)
                .order_by(LabObservation.trend_date.desc(), LabObservation.confirmed_at.desc())
            )
        )
