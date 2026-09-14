import secrets
from decimal import Decimal

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from api.models.Affiliate import Affiliate
from api.models.AffiliateCommission import AffiliateCommission
from api.models.PosRegister import PosRegister

# Pas de 0/O/1/I — même alphabet que InstallationCode.generate_installation_code().
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LENGTH = 8

# Barème dégressif : rang 1 = 20%, puis chaque rang suivant = 80% du taux du
# rang précédent, plafonné au rang 5 (rang 6+ = 0%, plafond FIXE — pas un
# seuil de pourcentage). Confirmé avec l'utilisateur, récurrent à chaque
# renouvellement de la caisse concernée.
_MAX_COMMISSION_RANK = 5
_BASE_RATE = Decimal("0.20")
_DECAY = Decimal("0.8")


def generate_referral_code(db: Session) -> str:
    """Code court, unique, lisible (pas de caractères ambigus)."""
    for _ in range(20):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(_CODE_LENGTH))
        if not db.query(Affiliate.id).filter(Affiliate.referral_code == code).first():
            return code
    raise RuntimeError("Impossible de générer un code de parrainage unique")


def commission_rate_for_rank(rank: int) -> Decimal:
    if rank < 1 or rank > _MAX_COMMISSION_RANK:
        return Decimal("0")
    return _BASE_RATE * (_DECAY ** (rank - 1))


def compute_rank(db: Session, tenant_id: str, register_id: str) -> int:
    """Rang (1-based) de cette caisse parmi toutes celles du tenant, par ordre
    de création — figé dans le temps puisque l'ordre de création ne change
    jamais."""
    ids = [
        r.id for r in db.query(PosRegister.id)
        .filter(PosRegister.tenant_id == tenant_id)
        .order_by(PosRegister.created_at.asc(), PosRegister.id.asc())
        .all()
    ]
    try:
        return ids.index(register_id) + 1
    except ValueError:
        return 1


def record_commission(
    db: Session, *, tenant, register, billing_payment_id: str, base_amount: float,
) -> AffiliateCommission | None:
    """Enregistre la commission du parrain de `tenant` pour ce renouvellement
    de `register`, s'il y en a un et si le rang de cette caisse est encore
    commissionné. Idempotent : un doublon (billing_payment_id, register_id)
    est silencieusement ignoré (confirm_payment rejoué)."""
    if not tenant.referred_by_affiliate_id:
        return None

    rank = compute_rank(db, tenant.id, register.id)
    rate = commission_rate_for_rank(rank)
    if rate <= 0:
        return None

    amount = (Decimal(str(base_amount)) * rate).quantize(Decimal("0.01"))
    commission = AffiliateCommission(
        affiliate_id=tenant.referred_by_affiliate_id,
        tenant_id=tenant.id,
        register_id=register.id,
        billing_payment_id=billing_payment_id,
        register_rank=rank,
        commission_rate=rate,
        base_amount=Decimal(str(base_amount)).quantize(Decimal("0.01")),
        commission_amount=amount,
    )
    db.add(commission)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return None
    return commission


def available_balance(db: Session, affiliate_id: str) -> Decimal:
    rows = db.query(AffiliateCommission.commission_amount).filter(
        AffiliateCommission.affiliate_id == affiliate_id,
        AffiliateCommission.status == 'available',
    ).all()
    return sum((r[0] for r in rows), Decimal("0"))
