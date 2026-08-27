"""complete medication version history and event metadata

Revision ID: 20260827_0014
Revises: 20260827_0012
Create Date: 2026-08-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260827_0014"
down_revision: str | None = "20260827_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("medication") as batch_op:
        batch_op.add_column(sa.Column("idempotency_key", sa.String(length=128), nullable=True))
        batch_op.create_unique_constraint(
            "uq_medication_patient_idempotency", ["patient_id", "idempotency_key"]
        )
    with op.batch_alter_table("medication_event") as batch_op:
        batch_op.add_column(sa.Column("stop_source", sa.String(length=32), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("medication_event") as batch_op:
        batch_op.drop_column("stop_source")
    with op.batch_alter_table("medication") as batch_op:
        batch_op.drop_constraint("uq_medication_patient_idempotency", type_="unique")
        batch_op.drop_column("idempotency_key")
