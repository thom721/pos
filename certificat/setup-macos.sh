#!/usr/bin/env bash
# Fait confiance au certificat auto-signé dans macOS Keychain
# et ajoute infini-post.local dans /etc/hosts.
# Doit être lancé avec sudo.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
CERT="$DIR/server.crt"
HOST="infini-post.local"

if [ ! -f "$CERT" ]; then
  echo "✗ Certificat introuvable. Lance d'abord : bash $DIR/generate.sh"
  exit 1
fi

# ── 1. Confiance macOS Keychain ───────────────────────────────────────────────
echo "→ Ajout du certificat dans le Keychain système ..."
security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$CERT"
echo "✓ Certificat approuvé par macOS."

# ── 2. /etc/hosts ─────────────────────────────────────────────────────────────
if grep -q "$HOST" /etc/hosts; then
  echo "→ $HOST déjà présent dans /etc/hosts."
else
  echo "→ Ajout de $HOST dans /etc/hosts ..."
  printf "\n127.0.0.1\t%s\n" "$HOST" >> /etc/hosts
  echo "✓ $HOST ajouté."
fi

echo ""
echo "✓ Configuration terminée."
echo "  Lance maintenant : docker compose up -d"
echo "  Puis ouvre : https://infini-post.local"
