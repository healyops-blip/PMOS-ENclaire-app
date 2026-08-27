"""Regression tests for UTC datetime round-tripping across sessions.

SQLite does not persist ``tzinfo``. A ``DateTime(timezone=True)`` column
writes a timezone-aware value but reads back naive once the original Python
object is no longer cached in a session's identity map (i.e. a fresh
request/session reading data written by a previous one). That silently
breaks any comparison against ``datetime.now(UTC)``, which is exactly what
session-expiry checks in the auth flow need to do.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

from pomi_backend.db import Base, build_engine, build_session_factory
from pomi_backend.repositories import AuthRepository


def test_expires_at_survives_a_fresh_session_as_utc_aware(tmp_path: Path) -> None:
    database_path = tmp_path / "roundtrip.db"
    engine = build_engine(f"sqlite:///{database_path}")
    Base.metadata.create_all(engine)
    session_factory = build_session_factory(engine)

    expires_at = datetime.now(UTC) + timedelta(days=7)

    with session_factory() as write_session:
        repository = AuthRepository(write_session)
        account = repository.create_account(account_name="roundtrip-user", password_hash="hash")
        write_session.commit()
        repository.create_session(
            account_uid=account.uid,
            session_hash="sha256:roundtrip",
            expires_at=expires_at,
        )
        write_session.commit()

    # A brand new session simulates a separate request reading data that a
    # prior request wrote: nothing here is served from an identity-map cache.
    with session_factory() as read_session:
        repository = AuthRepository(read_session)
        fetched = repository.get_session_by_hash("sha256:roundtrip")
        assert fetched is not None
        assert fetched.expires_at.tzinfo is not None
        assert fetched.expires_at == expires_at
        # This comparison raises TypeError if the driver dropped tzinfo.
        assert fetched.expires_at > datetime.now(UTC)

    engine.dispose()
