"""Mock and Qwen3-VL document-understanding provider adapters."""

from __future__ import annotations

import base64
import io
import json
from pathlib import Path
from typing import Any, Protocol

import httpx

from pomi_backend.api.business import BusinessError
from pomi_backend.config import Settings


class DocumentUnderstandingProvider(Protocol):
    result_source: str

    def recognize(self, path: Path, mime_type: str, document_type: str) -> dict[str, Any]: ...


class MockDocumentUnderstandingProvider:
    result_source = "fallback"

    def recognize(self, path: Path, mime_type: str, document_type: str) -> dict[str, Any]:
        del path, mime_type
        results: dict[str, dict[str, Any]] = {
            "lab_report": {
                "hospital_name": "Pomi synthetic development hospital",
                "sample_date": "2026-08-20",
                "report_date": "2026-08-20",
                "items": [
                    {
                        "item_name": "Total testosterone",
                        "item_code": None,
                        "raw_value": "1.42",
                        "numeric_value": 1.42,
                        "raw_unit": "nmol/L",
                        "normalized_unit": "nmol/L",
                        "reference_range_text": "0.29-1.67",
                        "reference_low": 0.29,
                        "reference_high": 1.67,
                    }
                ],
            },
            "medical_order": {
                "hospital_name": "Pomi synthetic development hospital",
                "department_name": "Gynecology",
                "prescribed_at": "2026-08-20",
                "orders": [
                    {
                        "source_text": "Metformin 0.5 g twice daily with meals",
                        "drug_name": "Metformin",
                        "normalized_drug_name": "metformin",
                        "specification": "0.5 g",
                        "dosage_text": "0.5 g",
                        "dosage_value": 0.5,
                        "dosage_unit": "g",
                        "frequency": "twice daily",
                        "duration": None,
                        "route": "oral",
                        "instruction": "with meals",
                    }
                ],
            },
            "imaging_text_report": {
                "examination_name": "Pelvic ultrasound",
                "body_part": "Pelvis",
                "examination_method": "Ultrasound",
                "findings_text": "Synthetic draft; verify against the source file.",
                "conclusion_text": "Synthetic result requiring user confirmation.",
                "examined_at": "2026-08-20",
                "reported_at": "2026-08-20",
            },
            "outpatient_record": {
                "hospital_name": "Pomi synthetic development hospital",
                "department_name": "Gynecology",
                "doctor_name": None,
                "visit_date": "2026-08-20",
                "chief_complaint": "Follow-up preparation",
                "diagnosis_summary": "PCOS follow-up",
                "treatment_plan": "Review medicines and recent tests",
                "medical_advice": "Confirm every field against the source document",
            },
        }
        return results[document_type]


class QwenDocumentUnderstandingProvider:
    result_source = "qwen_api"

    def __init__(self, settings: Settings) -> None:
        if not settings.qwen_api_url or not settings.qwen_api_key:
            raise BusinessError("OCR_PROVIDER_NOT_CONFIGURED", "Qwen OCR is not configured.", 503)
        self.settings = settings

    def recognize(self, path: Path, mime_type: str, document_type: str) -> dict[str, Any]:
        content, model_mime_type = model_image(path, mime_type)
        encoded = base64.b64encode(content).decode("ascii")
        prompt = (
            "Extract this medical document into JSON only. Preserve original text, "
            f"follow the Pomi schema for {document_type}, and never infer missing values."
        )
        payload = {
            "model": self.settings.qwen_model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{model_mime_type};base64,{encoded}"},
                        },
                    ],
                }
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0,
        }
        try:
            response = httpx.post(
                self.settings.qwen_api_url,
                headers={"Authorization": f"Bearer {self.settings.qwen_api_key}"},
                json=payload,
                timeout=httpx.Timeout(90, connect=10),
            )
            response.raise_for_status()
            content_value = response.json()["choices"][0]["message"]["content"]
            if isinstance(content_value, list):
                content_value = "".join(part.get("text", "") for part in content_value)
            cleaned = str(content_value).strip().removeprefix("```json").removesuffix("```")
            return json.loads(cleaned.strip())
        except httpx.TimeoutException as exc:
            raise BusinessError("MODEL_TIMEOUT", "The OCR provider timed out.", 504) from exc
        except (httpx.HTTPError, KeyError, TypeError, json.JSONDecodeError) as exc:
            raise BusinessError(
                "INVALID_MODEL_JSON", "The OCR provider returned invalid data.", 502
            ) from exc


def provider_for(settings: Settings) -> DocumentUnderstandingProvider:
    if settings.ocr_mode == "mock":
        return MockDocumentUnderstandingProvider()
    if settings.ocr_mode == "qwen":
        return QwenDocumentUnderstandingProvider(settings)
    raise BusinessError("OCR_PROVIDER_NOT_CONFIGURED", "Unsupported OCR mode.", 503)


def model_image(path: Path, mime_type: str) -> tuple[bytes, str]:
    if mime_type != "application/pdf":
        return path.read_bytes(), mime_type

    import pypdfium2 as pdfium

    document = pdfium.PdfDocument(path)
    try:
        page = document[0]
        try:
            image = page.render(scale=2).to_pil().convert("RGB")
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=92)
            return output.getvalue(), "image/jpeg"
        finally:
            page.close()
    finally:
        document.close()
