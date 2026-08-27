"""Generate 40 synthetic OCR PNGs plus field-level ground truth."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / "evaluation" / "ocr_quality"
MATERIAL_TYPES = (
    "lab_report",
    "medical_order",
    "imaging_text_report",
    "outpatient_record",
)


def _case(material_type: str, index: int) -> tuple[list[str], dict, list[dict]]:
    facility = f"POMI SYNTHETIC CLINIC {index:02d}"
    date = f"2026-07-{index:02d}"
    if material_type == "lab_report":
        name, value, unit = "LH", round(4.0 + index / 10, 1), "IU/L"
        draft = {
            "facility": facility,
            "report_date": date,
            "items": [{"name": name, "value": value, "unit": unit}],
        }
        lines = [facility, "LAB REPORT", f"DATE {date}", f"{name} {value} {unit}"]
        fields = [
            _gold("draft.items.0.name", name, "P0", critical=True),
            _gold("draft.items.0.value", value, "P0", critical=True),
            _gold("draft.items.0.unit", unit, "P0", critical=True),
            _gold("draft.report_date", date, "P1"),
            _gold("draft.facility", facility, "P2"),
        ]
    elif material_type == "medical_order":
        name, dose, unit, frequency = f"METFORMIN-{index}", 500, "mg", "twice daily"
        draft = {
            "facility": facility,
            "order_date": date,
            "order_text": f"{name} {dose} {unit} {frequency}",
            "medications": [
                {
                    "drug_name": name,
                    "specification": "500 mg/tablet",
                    "dosage_value": dose,
                    "dosage_unit": unit,
                    "frequency": frequency,
                    "course": "28 days",
                    "route": "oral",
                    "instructions": "Take after meals",
                    "raw_order_text": f"{name} {dose} {unit} {frequency}",
                    "explicitly_stopped": False,
                }
            ],
        }
        lines = [
            facility,
            "MEDICAL ORDER",
            f"DATE {date}",
            f"DRUG {name}",
            "SPECIFICATION 500 mg/tablet",
            f"DOSE {dose} {unit}",
            f"FREQUENCY {frequency}",
            "COURSE 28 days",
            "ROUTE oral",
            "INSTRUCTIONS Take after meals",
        ]
        fields = [
            _gold("draft.medications.0.drug_name", name, "P0", critical=True),
            _gold("draft.medications.0.dosage_value", dose, "P0", critical=True),
            _gold("draft.medications.0.dosage_unit", unit, "P0", critical=True),
            _gold("draft.medications.0.frequency", frequency, "P0", critical=True),
            _gold("draft.order_date", date, "P1"),
            _gold("draft.medications.0.route", "oral", "P2"),
        ]
    elif material_type == "imaging_text_report":
        findings = f"Synthetic finding {index}: bilateral ovaries visualized."
        impression = f"Synthetic impression {index}: no acute finding."
        draft = {
            "facility": facility,
            "examination_name": "Pelvic ultrasound",
            "body_part": "Pelvis",
            "examination_date": date,
            "report_date": date,
            "modality": "US",
            "findings": findings,
            "impression": impression,
        }
        lines = [
            facility,
            "IMAGING REPORT",
            "EXAM Pelvic ultrasound",
            "BODY Pelvis",
            "MODALITY US",
            f"EXAM DATE {date}",
            f"REPORT DATE {date}",
            findings,
            impression,
        ]
        fields = [
            _gold("draft.examination_name", "Pelvic ultrasound", "P0", critical=True),
            _gold("draft.findings", findings, "P1"),
            _gold("draft.impression", impression, "P1"),
            _gold("draft.examination_date", date, "P1"),
            _gold("draft.modality", "US", "P2"),
        ]
    else:
        diagnosis = f"Synthetic diagnosis {index}: irregular cycle."
        advice = f"Synthetic advice {index}: follow up in four weeks."
        draft = {
            "facility": facility,
            "department": "Endocrinology",
            "doctor_name": f"Demo Doctor {index}",
            "visit_date": date,
            "chief_complaint": "Irregular cycles",
            "diagnosis_summary": diagnosis,
            "treatment_plan": "Record symptoms",
            "medical_advice": advice,
        }
        lines = [
            facility,
            "OUTPATIENT RECORD",
            "DEPARTMENT Endocrinology",
            f"DOCTOR Demo Doctor {index}",
            f"VISIT {date}",
            "CHIEF COMPLAINT Irregular cycles",
            diagnosis,
            "PLAN Record symptoms",
            advice,
        ]
        fields = [
            _gold("draft.visit_date", date, "P0", critical=True),
            _gold("draft.diagnosis_summary", diagnosis, "P1"),
            _gold("draft.medical_advice", advice, "P1"),
            _gold("draft.department", "Endocrinology", "P2"),
            _gold("draft.facility", facility, "P2"),
        ]
    return lines, draft, fields


def _gold(path: str, expected: object, priority: str, *, critical: bool = False) -> dict:
    return {
        "path": path,
        "expected": expected,
        "priority": priority,
        "allowed_values": [],
        "critical": critical,
        "error_note": "Critical demo-path transcription" if critical else "Exact synthetic text",
    }


def _envelope(draft: dict, fields: list[dict]) -> dict:
    return {
        "draft": draft,
        "fields": [
            {
                "path": item["path"].removeprefix("draft."),
                "source_text": str(item["expected"]),
                "value": item["expected"],
                "confidence": 1.0,
                "uncertainty_reason": None,
                "source_region": None,
            }
            for item in fields
        ],
    }


def main() -> None:
    samples_dir = ROOT / "samples"
    samples_dir.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=24)
    dataset = []
    predictions = []
    for material_type in MATERIAL_TYPES:
        for index in range(1, 11):
            sample_id = f"{material_type}-{index:02d}"
            lines, draft, fields = _case(material_type, index)
            path = samples_dir / f"{sample_id}.png"
            image = Image.new("RGB", (1280, 720), "white")
            draw = ImageDraw.Draw(image)
            draw.rectangle((35, 35, 1245, 685), outline="#7258b5", width=4)
            draw.multiline_text((75, 80), "\n\n".join(lines), font=font, fill="#17131f")
            image.save(path, format="PNG", optimize=True)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            dataset.append(
                {
                    "sample_id": sample_id,
                    "material_type": material_type,
                    "file": f"samples/{path.name}",
                    "sha256": digest,
                    "synthetic": True,
                    "contains_real_patient_data": False,
                    "gold_fields": fields,
                }
            )
            predictions.append(
                {
                    "sample_id": sample_id,
                    "source": "qwen3-vl-offline-perfect-fixture",
                    "status": "succeeded",
                    "duration_ms": 100 + index,
                    "model": "offline-test-double",
                    "prompt_version": "pomi-ocr-v1",
                    "schema_version": "pomi-ocr-schema-v1",
                    "payload": _envelope(draft, fields),
                }
            )
    (ROOT / "dataset.json").write_text(
        json.dumps(dataset, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "offline-perfect-predictions.json").write_text(
        json.dumps(predictions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
