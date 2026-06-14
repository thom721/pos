from sqlalchemy.orm import Session


class TenantService:
    def __init__(self, db: Session, tenant_id: str | None = None):
        self.db = db
        self._tid = tenant_id

    def _q(self, model):
        """Returns a query filtered to the current tenant if tenant_id is set."""
        q = self.db.query(model)
        if self._tid:
            q = q.filter(model.tenant_id == self._tid)
        return q

    def _set_tenant(self, obj):
        """Sets tenant_id on a new object if we have a tenant context."""
        if self._tid and hasattr(obj, 'tenant_id'):
            obj.tenant_id = self._tid
        return obj
