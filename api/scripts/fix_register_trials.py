"""
Chiffre trial_ends_at sur toutes les caisses où il est NULL ou illisible.
Fallback : tenant.trial_ends_at, sinon now + 30 jours.

Usage (depuis le conteneur) :
    docker exec post_api python -c "
    import sys; sys.path.insert(0, '/app')
    exec(open('/app/api/scripts/fix_register_trials.py').read())
    "
"""
import sys
sys.path.insert(0, '/app')

from datetime import datetime, timedelta, timezone
from api.database import SessionLocal
from api.models.PosRegister import PosRegister
from api.models.Tenant import Tenant
from api.core.billing_crypto import try_decrypt_register_date

db = SessionLocal()
fixed = 0
already_ok = 0

try:
    registers = db.query(PosRegister).filter(PosRegister.is_active == True).all()

    for reg in registers:
        # Tenter de déchiffrer le token existant
        current = try_decrypt_register_date(reg._trial_ends_at, reg.id)

        if current is not None and current > datetime.now(timezone.utc):
            already_ok += 1
            continue  # token valide, rien à faire

        # Trouver une date de remplacement
        tenant = db.get(Tenant, reg.tenant_id)
        if tenant and tenant.trial_ends_at:
            t = tenant.trial_ends_at
            if t.tzinfo is None:
                t = t.replace(tzinfo=timezone.utc)
            new_trial = t
        else:
            new_trial = datetime.now(timezone.utc) + timedelta(days=30)

        reg.trial_ends_at = new_trial
        fixed += 1
        print(f"  Caisse {reg.name} ({reg.id[:8]}...) → trial jusqu'au {new_trial.date()}")

    db.commit()
    print(f"\nRésultat : {fixed} caisse(s) corrigée(s), {already_ok} déjà OK.")
finally:
    db.close()
