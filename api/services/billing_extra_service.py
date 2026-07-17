from datetime import datetime, timezone
from sqlalchemy.orm import Session

from api.models.BillingExtra import BillingExtra


def record_extra(db: Session, tenant_id: str, resource_type: str, resource_id: str) -> BillingExtra:
    """Record a new extra (caisse or depot) starting now. Call when limit is exceeded and user confirmed."""
    extra = BillingExtra(
        tenant_id=tenant_id,
        resource_type=resource_type,
        resource_id=resource_id,
        started_at=datetime.now(timezone.utc),
    )
    db.add(extra)
    return extra


def close_extra(db: Session, resource_id: str) -> None:
    """Close the active BillingExtra for this resource (deactivated or deleted)."""
    extra = db.query(BillingExtra).filter(
        BillingExtra.resource_id == resource_id,
        BillingExtra.ended_at == None,  # noqa: E711
    ).first()
    if extra:
        extra.ended_at = datetime.now(timezone.utc)


def compute_prorated(
    db: Session,
    tenant_id: str,
    cycle_start: datetime,
    cycle_end: datetime,
    price_per_caisse_htg: float,
    price_per_caisse_usd: float,
    price_per_depot_htg: float,
    price_per_depot_usd: float,
) -> dict:
    """
    Compute prorated extra costs for the billing cycle [cycle_start, cycle_end].
    Returns breakdown per extra and totals.
    """
    extras = (
        db.query(BillingExtra)
        .filter(
            BillingExtra.tenant_id == tenant_id,
            BillingExtra.started_at < cycle_end,
        )
        .filter(
            (BillingExtra.ended_at == None) | (BillingExtra.ended_at > cycle_start)  # noqa: E711
        )
        .all()
    )

    cycle_days = max(1, (cycle_end - cycle_start).days)
    total_htg = 0.0
    total_usd = 0.0
    breakdown = []

    for extra in extras:
        active_from = max(extra.started_at, cycle_start)
        active_to   = min(extra.ended_at or cycle_end, cycle_end)
        active_days = max(0, (active_to - active_from).days)
        fraction    = active_days / cycle_days

        if extra.resource_type == "caisse":
            htg = round(fraction * price_per_caisse_htg, 2)
            usd = round(fraction * price_per_caisse_usd, 2)
        else:
            htg = round(fraction * price_per_depot_htg, 2)
            usd = round(fraction * price_per_depot_usd, 2)

        total_htg += htg
        total_usd += usd
        breakdown.append({
            "resource_type": extra.resource_type,
            "resource_id":   extra.resource_id,
            "started_at":    extra.started_at.isoformat(),
            "ended_at":      extra.ended_at.isoformat() if extra.ended_at else None,
            "active_days":   active_days,
            "cycle_days":    cycle_days,
            "amount_htg":    htg,
            "amount_usd":    usd,
        })

    return {
        "extras":     breakdown,
        "total_htg":  round(total_htg, 2),
        "total_usd":  round(total_usd, 2),
    }
