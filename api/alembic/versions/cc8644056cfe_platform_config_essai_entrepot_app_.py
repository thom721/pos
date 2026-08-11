"""platform_config: essai entrepot + app_config alerte stock bas

Revision ID: cc8644056cfe
Revises: 2ae5df8ad12c
Create Date: 2026-08-11 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cc8644056cfe'
down_revision: Union[str, Sequence[str], None] = '2ae5df8ad12c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _col_exists(table: str, column: str) -> bool:
    n = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c"
    ), {"t": table, "c": column}).scalar()
    return int(n) > 0


def upgrade() -> None:
    if not _col_exists("platform_config", "entrepot_trial_days"):
        op.add_column("platform_config",
            sa.Column("entrepot_trial_days", sa.Integer, nullable=False, server_default="30"))
    if not _col_exists("platform_config", "entrepot_trial_all"):
        op.add_column("platform_config",
            sa.Column("entrepot_trial_all", sa.Boolean, nullable=False, server_default="0"))
    if not _col_exists("app_config", "low_stock_alert_enabled"):
        op.add_column("app_config",
            sa.Column("low_stock_alert_enabled", sa.Boolean, nullable=False, server_default="0"))
    if not _col_exists("app_config", "low_stock_alert_roles"):
        op.add_column("app_config",
            sa.Column("low_stock_alert_roles", sa.Text, nullable=True))


def downgrade() -> None:
    if _col_exists("app_config", "low_stock_alert_roles"):
        op.drop_column("app_config", "low_stock_alert_roles")
    if _col_exists("app_config", "low_stock_alert_enabled"):
        op.drop_column("app_config", "low_stock_alert_enabled")
    if _col_exists("platform_config", "entrepot_trial_all"):
        op.drop_column("platform_config", "entrepot_trial_all")
    if _col_exists("platform_config", "entrepot_trial_days"):
        op.drop_column("platform_config", "entrepot_trial_days")
