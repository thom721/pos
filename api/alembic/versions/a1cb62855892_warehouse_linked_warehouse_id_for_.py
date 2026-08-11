"""warehouse linked_warehouse_id for entrepot sync scoping

Revision ID: a1cb62855892
Revises: cc8644056cfe
Create Date: 2026-08-11 18:14:45.307081

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1cb62855892'
down_revision: Union[str, Sequence[str], None] = 'cc8644056cfe'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table("warehouses") as batch_op:
        batch_op.add_column(
            sa.Column("linked_warehouse_id", sa.String(length=36), nullable=True)
        )
        batch_op.create_foreign_key(
            "fk_warehouse_linked_warehouse_id",
            "warehouses", ["linked_warehouse_id"], ["id"],
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table("warehouses") as batch_op:
        batch_op.drop_constraint("fk_warehouse_linked_warehouse_id", type_="foreignkey")
        batch_op.drop_column("linked_warehouse_id")
