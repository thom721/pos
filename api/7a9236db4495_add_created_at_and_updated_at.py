"""add created_at and updated_at

Revision ID: 7a9236db4495
Revises: 
Create Date: 2025-12-21 08:20:48.315511

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7a9236db4495'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email", sa.String(255), nullable=True),
    )

    op.create_unique_constraint(
        "uq_users_email",
        "users",
        ["email"],
    )

    op.create_index(
        "ix_products_name",
        "products",
        ["name"],
        unique=True,
    )



def downgrade() -> None:
    op.drop_index("ix_products_name", table_name="products")

    op.drop_constraint(
        "uq_users_email",
        "users",
        type_="unique",
    )

    op.drop_column("users", "email")

