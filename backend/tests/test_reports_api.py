from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import Engine, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import (
    Document,
    DocumentRevision,
    ImagingReport,
    LabObservation,
    MedicalOrder,
    Medication,
    MedicationDaily,
    MedicationEvent,
    MenstrualCycle,
    OCRResult,
    OCRTask,
    OutpatientRecord,
    PatientProfile,
    ReportSnapshot,
    UserAccount,
    WeightRecord,
)


def _auth(client: TestClient, account_name: str) -> dict[str, str]:
    password = "report-pass-44"
    register = client.post(
        "/api/auth/register",
        json={"account_name": account_name, "password": password},
    )
    assert register.status_code == 201
    login = client.post(
        "/api/auth/login",
        json={"account_name": account_name, "password": password},
    )
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _confirmed_note(client: TestClient, headers: dict[str, str]) -> str:
    created = client.post(
        "/api/patient-notes",
        headers=headers,
        json={"original_text": "Discuss the original symptoms without rewriting."},
    )
    note_id = created.json()["data"]["id"]
    assert client.post(f"/api/patient-notes/{note_id}/confirm", headers=headers).status_code == 200
    return note_id


def _seed_confirmed_health_data(engine: Engine, account_name: str) -> str:
    session_factory = build_session_factory(engine)
    with session_factory() as session:
        account = session.scalar(
            select(UserAccount).where(UserAccount.account_name == account_name)
        )
        assert account is not None
        profile = session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == account.uid)
        )
        assert profile is not None
        profile.nickname = "Pomi Demo"
        profile.onboarding_completed = True
        medication = Medication(
            patient_id=profile.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
            dosage_value=Decimal("500"),
            dosage_unit="mg",
            frequency="once daily",
            status="active",
            start_date=date(2026, 1, 1),
        )
        session.add(medication)
        session.flush()
        session.add_all(
            [
                MedicationEvent(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    event_type="created",
                    event_date=date(2026, 1, 1),
                    new_instruction={"dose": "500 mg"},
                    source_type="manual",
                    acted_by_uid=account.uid,
                ),
                MedicationDaily(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    record_date=date(2026, 8, 27),
                    intake_status="taken",
                    recorded_by_uid=account.uid,
                ),
                MenstrualCycle(
                    patient_id=profile.patient_id,
                    start_date=date(2025, 1, 1),
                    end_date=date(2025, 1, 5),
                    source_type="manual",
                ),
                WeightRecord(
                    patient_id=profile.patient_id,
                    record_date=date(2026, 8, 20),
                    weight_kg=Decimal("61.2"),
                ),
            ]
        )
        session.commit()
        return profile.patient_id


