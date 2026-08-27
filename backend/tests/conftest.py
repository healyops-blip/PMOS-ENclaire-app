from __future__ import annotations

from collections.abc import Iterator

import pytest
from sqlalchemy.orm import Session

from pomi_backend.db import Base, build_engine, build_session_factory


@pytest.fixture
def db_session(tmp_path: object) -> Iterator[Session]:
    database_path = tmp_path / "repository.db"  # type: ignore[operator]
    engine = build_engine(f"sqlite:///{database_path}")
    Base.metadata.create_all(engine)
    session_factory = build_session_factory(engine)

    with session_factory() as session:
        yield session
        session.rollback()

    engine.dispose()
