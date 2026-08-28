from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime, timedelta
from io import BytesIO
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pypdf import PdfReader
from sqlalchemy import Engine, select

from pomi_backend.config import Settings
from pomi_backend.db import build_session_factory
from pomi_backend.db.models import PatientProfile, ReportFile, ReportSnapshot, UserAccount
from pomi_backend.repositories import PatientRepository, ReportFileRepository
from pomi_backend.services.report_pdf_renderer import (
    GENERAL_DISCLAIMER,
    PATIENT_NOTE_DISCLAIMER,
    SIMULATION_MARK,
    build_pdf_content,
    render_report_pdf,
)
from pomi_backend.worker.report_pdf import ReportPdfWorker


def _snapshot(*, many_labs: bool = False) -> dict[str, Any]:
    lab_points = [
        {
            "original_item_name": "总睾酮",
            "date": "2024-01-10" if index == 0 else f"2026-{index:02d}-10",
            "raw_value": str(0.5 + index / 10),
            "numeric_value": 0.5 + index / 10,
            "original_unit": "ng/mL",
            "reference_range_raw": "0.1-0.8",
            "abnormal_status": "high" if index > 3 else "normal",
            "freshness": "archived" if index == 0 else "current",
            "comparability": "incomparable" if index == 1 else "comparable",
            "exclusion_reason": "sample_context_mismatch" if index == 1 else None,
            "source_number": index + 5,
        }
        for index in range(0, 10 if many_labs else 3)
    ]
    sources = [
        {
            "source_number": 1,
            "source_type": "patient_profile",
            "origin_kind": "system_record",
            "document_revision_id": None,
        },
        {
            "source_number": 2,
            "source_type": "patient_note",
            "origin_kind": "patient_manual",
            "document_revision_id": None,
        },
        {
            "source_number": 3,
            "source_type": "medication",
            "origin_kind": "system_record",
            "document_revision_id": None,
        },
        {
            "source_number": 4,
            "source_type": "medication_daily",
            "origin_kind": "patient_manual",
            "document_revision_id": None,
        },
    ]
    sources.extend(
        {
            "source_number": point["source_number"],
            "source_type": "lab_observation",
            "origin_kind": "medical_document",
            "document_revision_id": f"revision-{point['source_number']}",
        }
        for point in lab_points
    )
    return {
        "metadata": {
            "generated_at": "2026-08-27T10:11:12+00:00",
            "template_version": "report-snapshot-v1",
            "simulated_data": True,
        },
        "summary": {
            "profile": {
                "nickname": "测试患者",
                "birth_date": "1998-03-20",
                "gender": "female",
                "height_cm": 165,
                "primary_condition": "PCOS",
            },
            "patient_note_text": "这是生成报告时冻结的患者自述。",
            "current_medications": [
                {
                    "id": "med-1",
                    "drug_name": "二甲双胍",
                    "specification": "500mg",
                    "dosage_value": 1,
                    "dosage_unit": "片",
                    "frequency": "每日一次",
                    "route": "口服",
                }
            ],
            "latest_observations": [lab_points[-1]],
            "missing_sections": ["imaging"],
            "disclaimers": [GENERAL_DISCLAIMER],
        },
        "trends": {
            "labs": [
                {
                    "metric_name": "总睾酮",
                    "comparability": "incomparable",
                    "comparability_reason": "sample_context_mismatch",
                    "points": lab_points,
                }
            ],
            "weights": [
                {
                    "date": "2025-01-10",
                    "weight_kg": 62.4,
                    "freshness": "archived",
                    "source_number": 20,
                },
                {
                    "date": "2026-08-20",
                    "weight_kg": 60.1,
                    "freshness": "current",
                    "source_number": 21,
                },
            ],
            "cycles": [
                {
                    "date": "2026-08-01",
                    "end_date": "2026-08-05",
                    "flow_level": "medium",
                    "freshness": "current",
                    "source_number": 22,
                }
            ],
            "medication_daily": [
                {
                    "date": f"2026-08-{day:02d}",
                    "medication_id": "med-1",
                    "intake_status": "taken" if day % 2 else "missed",
                    "source_number": 4,
                }
                for day in range(1, 29 if many_labs else 4)
            ],
        },
        "records": {
            "medication_history": [{"id": "med-1", "drug_name": "二甲双胍"}],
            "medical_orders": [],
            "imaging": [],
            "outpatient": [],
            # Values from #26 are deliberately ignored by the projection and renderer.
            "local_certification_demo": {
                "hospital_watermark": "禁止出现的医院认证演示水印",
                "transaction_hash": "0x-not-real",
                "doctor_signature": "虚构签名",
            },
        },
        "sources": sources,
    }


def _snapshot_hash(snapshot: dict[str, Any]) -> str:
    stable = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(stable.encode()).hexdigest()


def _auth(client: TestClient, name: str) -> dict[str, str]:
    password = "report-pdf-pass-44"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    response = client.post("/api/auth/login", json={"account_name": name, "password": password})
    return {"Authorization": f"Bearer {response.json()['session_id']}"}


