#!/usr/bin/env bash
# POS Connect — Linux build + .deb packaging script
# Run from the frontend/ folder on a Linux machine with Flutter installed:
#   chmod +x build_linux.sh && ./build_linux.sh

set -e

APP_NAME="pos-connect"
APP_VERSION="1.0.0"
ARCH="amd64"
DEB_DIR="build/linux/deb/${APP_NAME}_${APP_VERSION}"
BUNDLE="build/linux/x64/release/bundle"

echo "POS Connect — Linux Build"
echo "================================"

# 1. Get packages
echo ""
echo "[1/4] Getting packages..."
flutter pub get

# 2. Build release
echo ""
echo "[2/4] Building Linux release..."
flutter build linux --release
echo "  Bundle: $BUNDLE"

# 3. Assemble .deb structure
echo ""
echo "[3/4] Assembling .deb package..."

rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/opt/pos_connect"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy Flutter bundle
cp -r "$BUNDLE/." "$DEB_DIR/opt/pos_connect/"

# Symlink binary to /usr/bin
ln -sf /opt/pos_connect/pos_connect "$DEB_DIR/usr/bin/pos_connect"

# Desktop file
cp linux/pos_connect.desktop "$DEB_DIR/usr/share/applications/"

# Icon (use macOS 512x512 PNG)
ICON_SRC="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/pos_connect.png"
fi

# DEBIAN/control
cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: pos-connect
Version: ${APP_VERSION}
Architecture: ${ARCH}
Maintainer: POS Connect
Description: POS Connect — Système de caisse moderne
 Application de point de vente pour commerce, restaurant et dépôt.
Depends: libgtk-3-0, libblkid1, liblzma5
Section: office
Priority: optional
EOF

# DEBIAN/postinst — fix permissions after install
cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
chmod +x /opt/pos_connect/pos_connect
update-desktop-database /usr/share/applications/ 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# 4. Build .deb
echo ""
echo "[4/4] Building .deb package..."
dpkg-deb --build "$DEB_DIR" "build/linux/${APP_NAME}_${APP_VERSION}_${ARCH}.deb"

DEB_FILE="build/linux/${APP_NAME}_${APP_VERSION}_${ARCH}.deb"
SIZE=$(du -sh "$DEB_FILE" | cut -f1)
echo ""
echo "Done! Package: $DEB_FILE ($SIZE)"
echo ""
echo "To install:"
echo "  sudo dpkg -i $DEB_FILE"
echo "  sudo apt-get install -f   # fix dependencies if needed"
