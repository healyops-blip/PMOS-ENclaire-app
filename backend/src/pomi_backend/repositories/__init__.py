"""Persistence repositories."""

from pomi_backend.repositories.auth import AuthRepository
from pomi_backend.repositories.clinical_text import ClinicalTextRepository
from pomi_backend.repositories.documents import DocumentRepository
from pomi_backend.repositories.health import (
    MedicationDailyRepository,
    MedicationEventRepository,
    MedicationRepository,
    MenstrualCycleRepository,
    PatientRepository,
    WeightRepository,
)
from pomi_backend.repositories.labs import LabObservationRepository
from pomi_backend.repositories.ocr import OCRRepository
from pomi_backend.repositories.orders import MedicalOrderRepository, ReconciliationRepository
from pomi_backend.repositories.report_files import ReportFileRepository
from pomi_backend.repositories.reports import (
    PatientNoteRepository,
    ReportSnapshotRepository,
    ReportSourceRepository,
)

__all__ = [
    "AuthRepository",
    "ClinicalTextRepository",
    "DocumentRepository",
    "LabObservationRepository",
    "MedicationDailyRepository",
    "MedicationEventRepository",
    "MedicalOrderRepository",
    "MedicationRepository",
    "MenstrualCycleRepository",
    "OCRRepository",
    "PatientRepository",
    "ReconciliationRepository",
    "PatientNoteRepository",
    "ReportSnapshotRepository",
    "ReportFileRepository",
    "ReportSourceRepository",
    "WeightRepository",
]
