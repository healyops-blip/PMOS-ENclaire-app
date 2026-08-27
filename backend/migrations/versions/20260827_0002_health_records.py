"""Create patient profile and daily health-record tables.

Revision ID: 20260827_0002
Revises: 20260826_0001
Create Date: 2026-08-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260827_0002"
down_revision: str | None = "20260826_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "patient_profile",
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("account_uid", sa.String(length=36), nullable=False),
        sa.Column("nickname", sa.String(length=80), nullable=True),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column("gender", sa.String(length=24), nullable=True),
        sa.Column("height_cm", sa.Float(), nullable=True),
        sa.Column("diagnosis_year", sa.Integer(), nullable=True),
        sa.Column("primary_condition", sa.String(length=32), nullable=True),
        sa.Column("usual_cycle_length_days", sa.Integer(), nullable=True),
        sa.Column("next_visit_date", sa.Date(), nullable=True),
        sa.Column("health_goal", sa.String(length=500), nullable=True),
        sa.Column("onboarding_step", sa.Integer(), nullable=False),
        sa.Column("onboarding_completed", sa.Boolean(), nullable=False),
        sa.Column("external_ocr_notice_version", sa.String(length=32), nullable=True),
        sa.Column("external_ocr_notice_accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "gender IN ('female', 'male', 'other', 'prefer_not_to_say')",
            name=op.f("ck_patient_profile_patient_profile_gender"),
        ),
        sa.CheckConstraint(
            "onboarding_step BETWEEN 0 AND 4",
            name=op.f("ck_patient_profile_patient_profile_step"),
        ),
        sa.ForeignKeyConstraint(
            ["account_uid"],
            ["user_account.uid"],
            name=op.f("fk_patient_profile_account_uid_user_account"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("patient_id", name=op.f("pk_patient_profile")),
        sa.UniqueConstraint("account_uid", name=op.f("uq_patient_profile_account_uid")),
    )
    op.create_table(
        "medication",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("drug_name", sa.String(length=200), nullable=False),
        sa.Column("normalized_drug_name", sa.String(length=200), nullable=False),
        sa.Column("specification", sa.String(length=200), nullable=True),
        sa.Column("dosage_text", sa.String(length=200), nullable=True),
        sa.Column("dosage_value", sa.Float(), nullable=True),
        sa.Column("dosage_unit", sa.String(length=32), nullable=True),
        sa.Column("frequency", sa.String(length=200), nullable=True),
        sa.Column("route", sa.String(length=80), nullable=True),
        sa.Column("start_date", sa.Date(), nullable=True),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("current_status", sa.String(length=16), nullable=False),
        sa.Column("source_type", sa.String(length=32), nullable=False),
        sa.Column("source_document_id", sa.String(length=36), nullable=True),
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "current_status IN ('active', 'stopped', 'unknown')",
            name=op.f("ck_medication_medication_status"),
        ),
        sa.ForeignKeyConstraint(
            ["patient_id"],
            ["patient_profile.patient_id"],
            name=op.f("fk_medication_patient_id_patient_profile"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_medication")),
        sa.UniqueConstraint("patient_id", "idempotency_key", name="uq_medication_idempotency"),
    )
    op.create_index(
        "ix_medication_patient_status",
        "medication",
        ["patient_id", "current_status"],
        unique=False,
    )
    op.create_table(
        "medication_event",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("medication_id", sa.String(length=36), nullable=False),
        sa.Column("event_type", sa.String(length=16), nullable=False),
        sa.Column("event_date", sa.Date(), nullable=False),
        sa.Column("old_instruction_json", sa.Text(), nullable=True),
        sa.Column("new_instruction_json", sa.Text(), nullable=True),
        sa.Column("source_document_id", sa.String(length=36), nullable=True),
        sa.Column("confirmed_by_uid", sa.String(length=36), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("stop_source", sa.String(length=32), nullable=True),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.CheckConstraint(
            "event_type IN ('started', 'adjusted', 'continued', 'stopped')",
            name=op.f("ck_medication_event_medication_event_type"),
        ),
        sa.CheckConstraint(
            "stop_source IS NULL OR stop_source IN "
            "('written_order', 'verbal_doctor', 'patient_self', 'other')",
            name=op.f("ck_medication_event_medication_event_stop_source"),
        ),
        sa.ForeignKeyConstraint(
            ["confirmed_by_uid"],
            ["user_account.uid"],
            name=op.f("fk_medication_event_confirmed_by_uid_user_account"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["medication_id"],
            ["medication.id"],
            name=op.f("fk_medication_event_medication_id_medication"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["patient_id"],
            ["patient_profile.patient_id"],
            name=op.f("fk_medication_event_patient_id_patient_profile"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_medication_event")),
    )
    op.create_index(
        "ix_medication_event_medication_date",
        "medication_event",
        ["medication_id", "event_date"],
        unique=False,
    )
    op.create_table(
        "medication_daily",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("medication_id", sa.String(length=36), nullable=False),
        sa.Column("record_date", sa.Date(), nullable=False),
        sa.Column("intake_status", sa.String(length=16), nullable=False),
        sa.Column("actual_dosage", sa.Float(), nullable=True),
        sa.Column("actual_dosage_unit", sa.String(length=32), nullable=True),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_by_uid", sa.String(length=36), nullable=False),
        sa.CheckConstraint(
            "intake_status IN ('taken', 'missed', 'unrecorded')",
            name=op.f("ck_medication_daily_medication_daily_status"),
        ),
        sa.ForeignKeyConstraint(
            ["medication_id"],
            ["medication.id"],
            name=op.f("fk_medication_daily_medication_id_medication"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["patient_id"],
            ["patient_profile.patient_id"],
            name=op.f("fk_medication_daily_patient_id_patient_profile"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["recorded_by_uid"],
            ["user_account.uid"],
            name=op.f("fk_medication_daily_recorded_by_uid_user_account"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_medication_daily")),
        sa.UniqueConstraint("medication_id", "record_date", name="uq_medication_daily_date"),
    )
    op.create_index(
        "ix_medication_daily_patient_date",
        "medication_daily",
        ["patient_id", "record_date"],
        unique=False,
    )
    op.create_table(
        "menstrual_cycle",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("flow_level", sa.String(length=16), nullable=True),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("source_type", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "flow_level IS NULL OR flow_level IN ('light', 'medium', 'heavy', 'unknown')",
            name=op.f("ck_menstrual_cycle_menstrual_cycle_flow"),
        ),
        sa.ForeignKeyConstraint(
            ["patient_id"],
            ["patient_profile.patient_id"],
            name=op.f("fk_menstrual_cycle_patient_id_patient_profile"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_menstrual_cycle")),
    )
    op.create_index(
        "ix_menstrual_cycle_patient_start",
        "menstrual_cycle",
        ["patient_id", "start_date"],
        unique=False,
    )
    op.create_table(
        "weight_record",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("measured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("record_date", sa.Date(), nullable=False),
        sa.Column("weight_kg", sa.Float(), nullable=False),
        sa.Column("source_type", sa.String(length=32), nullable=False),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "weight_kg >= 20 AND weight_kg <= 350",
            name=op.f("ck_weight_record_weight_record_range"),
        ),
        sa.ForeignKeyConstraint(
            ["patient_id"],
            ["patient_profile.patient_id"],
            name=op.f("fk_weight_record_patient_id_patient_profile"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_weight_record")),
        sa.UniqueConstraint("patient_id", "record_date", name="uq_weight_record_patient_date"),
    )
    op.create_index(
        "ix_weight_record_patient_date",
        "weight_record",
        ["patient_id", "record_date"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_weight_record_patient_date", table_name="weight_record")
    op.drop_table("weight_record")
    op.drop_index("ix_menstrual_cycle_patient_start", table_name="menstrual_cycle")
    op.drop_table("menstrual_cycle")
    op.drop_index("ix_medication_daily_patient_date", table_name="medication_daily")
    op.drop_table("medication_daily")
    op.drop_index("ix_medication_event_medication_date", table_name="medication_event")
    op.drop_table("medication_event")
    op.drop_index("ix_medication_patient_status", table_name="medication")
    op.drop_table("medication")
    op.drop_table("patient_profile")
