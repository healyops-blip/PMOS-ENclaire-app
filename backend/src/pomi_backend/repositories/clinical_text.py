"""Patient-scoped confirmed clinical text repositories."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models.clinical_text import ImagingReport, OutpatientRecord
from pomi_backend.db.models.health import PatientProfile
from pomi_backend.db.models.ocr import OCRResult, OCRTask


class ClinicalTextRepository:
    def __init__(self, session: Session, patient_id: str) -> None:
        self.session = session
        self.patient_id = patient_id

    def imaging_by_result(self, result_id: str) -> ImagingReport | None:
        return self.session.scalar(
            select(ImagingReport).where(
                ImagingReport.patient_id == self.patient_id,
                ImagingReport.ocr_result_id == result_id,
            )
        )

    def outpatient_by_result(self, result_id: str) -> OutpatientRecord | None:
        return self.session.scalar(
            select(OutpatientRecord).where(
                OutpatientRecord.patient_id == self.patient_id,
                OutpatientRecord.ocr_result_id == result_id,
            )
        )

    def add_imaging(self, report: ImagingReport) -> ImagingReport:
        if report.patient_id != self.patient_id:
            raise ValueError("imaging report is outside repository scope")
        self._validate_lineage(report)
        self.session.add(report)
        self.session.flush()
        return report

    def add_outpatient(self, record: OutpatientRecord) -> OutpatientRecord:
        if record.patient_id != self.patient_id:
            raise ValueError("outpatient record is outside repository scope")
        self._validate_lineage(record)
        self.session.add(record)
        self.session.flush()
        return record

    def _validate_lineage(self, record: ImagingReport | OutpatientRecord) -> None:
        lineage = self.session.execute(
            select(
                OCRTask.patient_id,
                OCRTask.document_id,
                OCRTask.document_revision_id,
                PatientProfile.account_uid,
            )
            .join(OCRResult, OCRResult.task_id == OCRTask.id)
            .join(PatientProfile, PatientProfile.patient_id == OCRTask.patient_id)
            .where(OCRResult.id == record.ocr_result_id)
        ).one_or_none()
        if lineage != (
            record.patient_id,
            record.document_id,
            record.document_revision_id,
            record.confirmed_by_uid,
        ):
            raise ValueError("clinical record lineage does not match its OCR result")
