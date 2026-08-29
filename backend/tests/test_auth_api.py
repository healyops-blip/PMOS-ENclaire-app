from __future__ import annotations

import logging
from dataclasses import replace
from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient
from pytest import LogCaptureFixture
from sqlalchemy import Engine, select

from pomi_backend.config import Settings
from pomi_backend.db import build_session_factory
from pomi_backend.db.models import UserAccount, UserSession
from pomi_backend.main import create_app
from pomi_backend.services.security import hash_session_credential


def register_account(
    client: TestClient,
    *,
    account_name: str = "new-user",
    password: str = "aaaaaaaa1",
    phone_number: str = "+8613812345678",
) -> dict[str, object]:
    response = client.post(
        "/api/auth/register",
        json={
            "account_name": account_name,
            "password": password,
            "phone_number": phone_number,
        },
    )
    assert response.status_code == 201
    return response.json()


def login_account(
    client: TestClient,
    *,
    account_name: str = "new-user",
    password: str = "aaaaaaaa1",
) -> dict[str, object]:
    response = client.post(
        "/api/auth/login",
        json={
            "account_name": account_name,
            "password": password,
            "client_platform": "android",
            "device_name": "Pixel Emulator",
        },
    )
    assert response.status_code == 200
    return response.json()


def test_register_writes_hashed_account_without_session(
    api_client: TestClient, api_engine: Engine
) -> None:
    result = register_account(api_client, account_name=" New.User ")

    assert result["account_name"] == "new.user"
    assert result["phone_number"] == "+8613812345678"
    assert result["phone_verified"] is False
    assert "session_id" not in result
    assert "password" not in result
    assert "password_hash" not in result

    with build_session_factory(api_engine)() as session:
        account = session.scalar(select(UserAccount).where(UserAccount.account_name == "new.user"))
        assert account is not None
        assert account.password_hash != "aaaaaaaa1"
        assert account.password_hash.startswith("$argon2id$")


