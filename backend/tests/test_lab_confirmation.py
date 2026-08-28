from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from pomi_backend.db.models import LabObservation, OCRFieldResult, OCRResult, OCRTask
from pomi_backend.db.models.health import new_uuid
from pomi_backend.repositories.labs import LabObservationRepository
from pomi_backend.services.lab_rules import normalize_lab_item, parse_date, parse_number


def _headers(client: TestClient, name: str) -> dict[str, str]:
    password = "LabConfirmationPass123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _image() -> bytes:
    output = BytesIO()
    Image.new("RGB", (40, 30), "white").save(output, format="PNG")
    return output.getvalue()


def _draft_task(client: TestClient, headers: dict[str, str]) -> tuple[dict, dict]:
    uploaded = client.post(
        "/api/documents",
        headers={**headers, "Idempotency-Key": f"lab-source-{new_uuid()}"},
        data={
            "document_type": "lab_report",
            "external_processing_consent_version": "external-ocr-v1",
        },
        files={"file": ("lab.png", _image(), "image/png")},
    )
    assert uploaded.status_code == 201, uploaded.text
    document = uploaded.json()["data"]
    created = client.post(
        "/api/ocr/tasks",
        headers=headers,
        json={
            "document_id": document["id"],
            "document_revision_id": document["current_revision_id"],
        },
    )
    assert created.status_code == 201, created.text
    task = created.json()["data"]
    with client.app.state.session_factory() as session:
        model = session.get(OCRTask, task["id"])
        assert model is not None
        model.status = "pending_confirmation"
        result = OCRResult(
            id=new_uuid(),
            task_id=model.id,
            raw_response={"model_abnormal_status": "high"},
            validated_draft={
                "hospital_name": "Pomi Hospital",
                "sample_date": "2026-08-18",
                "report_date": "2026-08-20",
                "items": [
                    {
                        "item_name": "血糖",
                        "item_code": "GLU",
                        "raw_value": "bad",
                        "numeric_value": None,
                        "raw_unit": "mg/dL",
                        "normalized_unit": "mmol/L",
                        "reference_range_text": "70-100",
                        "reference_low": 70,
                        "reference_high": 100,
                    },
                    {
                        "item_name": "自定义指标",
                        "item_code": None,
                        "raw_value": "8",
                        "numeric_value": 8,
                        "raw_unit": "U/L",
                        "normalized_unit": "U/L",
                        "reference_range_text": None,
                        "reference_low": None,
                        "reference_high": None,
                    },
                ],
            },
        )
        session.add(result)
        session.flush()
        session.add_all(
            [
                OCRFieldResult(
                    result_id=result.id,
                    field_path="items.0.raw_value",
                    source_text="9O",
                    parsed_value="bad",
                    confidence=0.42,
                    uncertainty_reason="ambiguous character",
                    source_region={"page": 1, "x": 0.2, "y": 0.3, "width": 0.1, "height": 0.1},
                ),
                OCRFieldResult(
                    result_id=result.id,
                    field_path="items.0.raw_unit",
                    source_text="mg/dL",
                    parsed_value="mg/dL",
                    confidence=0.99,
                ),
            ]
        )
        session.commit()
        result_id = result.id
    return task, {"result_id": result_id, "document": document}


def _confirmation(task: dict, context: dict) -> dict:
    return {
        "result_id": context["result_id"],
        "expected_revision_id": task["document_revision_id"],
        "sample_date": None,
        "exam_date": None,
        "report_date": "2026-08-20",
        "visit_date": "2026-08-19",
        "visit_id": "visit-external-26",
        "items": [
            {
                "source_index": 0,
                "name": "血糖",
                "value": "90",
                "unit": "mg/dL",
                "reference_range": "70-100",
                "sample_date": "2026-08-18",
                "exam_date": None,
                "report_date": None,
                "visit_date": None,
                "note": None,
            },
            {
                "source_index": 1,
                "name": "自定义指标",
                "value": "8",
                "unit": "U/L",
                "reference_range": None,
                "sample_date": None,
                "exam_date": None,
                "report_date": None,
                "visit_date": None,
                "note": "人工核对原名",
            },
        ],
    }


