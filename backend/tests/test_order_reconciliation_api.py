from __future__ import annotations

from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import func, select

from pomi_backend.db import build_session_factory
from pomi_backend.db.models import Medication, MedicationEvent, OCRResult, OCRTask
from pomi_backend.db.models.health import new_uuid


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


def _task(client: TestClient, headers: dict[str, str], engine, medications: list[dict]) -> str:
    document = _data(
        client.post(
            "/api/documents",
            headers={**headers, "Idempotency-Key": f"order-source-{len(medications)}"},
            data={
                "document_type": "medical_order",
                "external_processing_consent_version": "ocr-v1",
            },
            files={"file": ("order.png", _png(len(medications)), "image/png")},
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
        session.add(
            OCRResult(
                id=new_uuid(),
                task_id=record.id,
                raw_response={"provider": "qwen3-vl"},
                validated_draft={
                    "facility": "Pomi",
                    "order_date": "2026-08-27",
                    "order_text": "original full order",
                    "medications": medications,
                },
            )
        )
        session.commit()
    return task["id"]


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
        "index": index,
        "confirmed": True,
        "drug_name": name,
        "specification": f"{dose} mg",
        "dosage_value": dose,
        "dosage_unit": "mg",
        "frequency": "twice daily",
        "course": "30 days",
        "route": "oral",
        "instructions": "after meals",
        "order_date": "2026-08-27",
        "raw_order_text": f"{name} {dose} mg twice daily",
        "explicitly_stopped": stopped,
    }


def test_confirmation_is_traceable_separate_idempotent_and_uid_scoped(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "order-owner")
    outsider = _auth(api_client, "order-outsider")
    task_id = _task(
        api_client, owner, api_engine, [{"drug_name": "Metformin"}, {"drug_name": "Unknown brand"}]
    )

    incomplete = api_client.post(
        f"/api/ocr/tasks/{task_id}/confirm",
        headers=owner,
        json={"items": [_confirmed(0, "Metformin", 500)]},
    )
    assert incomplete.status_code == 422
    assert incomplete.json()["error"]["code"] == "MEDICAL_ORDER_ITEMS_INCOMPLETE"

    payload = {"items": [_confirmed(0, "Metformin", 500), _confirmed(1, "Unknown brand", 10)]}
    confirmed = _data(
        api_client.post(f"/api/ocr/tasks/{task_id}/confirm", headers=owner, json=payload), 201
    )
    repeated = _data(
        api_client.post(f"/api/ocr/tasks/{task_id}/confirm", headers=owner, json=payload), 201
    )
    assert repeated["reused"] is True
    assert [item["id"] for item in repeated["items"]] == [item["id"] for item in confirmed["items"]]
    assert confirmed["items"][0]["standard_drug_id"] == "rxnorm:metformin"
    assert confirmed["items"][1]["standard_drug_id"] is None
    assert confirmed["items"][1]["review_required"] is True
    assert confirmed["items"][0]["raw_order_text"].startswith("Metformin")
    assert (
        api_client.post(
            f"/api/ocr/tasks/{task_id}/confirm", headers=outsider, json=payload
        ).status_code
        == 404
    )


def test_reconciliation_adjusts_adds_and_never_stops_an_omitted_drug(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "reconcile-owner")
    outsider = _auth(api_client, "reconcile-outsider")
    old = _medication(api_client, owner, "Metformin", 500, "old-metformin")
    omitted = _medication(api_client, owner, "Vitamin D3", 1000, "old-vitamin-d")
    task_id = _task(
        api_client, owner, api_engine, [{"drug_name": "Metformin"}, {"drug_name": "优思明"}]
    )
    _data(
        api_client.post(
            f"/api/ocr/tasks/{task_id}/confirm",
            headers=owner,
            json={"items": [_confirmed(0, "Metformin", 850), _confirmed(1, "优思明", 1)]},
        ),
        201,
    )

    reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations", headers=owner, json={"ocr_task_id": task_id}
        ),
        201,
    )
    assert reconciliation["rule_version"] == "pomi-med-reconcile-v1"
    assert {item["suggestion"] for item in reconciliation["items"]} == {
        "adjusted",
        "added",
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

    with build_session_factory(api_engine)() as session:
        original = session.get(Medication, old["id"])
        omitted_record = session.get(Medication, omitted["id"])
        assert original is not None and original.status == "stopped"
        assert omitted_record is not None and omitted_record.status == "active"
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


def test_manual_review_blocks_atomically_and_explicit_stop_requires_evidence(
    api_client: TestClient, api_engine
) -> None:
    owner = _auth(api_client, "atomic-owner")
    old = _medication(api_client, owner, "Metformin", 500, "atomic-old")
    task_id = _task(api_client, owner, api_engine, [{"drug_name": "Unknown"}])
    _data(
        api_client.post(
            f"/api/ocr/tasks/{task_id}/confirm",
            headers=owner,
            json={"items": [_confirmed(0, "Unknown", 5)]},
        ),
        201,
    )
    reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations", headers=owner, json={"ocr_task_id": task_id}
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

    stop_task = _task(
        api_client,
        owner,
        api_engine,
        [{"drug_name": "Metformin", "explicitly_stopped": True}, {"drug_name": "Unknown"}],
    )
    _data(
        api_client.post(
            f"/api/ocr/tasks/{stop_task}/confirm",
            headers=owner,
            json={
                "items": [
                    _confirmed(0, "Metformin", 500, stopped=True),
                    _confirmed(1, "Unknown", 1),
                ]
            },
        ),
        201,
    )
    stop_reconciliation = _data(
        api_client.post(
            "/api/medication-reconciliations", headers=owner, json={"ocr_task_id": stop_task}
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
