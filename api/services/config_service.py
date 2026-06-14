from sqlalchemy.orm import Session
from api.models.AppConfig import AppConfig


def get_or_create(db: Session, tenant_id: str | None = None) -> AppConfig:
    query = db.query(AppConfig)
    if tenant_id:
        query = query.filter(AppConfig.tenant_id == tenant_id)
    config = query.first()
    if not config:
        config = AppConfig()
        if tenant_id:
            config.tenant_id = tenant_id
        db.add(config)
        db.commit()
        db.refresh(config)
    return config


def update(db: Session, data: dict, tenant_id: str | None = None) -> AppConfig:
    config = get_or_create(db, tenant_id=tenant_id)
    for key, value in data.items():
        if hasattr(config, key):
            setattr(config, key, value)
    db.commit()
    db.refresh(config)
    return config
