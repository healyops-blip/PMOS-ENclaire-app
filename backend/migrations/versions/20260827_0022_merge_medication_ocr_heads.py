"""Merge medication history and OCR pipeline heads.

Revision ID: 20260827_0022
Revises: 20260827_0014, 20260827_0021
Create Date: 2026-08-27
"""

from collections.abc import Sequence

revision: str = "20260827_0022"
down_revision: tuple[str, str] = ("20260827_0014", "20260827_0021")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
