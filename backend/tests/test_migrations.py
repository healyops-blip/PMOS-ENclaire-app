from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from pytest import MonkeyPatch
from sqlalchemy import create_engine, inspect, text


def test_initial_migration_is_repeatable_and_safe(tmp_path: Path, monkeypatch: MonkeyPatch) -> None:
    monkeypatch.delenv("POMI_DATABASE_URL", raising=False)
    database_path = tmp_path / "migrated.db"
    database_url = f"sqlite:///{database_path}"
    backend_root = Path(__file__).resolve().parents[1]
    config = Config(backend_root / "alembic.ini")
    config.set_main_option("sqlalchemy.url", database_url)

    command.upgrade(config, "head")
    command.upgrade(config, "head")

    engine = create_engine(database_url)
    inspector = inspect(engine)
    assert set(inspector.get_table_names()) >= {
        "alembic_version",
        "document",
        "document_revision",
        "imaging_report",
        "lab_observation",
        "medication",
        "medication_daily",
        "medication_event",
        "medical_order",
        "medication_reconciliation",
        "medication_reconciliation_item",
        "menstrual_cycle",
        "ocr_field_result",
        "ocr_fallback_use",
        "ocr_result",
        "ocr_task",
        "outpatient_record",
        "patient_note",
        "patient_profile",
        "report_snapshot",
        "report_source",
        "user_account",
        "user_session",
        "weight_record",
    }

    account_columns = {column["name"] for column in inspector.get_columns("user_account")}
    session_columns = {column["name"] for column in inspector.get_columns("user_session")}
    medication_columns = {column["name"] for column in inspector.get_columns("medication")}
    event_columns = {column["name"] for column in inspector.get_columns("medication_event")}
    assert "password_hash" in account_columns
    assert "password" not in account_columns
    assert "session_hash" in session_columns
    assert "session_id" not in session_columns
    assert "idempotency_key" in medication_columns
    assert "stop_source" in event_columns
    assert "lab_observation" in inspector.get_table_names()
    lab_columns = {column["name"] for column in inspector.get_columns("lab_observation")}
    assert {
        "document_id",
        "document_revision_id",
        "ocr_result_id",
        "original_item_data",
        "confirmed_item_data",
        "confirmed_by_uid",
    } <= lab_columns

    unique_account_columns = {
        tuple(constraint["column_names"])
        for constraint in inspector.get_unique_constraints("user_account")
    }
    unique_session_columns = {
        tuple(constraint["column_names"])
        for constraint in inspector.get_unique_constraints("user_session")
    }
    assert ("uid",) in unique_account_columns
    assert ("account_name",) in unique_account_columns
    assert ("session_hash",) in unique_session_columns

    with engine.connect() as connection:
        assert connection.scalar(text("SELECT version_num FROM alembic_version")) == (
            "20260827_0032"
        )
    command.downgrade(config, "20260826_0001")
    inspector = inspect(engine)
    assert "medication" not in inspector.get_table_names()
    assert "user_account" in inspector.get_table_names()
    engine.dispose()


def test_laboratory_migration_upgrades_the_current_main_schema(
    tmp_path: Path, monkeypatch: MonkeyPatch
) -> None:
    monkeypatch.delenv("POMI_DATABASE_URL", raising=False)
    database_url = f"sqlite:///{tmp_path / 'upgrade-from-main.db'}"
    backend_root = Path(__file__).resolve().parents[1]
    config = Config(backend_root / "alembic.ini")
    config.set_main_option("sqlalchemy.url", database_url)

    command.upgrade(config, "20260827_0028")
    engine = create_engine(database_url)
    assert "document" in inspect(engine).get_table_names()
    assert "ocr_result" in inspect(engine).get_table_names()
    assert "lab_observation" not in inspect(engine).get_table_names()

    command.upgrade(config, "head")
    assert {
        "document",
        "document_revision",
        "patient_note",
        "report_snapshot",
        "report_source",
        "ocr_task",
        "ocr_result",
        "lab_observation",
        "imaging_report",
        "outpatient_record",
        "medical_order",
        "medication_reconciliation",
        "medication_reconciliation_item",
        "ocr_fallback_use",
    } <= set(inspect(engine).get_table_names())
    with engine.connect() as connection:
        assert connection.scalar(text("SELECT version_num FROM alembic_version")) == (
            "20260827_0032"
        )
    command.downgrade(config, "20260827_0031")
    assert "ocr_fallback_use" not in inspect(engine).get_table_names()
    command.upgrade(config, "head")
    assert "ocr_fallback_use" in inspect(engine).get_table_names()
    engine.dispose()
