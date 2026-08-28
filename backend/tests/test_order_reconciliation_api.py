from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import date
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import func, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import (
    MedicalOrder,
    Medication,
    MedicationEvent,
    MedicationReconciliation,
    OCRFieldResult,
    OCRResult,
    OCRTask,
)
from pomi_backend.db.models.health import new_uuid
from pomi_backend.services.orders import ReconciliationService


def _auth(client: TestClient, name: str) -> dict[str, str]:
    password = "OrderReview123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def _data(response, status: int = 200):
    assert response.status_code == status, response.text
    return response.json()["data"]


def _png(seed: int) -> bytes:
    output = BytesIO()
    Image.new("RGB", (20, 20), (seed % 255, 255, 255)).save(output, "PNG")
    return output.getvalue()


def _task(client: TestClient, headers: dict[str, str], engine, medications: list[dict]) -> dict:
    upload_key = f"order-source-{new_uuid()}"
    document = _data(
        client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": upload_key},
            data={
                "document_type": "medical_order",
                "external_processing_consent_version": "ocr-v1",
            },
            files={
                "file": (
                    "order.png",
                    _png(sum(upload_key.encode())),
                    "image/png",
                )
            },
        ),
        201,
    )
    task = _data(
        client.post(
            "/api/ocr/tasks",
            headers=headers,
            json={
                "document_id": document["id"],
                "document_revision_id": document["current_revision_id"],
            },
        ),
        201,
    )
    with build_session_factory(engine)() as session:
        record = session.get(OCRTask, task["id"])
        assert record is not None
        record.status = "pending_confirmation"
        result_id = new_uuid()
        result = OCRResult(
            id=result_id,
            task_id=record.id,
            raw_response={"provider": "qwen3-vl"},
            validated_draft={
                "hospital_name": "Pomi",
                "department_name": "Endocrinology",
                "prescribed_at": "2026-08-27",
                "orders": [
                    {
                        "source_text": f"{item['drug_name']} original order",
                        "drug_name": item["drug_name"],
                        "normalized_drug_name": None,
                        "specification": None,
                        "dosage_text": None,
                        "dosage_value": None,
                        "dosage_unit": None,
                        "frequency": None,
                        "duration": None,
                        "route": None,
                        "instruction": None,
                    }
                    for item in medications
                ],
            },
        )
        session.add(result)
        session.flush()
        for index, item in enumerate(medications):
            for field, value in (
                ("drug_name", item["drug_name"]),
                ("dosage_value", None),
                ("frequency", None),
            ):
                session.add(
                    OCRFieldResult(
                        id=new_uuid(),
                        result_id=result_id,
                        field_path=f"orders.{index}.{field}",
                        source_text=f"{item['drug_name']} original order",
                        parsed_value=value,
                        confidence=0.7,
                        confirmation_status="pending",
                    )
                )
        session.commit()
    return {
        "task_id": task["id"],
        "result_id": result_id,
        "revision_id": document["current_revision_id"],
        "document_id": document["id"],
    }


def _medication(
    client: TestClient, headers: dict[str, str], name: str, dose: int, key: str
) -> dict:
    return _data(
        client.post(
            "/api/medications",
            headers={**headers, "Idempotency-Key": key},
            json={
                "drug_name": name,
                "source_category": "prescribed",
                "dosage_value": dose,
                "dosage_unit": "mg",
                "frequency": "twice daily",
                "start_date": "2026-08-01",
                "event_date": "2026-08-01",
            },
        ),
        201,
    )["medication"]


def _confirmed(index: int, name: str, dose: int, *, stopped: bool = False) -> dict:
    return {
        "source_index": index,
        "confirmed": True,
        "source_text": f"{name} {dose} mg twice daily",
        "drug_name": name,
        "specification": f"{dose} mg",
        "dosage_value": dose,
        "dosage_unit": "mg",
        "frequency": "twice daily",
        "duration": "30 days",
        "route": "oral",
        "instruction": "after meals",
        "prescribed_at": "2026-08-27",
        "explicitly_stopped": stopped,
    }


def _confirmation(context: dict, items: list[dict]) -> dict:
    return {
        "result_id": context["result_id"],
        "expected_revision_id": context["revision_id"],
        "items": items,
    }


