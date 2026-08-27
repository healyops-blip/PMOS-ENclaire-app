"""Exact-match registry for synthetic demo OCR fallback results."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from pomi_backend.db.models import OCRFallbackUse, OCRTask

FALLBACK_DATA_VERSION = "pomi-demo-fallback-v1"
DEMO_FILE_HASHES = {
    "lab_report": "7386657b8caea45de4425904e32039271d8312720df07fcac63e8cc6eca5bc07",
    "medical_order": "0ba81f6e0bb9fef2f80be2cf981ca9d262113df0fc234b7a1e23b35323b6e461",
    "imaging_text_report": "d6ca521240a8af1755abee3e4157b2dd89ae9678cf495c0adab669fb7fcc14f6",
    "outpatient_record": "230ca95031d8e1ad75ac58a59024f716785f200b6a5ee78ba1dbca189e8d4ce1",
}
ALLOWED_FAILURE_CATEGORIES = frozenset({"network", "timeout", "provider_unavailable"})


@dataclass(frozen=True, slots=True)
class FallbackMatch:
    data_version: str
    payload: dict[str, Any]


def fallback_match(file_hash: str, material_type: str, data_version: str) -> FallbackMatch | None:
    """Return a copy only when hash, user-selected type, and version all match."""

    payload = _REGISTRY.get((file_hash.casefold(), material_type, data_version))
    return None if payload is None else FallbackMatch(data_version, deepcopy(payload))


def mark_fallback_confirmed(
    session: Session, task: OCRTask, *, uid: str, confirmed_at: datetime
) -> None:
    """Attach the human confirmer to fallback audit in the confirmation transaction."""

    if task.result_source != "fallback":
        return
    audit = session.scalar(select(OCRFallbackUse).where(OCRFallbackUse.task_id == task.id))
    if audit is not None:
        audit.confirmed_by_uid = uid
        audit.confirmed_at = confirmed_at


def _payload(draft: dict[str, Any], fields: list[tuple[str, Any]]) -> dict[str, Any]:
    return {
        "draft": draft,
        "fields": [
            {
                "path": path,
                "source_text": str(value),
                "value": value,
                "confidence": 1.0,
                "uncertainty_reason": "Synthetic demo fallback; not live model output.",
                "source_region": None,
            }
            for path, value in fields
        ],
    }


_REGISTRY = {
    (DEMO_FILE_HASHES["lab_report"], "lab_report", FALLBACK_DATA_VERSION): _payload(
        {
            "facility": "POMI SYNTHETIC CLINIC 01",
            "report_date": "2026-07-01",
            "items": [
                {
                    "name": "LH",
                    "value": 4.1,
                    "unit": "IU/L",
                    "reference_range": None,
                    "report_date": "2026-07-01",
                }
            ],
        },
        [("items.0.name", "LH"), ("items.0.value", 4.1), ("items.0.unit", "IU/L")],
    ),
    (DEMO_FILE_HASHES["medical_order"], "medical_order", FALLBACK_DATA_VERSION): _payload(
        {
            "facility": "POMI SYNTHETIC CLINIC 01",
            "order_date": "2026-07-01",
            "order_text": "METFORMIN-1 500 mg twice daily",
            "medications": [
                {
                    "drug_name": "METFORMIN-1",
                    "specification": "500 mg/tablet",
                    "dosage_value": 500,
                    "dosage_unit": "mg",
                    "frequency": "twice daily",
                    "course": "28 days",
                    "route": "oral",
                    "instructions": "Take after meals",
                    "raw_order_text": "METFORMIN-1 500 mg twice daily",
                    "explicitly_stopped": False,
                }
            ],
        },
        [
            ("medications.0.drug_name", "METFORMIN-1"),
            ("medications.0.dosage_value", 500),
            ("medications.0.dosage_unit", "mg"),
            ("medications.0.frequency", "twice daily"),
        ],
    ),
    (
        DEMO_FILE_HASHES["imaging_text_report"],
        "imaging_text_report",
        FALLBACK_DATA_VERSION,
    ): _payload(
        {
            "facility": "POMI SYNTHETIC CLINIC 01",
            "examination_name": "Pelvic ultrasound",
            "body_part": "Pelvis",
            "examination_date": "2026-07-01",
            "report_date": "2026-07-01",
            "modality": "US",
            "findings": "Synthetic finding 1: bilateral ovaries visualized.",
            "impression": "Synthetic impression 1: no acute finding.",
        },
        [
            ("examination_name", "Pelvic ultrasound"),
            ("findings", "Synthetic finding 1: bilateral ovaries visualized."),
            ("impression", "Synthetic impression 1: no acute finding."),
        ],
    ),
    (DEMO_FILE_HASHES["outpatient_record"], "outpatient_record", FALLBACK_DATA_VERSION): _payload(
        {
            "facility": "POMI SYNTHETIC CLINIC 01",
            "department": "Endocrinology",
            "doctor_name": "Demo Doctor 1",
            "visit_date": "2026-07-01",
            "chief_complaint": "Irregular cycles",
            "diagnosis_summary": "Synthetic diagnosis 1: irregular cycle.",
            "treatment_plan": "Record symptoms",
            "medical_advice": "Synthetic advice 1: follow up in four weeks.",
        },
        [
            ("visit_date", "2026-07-01"),
            ("diagnosis_summary", "Synthetic diagnosis 1: irregular cycle."),
            ("medical_advice", "Synthetic advice 1: follow up in four weeks."),
        ],
    ),
}
