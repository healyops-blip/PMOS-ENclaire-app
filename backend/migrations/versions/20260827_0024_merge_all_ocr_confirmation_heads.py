"""merge all OCR confirmation heads

Revision ID: 20260827_0024_merge
Revises: 20260827_0023_merge, 20260827_0024
Create Date: 2026-08-27 23:35:00
"""

from collections.abc import Sequence

revision: str = "20260827_0024_merge"
down_revision: tuple[str, str] = ("20260827_0023_merge", "20260827_0024")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
