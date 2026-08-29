from __future__ import annotations

from datetime import date
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
from pytest import MonkeyPatch
from sqlalchemy import func, select

from pomi_backend.db.models import (
    DocumentDisplayAsset,
    LabObservation,
    Medication,
    MedicationEvent,
    OCRResult,
    OCRTask,
)
from pomi_backend.services.ocr_provider import OCRProviderResponse


def _headers(client: TestClient, name: str) -> dict[str, str]:
    password = "SyncOcrPass123"
    registered = client.post(
        "/api/auth/register", json={"account_name": name, "password": password}
    )
    assert registered.status_code == 201
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _image() -> bytes:
    output = BytesIO()
    Image.new("RGB", (320, 240), (52, 64, 82)).save(output, format="PNG")
    return output.getvalue()


def _data(response, status_code: int = 200):
    assert response.status_code == status_code, response.text
    return response.json()["data"]


class FakeProvider:
    calls = 0

    def __init__(self, **_: object) -> None:
        pass

    def recognize(self, request) -> OCRProviderResponse:
        type(self).calls += 1
        payload = {
            "hospital": "南京市妇幼保健院",
            "department": "妇科",
            "visit_date": "2026-08-26",
            "diagnosis_summary": "多囊卵巢综合征",
            "medical_advice": "二甲双胍 500mg 每日两次",
            "examinations": [
                {
                    "item_name": "空腹血糖",
                    "value": "5.2",
                    "unit": "mmol/L",
                    "reference_range": "3.9-6.1",
                    "abnormal": False,
                }
            ],
            "medication_suggestions": [
                {
                    "drug_name": "二甲双胍",
                    "dosage": "500mg",
                    "frequency": "每日两次",
                    "duration": None,
                    "instruction": "每日两次",
                    "source_text": "二甲双胍 500mg 每日两次",
                }
            ],
            "original_file_name": request.file_name,
        }
        return OCRProviderResponse(
            raw_response={"provider": "fake"}, payload=payload, source="fake-qwen"
        )


def _recognize(
    client: TestClient,
    headers: dict[str, str],
    *,
    key: str = "sync-ocr-001",
) -> dict:
    return _data(
        client.post(
            "/api/ocr/recognize",
            headers={
                **headers,
                "Idempotency-Key": key,
                "X-External-Processing-Consent-Version": "external-ocr-v1",
            },
            data={"material_type": "imaging_text_report", "prompt_version": "pomi-ocr-v1"},
            files={"file": ("visit.png", _image(), "image/png")},
        )
    )


def _confirmation(*, drug_name: str = "二甲双胍", dosage: str = "500mg") -> dict:
    return {
        "visit_date": "2026-08-26",
        "examinations": [
            {
                "source_index": 0,
                "item_name": "空腹血糖",
                "value": "5.2",
                "unit": "mmol/L",
                "reference_range": "3.9-6.1",
            }
        ],
        "medication_suggestions": [
            {
                "source_index": 0,
                "drug_name": drug_name,
                "dosage": dosage,
                "frequency": "每日两次",
                "instruction": "每日两次",
                "source_text": f"{drug_name} {dosage} 每日两次",
            }
        ],
    }