def _seed_confirmed_ocr_data(engine: Engine, account_name: str) -> None:
    session_factory = build_session_factory(engine)
    with session_factory() as session:
        account = session.scalar(
            select(UserAccount).where(UserAccount.account_name == account_name)
        )
        assert account is not None
        profile = session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == account.uid)
        )
        assert profile is not None

        def source(kind: str) -> tuple[Document, DocumentRevision, OCRTask, OCRResult]:
            token = uuid4().hex
            document_id = str(uuid4())
            revision_id = str(uuid4())
            document = Document(
                id=document_id,
                patient_id=profile.patient_id,
                document_type=kind,
                original_file_name=f"{kind}.png",
                mime_type="image/png",
                file_size_bytes=10,
                page_count=1,
                file_hash=token * 2,
                current_revision_id=revision_id,
                upload_status="ready",
                uploaded_by_uid=account.uid,
                idempotency_key=f"report-{kind}-{token}",
            )
            revision = DocumentRevision(
                id=revision_id,
                document_id=document_id,
                revision_number=1,
                storage_path=f"{kind}/source.png",
                file_hash=token[::-1] * 2,
                file_size_bytes=10,
                mime_type="image/png",
                page_count=1,
                created_by_uid=account.uid,
            )
            task = OCRTask(
                patient_id=profile.patient_id,
                requested_by_uid=account.uid,
                document_id=document_id,
                document_revision_id=revision_id,
                material_type=kind,
                status="confirmed",
                model_name="test-model",
                prompt_version="test-prompt",
                schema_version="test-schema",
                deduplication_key=token * 2,
            )
            session.add_all([document, revision, task])
            session.flush()
            result = OCRResult(
                task_id=task.id,
                raw_response={},
                validated_draft={},
                confirmed_data={},
            )
            session.add(result)
            session.flush()
            return document, revision, task, result

        lab_doc, lab_rev, _, lab_result = source("lab_report")
        lab2_doc, lab2_rev, _, lab2_result = source("lab_report")
        lab3_doc, lab3_rev, _, lab3_result = source("lab_report")
        unmapped_doc, unmapped_rev, _, unmapped_result = source("lab_report")
        order_doc, order_rev, order_task, order_result = source("medical_order")
        image_doc, image_rev, _, image_result = source("imaging_text_report")
        visit_doc, visit_rev, _, visit_result = source("outpatient_record")
        session.add_all(
            [
                LabObservation(
                    patient_id=profile.patient_id,
                    document_id=lab_doc.id,
                    document_revision_id=lab_rev.id,
                    ocr_result_id=lab_result.id,
                    item_index=0,
                    original_item_name="Fasting glucose",
                    standard_metric_id="glucose",
                    mapping_status="mapped",
                    raw_value="126",
                    numeric_value=Decimal("126"),
                    original_unit="mg/dL",
                    standard_unit="mg/dL",
                    reference_range_raw="70-99",
                    reference_lower=Decimal("70"),
                    reference_upper=Decimal("99"),
                    abnormal_status="high",
                    sample_date=date(2026, 8, 26),
                    trend_date=date(2026, 8, 26),
                    trend_date_source="sample_date",
                    original_item_data={"sample_context": "fasting"},
                    confirmed_item_data={},
                    confirmed_by_uid=account.uid,
                ),
                LabObservation(
                    patient_id=profile.patient_id,
                    document_id=lab2_doc.id,
                    document_revision_id=lab2_rev.id,
                    ocr_result_id=lab2_result.id,
                    item_index=0,
                    original_item_name="Fasting glucose",
                    standard_metric_id="glucose",
                    mapping_status="mapped",
                    raw_value="7.0",
                    numeric_value=Decimal("7.0"),
                    original_unit="mmol/L",
                    standard_unit="mmol/L",
                    abnormal_status="high",
                    report_date=date(2026, 7, 20),
                    trend_date=date(2026, 7, 20),
                    trend_date_source="report_date",
                    original_item_data={"sample_context": "fasting"},
                    confirmed_item_data={},
                    confirmed_by_uid=account.uid,
                ),
                LabObservation(
                    patient_id=profile.patient_id,
                    document_id=lab3_doc.id,
                    document_revision_id=lab3_rev.id,
                    ocr_result_id=lab3_result.id,
                    item_index=0,
                    original_item_name="Fasting glucose",
                    standard_metric_id="glucose",
                    mapping_status="mapped",
                    raw_value="110",
                    numeric_value=Decimal("110"),
                    original_unit="mg/dL",
                    standard_unit="mg/dL",
                    abnormal_status="high",
                    visit_date=date(2026, 6, 18),
                    trend_date=date(2026, 6, 18),
                    trend_date_source="visit_date",
                    original_item_data={"sample_context": "fasting"},
                    confirmed_item_data={},
                    confirmed_by_uid=account.uid,
                ),
                LabObservation(
                    patient_id=profile.patient_id,
                    document_id=unmapped_doc.id,
                    document_revision_id=unmapped_rev.id,
                    ocr_result_id=unmapped_result.id,
                    item_index=0,
                    original_item_name="Unknown assay",
                    mapping_status="needs_manual_review",
                    raw_value="positive",
                    numeric_value=Decimal("1"),
                    original_unit="text",
                    standard_unit="text",
                    abnormal_status="unknown",
                    original_item_data={},
                    confirmed_item_data={},
                    confirmed_by_uid=account.uid,
                ),
                MedicalOrder(
                    patient_id=profile.patient_id,
                    document_id=order_doc.id,
                    document_revision_id=order_rev.id,
                    ocr_result_id=order_result.id,
                    ocr_task_id=order_task.id,
                    medication_index=0,
                    raw_order_text="Metformin 500 mg once daily",
                    drug_name="Metformin",
                    standard_drug_id="metformin",
                    dosage_value=Decimal("500"),
                    dosage_unit="mg",
                    frequency="once daily",
                    order_date=date(2026, 8, 25),
                    confirmed_by_uid=account.uid,
                ),
                ImagingReport(
                    patient_id=profile.patient_id,
                    document_id=image_doc.id,
                    document_revision_id=image_rev.id,
                    ocr_result_id=image_result.id,
                    examination_name="Pelvic ultrasound text",
                    examination_date=date(2026, 8, 24),
                    findings_text="Original findings text.",
                    conclusion_text="Original conclusion text.",
                    confirmed_payload={},
                    confirmed_by_uid=account.uid,
                ),
                OutpatientRecord(
                    patient_id=profile.patient_id,
                    document_id=visit_doc.id,
                    document_revision_id=visit_rev.id,
                    ocr_result_id=visit_result.id,
                    visit_date=date(2026, 8, 23),
                    diagnosis_summary="Confirmed diagnosis text.",
                    medical_advice="Confirmed disposition text.",
                    confirmed_payload={},
                    confirmed_by_uid=account.uid,
                ),
            ]
        )
        # A confirmed OCR result without a formal business record remains excluded.
        source("lab_report")
        session.commit()


