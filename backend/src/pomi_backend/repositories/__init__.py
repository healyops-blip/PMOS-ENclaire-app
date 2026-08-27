"""Persistence repositories."""

from pomi_backend.repositories.auth import AuthRepository
from pomi_backend.repositories.documents import DocumentRepository
from pomi_backend.repositories.health import (
    MedicationDailyRepository,
    MedicationEventRepository,
    MedicationRepository,
    MenstrualCycleRepository,
    PatientRepository,
    WeightRepository,
)
from pomi_backend.repositories.ocr import OCRRepository
from pomi_backend.repositories.reports import (
    PatientNoteRepository,
    ReportSnapshotRepository,
    ReportSourceRepository,
)

__all__ = [
    "AuthRepository",
    "DocumentRepository",
    "MedicationDailyRepository",
    "MedicationEventRepository",
    "MedicationRepository",
    "MenstrualCycleRepository",
    "OCRRepository",
    "PatientRepository",
    "PatientNoteRepository",
    "ReportSnapshotRepository",
    "ReportSourceRepository",
    "WeightRepository",
]