def test_sync_recognize_persists_result_and_reuses_idempotency_key(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    monkeypatch.setattr("pomi_backend.api.ocr.Qwen3VLOCRProvider", FakeProvider)
    FakeProvider.calls = 0
    owner = _headers(api_client, "sync-ocr-owner")

    first = _recognize(api_client, owner)
    repeated = _recognize(api_client, owner)

    assert repeated == first
    assert FakeProvider.calls == 1
    display = first["display_asset"]
    assert display["status"] == "ready"
    assert display["watermark_version"] == "pomi-watermark-v2"
    assert display["pixel_width"] == 320
    assert display["pixel_height"] == 240
    watermarked = api_client.get(display["file_endpoint"], headers=owner)
    assert watermarked.status_code == 200
    assert watermarked.headers["cache-control"] == "private, no-store"
    with Image.open(BytesIO(watermarked.content)) as image:
        assert image.size == (320, 240)
        assert image.convert("RGB").getpixel((160, 120)) != (52, 64, 82)
    with api_client.app.state.session_factory() as session:
        assert session.scalar(select(func.count()).select_from(OCRTask)) == 1
        assert session.scalar(select(func.count()).select_from(OCRResult)) == 1
        task = session.get(OCRTask, first["ocr_task_id"])
        assert task is not None
        assert task.status == "pending_confirmation"
        assert task.result_source == "fake-qwen"
        assert session.scalar(select(func.count()).select_from(DocumentDisplayAsset)) == 1

    second_owner = _headers(api_client, "sync-ocr-other-owner")
    other = _recognize(api_client, second_owner)
    assert other["ocr_task_id"] != first["ocr_task_id"]
    assert FakeProvider.calls == 2
    assert api_client.get(display["file_endpoint"], headers=second_owner).status_code == 404


def test_watermark_retry_isolated_from_successful_ocr(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    monkeypatch.setattr("pomi_backend.api.ocr.Qwen3VLOCRProvider", FakeProvider)
    owner = _headers(api_client, "sync-watermark-retry")
    from pomi_backend.services import watermarks

    renderer = watermarks._render_watermarked_image

    def fail_renderer(*_args, **_kwargs):
        raise OSError("synthetic renderer failure")

    monkeypatch.setattr(watermarks, "_render_watermarked_image", fail_renderer)
    recognized = _recognize(api_client, owner, key="sync-watermark-retry-001")
    failed = recognized["display_asset"]
    assert failed["status"] == "failed"
    assert failed["error"]["code"] == "WATERMARK_RENDER_FAILED"
    task = _data(api_client.get(f"/api/ocr/tasks/{recognized['ocr_task_id']}", headers=owner))
    assert task["status"] == "pending_confirmation"

    retry_endpoint = (
        f"/api/documents/{recognized['document_id']}/revisions/"
        f"{recognized['document_revision_id']}/display/retry"
    )
    monkeypatch.setattr(watermarks, "_render_watermarked_image", renderer)
    recovered = _data(api_client.post(retry_endpoint, headers=owner))
    assert recovered["status"] == "ready"
    assert recovered["id"] == failed["id"]
    assert recovered["attempt_count"] == failed["attempt_count"] + 1


def test_sync_confirmation_is_atomic_idempotent_and_owned(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    monkeypatch.setattr("pomi_backend.api.ocr.Qwen3VLOCRProvider", FakeProvider)
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 28)
    owner = _headers(api_client, "sync-confirm-owner")
    outsider = _headers(api_client, "sync-confirm-outsider")
    recognized = _recognize(api_client, owner, key="sync-confirm-001")
    endpoint = f"/api/ocr/results/{recognized['ocr_result_id']}/confirm"

    hidden = api_client.post(endpoint, headers=outsider, json=_confirmation())
    assert hidden.status_code == 404

    created = _data(api_client.post(endpoint, headers=owner, json=_confirmation()))
    assert created["status"] == "confirmed"
    assert created["reused"] is False
    assert created["observations"][0]["standard_metric_id"] == "glucose"
    assert created["medications"][0]["standard_drug_id"] == "rxnorm:metformin"

    repeated = _data(api_client.post(endpoint, headers=owner, json=_confirmation()))
    assert repeated["reused"] is True
    assert repeated["medications"] == created["medications"]

    documents = _data(api_client.get("/api/documents", headers=owner))
    assert len(documents["items"]) == 1
    assert documents["items"][0]["latest_ocr_task_id"] == recognized["ocr_task_id"]
    assert documents["items"][0]["latest_ocr_status"] == "confirmed"
    assert documents["items"][0]["latest_ocr_result_source"] == "fake-qwen"

    dashboard = _data(api_client.get("/api/dashboard", headers=owner))
    assert dashboard["document_summary"]["data"] == {"confirmed": 1, "total": 1}

    changed = _confirmation()
    changed["examinations"][0]["value"] = "5.3"
    conflict = api_client.post(endpoint, headers=owner, json=changed)
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "OCR_ALREADY_CONFIRMED"

    with api_client.app.state.session_factory() as session:
        assert session.scalar(select(func.count()).select_from(LabObservation)) == 1
        assert session.scalar(select(func.count()).select_from(Medication)) == 1
        event = session.scalar(select(MedicationEvent))
        assert event is not None
        assert event.event_date == date(2026, 8, 26)
        assert session.get(OCRTask, recognized["ocr_task_id"]).status == "confirmed"


def test_sync_confirmation_accepts_unmapped_drug_and_free_text_dosage(
    api_client: TestClient, monkeypatch: MonkeyPatch
) -> None:
    """未映射药名与无法解析为数值的剂量文本不再阻塞入库（缺空就缺着，但不失败）。"""
    monkeypatch.setattr("pomi_backend.api.ocr.Qwen3VLOCRProvider", FakeProvider)
    owner = _headers(api_client, "sync-confirm-lenient")
    recognized = _recognize(api_client, owner, key="sync-confirm-lenient-001")
    pending_task_id = recognized["ocr_task_id"]
    endpoint = f"/api/ocr/results/{recognized['ocr_result_id']}/confirm"

    unknown = api_client.post(
        endpoint,
        headers=owner,
        json=_confirmation(drug_name="未知药品"),
    )
    assert unknown.status_code == 200
    created = unknown.json()["data"]
    assert created["status"] == "confirmed"
    assert len(created["medications"]) == 1
    assert created["medications"][0]["standard_drug_id"] is None

    # 剂量为自由文本时不再 422：单独识别一个新任务验证。
    recognized_dosage = _recognize(api_client, owner, key="sync-confirm-lenient-002")
    dosage_endpoint = f"/api/ocr/results/{recognized_dosage['ocr_result_id']}/confirm"
    invalid_dosage = api_client.post(
        dosage_endpoint,
        headers=owner,
        json=_confirmation(dosage="一片"),
    )
    assert invalid_dosage.status_code == 200

    # 化验值非法仍然 422：单独识别一个新任务验证。
    recognized_lab = _recognize(api_client, owner, key="sync-confirm-lenient-003")
    lab_endpoint = f"/api/ocr/results/{recognized_lab['ocr_result_id']}/confirm"
    invalid_lab = _confirmation()
    invalid_lab["examinations"][0]["value"] = "not-a-number"
    rejected = api_client.post(lab_endpoint, headers=owner, json=invalid_lab)
    assert rejected.status_code == 422
    assert rejected.json()["error"]["code"] == "OCR_CONFIRMATION_INVALID"

    # 重复化验项 / 越界 source_index 仍然 422：复用第三个任务。
    duplicate = _confirmation()
    duplicate["examinations"].append(dict(duplicate["examinations"][0]))
    duplicate_response = api_client.post(lab_endpoint, headers=owner, json=duplicate)
    assert duplicate_response.status_code == 422

    invalid_source = _confirmation()
    invalid_source["examinations"][0]["source_index"] = 99
    source_response = api_client.post(lab_endpoint, headers=owner, json=invalid_source)
    assert source_response.status_code == 422
    assert source_response.json()["error"]["details"]["fields"][0]["code"] == (
        "OCR_SOURCE_INDEX_INVALID"
    )

    empty = api_client.post(
        f"/api/ocr/results/"
        f"{_recognize(api_client, owner, key='sync-confirm-lenient-004')['ocr_result_id']}/confirm",
        headers=owner,
        json={"examinations": [], "medication_suggestions": []},
    )
    assert empty.status_code == 422
    assert empty.json()["error"]["code"] == "OCR_CONFIRMATION_EMPTY"

    with api_client.app.state.session_factory() as session:
        # 任务 1（未知药品）与任务 2（自由文本剂量）各成功确认 1 条，共 2 条；
        # 任务 3（非法化验值/重复项/越界索引）与任务 4（空 payload）被 422 拒绝，不计数。
        assert session.scalar(select(func.count()).select_from(LabObservation)) == 2
        assert session.scalar(select(func.count()).select_from(Medication)) == 2
        assert session.scalar(select(func.count()).select_from(MedicationEvent)) == 2
        assert session.get(OCRTask, pending_task_id).status == "confirmed"
