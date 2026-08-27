from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy import Engine, select

from pomi_backend.admin import reset_password, seed_initial_accounts
from pomi_backend.config import Settings
from pomi_backend.db import build_session_factory
from pomi_backend.db.models import UserAccount, UserSession
from pomi_backend.main import create_app
from pomi_backend.services.security import PasswordManager


def test_seed_accounts_is_idempotent_and_sets_onboarding_state(
    api_engine: Engine, api_settings: Settings
) -> None:
    session_factory = build_session_factory(api_engine)
    password_manager = PasswordManager(api_settings)
    with session_factory() as session:
        first_run = seed_initial_accounts(
            session,
            password_manager,
            first_time_account_name="first-time-user",
            first_time_password="FirstTime123",
            returning_account_name="returning-user",
            returning_password="Returning123",
        )
        first_hashes = {
            account.account_name: account.password_hash
            for account in session.scalars(select(UserAccount)).all()
        }
        second_run = seed_initial_accounts(
            session,
            password_manager,
            first_time_account_name="first-time-user",
            first_time_password="IgnoredPass123",
            returning_account_name="returning-user",
            returning_password="IgnoredPass123",
        )
        second_hashes = {
            account.account_name: account.password_hash
            for account in session.scalars(select(UserAccount)).all()
        }

    assert [result.created for result in first_run] == [True, True]
    assert [result.created for result in second_run] == [False, False]
    assert first_hashes == second_hashes
    assert first_run[0].onboarding_completed is False
    assert first_run[1].onboarding_completed is True
    assert all("demo" not in result.account_name for result in first_run)

    with TestClient(create_app(settings=api_settings, engine=api_engine)) as client:
        first_login = client.post(
            "/api/auth/login",
            json={"account_name": "first-time-user", "password": "FirstTime123"},
        )
        returning_login = client.post(
            "/api/auth/login",
            json={"account_name": "returning-user", "password": "Returning123"},
        )
    assert first_login.status_code == returning_login.status_code == 200
    assert first_login.json()["account"]["onboarding_completed"] is False
    assert returning_login.json()["account"]["onboarding_completed"] is True


def test_reset_password_revokes_every_session_atomically(
    api_engine: Engine, api_settings: Settings
) -> None:
    session_factory = build_session_factory(api_engine)
    password_manager = PasswordManager(api_settings)
    with TestClient(create_app(settings=api_settings, engine=api_engine)) as client:
        assert (
            client.post(
                "/api/auth/register",
                json={"account_name": "reset-user", "password": "OldPassword123"},
            ).status_code
            == 201
        )
        sessions = [
            client.post(
                "/api/auth/login",
                json={"account_name": "reset-user", "password": "OldPassword123"},
            ).json()["session_id"]
            for _ in range(2)
        ]

        with session_factory() as database_session:
            revoked_count = reset_password(
                database_session,
                password_manager,
                account_name="reset-user",
                new_password="NewPassword456",
            )
        assert revoked_count == 2

        for session_id in sessions:
            assert (
                client.get(
                    "/api/auth/me", headers={"Authorization": f"Bearer {session_id}"}
                ).status_code
                == 401
            )
        assert (
            client.post(
                "/api/auth/login",
                json={"account_name": "reset-user", "password": "OldPassword123"},
            ).status_code
            == 401
        )
        assert (
            client.post(
                "/api/auth/login",
                json={"account_name": "reset-user", "password": "NewPassword456"},
            ).status_code
            == 200
        )

    with session_factory() as database_session:
        stored_sessions = database_session.scalars(select(UserSession)).all()
        assert len(stored_sessions) == 3
        assert [item.status for item in stored_sessions].count("revoked") == 2
