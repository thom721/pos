#!/usr/bin/env bash
# =============================================================================
# setup_ssl.sh  —  pos.infini-software.cloud
# Lancer sur le VPS en root :  sudo bash setup_ssl.sh
# =============================================================================
set -euo pipefail

DOMAIN="pos.infini-software.cloud"
EMAIL="admin@infini-software.cloud"     # ← votre email Let's Encrypt
PORT=9003

echo "=== 1. Libérer le port $PORT ==="
PIDS=$(lsof -ti tcp:$PORT 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
    kill -9 $PIDS
    echo "  Processus tués : $PIDS"
else
    echo "  Port $PORT déjà libre."
fi

echo ""
echo "=== 2. Installer la config nginx ==="
cp pos.infini-software.cloud.nginx.conf /etc/nginx/sites-available/$DOMAIN
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t
systemctl reload nginx
echo "  Nginx rechargé (bloc HTTP actif pour le challenge)."

echo ""
echo "=== 3. Obtenir le certificat SSL ==="
mkdir -p /var/www/certbot
certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN"

echo ""
echo "=== 4. Recharger nginx avec HTTPS ==="
nginx -t && systemctl reload nginx

echo ""
echo "=== 5. Renouvellement automatique (cron) ==="
CRON="0 3 * * * certbot renew --quiet && systemctl reload nginx"
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$CRON") | crontab -
echo "  Cron configuré : renouvellement tous les jours à 03h00."

echo ""
echo "============================================================"
echo "  https://$DOMAIN        → OK"
echo "  wss://$DOMAIN/ws       → OK"
echo "  Certificat             → /etc/letsencrypt/live/$DOMAIN/"
echo "============================================================"
echo ""
echo "Vérifications :"
echo "  curl -I https://$DOMAIN/api/setup/health"
echo "  nginx -t"
