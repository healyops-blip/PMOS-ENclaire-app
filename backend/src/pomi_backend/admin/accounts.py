"""Server-local account initialization and password reset operations."""

from __future__ import annotations

import re
from dataclasses import dataclass

from sqlalchemy.orm import Session

from pomi_backend.repositories import AuthRepository
from pomi_backend.services.security import PasswordManager, validate_password_strength


class AccountNotFound(Exception):
    pass


ACCOUNT_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,63}$")


@dataclass(frozen=True, slots=True)
class SeedAccountResult:
    account_name: str
    uid: str
    created: bool
    onboarding_completed: bool


def normalize_account_name(account_name: str) -> str:
    normalized = account_name.strip().lower()
    if not ACCOUNT_NAME_PATTERN.fullmatch(normalized):
        raise ValueError(
            "account name must contain only letters, numbers, dot, underscore, or hyphen"
        )
    return normalized


def _seed_account(
    session: Session,
    password_manager: PasswordManager,
    *,
    account_name: str,
    password: str,
    onboarding_completed: bool,
) -> SeedAccountResult:
    repository = AuthRepository(session)
    normalized_name = normalize_account_name(account_name)
    existing = repository.get_account_by_name(normalized_name)
    if existing is not None:
        if existing.onboarding_completed != onboarding_completed:
            existing.onboarding_completed = onboarding_completed
        return SeedAccountResult(
            account_name=existing.account_name,
            uid=existing.uid,
            created=False,
            onboarding_completed=existing.onboarding_completed,
        )

    validate_password_strength(password)
    account = repository.create_account(
        account_name=normalized_name,
        password_hash=password_manager.hash(password),
        onboarding_completed=onboarding_completed,
    )
    return SeedAccountResult(
        account_name=account.account_name,
        uid=account.uid,
        created=True,
        onboarding_completed=account.onboarding_completed,
    )


def seed_initial_accounts(
    session: Session,
    password_manager: PasswordManager,
    *,
    first_time_account_name: str,
    first_time_password: str,
    returning_account_name: str,
    returning_password: str,
) -> tuple[SeedAccountResult, SeedAccountResult]:
    if normalize_account_name(first_time_account_name) == normalize_account_name(
        returning_account_name
    ):
        raise ValueError("initial account names must be different")

    try:
        first_time = _seed_account(
            session,
            password_manager,
            account_name=first_time_account_name,
            password=first_time_password,
            onboarding_completed=False,
        )
        returning = _seed_account(
            session,
            password_manager,
            account_name=returning_account_name,
            password=returning_password,
            onboarding_completed=True,
        )
        session.commit()
        return first_time, returning
    except Exception:
        session.rollback()
        raise


def reset_password(
    session: Session,
    password_manager: PasswordManager,
    *,
    account_name: str,
    new_password: str,
) -> int:
    validate_password_strength(new_password)
    repository = AuthRepository(session)
    account = repository.get_account_by_name(normalize_account_name(account_name))
    if account is None:
        raise AccountNotFound(account_name)

    try:
        repository.update_password_hash(account, password_manager.hash(new_password))
        revoked_count = repository.revoke_all_sessions(account.uid)
        session.commit()
        return revoked_count
    except Exception:
        session.rollback()
        raise