def test_report_preflight_idempotency_immutability_and_update_detection(
    api_client: TestClient,
    api_engine: Engine,
) -> None:
    headers = _auth(api_client, "report-owner")
    note_id = _confirmed_note(api_client, headers)
    patient_id = _seed_confirmed_health_data(api_engine, "report-owner")
    payload = {
        "patient_note_id": note_id,
        "include_sections": [
            "profile",
            "patient_note",
            "medications",
            "cycles",
            "weights",
        ],
    }

    preflight = api_client.post("/api/reports/preflight", headers=headers, json=payload)
    assert preflight.status_code == 200
    assert preflight.json()["data"]["missing_sections"] == []

    first = api_client.post("/api/reports", headers=headers, json=payload)
    assert first.status_code == 201, first.text
    first_data = first.json()["data"]
    assert first_data["reused"] is False
    assert first_data["previous_report_id"] is None

    repeated = api_client.post("/api/reports", headers=headers, json=payload)
    assert repeated.status_code == 201
    assert repeated.json()["data"]["report_id"] == first_data["report_id"]
    assert repeated.json()["data"]["reused"] is True

    listed = api_client.get("/api/reports", headers=headers).json()["data"]["items"]
    assert len(listed) == 1
    assert listed[0]["has_updates"] is False

    session_factory = build_session_factory(api_engine)
    with session_factory() as session:
        frozen = session.get(ReportSnapshot, first_data["report_id"])
        assert frozen is not None
        old_snapshot = frozen.snapshot_json
        session.add(
            WeightRecord(
                patient_id=patient_id,
                record_date=date(2026, 8, 27),
                weight_kg=Decimal("60.8"),
            )
        )
        session.commit()

    listed = api_client.get("/api/reports", headers=headers).json()["data"]["items"]
    assert listed[0]["has_updates"] is True
    second = api_client.post("/api/reports", headers=headers, json=payload).json()["data"]
    assert second["report_id"] != first_data["report_id"]
    assert second["previous_report_id"] == first_data["report_id"]

    with session_factory() as session:
        frozen = session.get(ReportSnapshot, first_data["report_id"])
        assert frozen is not None
        assert frozen.snapshot_json == old_snapshot
        assert frozen.snapshot_json["trends"]["cycles"][0]["freshness"] == "archived"
        assert frozen.snapshot_json["trends"]["cycles"][0]["default_collapsed"] is True
        assert "用药调整" in frozen.snapshot_json["summary"]["disclaimers"][2]