def test_confirm_lab_is_validated_traceable_idempotent_and_uid_scoped(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "lab-owner")
    outsider = _headers(api_client, "lab-outsider")
    task, context = _draft_task(api_client, owner)
    payload = _confirmation(task, context)

    result_page = api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=owner)
    assert result_page.status_code == 200
    source = result_page.json()["data"]["source_document"]
    assert source["document_revision_id"] == task["document_revision_id"]
    assert source["original_file_name"] == "lab.png"
    assert source["file_endpoint"].startswith("/api/documents/")
    assert source["file_endpoint"].endswith("/file")

    before = api_client.get("/api/lab-observations", headers=owner).json()["data"]["items"]
    assert before == []
    forbidden = api_client.post(
        f"/api/ocr/tasks/{task['id']}/confirm", headers=outsider, json=payload
    )
    assert forbidden.status_code == 404

    confirmed = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload)
    assert confirmed.status_code == 200, confirmed.text
    data = confirmed.json()["data"]
    assert data["status"] == "confirmed"
    assert data["reused"] is False
    assert len(data["created_resource_ids"]) == 2
    assert data["p0_evaluation"]["total_fields"] == 6
    assert data["p0_evaluation"]["valid_fields"] == 6
    assert data["p0_evaluation"]["invalid_fields"] == 0
    assert data["p0_evaluation"]["user_corrected_fields"] == 1
    assert data["p0_evaluation"]["ocr_exact_match_rate"] == pytest.approx(5 / 6, abs=0.0001)
    glucose, custom = data["observations"]
    assert glucose["standard_metric_id"] == "glucose"
    assert glucose["numeric_value"] == "4.995000"
    assert glucose["original_unit"] == "mg/dL"
    assert glucose["standard_unit"] == "mmol/L"
    assert glucose["reference_lower"] == "3.885000"
    assert glucose["reference_upper"] == "5.550000"
    assert glucose["abnormal_status"] == "normal"
    assert glucose["trend_date"] == "2026-08-18"
    assert glucose["trend_date_source"] == "sample_date"
    assert custom["standard_metric_id"] is None
    assert custom["mapping_status"] == "needs_manual_review"
    assert custom["abnormal_status"] == "unknown"
    assert custom["trend_date"] == "2026-08-20"
    assert custom["trend_date_source"] == "report_date"

    repeated = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload)
    assert repeated.status_code == 200
    assert repeated.json()["data"]["reused"] is True
    assert repeated.json()["data"]["created_resource_ids"] == data["created_resource_ids"]

    changed = {**payload, "items": [{**payload["items"][0], "value": "91"}]}
    conflict = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=changed)
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "OCR_ALREADY_CONFIRMED"

    owner_list = api_client.get("/api/lab-observations", headers=owner).json()["data"]["items"]
    assert len(owner_list) == 2
    assert api_client.get("/api/lab-observations", headers=outsider).json()["data"]["items"] == []
    assert (
        api_client.get(f"/api/lab-observations/{owner_list[0]['id']}", headers=outsider).status_code
        == 404
    )
    with api_client.app.state.session_factory() as session:
        assert session.query(LabObservation).count() == 2
        result = session.get(OCRResult, context["result_id"])
        assert result is not None
        fields = {item.field_path: item for item in session.query(OCRFieldResult).all()}
        assert fields["items.0.raw_value"].confirmation_status == "edited"
        assert fields["items.0.raw_value"].user_value == "90"
        assert fields["items.0.raw_unit"].confirmation_status == "confirmed"
        assert result.user_modified_data == payload
        assert result.confirmed_data == payload
        observation = session.query(LabObservation).first()
        observation.document_id = new_uuid()
        with pytest.raises(ValueError, match="lineage"):
            LabObservationRepository(session, observation.patient_id).add(observation)
        session.rollback()


def test_invalid_p0_unit_reference_and_date_are_stable_field_errors(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "lab-invalid")
    task, context = _draft_task(api_client, owner)
    payload = _confirmation(task, context)
    payload["items"] = [
        {
            "name": "血糖",
            "value": "not-a-number",
            "unit": "banana",
            "reference_range": "about five",
            "sample_date": "2026-02-30",
        },
        {"name": None, "value": None, "unit": None},
    ]
    response = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload)
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "LAB_CONFIRMATION_INVALID"
    codes = {item["code"] for item in error["details"]["fields"]}
    assert codes >= {
        "LAB_VALUE_INVALID",
        "LAB_UNIT_UNSUPPORTED",
        "LAB_REFERENCE_RANGE_INVALID",
        "LAB_DATE_INVALID",
        "LAB_NAME_REQUIRED",
        "LAB_VALUE_REQUIRED",
        "LAB_UNIT_REQUIRED",
    }
    assert error["details"]["p0_evaluation"]["invalid_fields"] == 5
    with api_client.app.state.session_factory() as session:
        assert session.query(LabObservation).count() == 0
        assert session.get(OCRTask, task["id"]).status == "pending_confirmation"


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("12.30", "12.30"), ("1,234.5", "1234.5"), ("<5", None), (True, None)],
)
def test_numeric_rules_are_deterministic(raw: object, expected: str | None) -> None:
    value = parse_number(raw)
    assert (None if value is None else str(value)) == expected


