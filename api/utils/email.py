"""
Utilitaire d'envoi d'email SMTP pour les notifications de plan.
Config lue depuis PlatformConfig (table singleton).
"""
import json
import logging
import re
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import timedelta

from api.core.dt_coerce import now_local

_log = logging.getLogger("pos.email")

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _is_valid_email(addr: str | None) -> bool:
    return bool(addr) and bool(_EMAIL_RE.match(addr))


def _send_via_smtp(host: str, port: int, user: str, password: str,
                   from_addr: str, to_addr: str,
                   subject: str, html: str) -> None:
    if not _is_valid_email(to_addr):
        _log.warning("Email non envoyé — adresse invalide : %r", to_addr)
        return

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = from_addr
    msg["To"]      = to_addr
    msg.attach(MIMEText(html, "html", "utf-8"))

    with smtplib.SMTP(host, port, timeout=10) as server:
        server.ehlo()
        server.starttls()
        if user and password:
            server.login(user, password)
        server.sendmail(from_addr, [to_addr], msg.as_string())


def send_plan_warning_email(
    tenant_email: str,
    business_name: str,
    days_left: int,
    plan_type: str,           # "trial" | "subscription"
    smtp_host: str,
    smtp_port: int,
    smtp_user: str,
    smtp_password: str,
    smtp_from: str,
) -> None:
    """Lance l'envoi en arrière-plan — ne bloque pas la requête."""

    if not smtp_host or not smtp_from:
        _log.warning("Email non envoyé — SMTP non configuré (PlatformConfig.smtp_host/smtp_from vide)")
        return

    label = "période d'essai" if plan_type == "trial" else "abonnement"
    if days_left == 0:
        delay_txt = "aujourd'hui"
    elif days_left == 1:
        delay_txt = "demain"
    else:
        delay_txt = f"dans {days_left} jour(s)"

    subject = f"POS Connect — Votre {label} expire {delay_txt}"
    html = f"""
<html><body style="font-family:sans-serif;color:#222">
<h2 style="color:#c0392b">⚠️ Votre {label} POS Connect expire {delay_txt}</h2>
<p>Bonjour <strong>{business_name}</strong>,</p>
<p>Votre <strong>{label}</strong> arrive à expiration <strong>{delay_txt}</strong>.</p>
<p>Après expiration, vous aurez une période de grâce de <strong>10 jours</strong>
pendant laquelle la connexion reste possible, mais <strong>la création de nouvelles ventes
sera bloquée</strong>.</p>
<p>
  <a href="https://posconnect.ht/billing"
     style="background:#2980b9;color:#fff;padding:10px 20px;border-radius:4px;text-decoration:none">
    Renouveler maintenant
  </a>
</p>
<p style="color:#888;font-size:12px">
  POS Connect &mdash; posconnect.ht<br>
  Cet email a été envoyé automatiquement.
</p>
</body></html>
"""

    def _send():
        try:
            _send_via_smtp(smtp_host, smtp_port, smtp_user, smtp_password,
                           smtp_from, tenant_email, subject, html)
        except Exception:
            # Ne bloque jamais la requête HTTP (thread séparé) mais ne doit
            # plus jamais échouer en silence total — sans ce log, aucune
            # trace nulle part d'un envoi SMTP en échec (mauvais port/mode
            # TLS, identifiants invalides, etc.).
            _log.exception("Échec envoi email (plan warning) vers %s", tenant_email)

    threading.Thread(target=_send, daemon=True).start()


