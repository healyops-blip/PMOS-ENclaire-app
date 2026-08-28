"""Print privacy-safe aggregate OCR worker metrics from the configured database."""

from __future__ import annotations

import json

from sqlalchemy import select

from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.db.models import OCRTask
from pomi_backend.db.models.auth import utc_now
from pomi_backend.quality.ocr_observability import summarize_ocr_tasks


def main() -> None:
    settings = Settings.from_env()
    engine = build_engine(settings.database_url)
    with build_session_factory(engine)() as session:
        report = summarize_ocr_tasks(session.scalars(select(OCRTask)), now=utc_now())
    engine.dispose()
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
