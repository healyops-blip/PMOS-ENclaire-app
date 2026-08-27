"""Runtime configuration loaded from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_DATABASE_URL = "sqlite:///./runtime/pomi.db"
DEFAULT_SESSION_TTL_SECONDS = 7 * 24 * 60 * 60
DEFAULT_ARGON2_TIME_COST = 3
DEFAULT_ARGON2_MEMORY_COST_KIB = 65536
DEFAULT_ARGON2_PARALLELISM = 4
DEFAULT_AUTH_RATE_LIMIT_ATTEMPTS = 5
DEFAULT_AUTH_RATE_LIMIT_WINDOW_SECONDS = 60
DEFAULT_ALLOWED_HOSTS = ("api.healy1012-ops.top", "localhost", "127.0.0.1")
DEFAULT_STORAGE_ROOT = Path("./runtime/storage")
DEFAULT_OCR_API_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
DEFAULT_OCR_MODEL = "qwen3-vl-plus"
DEFAULT_BUSINESS_TIMEZONE = "Asia/Singapore"


@dataclass(frozen=True, slots=True)
class Settings:
    """Backend settings with local-development defaults."""

    database_url: str = DEFAULT_DATABASE_URL
    session_ttl_seconds: int = DEFAULT_SESSION_TTL_SECONDS
    environment: str = "development"
    argon2_time_cost: int = DEFAULT_ARGON2_TIME_COST
    argon2_memory_cost_kib: int = DEFAULT_ARGON2_MEMORY_COST_KIB
    argon2_parallelism: int = DEFAULT_ARGON2_PARALLELISM
    auth_rate_limit_attempts: int = DEFAULT_AUTH_RATE_LIMIT_ATTEMPTS
    auth_rate_limit_window_seconds: int = DEFAULT_AUTH_RATE_LIMIT_WINDOW_SECONDS
    allowed_hosts: tuple[str, ...] = DEFAULT_ALLOWED_HOSTS
    storage_root: Path = DEFAULT_STORAGE_ROOT
    ocr_api_base_url: str = DEFAULT_OCR_API_BASE_URL
    ocr_api_key: str | None = None
    ocr_model: str = DEFAULT_OCR_MODEL
    ocr_request_timeout_seconds: int = 90
    ocr_lease_seconds: int = 180
    business_timezone: str = DEFAULT_BUSINESS_TIMEZONE

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            database_url=os.getenv("POMI_DATABASE_URL", DEFAULT_DATABASE_URL),
            session_ttl_seconds=int(
                os.getenv("POMI_SESSION_TTL_SECONDS", str(DEFAULT_SESSION_TTL_SECONDS))
            ),
            environment=os.getenv("POMI_ENVIRONMENT", "development"),
            argon2_time_cost=int(os.getenv("POMI_ARGON2_TIME_COST", str(DEFAULT_ARGON2_TIME_COST))),
            argon2_memory_cost_kib=int(
                os.getenv("POMI_ARGON2_MEMORY_COST_KIB", str(DEFAULT_ARGON2_MEMORY_COST_KIB))
            ),
            argon2_parallelism=int(
                os.getenv("POMI_ARGON2_PARALLELISM", str(DEFAULT_ARGON2_PARALLELISM))
            ),
            auth_rate_limit_attempts=int(
                os.getenv(
                    "POMI_AUTH_RATE_LIMIT_ATTEMPTS",
                    str(DEFAULT_AUTH_RATE_LIMIT_ATTEMPTS),
                )
            ),
            auth_rate_limit_window_seconds=int(
                os.getenv(
                    "POMI_AUTH_RATE_LIMIT_WINDOW_SECONDS",
                    str(DEFAULT_AUTH_RATE_LIMIT_WINDOW_SECONDS),
                )
            ),
            allowed_hosts=tuple(
                host.strip()
                for host in os.getenv("POMI_ALLOWED_HOSTS", ",".join(DEFAULT_ALLOWED_HOSTS)).split(
                    ","
                )
                if host.strip()
            ),
            storage_root=Path(os.getenv("POMI_STORAGE_ROOT", str(DEFAULT_STORAGE_ROOT))),
            ocr_api_base_url=os.getenv("POMI_OCR_API_BASE_URL", DEFAULT_OCR_API_BASE_URL),
            ocr_api_key=os.getenv("POMI_OCR_API_KEY"),
            ocr_model=os.getenv("POMI_OCR_MODEL", DEFAULT_OCR_MODEL),
            ocr_request_timeout_seconds=int(os.getenv("POMI_OCR_TIMEOUT_SECONDS", "90")),
            ocr_lease_seconds=int(os.getenv("POMI_OCR_LEASE_SECONDS", "180")),
            business_timezone=os.getenv("POMI_BUSINESS_TIMEZONE", DEFAULT_BUSINESS_TIMEZONE),
        )
