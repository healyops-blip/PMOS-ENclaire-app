from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.db.models import UserAccount, UserSession
from pomi_backend.repositories import AuthRepository


def test_account_and_session_lifecycle(db_session: Session) -> None:
    repository = AuthRepository(db_session)
    account = repository.create_account(
        account_name="new-user",
        password_hash="$argon2id$stored-hash-only",
        phone_number=None,
    )
    db_session.commit()

    assert account.id is not None
    assert len(account.uid) == 36
    assert account.uid != str(account.id)
    assert repository.get_account_by_uid(account.uid) is account
    assert repository.get_account_by_name("new-user") is account

    expires_at = datetime.now(UTC) + timedelta(days=7)
    user_session = repository.create_session(
        account_uid=account.uid,
        session_hash="sha256:opaque-session-hash",
        expires_at=expires_at,
        client_platform="android",
        device_name="Pixel Emulator",
    )
    db_session.commit()

    assert user_session.status == "active"
    assert repository.get_session_by_hash(user_session.session_hash) is user_session
    assert repository.revoke_session(user_session.session_hash)
    db_session.commit()
    assert user_session.status == "revoked"
    assert user_session.revoked_at is not None
    assert not repository.revoke_session(user_session.session_hash)


def test_revoke_all_active_sessions(db_session: Session) -> None:
    repository = AuthRepository(db_session)
    account = repository.create_account(
        account_name="returning-user",
        password_hash="$argon2id$stored-hash-only",
        onboarding_completed=True,
    )
    expires_at = datetime.now(UTC) + timedelta(days=7)
    for index in range(2):
        repository.create_session(
            account_uid=account.uid,
            session_hash=f"sha256:session-{index}",
            expires_at=expires_at,
        )
    db_session.commit()

    assert repository.revoke_all_sessions(account.uid) == 2
    db_session.commit()
    assert {item.status for item in account.sessions} == {"revoked"}


def test_unique_account_name_and_session_hash(db_session: Session) -> None:
    repository = AuthRepository(db_session)
    first = repository.create_account(account_name="unique-name", password_hash="$argon2id$first")
    db_session.commit()

    with pytest.raises(IntegrityError):
        repository.create_account(account_name="unique-name", password_hash="$argon2id$second")
    db_session.rollback()

    expires_at = datetime.now(UTC) + timedelta(days=7)
    repository.create_session(
        account_uid=first.uid,
        session_hash="sha256:unique",
        expires_at=expires_at,
    )
    db_session.commit()
    with pytest.raises(IntegrityError):
        repository.create_session(
            account_uid=first.uid,
            session_hash="sha256:unique",
            expires_at=expires_at,
        )


def test_foreign_key_and_cascade_delete(db_session: Session) -> None:
    repository = AuthRepository(db_session)
    account = repository.create_account(account_name="cascade-user", password_hash="$argon2id$hash")
    repository.create_session(
        account_uid=account.uid,
        session_hash="sha256:cascade",
        expires_at=datetime.now(UTC) + timedelta(days=7),
    )
    db_session.commit()

    db_session.execute(delete(UserAccount).where(UserAccount.uid == account.uid))
    db_session.commit()
    assert db_session.query(UserSession).count() == 0


def test_invalid_status_is_rejected(db_session: Session) -> None:
    invalid = UserAccount(
        account_name="invalid-status",
        password_hash="$argon2id$hash",
        status="unknown",
    )
    db_session.add(invalid)
    with pytest.raises(IntegrityError):
        db_session.commit()
