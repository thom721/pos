from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc

from api.database import get_db
from api.models.User import User
from api.models.AuditLog import AuditLog
from api.dependencies.auth import require_permission
from api.core.permissions import P

router = APIRouter(prefix="/api/audit", tags=["Audit"])


@router.get("/")
def list_audit_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(50, le=200),
    resource_type: str | None = Query(None),
    action: str | None = Query(None),
    user_id: str | None = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission(P.AUDIT_READ)),
):
    q = db.query(AuditLog).filter(AuditLog.tenant_id == current_user.tenant_id)

    if resource_type:
        q = q.filter(AuditLog.resource_type == resource_type)
    if action:
        q = q.filter(AuditLog.action == action)
    if user_id:
        q = q.filter(AuditLog.user_id == user_id)

    total = q.count()
    items = (
        q.order_by(desc(AuditLog.created_at))
         .offset((page - 1) * limit)
         .limit(limit)
         .all()
    )

    # Enrich with user name from joined query
    from api.models.User import User as UserModel
    user_cache: dict[str, str] = {}

    def _user_name(uid: str | None) -> str:
        if not uid:
            return "Système"
        if uid not in user_cache:
            u = db.get(UserModel, uid)
            user_cache[uid] = f"{u.fname} {u.lname}".strip() if u else uid
        return user_cache[uid]

    return {
        "total": total,
        "page": page,
        "limit": limit,
        "data": [
            {
                "id":            row.id,
                "action":        row.action,
                "resource_type": row.resource_type,
                "resource_id":   row.resource_id,
                "detail":        row.detail,
                "user_id":       row.user_id,
                "user_name":     _user_name(row.user_id),
                "ip_address":    row.ip_address,
                "created_at":    row.created_at,
            }
            for row in items
        ],
    }
