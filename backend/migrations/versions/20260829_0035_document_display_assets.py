"""add private document display derivatives

Revision ID: 20260829_0035
Revises: 20260829_0034
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260829_0035"
down_revision: str | None = "20260829_0034"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "document_display_asset",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("document_id", sa.String(length=36), nullable=False),
        sa.Column("document_revision_id", sa.String(length=36), nullable=False),
        sa.Column("asset_type", sa.String(length=40), nullable=False),
        sa.Column("watermark_version", sa.String(length=40), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("storage_path", sa.String(length=500), nullable=True),
        sa.Column("file_hash", sa.String(length=64), nullable=True),
        sa.Column("file_size_bytes", sa.Integer(), nullable=True),
        sa.Column("mime_type", sa.String(length=64), nullable=True),
        sa.Column("pixel_width", sa.Integer(), nullable=True),
        sa.Column("pixel_height", sa.Integer(), nullable=True),
        sa.Column("attempt_count", sa.Integer(), nullable=False),
        sa.Column("failure_code", sa.String(length=80), nullable=True),
        sa.Column("failure_message", sa.String(length=500), nullable=True),
        sa.Column("generated_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "asset_type IN ('pomi_watermarked_display')",
            name=op.f("ck_document_display_asset_document_display_asset_type"),
        ),
        sa.CheckConstraint(
            "status IN ('processing', 'ready', 'failed', 'unsupported', 'purged')",
            name=op.f("ck_document_display_asset_document_display_asset_status"),
        ),
        sa.ForeignKeyConstraint(
            ["document_id"],
            ["document.id"],
            name=op.f("fk_document_display_asset_document_id_document"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["document_revision_id"],
            ["document_revision.id"],
            name=op.f("fk_document_display_asset_document_revision_id_document_revision"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_document_display_asset")),
        sa.UniqueConstraint(
            "document_revision_id",
            "asset_type",
            "watermark_version",
            name="uq_document_display_asset_revision_variant",
        ),
    )
    op.create_index(
        "ix_document_display_asset_document_revision",
        "document_display_asset",
        ["document_id", "document_revision_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_document_display_asset_document_revision",
        table_name="document_display_asset",
    )
    op.drop_table("document_display_asset")