def test_metric_mapping_never_guesses_and_date_priority_is_explicit() -> None:
    parsed, issues = normalize_lab_item(
        {
            "name": "不是 LH 的陌生指标",
            "value": "6.5",
            "unit": "IU/L",
            "reference_range": "2-9",
            "exam_date": "2026/08/18",
        },
        0,
        {"report_date": "2026-08-20", "visit_date": "2026-08-21"},
    )
    assert issues == []
    assert parsed is not None
    assert parsed.standard_metric_id is None
    assert parsed.mapping_status == "needs_manual_review"
    assert parsed.trend_date == parse_date("2026-08-18")
    assert parsed.trend_date_source == "exam_date"


@pytest.mark.parametrize(
    ("reference_range", "expected"),
    [("<5", "high"), ("<=5", "normal"), (">5", "low"), (">=5", "normal")],
)
def test_one_sided_reference_boundaries_preserve_strictness(
    reference_range: str, expected: str
) -> None:
    parsed, issues = normalize_lab_item(
        {"name": "自定义指标", "value": "5", "unit": "U/L", "reference_range": reference_range},
        0,
        {},
    )
    assert issues == []
    assert parsed is not None
    assert parsed.abnormal_status == expected


def test_openapi_exposes_confirmation_and_formal_observations(api_client: TestClient) -> None:
    paths = api_client.get("/openapi.json").json()["paths"]
    assert "/api/ocr/tasks/{task_id}/confirm" in paths
    assert "/api/lab-observations" in paths
    assert "/api/lab-observations/{observation_id}" in paths


def test_concurrent_identical_confirmation_creates_one_observation_set(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "lab-concurrent")
    task, context = _draft_task(api_client, owner)
    payload = _confirmation(task, context)

    def confirm() -> tuple[int, dict]:
        response = api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(lambda _: confirm(), range(2)))

    assert {status for status, _ in responses} == {200}
    payloads = [body["data"] for _, body in responses]
    assert {value["reused"] for value in payloads} == {False, True}
    assert payloads[0]["created_resource_ids"] == payloads[1]["created_resource_ids"]
    with api_client.app.state.session_factory() as session:
        assert session.query(LabObservation).count() == 2


def test_deleted_source_and_revoked_session_cannot_confirm(api_client: TestClient) -> None:
    owner = _headers(api_client, "lab-deleted")
    task, context = _draft_task(api_client, owner)
    payload = _confirmation(task, context)
    deleted = api_client.delete(f"/api/documents/{context['document']['id']}", headers=owner)
    assert deleted.status_code == 200

    response = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "RESOURCE_NOT_FOUND"
    result_page = api_client.get(f"/api/ocr/tasks/{task['id']}/result", headers=owner)
    assert "source_document" not in result_page.json()["data"]

    logged_out = api_client.post("/api/auth/logout", headers=owner)
    assert logged_out.status_code == 204
    assert (
        api_client.post(
            f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload
        ).status_code
        == 401
    )


def test_removed_source_item_is_rejected_without_losing_remaining_lineage(
    api_client: TestClient,
) -> None:
    owner = _headers(api_client, "lab-remove-item")
    task, context = _draft_task(api_client, owner)
    payload = _confirmation(task, context)
    payload["items"] = [payload["items"][1]]

    response = api_client.post(f"/api/ocr/tasks/{task['id']}/confirm", headers=owner, json=payload)
    assert response.status_code == 200, response.text
    observation = response.json()["data"]["observations"][0]
    assert observation["item_index"] == 1
    with api_client.app.state.session_factory() as session:
        fields = {
            item.field_path: item
            for item in session.query(OCRFieldResult)
            .filter(OCRFieldResult.result_id == context["result_id"])
            .all()
        }
        assert fields["items.0.raw_value"].confirmation_status == "rejected"
