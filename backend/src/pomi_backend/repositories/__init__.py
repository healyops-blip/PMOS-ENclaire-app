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
from pomi_backend.repositories.labs import LabObservationRepository
from pomi_backend.repositories.ocr import OCRRepository

__all__ = [
    "AuthRepository",
    "DocumentRepository",
    "LabObservationRepository",
    "MedicationDailyRepository",
    "MedicationEventRepository",
    "MedicationRepository",
    "MenstrualCycleRepository",
    "OCRRepository",
    "PatientRepository",
    "WeightRepository",
]
