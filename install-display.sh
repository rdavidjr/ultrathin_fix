#!/bin/bash
# Install reversible MacBook8,1 display remanence mitigations.
# Independent of the SPI/s2idle fix (install.sh).
# Run: sudo bash install-display.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/var/backups/macbook8.1-display-${STAMP}"
STATE_FILE="/var/lib/macbook8.1-display/install-state"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$PRODUCT" != "MacBook8,1" ] && [ "${FORCE_INSTALL:-}" != "1" ]; then
  echo "This machine reports product_name='$PRODUCT' (expected MacBook8,1)."
  echo "Refusing to install. Set FORCE_INSTALL=1 to override."
  exit 1
fi

mkdir -p "$BACKUP_ROOT" /var/lib/macbook8.1-display \
  /etc/macbook8.1-display /usr/local/sbin /usr/local/bin /etc/udev/rules.d

{
  echo "STAMP=$STAMP"
  echo "BACKUP_ROOT=$BACKUP_ROOT"
  echo "PRODUCT=$PRODUCT"
  echo "INSTALLED_AT=$(date -Is)"
} > "$STATE_FILE"
cp -a "$STATE_FILE" "$BACKUP_ROOT/install-state"

echo "==> Installing brightness soft-cap (default 70%)"
install -m 0755 "$PKG_DIR/bin/macbook-brightness-cap.sh" /usr/local/sbin/macbook-brightness-cap.sh
install -m 0644 "$PKG_DIR/systemd/brightness-cap.conf" /etc/macbook8.1-display/brightness-cap.conf
install -m 0644 "$PKG_DIR/systemd/90-macbook-brightness-cap.rules" \
  /etc/udev/rules.d/90-macbook-brightness-cap.rules
install -m 0644 "$PKG_DIR/systemd/macbook-brightness-cap.service" \
  /etc/systemd/system/macbook-brightness-cap.service

udevadm control --reload-rules 2>/dev/null || true
systemctl daemon-reload
systemctl enable macbook-brightness-cap.service
systemctl start macbook-brightness-cap.service || true

echo "==> Installing panel-clear helper"
install -m 0755 "$PKG_DIR/bin/panel-clear.py" /usr/local/bin/panel-clear

echo
echo "Display mitigations installed."
echo "  Backup:       $BACKUP_ROOT"
echo "  Brightness:   capped to BRIGHTNESS_CAP_PERCENT in /etc/macbook8.1-display/brightness-cap.conf"
echo "  Clear panel:  panel-clear                 # 5 min white, then black"
echo "                panel-clear --minutes 10"
echo "  Revert:       sudo bash $PKG_DIR/revert-display.sh"
echo
echo "This reduces IPS image retention; it does not replace a worn panel."
