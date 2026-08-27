from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from pomi_backend.config import Settings
from pomi_backend.db import Base, build_engine, build_session_factory
from pomi_backend.main import create_app


@pytest.fixture
def db_session(tmp_path: Path) -> Iterator[Session]:
    database_path = tmp_path / "repository.db"
    engine = build_engine(f"sqlite:///{database_path}")
    Base.metadata.create_all(engine)
    session_factory = build_session_factory(engine)

    with session_factory() as session:
        yield session
        session.rollback()

    engine.dispose()


@pytest.fixture
def api_engine(tmp_path: Path) -> Iterator[Engine]:
    engine = build_engine(f"sqlite:///{tmp_path / 'api.db'}")
    Base.metadata.create_all(engine)
    yield engine
    engine.dispose()


@pytest.fixture
def api_settings() -> Settings:
    return Settings(
        database_url="sqlite://",
        session_ttl_seconds=7 * 24 * 60 * 60,
        environment="test",
        argon2_time_cost=1,
        argon2_memory_cost_kib=8192,
        argon2_parallelism=1,
        auth_rate_limit_attempts=100,
        auth_rate_limit_window_seconds=60,
    )


@pytest.fixture
def api_client(api_engine: Engine, api_settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings=api_settings, engine=api_engine)) as client:
        yield client
