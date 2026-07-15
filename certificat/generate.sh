#!/usr/bin/env bash
# Génère un certificat auto-signé pour infini-post.local (valide 10 ans)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ Génération de server.key et server.crt dans $DIR ..."
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout "$DIR/server.key" \
  -out    "$DIR/server.crt" \
  -config "$DIR/openssl.cnf"

chmod 600 "$DIR/server.key"
echo "✓ Certificat généré."
echo ""
echo "Exécute ensuite :"
echo "  sudo bash $DIR/setup-macos.sh"
