"""Patient-scoped persistence for confirmed laboratory observations."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models.labs import LabObservation


class LabObservationRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def add(self, observation: LabObservation) -> LabObservation:
        if observation.patient_id != self.patient_id:
            raise ValueError("observation does not match repository scope")
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
