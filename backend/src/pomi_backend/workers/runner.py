"""Single-process worker runner for P0 background queues."""

from __future__ import annotations

import logging
import time

from pomi_backend.config import Settings
from pomi_backend.db import build_engine, build_session_factory
from pomi_backend.workers.ocr import run_ocr_once
from pomi_backend.workers.pdf import run_pdf_once


def main() -> None:
    settings = Settings.from_env()
    engine = build_engine(settings.database_url)
    factory = build_session_factory(engine)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    while True:
        worked = run_ocr_once(factory, settings)
        worked = run_pdf_once(factory, settings) or worked
        if not worked:
            time.sleep(1)


if __name__ == "__main__":
    main()
