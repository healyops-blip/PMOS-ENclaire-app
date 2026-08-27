"""Password and opaque Session credential primitives."""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from pomi_backend.config import Settings


class PasswordManager:
    def __init__(self, settings: Settings) -> None:
        self._hasher = PasswordHasher(
            time_cost=settings.argon2_time_cost,
            memory_cost=settings.argon2_memory_cost_kib,
            parallelism=settings.argon2_parallelism,
            hash_len=32,
            salt_len=16,
        )
        self.dummy_hash = self.hash("not-a-real-user-password-2026")

    def hash(self, password: str) -> str:
        return self._hasher.hash(password)

    def verify(self, password_hash: str, password: str) -> bool:
        try:
            return self._hasher.verify(password_hash, password)
        except (InvalidHashError, VerificationError, VerifyMismatchError):
            return False

    def needs_rehash(self, password_hash: str) -> bool:
        try:
            return self._hasher.check_needs_rehash(password_hash)
        except InvalidHashError:
            return False


@dataclass(frozen=True, slots=True)
class SessionCredential:
    plaintext: str
    digest: str


def issue_session_credential() -> SessionCredential:
    plaintext = secrets.token_urlsafe(32)
    return SessionCredential(plaintext=plaintext, digest=hash_session_credential(plaintext))


def hash_session_credential(session_id: str) -> str:
    return hashlib.sha256(session_id.encode("utf-8")).hexdigest()