def send_password_reset_email(
    to_addr: str,
    code: str,
    smtp_host: str,
    smtp_port: int,
    smtp_user: str,
    smtp_password: str,
    smtp_from: str,
) -> None:
    """Lance l'envoi en arrière-plan — ne bloque pas la requête."""
    if not smtp_host or not smtp_from:
        _log.warning("Email non envoyé — SMTP non configuré (PlatformConfig.smtp_host/smtp_from vide)")
        return

    subject = "POS Connect — Code de réinitialisation de mot de passe"
    html = f"""
<html><body style="font-family:sans-serif;color:#222">
<h2>Réinitialisation de mot de passe</h2>
<p>Voici votre code de vérification :</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:4px">{code}</p>
<p>Ce code expire dans 15 minutes. Si vous n'êtes pas à l'origine de cette
demande, ignorez cet email — votre mot de passe reste inchangé.</p>
<p style="color:#888;font-size:12px">
  POS Connect &mdash; posconnect.ht<br>
  Cet email a été envoyé automatiquement.
</p>
</body></html>
"""

    def _send():
        try:
            _send_via_smtp(smtp_host, smtp_port, smtp_user, smtp_password,
                           smtp_from, to_addr, subject, html)
        except Exception:
            _log.exception("Échec envoi email (reset mot de passe) vers %s", to_addr)

    threading.Thread(target=_send, daemon=True).start()


def send_low_stock_digest_email(
    to_addr: str,
    business_name: str,
    products: list[dict],   # [{"name", "stock", "alert_stock"}, ...]
    smtp_host: str,
    smtp_port: int,
    smtp_user: str,
    smtp_password: str,
    smtp_from: str,
) -> None:
    """Lance l'envoi en arrière-plan — ne bloque pas la requête.
    Un seul email récapitulatif listant tous les produits sous leur seuil
    d'alerte (au lieu d'un email par produit/par franchissement)."""
    if not smtp_host or not smtp_from:
        _log.warning("Email non envoyé — SMTP non configuré (PlatformConfig.smtp_host/smtp_from vide)")
        return

    count = len(products)
    subject = f"POS Connect — {count} produit(s) en stock bas"
    rows = "".join(
        f'<tr><td style="padding:6px 12px;border-bottom:1px solid #eee">{p["name"]}</td>'
        f'<td style="padding:6px 12px;border-bottom:1px solid #eee;text-align:right">{p["stock"]}</td>'
        f'<td style="padding:6px 12px;border-bottom:1px solid #eee;text-align:right">{p["alert_stock"]}</td></tr>'
        for p in products
    )
    html = f"""
<html><body style="font-family:sans-serif;color:#222">
<h2 style="color:#c0392b">⚠️ Stock bas — {business_name}</h2>
<p>Bonjour,</p>
<p><strong>{count}</strong> produit(s) sont actuellement sous leur seuil d'alerte :</p>
<table style="border-collapse:collapse;width:100%;max-width:500px">
<tr style="background:#f5f5f5">
  <th style="padding:6px 12px;text-align:left">Produit</th>
  <th style="padding:6px 12px;text-align:right">Stock</th>
  <th style="padding:6px 12px;text-align:right">Seuil</th>
</tr>
{rows}
</table>
<p style="color:#888;font-size:12px">
  POS Connect &mdash; posconnect.ht<br>
  Récapitulatif quotidien envoyé automatiquement.
</p>
</body></html>
"""

    def _send():
        try:
            _send_via_smtp(smtp_host, smtp_port, smtp_user, smtp_password,
                           smtp_from, to_addr, subject, html)
        except Exception:
            _log.exception("Échec envoi email (digest stock bas) vers %s", to_addr)

    threading.Thread(target=_send, daemon=True).start()


