"""Registration, login, and Session authentication use cases."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from pomi_backend.db.models import UserAccount
from pomi_backend.repositories import AuthRepository
from pomi_backend.services.security import (
    PasswordManager,
    hash_session_credential,
    issue_session_credential,
)


class AuthError(Exception):
    code = "AUTHENTICATION_REQUIRED"
    message = "Valid authentication is required."
    status_code = 401


class AccountNameTaken(AuthError):
    code = "ACCOUNT_NAME_TAKEN"
    message = "This account name is unavailable."
    status_code = 409


class InvalidCredentials(AuthError):
    code = "INVALID_CREDENTIALS"
    message = "The account name or password is incorrect."
    status_code = 401


@dataclass(frozen=True, slots=True)
class LoginResult:
    session_id: str
    expires_at: datetime
    account: UserAccount


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


class AuthService:
    def __init__(
        self,
        session: Session,
        *,
        password_manager: PasswordManager,
        session_ttl_seconds: int,
    ) -> None:
        self._session = session
        self._repository = AuthRepository(session)
        self._password_manager = password_manager
        self._session_ttl_seconds = session_ttl_seconds

    def register(
        self, *, account_name: str, password: str, phone_number: str | None
    ) -> UserAccount:
        if self._repository.get_account_by_name(account_name) is not None:
            raise AccountNameTaken
        try:
            account = self._repository.create_account(
                account_name=account_name,
                password_hash=self._password_manager.hash(password),
                phone_number=phone_number,
            )
            self._session.commit()
            return account
        except IntegrityError as error:
            self._session.rollback()
            raise AccountNameTaken from error

    def login(
        self,
        *,
        account_name: str,
        password: str,
        client_platform: str | None,
        device_name: str | None,
    ) -> LoginResult:
        account = self._repository.get_account_by_name(account_name)
        password_hash = (
            account.password_hash if account is not None else self._password_manager.dummy_hash
        )
        password_valid = self._password_manager.verify(password_hash, password)
        if account is None or not password_valid or account.status != "active":
            raise InvalidCredentials

        if self._password_manager.needs_rehash(account.password_hash):
            self._repository.update_password_hash(account, self._password_manager.hash(password))

        now = datetime.now(UTC)
        expires_at = now + timedelta(seconds=self._session_ttl_seconds)
        credential = issue_session_credential()
        self._repository.update_last_login(account, at=now)
        self._repository.create_session(
            account_uid=account.uid,
            session_hash=credential.digest,
            expires_at=expires_at,
            client_platform=client_platform,
            device_name=device_name,
        )
        self._session.commit()
        return LoginResult(
            session_id=credential.plaintext,
            expires_at=expires_at,
            account=account,
        )

    def authenticate(self, session_id: str) -> UserAccount:
        user_session = self._repository.get_session_by_hash(hash_session_credential(session_id))
        if user_session is None or user_session.status != "active":
            raise AuthError

        now = datetime.now(UTC)
        if _as_utc(user_session.expires_at) <= now:
            self._repository.expire_session(user_session)
            self._session.commit()
            raise AuthError

        account = user_session.account
        if account.status != "active":
            raise AuthError

        self._repository.touch_session(user_session, at=now)
        self._session.commit()
        return account
