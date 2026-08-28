"""add resumable onboarding draft"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260828_0032"
down_revision: str | None = "20260828_0031"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "onboarding_draft",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("account_uid", sa.String(length=36), nullable=False),
        sa.Column("current_step", sa.String(length=16), nullable=False),
        sa.Column("basic_data", sa.JSON(), nullable=True),
        sa.Column("cycle_data", sa.JSON(), nullable=True),
        sa.Column("medications_data", sa.JSON(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "current_step IN ('basic', 'cycle', 'medications', 'complete')",
            name="onboarding_draft_current_step",
        ),
        sa.ForeignKeyConstraint(["account_uid"], ["user_account.uid"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("account_uid", name="uq_onboarding_draft_account_uid"),
    )


def downgrade() -> None:
    op.drop_table("onboarding_draft")