def test_report_requires_missing_data_confirmation_and_rejects_cross_uid_note(
    api_client: TestClient,
) -> None:
    owner = _auth(api_client, "report-first")
    stranger = _auth(api_client, "report-second")
    note_id = _confirmed_note(api_client, owner)
    payload = {"patient_note_id": note_id, "include_sections": ["labs"]}

    missing = api_client.post("/api/reports", headers=owner, json=payload)
    assert missing.status_code == 409
    assert missing.json()["error"]["code"] == "REPORT_INCOMPLETE_CONFIRMATION_REQUIRED"
    assert missing.json()["error"]["details"]["missing_sections"] == ["labs"]

    accepted = api_client.post(
        "/api/reports",
        headers=owner,
        json={**payload, "confirm_incomplete": True},
    )
    assert accepted.status_code == 201
    assert accepted.json()["data"]["missing_sections"] == ["labs"]

    denied = api_client.post(
        "/api/reports",
        headers=stranger,
        json={**payload, "confirm_incomplete": True},
    )
    assert denied.status_code == 404
    assert api_client.get("/api/reports", headers=stranger).json()["data"]["items"] == []


def test_report_uses_only_confirmed_ocr_records_with_revision_level_sources(
    api_client: TestClient,
    api_engine: Engine,
) -> None:
    headers = _auth(api_client, "report-ocr-owner")
    note_id = _confirmed_note(api_client, headers)
    _seed_confirmed_health_data(api_engine, "report-ocr-owner")
    _seed_confirmed_ocr_data(api_engine, "report-ocr-owner")
    response = api_client.post(
        "/api/reports",
        headers=headers,
        json={"patient_note_id": note_id, "confirm_incomplete": True},
    )
    assert response.status_code == 201, response.text
    report_id = response.json()["data"]["report_id"]

    session_factory = build_session_factory(api_engine)
    with session_factory() as session:
        report = session.get(ReportSnapshot, report_id)
        assert report is not None
        snapshot = report.snapshot_json
        assert snapshot is not None
        glucose = snapshot["trends"]["labs"][0]
        assert glucose["display_mode"] == "trend"
        assert glucose["comparability"] == "comparable"
        assert glucose["points"][1]["normalized_value"] == 126
        assert glucose["points"][2]["date_source"] == "sample_date"
        unmapped = snapshot["trends"]["labs"][1]
        assert unmapped["points"][0]["exclusion_reason"] == ("metric_needs_manual_review")
        assert unmapped["points"][0]["date"] is None
        assert len(snapshot["records"]["medical_orders"]) == 1
        assert snapshot["records"]["imaging"][0]["findings"] == "Original findings text."
        assert snapshot["records"]["outpatient"][0]["medical_advice"] == (
            "Confirmed disposition text."
        )
        medical_sources = [
            source for source in snapshot["sources"] if source["origin_kind"] == "medical_document"
        ]
        assert len(medical_sources) == 7
        assert all(source["document_revision_id"] for source in medical_sources)

    labs_only = api_client.post(
        "/api/reports",
        headers=headers,
        json={"patient_note_id": note_id, "include_sections": ["labs"]},
    )
    assert labs_only.status_code == 201, labs_only.text
    with session_factory() as session:
        report = session.get(ReportSnapshot, labs_only.json()["data"]["report_id"])
        assert report is not None and report.snapshot_json is not None
        assert {source["source_type"] for source in report.snapshot_json["sources"]} == {
            "lab_observation",
            "rule_execution",
        }
