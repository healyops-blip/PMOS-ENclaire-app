"""merge laboratory and medical-order OCR confirmation heads

Revision ID: 20260827_0023_merge
Revises: 20260827_0022_lab, 20260827_0023
Create Date: 2026-08-27 23:25:00
"""

from collections.abc import Sequence

revision: str = "20260827_0023_merge"
down_revision: tuple[str, str] = ("20260827_0022_lab", "20260827_0023")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
