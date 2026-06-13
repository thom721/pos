from sqlalchemy.orm import Session
from api.models.AppConfig import AppConfig


def get_or_create(db: Session) -> AppConfig:
    config = db.query(AppConfig).first()
    if not config:
        config = AppConfig()
        db.add(config)
        db.commit()
        db.refresh(config)
    return config


def update(db: Session, data: dict) -> AppConfig:
    config = get_or_create(db)
    for key, value in data.items():
        if hasattr(config, key):
            setattr(config, key, value)
    db.commit()
    db.refresh(config)
    return config