def _seed_report(engine: Engine, account_name: str, snapshot: dict[str, Any]) -> str:
    session_factory = build_session_factory(engine)
    with session_factory() as session:
        account = session.scalar(
            select(UserAccount).where(UserAccount.account_name == account_name)
        )
        assert account is not None
        profile = PatientRepository(session).get_or_create(account.uid)
        report = ReportSnapshot(
            patient_id=profile.patient_id,
            report_status="succeeded",
            snapshot_json=snapshot,
            date_source_json={},
            freshness_result_json={},
            source_digest=hashlib.sha256(uuid4().bytes).hexdigest(),
            snapshot_hash=_snapshot_hash(snapshot),
            generated_by_uid=account.uid,
            report_generated_at=datetime(2026, 8, 27, 10, 11, 12, tzinfo=UTC),
        )
        session.add(report)
        session.commit()
        return report.id


def test_content_projection_retains_history_traceability_and_ignores_certification() -> None:
    content = build_pdf_content(_snapshot(many_labs=True))
    assert content.patient_note_lines[0] == "这是生成报告时冻结的患者自述。"
    assert content.medication_daily_rows[0][1] == "二甲双胍"
    assert any(row[1] == "2024-01-10" for row in content.lab_rows)
    assert any("保留原值，未绘制误导性连线" in line for line in content.quality_lines)
    assert any(row[3] == "患者手工记录" for row in content.source_rows)
    assert any(row[4].startswith("修订 revision-") for row in content.source_rows)
    all_content = repr(content)
    assert SIMULATION_MARK in all_content
    assert PATIENT_NOTE_DISCLAIMER in all_content
    assert "医院认证演示水印" not in all_content
    assert "0x-not-real" not in all_content
    assert "虚构签名" not in all_content


def test_renderer_is_deterministic_paginated_and_uses_bundled_chinese_font() -> None:
    snapshot = _snapshot(many_labs=True)
    first = render_report_pdf(snapshot)
    second = render_report_pdf(snapshot)
    assert first == second
    assert hashlib.sha256(first).hexdigest() == hashlib.sha256(second).hexdigest()
    reader = PdfReader(BytesIO(first))
    assert len(reader.pages) >= 2
    assert reader.metadata.title == "POMI 健康资料报告"
    assert reader.metadata.subject == SIMULATION_MARK


def test_pdf_api_worker_idempotency_download_and_uid_isolation(
    api_client: TestClient,
    api_engine: Engine,
    api_settings: Settings,
) -> None:
    owner = _auth(api_client, "pdf-owner")
    stranger = _auth(api_client, "pdf-stranger")
    snapshot = _snapshot()
    report_id = _seed_report(api_engine, "pdf-owner", snapshot)
    endpoint = f"/api/reports/{report_id}/pdf"

    created = api_client.post(endpoint, headers={**owner, "Idempotency-Key": "pdf-create-owner-1"})
    assert created.status_code == 202
    queued = created.json()["data"]
    assert queued["generation_status"] == "queued"
    assert queued["attempt_count"] == 0
    assert queued["download_url"] is None
    assert "storage_path" not in queued
    file_id = queued["file_id"]

    assert (
        api_client.post(
            endpoint, headers={**stranger, "Idempotency-Key": "pdf-stranger-create"}
        ).status_code
        == 404
    )
    assert api_client.get(endpoint, headers=stranger).status_code == 404
    assert api_client.get(f"{endpoint}/file", headers=stranger).status_code == 404

    session_factory = build_session_factory(api_engine)
    worker = ReportPdfWorker(
        session_factory,
        storage_root=api_settings.storage_root,
        worker_id="pdf-worker-test",
        lease_seconds=30,
    )
    assert worker.run_once() is True
    assert worker.run_once() is False

    status = api_client.get(endpoint, headers=owner)
    assert status.status_code == 200
    completed = status.json()["data"]
    assert completed["file_id"] == file_id
    assert completed["generation_status"] == "succeeded"
    assert completed["attempt_count"] == 1
    assert completed["file_hash"]
    assert completed["file_size_bytes"] > 1000

    download = api_client.get(f"{endpoint}/file", headers=owner)
    assert download.status_code == 200
    assert download.headers["content-type"] == "application/pdf"
    assert download.headers["cache-control"] == "private, no-store, max-age=0"
    assert hashlib.sha256(download.content).hexdigest() == completed["file_hash"]

    reused = api_client.post(endpoint, headers={**owner, "Idempotency-Key": "pdf-create-owner-2"})
    assert reused.status_code == 202
    assert reused.json()["data"]["file_id"] == file_id
    assert reused.json()["meta"]["reused"] is True
    assert api_client.get(f"{endpoint}/file", headers=owner).content == download.content


