"""Patient-scoped medical-order and reconciliation persistence."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models import (
    MedicalOrder,
    Medication,
    MedicationReconciliation,
    MedicationReconciliationItem,
    OCRResult,
    OCRTask,
    PatientProfile,
)


class MedicalOrderRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def for_task(self, task_id: str) -> list[MedicalOrder]:
        return list(
            self.session.scalars(
                select(MedicalOrder)
                .where(
                    MedicalOrder.patient_id == self.patient_id, MedicalOrder.ocr_task_id == task_id
                )
                .order_by(MedicalOrder.medication_index)
            )
        )

    def add(self, order: MedicalOrder) -> MedicalOrder:
        if order.patient_id != self.patient_id:
            raise ValueError("medical order is outside repository scope")
        lineage = self.session.execute(
            select(
                OCRTask.patient_id,
                OCRTask.document_id,
                OCRTask.document_revision_id,
                OCRTask.id,
                PatientProfile.account_uid,
            )
            .join(OCRResult, OCRResult.task_id == OCRTask.id)
            .join(PatientProfile, PatientProfile.patient_id == OCRTask.patient_id)
            .where(OCRResult.id == order.ocr_result_id)
        ).one_or_none()
        if lineage != (
            order.patient_id,
            order.document_id,
            order.document_revision_id,
            order.ocr_task_id,
            order.confirmed_by_uid,
        ):
            raise ValueError("medical order lineage does not match its OCR result")
        self.session.add(order)
        self.session.flush()
        return order


class ReconciliationRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def get(self, reconciliation_id: str) -> MedicationReconciliation | None:
        return self.session.scalar(
            select(MedicationReconciliation).where(
                MedicationReconciliation.id == reconciliation_id,
                MedicationReconciliation.patient_id == self.patient_id,
            )
        )

    def for_task(self, task_id: str) -> MedicationReconciliation | None:
        return self.session.scalar(
            select(MedicationReconciliation).where(
                MedicationReconciliation.patient_id == self.patient_id,
                MedicationReconciliation.ocr_task_id == task_id,
            )
        )

    def items(self, reconciliation_id: str) -> list[MedicationReconciliationItem]:
        return list(
            self.session.scalars(
                select(MedicationReconciliationItem)
                .where(
                    MedicationReconciliationItem.patient_id == self.patient_id,
                    MedicationReconciliationItem.reconciliation_id == reconciliation_id,
                )
                .order_by(MedicationReconciliationItem.position)
            )
        )

    def add(
        self, reconciliation: MedicationReconciliation, items: list[MedicationReconciliationItem]
    ) -> None:
        if reconciliation.patient_id != self.patient_id or any(
            item.patient_id != self.patient_id for item in items
        ):
            raise ValueError("reconciliation is outside repository scope")
        task_patient = self.session.scalar(
            select(OCRTask.patient_id).where(OCRTask.id == reconciliation.ocr_task_id)
        )
        if task_patient != self.patient_id:
            raise ValueError("reconciliation task is outside repository scope")
        for item in items:
            old_patient = (
                self.session.scalar(
                    select(Medication.patient_id).where(Medication.id == item.old_medication_id)
                )
                if item.old_medication_id
                else self.patient_id
            )
            order_patient = (
                self.session.scalar(
                    select(MedicalOrder.patient_id).where(
                        MedicalOrder.id == item.new_medical_order_id
                    )
                )
                if item.new_medical_order_id
                else self.patient_id
            )
            if (
                item.reconciliation_id != reconciliation.id
                or old_patient != self.patient_id
                or order_patient != self.patient_id
            ):
                raise ValueError("reconciliation item lineage is outside repository scope")
        self.session.add(reconciliation)
        self.session.flush()
        self.session.add_all(items)
        self.session.flush()
