"""Runtime configuration loaded from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass

DEFAULT_DATABASE_URL = "sqlite:///./runtime/pomi.db"
DEFAULT_SESSION_TTL_SECONDS = 7 * 24 * 60 * 60


@dataclass(frozen=True, slots=True)
class Settings:
    """Backend settings with local-development defaults."""

    database_url: str = DEFAULT_DATABASE_URL
    session_ttl_seconds: int = DEFAULT_SESSION_TTL_SECONDS

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            database_url=os.getenv("POMI_DATABASE_URL", DEFAULT_DATABASE_URL),
            session_ttl_seconds=int(
                os.getenv("POMI_SESSION_TTL_SECONDS", str(DEFAULT_SESSION_TTL_SECONDS))
            ),
        )
