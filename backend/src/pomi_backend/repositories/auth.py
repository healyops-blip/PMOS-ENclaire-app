"""Account and session persistence operations."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from pomi_backend.db.models.auth import UserAccount, UserSession


class AuthRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def create_account(
        self,
        *,
        account_name: str,
        password_hash: str,
        uid: str | None = None,
        phone_number: str | None = None,
        account_type: str = "user",
        onboarding_completed: bool = False,
    ) -> UserAccount:
        values: dict[str, object] = {
            "account_name": account_name,
            "password_hash": password_hash,
            "phone_number": phone_number,
            "account_type": account_type,
            "onboarding_completed": onboarding_completed,
        }
        if uid is not None:
            values["uid"] = uid
        account = UserAccount(**values)
        self._session.add(account)
        self._session.flush()
        return account

    def get_account_by_uid(self, uid: str) -> UserAccount | None:
        return self._session.scalar(select(UserAccount).where(UserAccount.uid == uid))

    def get_account_by_name(self, account_name: str) -> UserAccount | None:
        return self._session.scalar(
            select(UserAccount).where(UserAccount.account_name == account_name)
        )

    def create_session(
        self,
        *,
        account_uid: str,
        session_hash: str,
        expires_at: datetime,
        client_platform: str | None = None,
        device_name: str | None = None,
    ) -> UserSession:
        user_session = UserSession(
            account_uid=account_uid,
            session_hash=session_hash,
            expires_at=expires_at,
            client_platform=client_platform,
            device_name=device_name,
        )
        self._session.add(user_session)
        self._session.flush()
        return user_session

    def get_session_by_hash(self, session_hash: str) -> UserSession | None:
        return self._session.scalar(
            select(UserSession).where(UserSession.session_hash == session_hash)
        )

    def update_last_login(self, account: UserAccount, *, at: datetime | None = None) -> None:
        account.last_login_at = at or datetime.now(UTC)
        self._session.flush()

    def update_password_hash(self, account: UserAccount, password_hash: str) -> None:
        account.password_hash = password_hash
        self._session.flush()

    def touch_session(self, user_session: UserSession, *, at: datetime | None = None) -> None:
        user_session.last_active_at = at or datetime.now(UTC)
        self._session.flush()

    def expire_session(self, user_session: UserSession) -> None:
        user_session.status = "expired"
        self._session.flush()

    def revoke_session(self, session_hash: str, *, at: datetime | None = None) -> bool:
        revoked_at = at or datetime.now(UTC)
        result = self._session.execute(
            update(UserSession)
            .where(UserSession.session_hash == session_hash, UserSession.status == "active")
            .values(status="revoked", revoked_at=revoked_at)
        )
        return bool(result.rowcount)

    def revoke_all_sessions(self, account_uid: str, *, at: datetime | None = None) -> int:
        revoked_at = at or datetime.now(UTC)
        result = self._session.execute(
            update(UserSession)
            .where(UserSession.account_uid == account_uid, UserSession.status == "active")
            .values(status="revoked", revoked_at=revoked_at)
        )
        return int(result.rowcount or 0)
