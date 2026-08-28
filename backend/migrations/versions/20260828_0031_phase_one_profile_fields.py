"""add phase-one profile fields"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260828_0031"
down_revision: str | None = "20260827_0031"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("patient_profile", schema=None) as batch_op:
        batch_op.add_column(sa.Column("birth_year", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("usual_cycle_min_days", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("usual_cycle_max_days", sa.Integer(), nullable=True))
        batch_op.create_check_constraint(
            "patient_profile_cycle_range",
            "usual_cycle_min_days IS NULL OR usual_cycle_max_days IS NULL "
            "OR usual_cycle_min_days <= usual_cycle_max_days",
        )


def downgrade() -> None:
    with op.batch_alter_table("patient_profile", schema=None) as batch_op:
        batch_op.drop_constraint("patient_profile_cycle_range", type_="check")
        batch_op.drop_column("usual_cycle_max_days")
        batch_op.drop_column("usual_cycle_min_days")
        batch_op.drop_column("birth_year")
