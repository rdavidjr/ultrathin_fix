#!/bin/bash
# Revert MacBook8,1 SPI fixes installed by install.sh
# Run: sudo bash revert.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/var/lib/macbook8.1-spi-fix/install-state"
PARAM="mem_sleep_default=s2idle"
GRUB=/etc/default/grub

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

BACKUP_ROOT=""
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

echo "==> Disabling boot retry service"
systemctl disable --now applespi-boot-retry.service 2>/dev/null || true
rm -f /etc/systemd/system/applespi-boot-retry.service
rm -f /usr/local/sbin/applespi-boot-retry.sh
systemctl daemon-reload

echo "==> Removing systemd sleep drop-in"
rm -f /etc/systemd/sleep.conf.d/10-macbook8.1-s2idle.conf
rmdir /etc/systemd/sleep.conf.d 2>/dev/null || true

echo "==> Restoring GRUB"
if [ -n "${BACKUP_ROOT:-}" ] && [ -f "$BACKUP_ROOT/grub" ]; then
  cp -a "$BACKUP_ROOT/grub" "$GRUB"
  echo "Restored $GRUB from $BACKUP_ROOT/grub"
else
  # Best-effort cleanup if backup is missing.
  if grep -q "$PARAM" "$GRUB"; then
    sed -i "s/ ${PARAM}//g; s/${PARAM} //g; s/${PARAM}//g" "$GRUB"
    echo "Removed $PARAM from $GRUB (no backup available)."
  fi
fi

if command -v update-grub >/dev/null 2>&1; then
  update-grub
elif command -v grub-mkconfig >/dev/null 2>&1; then
  grub-mkconfig -o /boot/grub/grub.cfg
fi

rm -f "$STATE_FILE"
rmdir /var/lib/macbook8.1-spi-fix 2>/dev/null || true

echo
echo "Revert complete. Reboot to fully restore previous sleep defaults."
echo "Note: backup trees under /var/backups/macbook8.1-spi-fix-* were left in place."