def test_confirmation_is_traceable_separate_idempotent_and_uid_scoped(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "order-owner")
    outsider = _auth(api_client, "order-outsider")
    context = _task(
        api_client, owner, api_engine, [{"drug_name": "Metformin"}, {"drug_name": "Unknown brand"}]
    )

    incomplete = api_client.post(
        f"/api/ocr/tasks/{context['task_id']}/confirm",
        headers=owner,
        json=_confirmation(context, [_confirmed(0, "Metformin", 500)]),
    )
    assert incomplete.status_code == 422
    assert incomplete.json()["error"]["code"] == "MEDICAL_ORDER_ITEMS_INCOMPLETE"

    payload = _confirmation(
        context,
        [_confirmed(0, "Metformin", 500), _confirmed(1, "Unknown brand", 10)],
    )
    confirmed = _data(
        api_client.post(f"/api/ocr/tasks/{context['task_id']}/confirm", headers=owner, json=payload)
    )
    repeated = _data(
        api_client.post(f"/api/ocr/tasks/{context['task_id']}/confirm", headers=owner, json=payload)
    )
    assert repeated["reused"] is True
    assert [item["id"] for item in repeated["items"]] == [item["id"] for item in confirmed["items"]]
    assert confirmed["items"][0]["standard_drug_id"] == "rxnorm:metformin"
    assert confirmed["items"][1]["standard_drug_id"] is None
    assert confirmed["items"][1]["review_required"] is True
    assert confirmed["items"][0]["source_text"].startswith("Metformin")
    assert confirmed["p0_evaluation"] == {
        "total_fields": 6,
        "valid_fields": 6,
        "invalid_fields": 0,
        "valid_rate": 1.0,
        "ocr_exact_match_fields": 2,
        "user_corrected_fields": 4,
        "ocr_exact_match_rate": pytest.approx(2 / 6, abs=0.0001),
    }
    changed = _confirmation(
        context,
        [_confirmed(0, "Metformin", 500), _confirmed(1, "Unknown brand", 10)],
    )
    changed["items"][0]["instruction"] = "before meals"
    conflict = api_client.post(
        f"/api/ocr/tasks/{context['task_id']}/confirm", headers=owner, json=changed
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "OCR_ALREADY_CONFIRMED"
    assert (
        api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm", headers=outsider, json=payload
        ).status_code
        == 404
    )
    with build_session_factory(api_engine)() as session:
        orders = list(session.scalars(select(MedicalOrder).order_by(MedicalOrder.medication_index)))
        assert len(orders) == 2
        assert orders[0].original_item_data["drug_name"] == "Metformin"
        assert orders[0].confirmed_item_data["dosage_value"] == "500"
        statuses = set(session.scalars(select(OCRFieldResult.confirmation_status)))
        assert statuses <= {"confirmed", "edited", "rejected"}
        assert session.scalar(select(func.count()).select_from(Medication)) == 0


def test_confirmation_rejects_deleted_source_revoked_session_and_bad_dates(
    api_client: TestClient, api_engine
) -> None:
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 27)
    owner = _auth(api_client, "order-source-guard")
    deleted = _task(api_client, owner, api_engine, [{"drug_name": "Metformin"}])
    assert (
        api_client.delete(f"/api/documents/{deleted['document_id']}", headers=owner).status_code
        == 200
    )
    response = api_client.post(
        f"/api/ocr/tasks/{deleted['task_id']}/confirm",
        headers=owner,
        json=_confirmation(deleted, [_confirmed(0, "Metformin", 500)]),
    )
    assert response.status_code == 404

    active = _task(api_client, owner, api_engine, [{"drug_name": "Metformin"}])
    invalid = _confirmed(0, "Metformin", 500)
    invalid["prescribed_at"] = "2026-08-28"
    response = api_client.post(
        f"/api/ocr/tasks/{active['task_id']}/confirm",
        headers=owner,
        json=_confirmation(active, [invalid]),
    )
    assert response.status_code == 422
    assert response.json()["error"]["details"]["fields"][0]["path"] == ("items.0.prescribed_at")
    assert api_client.post("/api/auth/logout", headers=owner).status_code == 204
    response = api_client.post(
        f"/api/ocr/tasks/{active['task_id']}/confirm",
        headers=owner,
        json=_confirmation(active, [_confirmed(0, "Metformin", 500)]),
    )
    assert response.status_code == 401
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicalOrder)) == 0


def test_concurrent_confirmation_creates_one_formal_order_set(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "order-confirm-race")
    context = _task(api_client, owner, api_engine, [{"drug_name": "Metformin"}])
    payload = _confirmation(context, [_confirmed(0, "Metformin", 500)])

    def submit() -> tuple[int, dict]:
        response = api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm", headers=owner, json=payload
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: submit(), range(2)))
    assert [status for status, _ in results] == [200, 200]
    assert sorted(body["data"]["reused"] for _, body in results) == [False, True]
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(MedicalOrder)) == 1


