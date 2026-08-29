"""allow OCR-confirmed fields to be stored as NULL when unavailable"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260830_0036"
down_revision: str | None = "20260829_0035"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("imaging_report") as batch:
        batch.alter_column("findings_text", existing_type=sa.Text(), nullable=True)
        batch.alter_column("conclusion_text", existing_type=sa.Text(), nullable=True)
        batch.drop_constraint("ck_imaging_findings_nonblank", type_="check")
        batch.drop_constraint("ck_imaging_conclusion_nonblank", type_="check")
    with op.batch_alter_table("outpatient_record") as batch:
        batch.alter_column("visit_date", existing_type=sa.Date(), nullable=True)
        batch.alter_column("diagnosis_summary", existing_type=sa.Text(), nullable=True)
        batch.alter_column("medical_advice", existing_type=sa.Text(), nullable=True)
        batch.drop_constraint("ck_outpatient_diagnosis_nonblank", type_="check")
        batch.drop_constraint("ck_outpatient_advice_nonblank", type_="check")
    with op.batch_alter_table("lab_observation") as batch:
        batch.alter_column("original_item_name", existing_type=sa.String(length=200), nullable=True)
        batch.alter_column("raw_value", existing_type=sa.String(length=100), nullable=True)
        batch.alter_column("numeric_value", existing_type=sa.Numeric(18, 6), nullable=True)
        batch.alter_column("original_unit", existing_type=sa.String(length=40), nullable=True)
        batch.alter_column("standard_unit", existing_type=sa.String(length=40), nullable=True)


def downgrade() -> None:
    raise NotImplementedError("Downgrade would discard NULL OCR fields")
