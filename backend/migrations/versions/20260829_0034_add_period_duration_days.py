"""add the usual period duration to patient profiles"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260829_0034"
down_revision: str | None = "20260828_0033"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("patient_profile", schema=None) as batch_op:
        batch_op.add_column(sa.Column("period_duration_days", sa.Integer(), nullable=True))
        batch_op.create_check_constraint(
            "patient_profile_period_duration",
            "period_duration_days IS NULL OR period_duration_days BETWEEN 1 AND 14",
        )


def downgrade() -> None:
    with op.batch_alter_table("patient_profile", schema=None) as batch_op:
        batch_op.drop_constraint("patient_profile_period_duration", type_="check")
        batch_op.drop_column("period_duration_days")