def maybe_send_low_stock_digest(db, tenant_id: str) -> None:
    """
    Envoie, une fois par jour au maximum, un email récapitulatif listant tous
    les produits actuellement sous leur seuil d'alerte pour ce tenant —
    appelé depuis la boucle _daily_notif_loop (api/main.py) en fin de
    journée. Remplace l'ancien envoi immédiat par produit/par franchissement
    (trop de mails). Réglage par tenant : AppConfig.low_stock_alert_enabled/
    _roles ; anti-doublon : AppConfig.low_stock_digest_sent_date.
    """
    from api.models.AppConfig import AppConfig
    from api.models.PlatformConfig import PlatformConfig
    from api.models.User import User
    from api.services.stock_service import list_low_stock_products

    cfg = (
        db.query(AppConfig)
        .filter(AppConfig.tenant_id == tenant_id, AppConfig.warehouse_id.is_(None))
        .first()
    )
    if not cfg or not cfg.low_stock_alert_enabled:
        return

    today = now_local().date()
    if cfg.low_stock_digest_sent_date == today:
        return  # déjà envoyé aujourd'hui

    roles = []
    if cfg.low_stock_alert_roles:
        try:
            roles = json.loads(cfg.low_stock_alert_roles)
        except (ValueError, TypeError):
            roles = []
    if not roles:
        return

    products = list_low_stock_products(db, tenant_id=tenant_id)
    if not products:
        return

    platform_cfg = db.query(PlatformConfig).first()
    if not platform_cfg or not platform_cfg.smtp_host or not platform_cfg.smtp_from:
        return  # SMTP non configuré

    recipients = (
        db.query(User)
        .filter(User.tenant_id == tenant_id, User.is_active == True)  # noqa: E712
        .all()
    )
    business_name = getattr(cfg, "business_name", None) or ""
    for user in recipients:
        if not user.email or not any(r in (user.roles or []) for r in roles):
            continue
        send_low_stock_digest_email(
            to_addr       = user.email,
            business_name = business_name,
            products      = products,
            smtp_host     = platform_cfg.smtp_host,
            smtp_port     = platform_cfg.smtp_port,
            smtp_user     = platform_cfg.smtp_user,
            smtp_password = platform_cfg.smtp_password,
            smtp_from     = platform_cfg.smtp_from,
        )

    cfg.low_stock_digest_sent_date = today
    try:
        db.commit()
    except Exception:
        db.rollback()


def send_evening_low_stock_digests(db) -> None:
    """Parcourt tous les tenants ayant activé low_stock_alert_enabled et
    envoie le digest quotidien (voir maybe_send_low_stock_digest, qui gère
    déjà l'anti-doublon). Appelé une fois par jour en fin de journée par
    _daily_notif_loop (api/main.py)."""
    from api.models.AppConfig import AppConfig

    tenant_ids = (
        db.query(AppConfig.tenant_id)
        .filter(AppConfig.low_stock_alert_enabled == True, AppConfig.tenant_id.isnot(None))  # noqa: E712
        .distinct()
        .all()
    )
    for (tenant_id,) in tenant_ids:
        maybe_send_low_stock_digest(db, tenant_id)


def maybe_send_warning(tenant, db) -> None:
    """
    Envoie l'email de warning si :
    - Le plan expire dans ≤ 5 jours
    - Aucun email envoyé dans les dernières 24h
    Appelé une fois par jour le matin par send_morning_plan_warnings, via
    _daily_notif_loop (api/main.py) — plus à chaque connexion (trop de mails
    en rafale à chaque login avec plusieurs caisses/utilisateurs).
    """
    from api.models.PlatformConfig import PlatformConfig
    from api.core.tenant import plan_warning

    warning = plan_warning(tenant)
    if not warning:
        return

    now = now_local()
    last = getattr(tenant, "last_warning_sent_at", None)
    if last:
        if now - last < timedelta(hours=24):
            return  # déjà envoyé récemment

    cfg = db.query(PlatformConfig).first()
    if not cfg or not cfg.smtp_host or not cfg.smtp_from:
        return  # SMTP non configuré

    send_plan_warning_email(
        tenant_email  = tenant.owner_email,
        business_name = tenant.business_name,
        days_left     = warning["days_left"],
        plan_type     = warning["type"],
        smtp_host     = cfg.smtp_host,
        smtp_port     = cfg.smtp_port,
        smtp_user     = cfg.smtp_user,
        smtp_password = cfg.smtp_password,
        smtp_from     = cfg.smtp_from,
    )

    tenant.last_warning_sent_at = now
    try:
        db.commit()
    except Exception:
        db.rollback()


def send_morning_plan_warnings(db) -> None:
    """Parcourt tous les tenants non-locaux et envoie l'avertissement
    d'expiration de plan si applicable (voir maybe_send_warning, qui gère
    déjà le seuil ≤5 jours et le anti-doublon 24h). Appelé une fois par jour
    le matin par _daily_notif_loop (api/main.py)."""
    from api.models.Tenant import Tenant

    tenants = db.query(Tenant).filter(Tenant.is_local == False).all()  # noqa: E712
    for tenant in tenants:
        maybe_send_warning(tenant, db)
