"""Add confirmed medical orders and medication reconciliations.

Revision ID: 20260827_0031
Revises: 20260827_0030
Create Date: 2026-08-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

import pomi_backend.db.types

revision: str = "20260827_0031"
down_revision: str | None = "20260827_0030"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("medication") as batch_op:
        batch_op.add_column(sa.Column("standard_drug_id", sa.String(length=80), nullable=True))

    op.create_table(
        "medical_order",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("document_id", sa.String(length=36), nullable=False),
        sa.Column("document_revision_id", sa.String(length=36), nullable=False),
        sa.Column("ocr_result_id", sa.String(length=36), nullable=False),
        sa.Column("ocr_task_id", sa.String(length=36), nullable=False),
        sa.Column("medication_index", sa.Integer(), nullable=False),
        sa.Column("raw_order_text", sa.Text(), nullable=False),
        sa.Column("drug_name", sa.String(length=200), nullable=False),
        sa.Column("standard_drug_id", sa.String(length=80), nullable=True),
        sa.Column("specification", sa.String(length=200), nullable=True),
        sa.Column("dosage_value", sa.Numeric(8, 3), nullable=False),
        sa.Column("dosage_unit", sa.String(length=32), nullable=False),
        sa.Column("frequency", sa.String(length=200), nullable=False),
        sa.Column("course", sa.String(length=200), nullable=True),
        sa.Column("route", sa.String(length=80), nullable=True),
        sa.Column("instructions", sa.Text(), nullable=True),
        sa.Column("order_date", sa.Date(), nullable=False),
        sa.Column("explicitly_stopped", sa.Boolean(), nullable=False),
        sa.Column("review_required", sa.Boolean(), nullable=False),
        sa.Column("original_item_data", sa.JSON(), nullable=False),
        sa.Column("confirmed_item_data", sa.JSON(), nullable=False),
        sa.Column("confirmed_by_uid", sa.String(length=36), nullable=False),
        sa.Column("confirmed_at", pomi_backend.db.types.UTCDateTime(), nullable=False),
        sa.ForeignKeyConstraint(["confirmed_by_uid"], ["user_account.uid"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["document_id"], ["document.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["document_revision_id"], ["document_revision.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["ocr_result_id"], ["ocr_result.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["ocr_task_id"], ["ocr_task.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["patient_id"], ["patient_profile.patient_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.CheckConstraint(
            "length(trim(raw_order_text)) > 0", name="ck_medical_order_source_nonblank"
        ),
        sa.CheckConstraint("length(trim(drug_name)) > 0", name="ck_medical_order_drug_nonblank"),
        sa.CheckConstraint("dosage_value > 0", name="ck_medical_order_dosage_positive"),
        sa.CheckConstraint("length(trim(dosage_unit)) > 0", name="ck_medical_order_unit_nonblank"),
        sa.CheckConstraint(
            "length(trim(frequency)) > 0", name="ck_medical_order_frequency_nonblank"
        ),
        sa.UniqueConstraint(
            "ocr_result_id", "medication_index", name="uq_medical_order_result_item"
        ),
    )
    op.create_index(
        "ix_medical_order_patient_confirmed", "medical_order", ["patient_id", "confirmed_at"]
    )

    op.create_table(
        "medication_reconciliation",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("ocr_task_id", sa.String(length=36), nullable=False),
        sa.Column("rule_version", sa.String(length=40), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_by_uid", sa.String(length=36), nullable=False),
        sa.Column("executed_by_uid", sa.String(length=36), nullable=True),
        sa.Column("executed_at", pomi_backend.db.types.UTCDateTime(), nullable=True),
        sa.Column("execution_payload", sa.JSON(), nullable=True),
        sa.Column("created_at", pomi_backend.db.types.UTCDateTime(), nullable=False),
        sa.Column("updated_at", pomi_backend.db.types.UTCDateTime(), nullable=False),
        sa.CheckConstraint(
            "status IN ('draft', 'executing', 'executed')",
            name="medication_reconciliation_status",
        ),
        sa.ForeignKeyConstraint(["created_by_uid"], ["user_account.uid"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["executed_by_uid"], ["user_account.uid"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["ocr_task_id"], ["ocr_task.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["patient_id"], ["patient_profile.patient_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("patient_id", "ocr_task_id", name="uq_reconciliation_patient_task"),
    )
    op.create_table(
        "medication_reconciliation_item",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("reconciliation_id", sa.String(length=36), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("old_medication_id", sa.String(length=36), nullable=True),
        sa.Column("new_medical_order_id", sa.String(length=36), nullable=True),
        sa.Column("match_basis", sa.JSON(), nullable=False),
        sa.Column("suggestion", sa.String(length=24), nullable=False),
        sa.Column("user_decision", sa.String(length=24), nullable=True),
        sa.Column("decision_note", sa.String(length=500), nullable=True),
        sa.Column("stop_date", sa.Date(), nullable=True),
        sa.Column("stop_source", sa.String(length=80), nullable=True),
        sa.Column("execution_result", sa.JSON(), nullable=True),
        sa.CheckConstraint(
            "suggestion IN ('unchanged', 'adjusted', 'added', "
            "'stopped', 'uncertain', 'manual_review')",
            name="medication_reconciliation_item_suggestion",
        ),
        sa.CheckConstraint(
            "user_decision IS NULL OR user_decision IN ('accept', 'keep_current', 'reject')",
            name="medication_reconciliation_item_decision",
        ),
        sa.CheckConstraint(
            "old_medication_id IS NOT NULL OR new_medical_order_id IS NOT NULL",
            name="ck_reconciliation_item_has_source",
        ),
        sa.ForeignKeyConstraint(
            ["new_medical_order_id"], ["medical_order.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["old_medication_id"], ["medication.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["patient_id"], ["patient_profile.patient_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["reconciliation_id"], ["medication_reconciliation.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "reconciliation_id", "position", name="uq_reconciliation_item_position"
        ),
    )


def downgrade() -> None:
    op.drop_table("medication_reconciliation_item")
    op.drop_table("medication_reconciliation")
    op.drop_index("ix_medical_order_patient_confirmed", table_name="medical_order")
    op.drop_table("medical_order")
    with op.batch_alter_table("medication") as batch_op:
        batch_op.drop_column("standard_drug_id")
