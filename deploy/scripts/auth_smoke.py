#!/usr/bin/env python3
"""Run a destructive authentication smoke test against the deployed HTTPS API."""

from __future__ import annotations

import getpass
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "https://api.healy1012-ops.top"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def request(
    method: str,
    path: str,
    *,
    payload: dict[str, object] | None = None,
    session_id: str | None = None,
    expected_status: int,
) -> dict[str, object] | None:
    body = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"}
    if session_id is not None:
        headers["Authorization"] = f"Bearer {session_id}"
    api_request = urllib.request.Request(
        f"{BASE_URL}{path}", data=body, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(api_request, timeout=15) as response:
            status = response.status
            content = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        content = error.read()
    if status != expected_status:
        raise RuntimeError(f"{method} {path}: expected {expected_status}, received {status}")
    return json.loads(content) if content else None


def main() -> int:
    first_time_password = os.getenv("POMI_FIRST_TIME_ACCOUNT_PASSWORD") or getpass.getpass(
        "First-time account password: "
    )
    returning_password = os.getenv("POMI_RETURNING_ACCOUNT_PASSWORD") or getpass.getpass(
        "Returning account password: "
    )
    account_name = f"smoke-{int(time.time())}-{secrets.token_hex(3)}"
    password = f"Smoke{secrets.token_urlsafe(18)}7"
    reset_password = f"Reset{secrets.token_urlsafe(18)}7"
    request(
        "POST",
        "/api/auth/register",
        payload={"account_name": account_name, "password": password},
        expected_status=201,
    )
    login = request(
        "POST",
        "/api/auth/login",
        payload={
            "account_name": account_name,
            "password": password,
            "client_platform": "android",
            "device_name": "deployment-smoke",
        },
        expected_status=200,
    )
    assert login is not None
    session_id = str(login["session_id"])
    request("GET", "/api/auth/me", session_id=session_id, expected_status=200)

    admin_command = REPOSITORY_ROOT / "backend" / ".venv" / "bin" / "pomi-admin"
    admin_environment = os.environ.copy()
    admin_environment.setdefault("POMI_DATABASE_URL", "sqlite:////var/lib/pomi/pomi.db")
    admin_environment["POMI_RESET_PASSWORD"] = reset_password
    reset_result = subprocess.run(
        [str(admin_command), "reset-password", account_name],
        check=False,
        capture_output=True,
        text=True,
        env=admin_environment,
    )
    if reset_result.returncode != 0:
        raise RuntimeError("server-local password reset command failed")

    request("GET", "/api/auth/me", session_id=session_id, expected_status=401)
    request(
        "POST",
        "/api/auth/login",
        payload={"account_name": account_name, "password": password},
        expected_status=401,
    )
    reset_login = request(
        "POST",
        "/api/auth/login",
        payload={"account_name": account_name, "password": reset_password},
        expected_status=200,
    )
    assert reset_login is not None
    reset_session_id = str(reset_login["session_id"])
    request("POST", "/api/auth/logout", session_id=reset_session_id, expected_status=204)
    request("POST", "/api/auth/logout", session_id=reset_session_id, expected_status=204)
    request("GET", "/api/auth/me", session_id=reset_session_id, expected_status=401)

    initial_accounts = (
        (
            os.getenv("POMI_FIRST_TIME_ACCOUNT_NAME", "first-time-user"),
            first_time_password,
            False,
        ),
        (
            os.getenv("POMI_RETURNING_ACCOUNT_NAME", "returning-user"),
            returning_password,
            True,
        ),
    )
    for initial_name, initial_password, expected_onboarding in initial_accounts:
        initial_login = request(
            "POST",
            "/api/auth/login",
            payload={"account_name": initial_name, "password": initial_password},
            expected_status=200,
        )
        assert initial_login is not None
        account = initial_login["account"]
        if not isinstance(account, dict) or account.get(
            "onboarding_completed"
        ) is not expected_onboarding:
            raise RuntimeError(f"unexpected onboarding state for {initial_name}")
        initial_session_id = str(initial_login["session_id"])
        request(
            "POST", "/api/auth/logout", session_id=initial_session_id, expected_status=204
        )

    print(f"Authentication smoke test passed for temporary account {account_name}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, AssertionError, KeyError) as error:
        print(f"Authentication smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