def test_reconciliation_adjusts_adds_and_never_stops_an_omitted_drug(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "reconcile-owner")
    outsider = _auth(api_client, "reconcile-outsider")
    old = _medication(api_client, owner, "Metformin", 500, "old-metformin")
    omitted = _medication(api_client, owner, "Vitamin D3", 1000, "old-vitamin-d")
    unchanged = _medication(api_client, owner, "Cholecalciferol", 1000, "old-cholecalciferol")
    context = _task(
        api_client,
        owner,
        api_engine,
        [
            {"drug_name": "Metformin"},
            {"drug_name": "优思明"},
            {"drug_name": "Cholecalciferol"},
        ],
    )
    _data(
        api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm",
            headers=owner,
            json=_confirmation(
                context,
                [
                    _confirmed(0, "Metformin", 850),
                    _confirmed(1, "优思明", 1),
                    _confirmed(2, "Cholecalciferol", 1000),
                ],
            ),
        )
    )

    reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations",
            headers=owner,
            json={"ocr_task_id": context["task_id"]},
        ),
        201,
    )
    assert reconciliation["rule_version"] == "pomi-med-reconcile-v1"
    assert {item["suggestion"] for item in reconciliation["items"]} == {
        "adjusted",
        "added",
        "unchanged",
        "uncertain",
    }
    uncertain = next(item for item in reconciliation["items"] if item["suggestion"] == "uncertain")
    assert uncertain["old_medication"]["id"] == omitted["id"]
    assert uncertain["match_basis"]["automatic_stop"] is False
    assert (
        api_client.get(
            f"/api/medication-reconciliations/{reconciliation['id']}", headers=outsider
        ).status_code
        == 404
    )

    decisions = [{"item_id": item["id"], "decision": "accept"} for item in reconciliation["items"]]
    executed = _data(
        api_client.put(
            f"/api/medication-reconciliations/{reconciliation['id']}",
            headers=owner,
            json={"decisions": decisions},
        )
    )
    repeated = _data(
        api_client.put(
            f"/api/medication-reconciliations/{reconciliation['id']}",
            headers=owner,
            json={"decisions": decisions},
        )
    )
    assert executed["status"] == repeated["status"] == "executed"
    changed_decisions = [dict(item) for item in decisions]
    changed_decisions[0]["decision"] = "reject"
    conflict = api_client.put(
        f"/api/medication-reconciliations/{reconciliation['id']}",
        headers=owner,
        json={"decisions": changed_decisions},
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "RECONCILIATION_ALREADY_EXECUTED"

    with build_session_factory(api_engine)() as session:
        original = session.get(Medication, old["id"])
        omitted_record = session.get(Medication, omitted["id"])
        assert original is not None and original.status == "stopped"
        assert omitted_record is not None and omitted_record.status == "active"
        unchanged_record = session.get(Medication, unchanged["id"])
        assert unchanged_record is not None and unchanged_record.status == "active"
        replacement = session.scalar(
            select(Medication).where(Medication.replaces_medication_id == old["id"])
        )
        assert replacement is not None and replacement.dosage_value == 850
        assert (
            session.scalar(
                select(func.count())
                .select_from(MedicationEvent)
                .where(MedicationEvent.medication_id == replacement.id)
            )
            == 1
        )


def test_concurrent_reconciliation_creation_and_execution_are_idempotent(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "reconcile-race")
    _medication(api_client, owner, "Metformin", 500, "race-old")
    context = _task(api_client, owner, api_engine, [{"drug_name": "Metformin"}])
    _data(
        api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm",
            headers=owner,
            json=_confirmation(context, [_confirmed(0, "Metformin", 850)]),
        )
    )

    def create() -> tuple[int, dict]:
        response = api_client.post(
            "/api/medication-reconciliations",
            headers=owner,
            json={"ocr_task_id": context["task_id"]},
        )
        return response.status_code, response.json()["data"]

    with ThreadPoolExecutor(max_workers=2) as executor:
        created = list(executor.map(lambda _: create(), range(2)))
    assert [status for status, _ in created] == [201, 201]
    assert len({body["id"] for _, body in created}) == 1
    reconciliation = created[0][1]
    decisions = [{"item_id": item["id"], "decision": "accept"} for item in reconciliation["items"]]

    def execute() -> tuple[int, dict]:
        response = api_client.put(
            f"/api/medication-reconciliations/{reconciliation['id']}",
            headers=owner,
            json={"decisions": decisions},
        )
        return response.status_code, response.json()

    with ThreadPoolExecutor(max_workers=2) as executor:
        executed = list(executor.map(lambda _: execute(), range(2)))
    assert [status for status, _ in executed] == [200, 200]
    with build_session_factory(api_engine)() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(MedicationEvent)
                .where(MedicationEvent.source_type == "medical_order")
            )
            == 1
        )
        assert (
            session.scalar(
                select(func.count()).select_from(Medication).where(Medication.status == "active")
            )
            == 1
        )


