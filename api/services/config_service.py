from sqlalchemy.orm import Session
from api.models.AppConfig import AppConfig


def get_or_create(db: Session, tenant_id: str | None = None) -> AppConfig:
    q = db.query(AppConfig)
    if tenant_id:
        config = q.filter(AppConfig.tenant_id == tenant_id).first()
        if not config:
            # Fall back to the global (local-mode) config so admins who
            # configured the app in local mode don't lose their data when
            # the system switches to cloud mode.
            fallback = q.filter(AppConfig.tenant_id.is_(None)).first()
            if fallback:
                fallback.tenant_id = tenant_id
                db.commit()
                db.refresh(fallback)
                return fallback
    else:
        config = q.filter(AppConfig.tenant_id.is_(None)).first()

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
