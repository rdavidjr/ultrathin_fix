#!/bin/bash
# Revert display remanence mitigations installed by install-display.sh.
# Does not touch the SPI/s2idle fix.
# Run: sudo bash revert-display.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/var/lib/macbook8.1-display/install-state"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

BACKUP_ROOT=""
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

echo "==> Removing brightness soft-cap"
systemctl disable --now macbook-brightness-cap.service 2>/dev/null || true
rm -f /etc/systemd/system/macbook-brightness-cap.service
rm -f /etc/udev/rules.d/90-macbook-brightness-cap.rules
rm -f /usr/local/sbin/macbook-brightness-cap.sh
rm -f /etc/macbook8.1-display/brightness-cap.conf
rmdir /etc/macbook8.1-display 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
systemctl daemon-reload

echo "==> Removing panel-clear"
rm -f /usr/local/bin/panel-clear

rm -f "$STATE_FILE"
rmdir /var/lib/macbook8.1-display 2>/dev/null || true

echo
echo "Display mitigations reverted."
if [ -n "${BACKUP_ROOT:-}" ]; then
  echo "Backup left at: $BACKUP_ROOT"
fi
echo "Note: current backlight level is left as-is; raise it in Settings if desired."
