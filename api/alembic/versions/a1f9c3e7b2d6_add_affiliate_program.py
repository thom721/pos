"""add affiliate referral program

Revision ID: a1f9c3e7b2d6
Revises: 9d52902ed421
Create Date: 2026-09-13

Programme de parrainage — indépendant du système Tenant/User (sa propre
table de comptes/auth). Ajoute :
- affiliates : comptes de parrainage (email/password/referral_code)
- affiliate_commissions : ledger append-only des commissions gagnées
- affiliate_withdrawals : demandes de retrait, traitées par un superadmin
- tenants.referred_by_affiliate_id : FK nullable, posée une seule fois à
  l'inscription si le tenant vient d'un lien ?ref=CODE.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a1f9c3e7b2d6'
down_revision: Union[str, Sequence[str], None] = '9d52902ed421'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "affiliates",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("email", sa.String(255), nullable=False, unique=True, index=True),
        sa.Column("password", sa.String(255), nullable=False),
        sa.Column("full_name", sa.String(200), nullable=False),
        sa.Column("phone", sa.String(50), nullable=True),
        sa.Column("referral_code", sa.String(20), nullable=False, unique=True, index=True),
        sa.Column("is_email_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("email_verification_code", sa.String(10), nullable=True),
        sa.Column("email_verification_expires_at", sa.DateTime(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )

    op.create_table(
        "affiliate_commissions",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("affiliate_id", sa.String(36), sa.ForeignKey("affiliates.id"), nullable=False, index=True),
        sa.Column("tenant_id", sa.String(36), sa.ForeignKey("tenants.id"), nullable=False, index=True),
        sa.Column("register_id", sa.String(36), sa.ForeignKey("pos_registers.id"), nullable=False, index=True),
        sa.Column("billing_payment_id", sa.String(36), sa.ForeignKey("billing_payments.id"), nullable=False, index=True),
        sa.Column("register_rank", sa.Integer(), nullable=False),
        sa.Column("commission_rate", sa.Numeric(6, 5), nullable=False),
        sa.Column("base_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("commission_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="available"),
        sa.UniqueConstraint("billing_payment_id", "register_id", name="uq_affiliate_commission_payment_register"),
    )

    op.create_table(
        "affiliate_withdrawals",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("affiliate_id", sa.String(36), sa.ForeignKey("affiliates.id"), nullable=False, index=True),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("payout_method", sa.Text(), nullable=True),
        sa.Column("admin_note", sa.Text(), nullable=True),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
        sa.Column("processed_by", sa.String(255), nullable=True),
    )

    with op.batch_alter_table("tenants") as batch_op:
        batch_op.add_column(
            sa.Column("referred_by_affiliate_id", sa.String(36), sa.ForeignKey("affiliates.id"), nullable=True)
        )
        batch_op.create_index(
            "ix_tenants_referred_by_affiliate_id", ["referred_by_affiliate_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("tenants") as batch_op:
        batch_op.drop_index("ix_tenants_referred_by_affiliate_id")
        batch_op.drop_column("referred_by_affiliate_id")
    op.drop_table("affiliate_withdrawals")
    op.drop_table("affiliate_commissions")
    op.drop_table("affiliates")
