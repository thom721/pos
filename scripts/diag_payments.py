"""Diagnostic en lecture seule — répartition des payments par caissier
aujourd'hui, pour trouver d'ou vient un total de fermeture de caisse
incoherent avec les ventes reellement synchronisees.
"""
from datetime import datetime

from sqlalchemy import text

from api.database import SessionLocal

TODAY_7AM = datetime.now().strftime("%Y-%m-%d 00:00:00")


def main():
    db = SessionLocal()
    try:
        print("=== Sessions de caisse ouvertes aujourd'hui ===")
        for r in db.execute(text("""
            SELECT id, cashier_id, warehouse_id, opening_balance, opened_at, status
            FROM cashier_sessions
            WHERE opened_at >= :since
            ORDER BY opened_at
        """), {"since": TODAY_7AM}):
            print(dict(r._mapping))

        print("\n=== Payments d'aujourd'hui, groupes par caissier ===")
        for r in db.execute(text("""
            SELECT p.user_id, u.username, u.fname, u.lname,
                   COUNT(*) AS nb, SUM(p.amount) AS total
            FROM payments p
            LEFT JOIN users u ON u.id = p.user_id
            WHERE p.created_at >= :since AND p.reference_type = 'SALE'
            GROUP BY p.user_id, u.username, u.fname, u.lname
        """), {"since": TODAY_7AM}):
            print(dict(r._mapping))

        print("\n=== Detail des payments PAS lies a une vente existante (orphelins) ===")
        for r in db.execute(text("""
            SELECT p.id, p.reference_id, p.amount, p.method, p.user_id, p.created_at
            FROM payments p
            LEFT JOIN sales s ON s.id = p.reference_id AND p.reference_type = 'SALE'
            WHERE p.created_at >= :since AND p.reference_type = 'SALE' AND s.id IS NULL
        """), {"since": TODAY_7AM}):
            print(dict(r._mapping))
    finally:
        db.close()


if __name__ == "__main__":
    main()