def test_register_rejects_duplicate_and_invalid_fields(api_client: TestClient) -> None:
    register_account(api_client)
    duplicate = api_client.post(
        "/api/auth/register",
        json={"account_name": "new-user", "password": "bbbbbbbb2"},
    )
    assert duplicate.status_code == 409
    assert duplicate.json() == {
        "error": {
            "code": "ACCOUNT_NAME_TAKEN",
            "message": "This account name is unavailable.",
        }
    }

    duplicate_phone = api_client.post(
        "/api/auth/register",
        json={
            "account_name": "another-user",
            "password": "bbbbbbbb2",
            "phone_number": "+8613812345678",
        },
    )
    assert duplicate_phone.status_code == 409
    assert duplicate_phone.json()["error"]["code"] == "PHONE_NUMBER_TAKEN"

    invalid = api_client.post(
        "/api/auth/register",
        json={
            "account_name": "bad name",
            "password": "allletters",
            "unexpected_role": "admin",
        },
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "VALIDATION_ERROR"


def test_login_returns_plaintext_once_and_stores_only_digest(
    api_client: TestClient, api_engine: Engine
) -> None:
    register_account(api_client)
    result = login_account(api_client)

    session_id = str(result["session_id"])
    assert len(session_id) >= 43
    assert result["token_type"] == "Bearer"
    assert result["account"]["account_name"] == "new-user"

    with build_session_factory(api_engine)() as session:
        stored = session.scalar(select(UserSession))
        account = session.scalar(select(UserAccount))
        assert stored is not None
        assert stored.session_hash == hash_session_credential(session_id)
        assert session_id not in stored.session_hash
        assert stored.client_platform == "android"
        assert account is not None
        assert account.last_login_at is not None


def test_login_accepts_registered_phone_number(api_client: TestClient) -> None:
    register_account(api_client)
    result = login_account(api_client, account_name="+8613812345678")
    assert result["account"]["account_name"] == "new-user"


def test_login_does_not_reveal_account_existence_and_rejects_disabled_account(
    api_client: TestClient, api_engine: Engine
) -> None:
    register_account(api_client)
    wrong_password = api_client.post(
        "/api/auth/login",
        json={"account_name": "new-user", "password": "cccccccc3"},
    )
    missing_account = api_client.post(
        "/api/auth/login",
        json={"account_name": "missing-user", "password": "cccccccc3"},
    )
    assert wrong_password.status_code == missing_account.status_code == 401
    assert wrong_password.json() == missing_account.json()
    assert wrong_password.json()["error"]["code"] == "INVALID_CREDENTIALS"

    with build_session_factory(api_engine)() as session:
        account = session.scalar(select(UserAccount))
        assert account is not None
        account.status = "disabled"
        session.commit()
    disabled = api_client.post(
        "/api/auth/login",
        json={"account_name": "new-user", "password": "aaaaaaaa1"},
    )
    assert disabled.status_code == 401
    assert disabled.json() == wrong_password.json()


def test_bearer_session_authentication_and_uid_cannot_override_identity(
    api_client: TestClient,
) -> None:
    first = register_account(api_client, account_name="first-user")
    register_account(
        api_client,
        account_name="second-user",
        phone_number="+8613812345679",
    )
    login = login_account(api_client, account_name="first-user")
    headers = {"Authorization": f"Bearer {login['session_id']}"}

    current = api_client.get(
        f"/api/auth/me?uid={first['uid']}-client-overwrite-attempt", headers=headers
    )
    assert current.status_code == 200
    assert current.json()["uid"] == first["uid"]
    assert current.json()["account_name"] == "first-user"

    missing = api_client.get(f"/api/auth/me?uid={first['uid']}")
    forged = api_client.get("/api/auth/me", headers={"Authorization": "Bearer forged-session-id"})
    assert missing.status_code == forged.status_code == 401
    assert missing.json()["error"]["code"] == "AUTHENTICATION_REQUIRED"
    assert missing.headers["www-authenticate"] == "Bearer"


def test_logout_is_idempotent_and_invalidates_session(api_client: TestClient) -> None:
    register_account(api_client)
    login = login_account(api_client)
    headers = {"Authorization": f"Bearer {login['session_id']}"}

    assert api_client.post("/api/auth/logout", headers=headers).status_code == 204
    assert api_client.post("/api/auth/logout", headers=headers).status_code == 204
    assert api_client.get("/api/auth/me", headers=headers).status_code == 401
    assert api_client.post("/api/auth/logout").status_code == 401


def test_expired_and_revoked_sessions_are_rejected(
    api_client: TestClient, api_engine: Engine
) -> None:
    register_account(api_client)
    expired_login = login_account(api_client)
    revoked_login = login_account(api_client)

    with build_session_factory(api_engine)() as session:
        expired = session.scalar(
            select(UserSession).where(
                UserSession.session_hash
                == hash_session_credential(str(expired_login["session_id"]))
            )
        )
        revoked = session.scalar(
            select(UserSession).where(
                UserSession.session_hash
                == hash_session_credential(str(revoked_login["session_id"]))
            )
        )
        assert expired is not None and revoked is not None
        expired.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        revoked.status = "revoked"
        revoked.revoked_at = datetime.now(UTC)
        session.commit()

    for session_id in (expired_login["session_id"], revoked_login["session_id"]):
        response = api_client.get("/api/auth/me", headers={"Authorization": f"Bearer {session_id}"})
        assert response.status_code == 401

    with build_session_factory(api_engine)() as session:
        expired = session.scalar(
            select(UserSession).where(
                UserSession.session_hash
                == hash_session_credential(str(expired_login["session_id"]))
            )
        )
        assert expired is not None
        assert expired.status == "expired"


def test_auth_rate_limit_returns_retry_after(api_engine: Engine) -> None:
    settings = Settings(
        database_url="sqlite://",
        environment="test",
        argon2_time_cost=1,
        argon2_memory_cost_kib=8192,
        argon2_parallelism=1,
        auth_rate_limit_attempts=2,
        auth_rate_limit_window_seconds=60,
    )
    with TestClient(create_app(settings=settings, engine=api_engine)) as client:
        payload = {"account_name": "missing-user", "password": "cccccccc3"}
        assert client.post("/api/auth/login", json=payload).status_code == 401
        assert client.post("/api/auth/login", json=payload).status_code == 401
        limited = client.post("/api/auth/login", json=payload)

    assert limited.status_code == 429
    assert limited.json()["error"]["code"] == "AUTH_RATE_LIMITED"
    assert int(limited.headers["retry-after"]) >= 1


def test_openapi_exposes_contract_and_bearer_security(api_client: TestClient) -> None:
    schema = api_client.get("/openapi.json").json()
    assert "/api/auth/register" in schema["paths"]
    assert "/api/auth/login" in schema["paths"]
    assert "/api/auth/me" in schema["paths"]
    assert "/api/auth/logout" in schema["paths"]
    assert schema["components"]["securitySchemes"]["SessionBearer"] == {
        "type": "http",
        "scheme": "bearer",
    }
    assert schema["paths"]["/api/auth/me"]["get"]["security"] == [{"SessionBearer": []}]


def test_health_security_headers_and_production_docs(
    api_client: TestClient, api_engine: Engine, api_settings: Settings
) -> None:
    live = api_client.get("/health/live")
    ready = api_client.get("/health/ready")
    assert live.status_code == ready.status_code == 200
    assert ready.json() == {"status": "ok"}
    assert ready.headers["x-content-type-options"] == "nosniff"
    assert ready.headers["x-frame-options"] == "DENY"

    production_settings = replace(
        api_settings,
        environment="production",
        allowed_hosts=("api.healy1012-ops.top",),
    )
    with TestClient(create_app(settings=production_settings, engine=api_engine)) as client:
        assert client.get("/docs", headers={"Host": "api.healy1012-ops.top"}).status_code == 404
        assert (
            client.get("/openapi.json", headers={"Host": "api.healy1012-ops.top"}).status_code
            == 404
        )
        assert client.get("/health/live", headers={"Host": "attacker.invalid"}).status_code == 400


def test_database_persists_across_app_restart(api_engine: Engine, api_settings: Settings) -> None:
    with TestClient(create_app(settings=api_settings, engine=api_engine)) as first_client:
        register_account(first_client, account_name="restart-user")

    with TestClient(create_app(settings=api_settings, engine=api_engine)) as second_client:
        login = login_account(second_client, account_name="restart-user")
        assert login["account"]["account_name"] == "restart-user"


def test_sensitive_credentials_are_not_logged(
    api_client: TestClient, caplog: LogCaptureFixture
) -> None:
    password = "dddddddd4"
    session_id_marker = "NeverLogThisSessionMarker"
    with caplog.at_level(logging.DEBUG):
        register_account(api_client, password=password)
        login = login_account(api_client, password=password)
        api_client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {login['session_id']}{session_id_marker}"},
        )

    log_output = caplog.text
    assert password not in log_output
    assert str(login["session_id"]) not in log_output
    assert session_id_marker not in log_output
