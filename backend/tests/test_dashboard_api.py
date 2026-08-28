from __future__ import annotations

from datetime import UTC, date, datetime

from fastapi.testclient import TestClient
from sqlalchemy import select

from pomi_backend.db.models import (
    Medication,
    MedicationDaily,
    MedicationEvent,
    PatientProfile,
    ReportSnapshot,
    UserAccount,
)
from pomi_backend.services.dashboard import DashboardService


def auth(client: TestClient, name: str) -> dict[str, str]:
    password = "Dashboard123"
    assert (
        client.post(
            "/api/auth/register", json={"account_name": name, "password": password}
        ).status_code
        == 201
    )
    login = client.post("/api/auth/login", json={"account_name": name, "password": password})
    return {"Authorization": f"Bearer {login.json()['session_id']}"}


def data(response) -> dict:
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_new_patient_gets_stable_empty_sections_and_requires_authentication(
    api_client: TestClient,
) -> None:
    assert api_client.get("/api/dashboard").status_code == 401
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 27)
    dashboard = data(api_client.get("/api/dashboard", headers=auth(api_client, "dash-empty")))

    assert dashboard["server_date"] == "2026-08-27"
    assert dashboard["data_as_of"]
    assert dashboard["follow_up"]["status"] == "empty"
    assert dashboard["today_medications"]["data"] == []
    assert dashboard["monthly_medication_summary"]["status"] == "empty"
    assert dashboard["latest_report"] == {
        "status": "empty",
        "data": None,
        "error_code": None,
        "error": None,
    }


def test_follow_up_states_never_return_negative_countdowns(api_client: TestClient) -> None:
    headers = auth(api_client, "dash-follow-up")
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 27)
    profile = data(api_client.get("/api/patient/profile", headers=headers))

    for visit, expected_state, expected_days in (
        ("2026-09-01", "upcoming", 5),
        ("2026-08-27", "due", 0),
        ("2026-08-20", "overdue", 0),
    ):
        payload = {
            "nickname": "Patient",
            "next_visit_date": visit,
            "updated_at": profile["updated_at"],
        }
        profile = data(api_client.put("/api/patient/profile", headers=headers, json=payload))
        follow_up = data(api_client.get("/api/dashboard", headers=headers))["follow_up"]
        assert follow_up["data"]["state"] == expected_state
        assert follow_up["data"]["days_remaining"] == expected_days


def test_monthly_three_state_respects_pause_resume_and_stop_boundaries(
    api_client: TestClient,
) -> None:
    headers = auth(api_client, "dash-boundaries")
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 27)
    data(api_client.get("/api/patient/profile", headers=headers))
    factory = api_client.app.state.session_factory
    with factory() as session:
        account = session.scalar(
            select(UserAccount).where(UserAccount.account_name == "dash-boundaries")
        )
        assert account is not None
        profile = session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == account.uid)
        )
        assert profile is not None
        medication = Medication(
            patient_id=profile.patient_id,
            drug_name="Metformin",
            source_category="prescribed",
            frequency="daily",
            status="stopped",
            start_date=date(2026, 8, 1),
            end_date=date(2026, 8, 20),
        )
        session.add(medication)
        session.flush()
        for kind, event_date in (
            ("created", date(2026, 8, 1)),
            ("paused", date(2026, 8, 10)),
            ("resumed", date(2026, 8, 15)),
            ("stopped", date(2026, 8, 20)),
        ):
            session.add(
                MedicationEvent(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    event_type=kind,
                    event_date=event_date,
                    source_type="manual",
                    acted_by_uid=account.uid,
                )
            )
        session.add_all(
            [
                MedicationDaily(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    record_date=date(2026, 8, 2),
                    intake_status="taken",
                    recorded_by_uid=account.uid,
                ),
                MedicationDaily(
                    patient_id=profile.patient_id,
                    medication_id=medication.id,
                    record_date=date(2026, 8, 16),
                    intake_status="missed",
                    recorded_by_uid=account.uid,
                ),
            ]
        )
        session.commit()

    dashboard = data(api_client.get("/api/dashboard", headers=headers))
    assert dashboard["today_medications"]["status"] == "empty"
    assert dashboard["monthly_medication_summary"]["data"] == {
        "month": "2026-08",
        "taken_count": 1,
        "missed_count": 1,
        "unrecorded_count": 12,
    }


