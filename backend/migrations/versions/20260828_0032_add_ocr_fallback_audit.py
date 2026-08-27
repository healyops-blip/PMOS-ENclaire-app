"""add OCR fallback audit

Revision ID: 20260827_0032
Revises: 20260827_0031
Create Date: 2026-08-28 01:20:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

import pomi_backend.db.types

revision: str = "20260827_0032"
down_revision: str | None = "20260827_0031"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ocr_fallback_use",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("task_id", sa.String(length=36), nullable=False),
        sa.Column("patient_id", sa.String(length=36), nullable=False),
        sa.Column("document_id", sa.String(length=36), nullable=False),
        sa.Column("document_revision_id", sa.String(length=36), nullable=False),
        sa.Column("file_hash", sa.String(length=64), nullable=False),
        sa.Column("material_type", sa.String(length=32), nullable=False),
        sa.Column("data_version", sa.String(length=40), nullable=False),
        sa.Column("trigger_category", sa.String(length=40), nullable=False),
        sa.Column("trigger_code", sa.String(length=80), nullable=False),
        sa.Column("selected_by_uid", sa.String(length=36), nullable=False),
        sa.Column("selected_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=False),
        sa.Column("confirmed_by_uid", sa.String(length=36), nullable=True),
        sa.Column("confirmed_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["document_id"], ["document.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["document_revision_id"], ["document_revision.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patient_profile.patient_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["task_id"], ["ocr_task.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["selected_by_uid"], ["user_account.uid"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["confirmed_by_uid"], ["user_account.uid"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("task_id", name="uq_ocr_fallback_use_task"),
    )
    op.create_index(
        "ix_ocr_fallback_use_patient_selected",
        "ocr_fallback_use",
        ["patient_id", "selected_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_ocr_fallback_use_patient_selected", table_name="ocr_fallback_use")
    op.drop_table("ocr_fallback_use")
