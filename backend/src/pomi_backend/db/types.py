"""Custom SQLAlchemy column types."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime
from sqlalchemy.types import TypeDecorator


class UTCDateTime(TypeDecorator):
    """A timezone-aware ``DateTime`` that always round-trips in UTC.

    SQLite does not persist ``tzinfo``: a value written as timezone-aware is
    read back as a naive ``datetime``. That silently breaks any comparison
    against ``datetime.now(UTC)`` (e.g. session-expiry checks) as soon as the
    value crosses a session/request boundary. This type rejects naive input
    on write and reattaches UTC ``tzinfo`` on read when the driver dropped it,
    so application code always sees timezone-aware UTC datetimes regardless
    of backend.
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return value
        if value.tzinfo is None:
            raise ValueError("naive datetime is not allowed; use a timezone-aware UTC value")
        return value.astimezone(UTC)

    def process_result_value(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return value
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)