def test_section_failure_returns_200_without_blocking_siblings(
    api_client: TestClient, monkeypatch
) -> None:
    headers = auth(api_client, "dash-partial")
    monkeypatch.setattr(
        DashboardService,
        "today_medications",
        lambda _: (_ for _ in ()).throw(RuntimeError("database unavailable")),
    )

    dashboard = data(api_client.get("/api/dashboard", headers=headers))

    assert dashboard["today_medications"]["status"] == "error"
    assert dashboard["today_medications"]["error"]["code"] == ("TODAY_MEDICATIONS_UNAVAILABLE")
    assert dashboard["follow_up"]["status"] == "empty"
    assert dashboard["latest_report"]["status"] == "empty"


def test_latest_report_returns_only_the_newest_successful_owned_snapshot(
    api_client: TestClient,
) -> None:
    owner = auth(api_client, "dash-report-owner")
    stranger = auth(api_client, "dash-report-stranger")
    data(api_client.get("/api/patient/profile", headers=owner))
    factory = api_client.app.state.session_factory
    with factory() as session:
        account = session.scalar(
            select(UserAccount).where(UserAccount.account_name == "dash-report-owner")
        )
        assert account is not None
        profile = session.scalar(
            select(PatientProfile).where(PatientProfile.account_uid == account.uid)
        )
        assert profile is not None
        older = ReportSnapshot(
            patient_id=profile.patient_id,
            report_status="succeeded",
            snapshot_json={"private": "older body"},
            source_digest="a" * 64,
            snapshot_hash="b" * 64,
            generated_by_uid=account.uid,
            report_generated_at=datetime(2026, 8, 26, 10, tzinfo=UTC),
        )
        newer = ReportSnapshot(
            patient_id=profile.patient_id,
            report_status="succeeded",
            snapshot_json={"private": "newer body"},
            source_digest="c" * 64,
            snapshot_hash="d" * 64,
            generated_by_uid=account.uid,
            report_generated_at=datetime(2026, 8, 27, 10, tzinfo=UTC),
        )
        failed = ReportSnapshot(
            patient_id=profile.patient_id,
            report_status="failed",
            source_digest="e" * 64,
            generated_by_uid=account.uid,
            failure_reason="generation failed",
        )
        session.add_all([older, newer, failed])
        session.commit()
        newer_id = newer.id

    latest = data(api_client.get("/api/dashboard", headers=owner))["latest_report"]
    assert latest["status"] == "ok"
    assert latest["data"] == {
        "report_id": newer_id,
        "status": "succeeded",
        "generated_at": "2026-08-27T10:00:00+00:00",
        "snapshot_hash": "d" * 64,
    }
    assert "private" not in latest["data"]
    assert (
        data(api_client.get("/api/dashboard", headers=stranger))["latest_report"]["status"]
        == "empty"
    )


def test_dashboard_is_strictly_isolated_by_session_uid(api_client: TestClient) -> None:
    first = auth(api_client, "dash-owner-a")
    second = auth(api_client, "dash-owner-b")
    api_client.app.state.business_date_provider = lambda: date(2026, 8, 27)
    first_profile = data(api_client.get("/api/patient/profile", headers=first))
    data(
        api_client.put(
            "/api/patient/profile",
            headers=first,
            json={
                "nickname": "Owner A",
                "next_visit_date": "2026-09-09",
                "updated_at": first_profile["updated_at"],
            },
        )
    )
    created = api_client.post(
        "/api/medications",
        headers={**first, "Idempotency-Key": "dashboard-owner-medication"},
        json={
            "drug_name": "Private medication",
            "source_category": "prescribed",
            "frequency": "daily",
            "start_date": "2026-08-01",
            "event_date": "2026-08-01",
        },
    )
    assert created.status_code == 201, created.text

    owner_dashboard = data(api_client.get("/api/dashboard", headers=first))
    stranger_dashboard = data(
        api_client.get("/api/dashboard?uid=attacker-controlled", headers=second)
    )
    assert owner_dashboard["follow_up"]["status"] == "ok"
    assert len(owner_dashboard["today_medications"]["data"]) == 1
    assert stranger_dashboard["follow_up"]["status"] == "empty"
    assert stranger_dashboard["today_medications"]["data"] == []
