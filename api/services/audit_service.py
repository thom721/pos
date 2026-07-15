import json
from sqlalchemy.orm import Session
from api.models.AuditLog import AuditLog


def log(
    db: Session,
    *,
    user_id: str | None,
    tenant_id: str | None,
    action: str,
    resource_type: str,
    resource_id: str | None = None,
    detail: dict | str | None = None,
    ip: str | None = None,
) -> None:
    """Write an audit entry. Does NOT commit — the caller's transaction must commit."""
    detail_str: str | None = None
    if isinstance(detail, dict):
        detail_str = json.dumps(detail, ensure_ascii=False, default=str)
    elif isinstance(detail, str):
        detail_str = detail

    entry = AuditLog(
        user_id=user_id,
        tenant_id=tenant_id,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        detail=detail_str,
        ip_address=ip,
    )
    db.add(entry)
