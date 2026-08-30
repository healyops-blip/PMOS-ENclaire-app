"""merge the document display-asset branch and the medication-catalog branch

Both PR branches added a ``0035`` head independently
(``20260829_0035`` document display assets, ``20260830_0035`` medication
catalog + profile). This revision joins them into a single head; it carries
no schema changes of its own.
"""

from collections.abc import Sequence

revision: str = "20260830_0036"
down_revision: tuple[str, str] = ("20260829_0035", "20260830_0035")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
