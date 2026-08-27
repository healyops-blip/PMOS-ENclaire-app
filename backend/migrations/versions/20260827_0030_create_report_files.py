"""create private report PDF artifacts

Revision ID: 20260827_0030
Revises: 20260827_0027
Create Date: 2026-08-27 23:30:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

import pomi_backend.db.types

revision: str = "20260827_0030"
down_revision: str | tuple[str, str] | None = "20260827_0027"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "report_file",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("report_id", sa.String(length=36), nullable=False),
        sa.Column("file_type", sa.String(length=16), nullable=False),
        sa.Column("template_version", sa.String(length=40), nullable=False),
        sa.Column("snapshot_hash", sa.String(length=64), nullable=False),
        sa.Column("idempotency_key", sa.String(length=64), nullable=False),
        sa.Column("storage_path", sa.String(length=500), nullable=True),
        sa.Column("file_hash", sa.String(length=64), nullable=True),
        sa.Column("file_size_bytes", sa.Integer(), nullable=True),
        sa.Column("generation_status", sa.String(length=16), nullable=False),
        sa.Column("attempt_count", sa.Integer(), nullable=False),
        sa.Column("available_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=False),
        sa.Column("lease_owner", sa.String(length=100), nullable=True),
        sa.Column(
            "lease_expires_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=True
        ),
        sa.Column("started_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=True),
        sa.Column("generated_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.String(length=500), nullable=True),
        sa.Column("created_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=False),
        sa.Column("updated_at", pomi_backend.db.types.UTCDateTime(timezone=True), nullable=False),
        sa.CheckConstraint("file_type IN ('pdf')", name=op.f("ck_report_file_report_file_type")),
        sa.CheckConstraint(
            "generation_status IN ('queued', 'processing', 'succeeded', 'failed')",
            name=op.f("ck_report_file_report_file_generation_status"),
        ),
        sa.ForeignKeyConstraint(
            ["report_id"],
            ["report_snapshot.id"],
            name=op.f("fk_report_file_report_id_report_snapshot"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_report_file")),
        sa.UniqueConstraint("idempotency_key", name="uq_report_file_idempotency_key"),
    )
    with op.batch_alter_table("report_file", schema=None) as batch_op:
        batch_op.create_index(
            "ix_report_file_claim",
            ["generation_status", "available_at", "lease_expires_at"],
            unique=False,
        )
        batch_op.create_index(
            "ix_report_file_report_created", ["report_id", "created_at"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("report_file", schema=None) as batch_op:
        batch_op.drop_index("ix_report_file_report_created")
        batch_op.drop_index("ix_report_file_claim")
    op.drop_table("report_file")