def test_execution_failure_rolls_back_every_medication_and_event(
    api_client: TestClient, api_engine, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = _auth(api_client, "reconcile-rollback")
    context = _task(
        api_client,
        owner,
        api_engine,
        [{"drug_name": "Metformin"}, {"drug_name": "优思明"}],
    )
    _data(
        api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm",
            headers=owner,
            json=_confirmation(
                context,
                [_confirmed(0, "Metformin", 500), _confirmed(1, "优思明", 1)],
            ),
        )
    )
    reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations",
            headers=owner,
            json={"ocr_task_id": context["task_id"]},
        ),
        201,
    )
    original = ReconciliationService._create_medication
    calls = 0

    def fail_on_second(self, order, old):
        nonlocal calls
        calls += 1
        created = original(self, order, old)
        if calls == 2:
            raise RuntimeError("simulated persistence failure")
        return created

    monkeypatch.setattr(ReconciliationService, "_create_medication", fail_on_second)
    decisions = [{"item_id": item["id"], "decision": "accept"} for item in reconciliation["items"]]
    with pytest.raises(RuntimeError, match="simulated persistence failure"):
        api_client.put(
            f"/api/medication-reconciliations/{reconciliation['id']}",
            headers=owner,
            json={"decisions": decisions},
        )
    with build_session_factory(api_engine)() as session:
        assert session.scalar(select(func.count()).select_from(Medication)) == 0
        assert session.scalar(select(func.count()).select_from(MedicationEvent)) == 0
        record = session.get(MedicationReconciliation, reconciliation["id"])
        assert record is not None and record.status == "draft"


def test_manual_review_blocks_atomically_and_explicit_stop_requires_evidence(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "atomic-owner")
    old = _medication(api_client, owner, "Metformin", 500, "atomic-old")
    context = _task(api_client, owner, api_engine, [{"drug_name": "Unknown"}])
    _data(
        api_client.post(
            f"/api/ocr/tasks/{context['task_id']}/confirm",
            headers=owner,
            json=_confirmation(context, [_confirmed(0, "Unknown", 5)]),
        )
    )
    reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations",
            headers=owner,
            json={"ocr_task_id": context["task_id"]},
        ),
        201,
    )
    manual = next(item for item in reconciliation["items"] if item["suggestion"] == "manual_review")
    before = len(_data(api_client.get("/api/medications", headers=owner))["items"])
    failed = api_client.put(
        f"/api/medication-reconciliations/{reconciliation['id']}",
        headers=owner,
        json={
            "decisions": [
                {
                    "item_id": item["id"],
                    "decision": "accept" if item["id"] == manual["id"] else "keep_current",
                }
                for item in reconciliation["items"]
            ]
        },
    )
    assert failed.status_code == 422
    assert len(_data(api_client.get("/api/medications", headers=owner))["items"]) == before
    with build_session_factory(api_engine)() as session:
        assert session.get(Medication, old["id"]).status == "active"  # type: ignore[union-attr]

    stop_context = _task(
        api_client,
        owner,
        api_engine,
        [{"drug_name": "Metformin", "explicitly_stopped": True}, {"drug_name": "Unknown"}],
    )
    _data(
        api_client.post(
            f"/api/ocr/tasks/{stop_context['task_id']}/confirm",
            headers=owner,
            json=_confirmation(
                stop_context,
                [
                    _confirmed(0, "Metformin", 500, stopped=True),
                    _confirmed(1, "Unknown", 1),
                ],
            ),
        )
    )
    stop_reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations",
            headers=owner,
            json={"ocr_task_id": stop_context["task_id"]},
        ),
        201,
    )
    stopped = next(item for item in stop_reconciliation["items"] if item["suggestion"] == "stopped")
    decisions = [
        {
            "item_id": item["id"],
            "decision": "accept" if item["id"] == stopped["id"] else "keep_current",
        }
        for item in stop_reconciliation["items"]
    ]
    no_evidence = api_client.put(
        f"/api/medication-reconciliations/{stop_reconciliation['id']}",
        headers=owner,
        json={"decisions": decisions},
    )
    assert no_evidence.status_code == 422
    for decision in decisions:
        if decision["item_id"] == stopped["id"]:
            decision.update({"stop_date": "2026-08-27", "stop_source": "written_order"})
    _data(
        api_client.put(
            f"/api/medication-reconciliations/{stop_reconciliation['id']}",
            headers=owner,
            json={"decisions": decisions},
        )
    )
    with build_session_factory(api_engine)() as session:
        record = session.get(Medication, old["id"])
        assert record is not None and record.status == "stopped"
        event = session.scalar(
            select(MedicationEvent).where(
                MedicationEvent.medication_id == old["id"], MedicationEvent.event_type == "stopped"
            )
        )
        assert event is not None and event.stop_source == "written_order"
