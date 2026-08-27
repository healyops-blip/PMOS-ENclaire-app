"""add menstrual cycle history fields

Revision ID: 20260827_0015
Revises: 20260827_0014
Create Date: 2026-08-27 21:30:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260827_0015"
down_revision: str | None = "20260827_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("menstrual_cycle", schema=None) as batch_op:
        batch_op.add_column(sa.Column("flow_level", sa.String(length=16), nullable=True))
        batch_op.add_column(
            sa.Column(
                "source_type",
                sa.String(length=16),
                nullable=False,
                server_default="manual",
            )
        )
        batch_op.create_check_constraint(
            "menstrual_cycle_flow_level",
            "flow_level IS NULL OR flow_level IN ('light', 'medium', 'heavy', 'unknown')",
        )
        batch_op.create_check_constraint(
            "menstrual_cycle_source_type",
            "source_type IN ('manual', 'imported')",
        )


def downgrade() -> None:
    with op.batch_alter_table("menstrual_cycle", schema=None) as batch_op:
        batch_op.drop_constraint(
            "menstrual_cycle_source_type",
            type_="check",
        )
        batch_op.drop_constraint(
            "menstrual_cycle_flow_level",
            type_="check",
        )
        batch_op.drop_column("source_type")
        batch_op.drop_column("flow_level")
