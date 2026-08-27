"""Create authentication account and session tables.

Revision ID: 20260826_0001
Revises:
Create Date: 2026-08-26
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260826_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_account",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("uid", sa.String(length=36), nullable=False),
        sa.Column("account_name", sa.String(length=64), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("phone_number", sa.String(length=32), nullable=True),
        sa.Column("phone_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("account_type", sa.String(length=16), nullable=False),
        sa.Column("onboarding_completed", sa.Boolean(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "account_type IN ('user', 'admin')",
            name="account_type",
        ),
        sa.CheckConstraint(
            "status IN ('active', 'disabled', 'locked')",
            name="status",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_user_account"),
        sa.UniqueConstraint("account_name", name="uq_user_account_account_name"),
        sa.UniqueConstraint("uid", name="uq_user_account_uid"),
    )
    op.create_table(
        "user_session",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("account_uid", sa.String(length=36), nullable=False),
        sa.Column("session_hash", sa.String(length=128), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("client_platform", sa.String(length=32), nullable=True),
        sa.Column("device_name", sa.String(length=128), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.CheckConstraint(
            "status IN ('active', 'revoked', 'expired')",
            name="status",
        ),
        sa.ForeignKeyConstraint(
            ["account_uid"],
            ["user_account.uid"],
            name="fk_user_session_account_uid_user_account",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_user_session"),
        sa.UniqueConstraint("session_hash", name="uq_user_session_session_hash"),
    )
    op.create_index(
        "ix_user_session_account_uid_status",
        "user_session",
        ["account_uid", "status"],
        unique=False,
    )
    op.create_index("ix_user_session_expires_at", "user_session", ["expires_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_user_session_expires_at", table_name="user_session")
    op.drop_index("ix_user_session_account_uid_status", table_name="user_session")
    op.drop_table("user_session")
    op.drop_table("user_account")