def test_expired_worker_lease_is_recovered_without_duplicate_file(
    api_client: TestClient,
    api_engine: Engine,
    api_settings: Settings,
) -> None:
    headers = _auth(api_client, "pdf-recovery")
    report_id = _seed_report(api_engine, "pdf-recovery", _snapshot())
    endpoint = f"/api/reports/{report_id}/pdf"
    response = api_client.post(endpoint, headers={**headers, "Idempotency-Key": "pdf-recovery-key"})
    file_id = response.json()["data"]["file_id"]
    session_factory = build_session_factory(api_engine)
    with session_factory() as session:
        report_file = session.get(ReportFile, file_id)
        assert report_file is not None
        report_file.generation_status = "processing"
        report_file.lease_owner = "dead-worker"
        report_file.lease_expires_at = datetime.now(UTC) - timedelta(seconds=1)
        report_file.attempt_count = 1
        session.commit()

    worker = ReportPdfWorker(
        session_factory,
        storage_root=api_settings.storage_root,
        worker_id="recovery-worker",
        lease_seconds=30,
    )
    assert worker.run_once() is True
    with session_factory() as session:
        rows = list(session.scalars(select(ReportFile).where(ReportFile.report_id == report_id)))
        assert len(rows) == 1
        assert rows[0].generation_status == "succeeded"
        assert rows[0].attempt_count == 2


def test_render_failure_can_be_retried_without_replacing_snapshot(
    api_client: TestClient,
    api_engine: Engine,
    api_settings: Settings,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    headers = _auth(api_client, "pdf-retry")
    snapshot = _snapshot()
    report_id = _seed_report(api_engine, "pdf-retry", snapshot)
    endpoint = f"/api/reports/{report_id}/pdf"
    queued = api_client.post(endpoint, headers={**headers, "Idempotency-Key": "pdf-retry-first"})
    file_id = queued.json()["data"]["file_id"]
    session_factory = build_session_factory(api_engine)
    worker = ReportPdfWorker(
        session_factory,
        storage_root=api_settings.storage_root,
        worker_id="failure-worker",
        lease_seconds=30,
    )

    def fail(_: dict[str, Any]) -> bytes:
        raise RuntimeError("must not leak frozen medical text")

    monkeypatch.setattr("pomi_backend.worker.report_pdf.render_report_pdf", fail)
    assert worker.run_once() is True
    failed = api_client.get(endpoint, headers=headers).json()["data"]
    assert failed["generation_status"] == "failed"
    assert "medical" not in failed["failure_reason"]

    retried = api_client.post(endpoint, headers={**headers, "Idempotency-Key": "pdf-retry-second"})
    assert retried.status_code == 202
    assert retried.json()["data"]["file_id"] == file_id
    assert retried.json()["data"]["generation_status"] == "queued"
    with session_factory() as session:
        report = session.get(ReportSnapshot, report_id)
        assert report is not None
        assert report.snapshot_json == snapshot


def test_repository_scope_and_atomic_claim_are_patient_safe(db_session) -> None:
    accounts = [
        UserAccount(uid=str(uuid4()), account_name=f"pdf-repo-{index}", password_hash="test-only")
        for index in range(2)
    ]
    db_session.add_all(accounts)
    db_session.flush()
    profiles: list[PatientProfile] = [
        PatientRepository(db_session).get_or_create(account.uid) for account in accounts
    ]
    reports = []
    for index, (account, profile) in enumerate(zip(accounts, profiles, strict=True)):
        report = ReportSnapshot(
            patient_id=profile.patient_id,
            report_status="succeeded",
            snapshot_json={"owner": index},
            source_digest=str(index) * 64,
            snapshot_hash=hashlib.sha256(str(index).encode()).hexdigest(),
            generated_by_uid=account.uid,
            report_generated_at=datetime.now(UTC),
        )
        db_session.add(report)
        reports.append(report)
    db_session.flush()
    first_repo = ReportFileRepository(db_session, profiles[0].patient_id)
    report_file = ReportFile(
        report_id=reports[0].id,
        template_version="report-pdf-v1",
        snapshot_hash=reports[0].snapshot_hash,
        idempotency_key="a" * 64,
    )
    first_repo.add(report_file)
    assert first_repo.get(report_file.id) is report_file
    assert ReportFileRepository(db_session, profiles[1].patient_id).get(report_file.id) is None
    claimed = ReportFileRepository(db_session).claim(
        worker_id="repo-worker", now=datetime.now(UTC), lease_seconds=30
    )
    assert claimed is not None
    assert claimed.id == report_file.id
    assert claimed.attempt_count == 1


def test_runtime_openapi_exposes_the_authenticated_pdf_lifecycle(api_client: TestClient) -> None:
    paths = api_client.get("/openapi.json").json()["paths"]
    lifecycle = paths["/api/reports/{report_id}/pdf"]
    file_endpoint = paths["/api/reports/{report_id}/pdf/file"]["get"]
    assert lifecycle["post"]["responses"].get("202") is not None
    assert lifecycle["post"]["security"] == [{"SessionBearer": []}]
    assert lifecycle["get"]["security"] == [{"SessionBearer": []}]
    assert file_endpoint["security"] == [{"SessionBearer": []}]
    assert "application/pdf" in file_endpoint["responses"]["200"]["content"]
