"""make account phone numbers unique for phone login"""

from collections.abc import Sequence

from alembic import op

revision: str = "20260828_0033"
down_revision: str | None = "20260828_0032"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("user_account", schema=None) as batch_op:
        batch_op.create_unique_constraint(
            "uq_user_account_phone_number",
            ["phone_number"],
        )


def downgrade() -> None:
    with op.batch_alter_table("user_account", schema=None) as batch_op:
        batch_op.drop_constraint("uq_user_account_phone_number", type_="unique")
