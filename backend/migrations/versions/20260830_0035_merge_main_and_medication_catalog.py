"""merge the main profile migration and the medication catalog migration"""

from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

from pomi_backend.data.medication_catalog import (
    CATALOG_DISCLAIMER,
    CATALOG_ENTRIES,
    CATALOG_SOURCE,
    CATALOG_VERSION,
)

revision: str = "20260830_0035"
down_revision: tuple[str, str] = ("20260828_0034", "20260829_0034")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _catalog_table() -> sa.TableClause:
    return sa.table(
        "medication_catalog",
        sa.column("id", sa.String(80)),
        sa.column("version", sa.String(32)),
        sa.column("source", sa.String(200)),
        sa.column("disclaimer", sa.Text()),
        sa.column("name", sa.String(200)),
        sa.column("category", sa.String(80)),
        sa.column("item_type", sa.String(40)),
        sa.column("pcos_context", sa.String(40)),
        sa.column("dosage_forms", sa.JSON()),
        sa.column("strength_candidates", sa.JSON()),
        sa.column("aliases", sa.JSON()),
        sa.column("route", sa.String(120)),
        sa.column("usage_reference", sa.Text()),
        sa.column("schedule_source", sa.String(160)),
        sa.column("user_editable", sa.Boolean()),
        sa.column("can_prefill_reminder", sa.Boolean()),
        sa.column("review_status", sa.String(160)),
        sa.column("record_status", sa.String(80)),
        sa.column("created_at", sa.DateTime(timezone=True)),
        sa.column("updated_at", sa.DateTime(timezone=True)),
    )


def upgrade() -> None:
    bind = op.get_bind()
    if "medication_catalog" not in inspect(bind).get_table_names():
        op.create_table(
            "medication_catalog",
            sa.Column("id", sa.String(length=80), nullable=False),
            sa.Column("version", sa.String(length=32), nullable=False),
            sa.Column("source", sa.String(length=200), nullable=False),
            sa.Column("disclaimer", sa.Text(), nullable=False),
            sa.Column("name", sa.String(length=200), nullable=False),
            sa.Column("category", sa.String(length=80), nullable=False),
            sa.Column("item_type", sa.String(length=40), nullable=False),
            sa.Column("pcos_context", sa.String(length=40), nullable=False),
            sa.Column("dosage_forms", sa.JSON(), nullable=False),
            sa.Column("strength_candidates", sa.JSON(), nullable=False),
            sa.Column("aliases", sa.JSON(), nullable=False),
            sa.Column("route", sa.String(length=120), nullable=False),
            sa.Column("usage_reference", sa.Text(), nullable=False),
            sa.Column("schedule_source", sa.String(length=160), nullable=False),
            sa.Column("user_editable", sa.Boolean(), nullable=False),
            sa.Column("can_prefill_reminder", sa.Boolean(), nullable=False),
            sa.Column("review_status", sa.String(length=160), nullable=False),
            sa.Column("record_status", sa.String(length=80), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.PrimaryKeyConstraint("id", name=op.f("pk_medication_catalog")),
        )
        op.create_index("ix_medication_catalog_name", "medication_catalog", ["name"])
        op.create_index("ix_medication_catalog_category", "medication_catalog", ["category"])
        now = datetime.now(UTC)
        op.bulk_insert(
            _catalog_table(),
            [
                {
                    **entry,
                    "version": CATALOG_VERSION,
                    "source": CATALOG_SOURCE,
                    "disclaimer": CATALOG_DISCLAIMER,
                    "created_at": now,
                    "updated_at": now,
                }
                for entry in CATALOG_ENTRIES
            ],
        )


def downgrade() -> None:
    # The catalog branch owns this table; leave it intact when downgrading only
    # the merge revision so an existing catalog migration remains reversible.
    pass
