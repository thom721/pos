"""billing: annual plan, register trial, trial_included_in_billing, is_initial

Revision ID: a1b2c3d4e5f6
Revises: e1f2a3b4c5d6
Create Date: 2026-07-24

Nouveaux champs :
  platform_config : trial_included_in_billing (BOOL), annual_discount_pct (INT)
  pos_registers   : is_initial (BOOL), trial_ends_at (DATETIME), subscription_ends_at (DATETIME)
  billing_payments: plan_type (VARCHAR 10), register_ids_json (TEXT)
"""

from alembic import op
import sqlalchemy as sa

revision = 'a1b2c3d4e5f6'
down_revision = 'e1f2a3b4c5d6'
branch_labels = None
depends_on = None


def upgrade():
    # ── platform_config ──────────────────────────────────────────────────────
    with op.batch_alter_table('platform_config') as batch:
        batch.add_column(sa.Column(
            'trial_included_in_billing',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('0'),
        ))
        batch.add_column(sa.Column(
            'annual_discount_pct',
            sa.Integer(),
            nullable=False,
            server_default=sa.text('20'),
        ))

    # ── pos_registers ────────────────────────────────────────────────────────
    with op.batch_alter_table('pos_registers') as batch:
        batch.add_column(sa.Column(
            'is_initial',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('0'),
        ))
        batch.add_column(sa.Column(
            'trial_ends_at',
            sa.DateTime(timezone=True),
            nullable=True,
        ))
        batch.add_column(sa.Column(
            'subscription_ends_at',
            sa.DateTime(timezone=True),
            nullable=True,
        ))

    # ── billing_payments ─────────────────────────────────────────────────────
    with op.batch_alter_table('billing_payments') as batch:
        batch.add_column(sa.Column(
            'plan_type',
            sa.String(10),
            nullable=False,
            server_default=sa.text("'monthly'"),
        ))
        batch.add_column(sa.Column(
            'register_ids_json',
            sa.Text(),
            nullable=True,
        ))


def downgrade():
    with op.batch_alter_table('billing_payments') as batch:
        batch.drop_column('register_ids_json')
        batch.drop_column('plan_type')

    with op.batch_alter_table('pos_registers') as batch:
        batch.drop_column('subscription_ends_at')
        batch.drop_column('trial_ends_at')
        batch.drop_column('is_initial')

    with op.batch_alter_table('platform_config') as batch:
        batch.drop_column('annual_discount_pct')
        batch.drop_column('trial_included_in_billing')
