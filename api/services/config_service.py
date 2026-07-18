import copy
from sqlalchemy.orm import Session
from api.models.AppConfig import AppConfig


def _copy_fields(src: AppConfig) -> dict:
    """Return field values from src that can seed a new AppConfig row."""
    skip = {'id', 'tenant_id', 'warehouse_id', '_sa_instance_state'}
    return {k: copy.copy(v) for k, v in src.__dict__.items() if k not in skip}


def get_or_create(
    db: Session,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
) -> AppConfig:
    q = db.query(AppConfig)

    # Exact match: (tenant_id, warehouse_id)
    if tenant_id and warehouse_id:
        config = q.filter(
            AppConfig.tenant_id == tenant_id,
            AppConfig.warehouse_id == warehouse_id,
        ).first()
        if config:
            return config

        # Fallback: tenant row without warehouse_id (legacy or global config)
        fallback = q.filter(
            AppConfig.tenant_id == tenant_id,
            AppConfig.warehouse_id.is_(None),
        ).first()

        # Create a warehouse-specific row (copy data from fallback or defaults)
        config = AppConfig(tenant_id=tenant_id, warehouse_id=warehouse_id)
        if fallback:
            for field, value in _copy_fields(fallback).items():
                setattr(config, field, value)
        db.add(config)
        db.commit()
        db.refresh(config)
        return config

    elif tenant_id:
        # Local mode (no warehouse_id): use the tenant-global NULL-warehouse row
        config = q.filter(
            AppConfig.tenant_id == tenant_id,
            AppConfig.warehouse_id.is_(None),
        ).first()

    else:
        # Fully local (no tenant either): any row without tenant
        config = q.filter(
            AppConfig.tenant_id.is_(None),
            AppConfig.warehouse_id.is_(None),
        ).first()

    if not config:
        config = AppConfig(tenant_id=tenant_id, warehouse_id=warehouse_id)
        db.add(config)
        db.commit()
        db.refresh(config)
    return config


def create_for_warehouse(
    db: Session,
    tenant_id: str,
    warehouse_id: str,
) -> AppConfig:
    """Ensure an AppConfig row exists for a newly created warehouse.
    Called automatically from the warehouse creation route."""
    return get_or_create(db, tenant_id=tenant_id, warehouse_id=warehouse_id)


def update(
    db: Session,
    data: dict,
    tenant_id: str | None = None,
    warehouse_id: str | None = None,
) -> AppConfig:
    config = get_or_create(db, tenant_id=tenant_id, warehouse_id=warehouse_id)
    for key, value in data.items():
        if hasattr(config, key):
            setattr(config, key, value)
    db.commit()
    db.refresh(config)
    return config
