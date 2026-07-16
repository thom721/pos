"""
Utilitaire d'envoi d'email SMTP pour les notifications de plan.
Config lue depuis PlatformConfig (table singleton).
"""
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime, timezone, timedelta


def _send_via_smtp(host: str, port: int, user: str, password: str,
                   from_addr: str, to_addr: str,
                   subject: str, html: str) -> None:
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
        return  # SMTP non configuré → silencieux

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
            pass  # échec silencieux

    threading.Thread(target=_send, daemon=True).start()


def maybe_send_warning(tenant, db) -> None:
    """
    Envoie l'email de warning si :
    - Le plan expire dans ≤ 5 jours
    - Aucun email envoyé dans les dernières 24h
    Appeler depuis le login handler.
    """
    from api.models.PlatformConfig import PlatformConfig
    from api.core.tenant import plan_warning

    warning = plan_warning(tenant)
    if not warning:
        return

    now = datetime.now(timezone.utc)
    last = getattr(tenant, "last_warning_sent_at", None)
    if last:
        if last.tzinfo is None:
            last = last.replace(tzinfo=timezone.utc)
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
