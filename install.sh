#!/bin/bash
# Install reversible MacBook8,1 SPI keyboard/trackpad fixes.
# Run: sudo bash install.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/var/backups/macbook8.1-spi-fix-${STAMP}"
MARKER_BEGIN="# >>> macbook8.1-spi-fix (begin) — do not edit by hand"
MARKER_END="# <<< macbook8.1-spi-fix (end)"
PARAM="mem_sleep_default=s2idle"
GRUB=/etc/default/grub
STATE_FILE="/var/lib/macbook8.1-spi-fix/install-state"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

# Only run on MacBook8,1 unless forced.
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$PRODUCT" != "MacBook8,1" ] && [ "${FORCE_INSTALL:-}" != "1" ]; then
  echo "This machine reports product_name='$PRODUCT' (expected MacBook8,1)."
  echo "Refusing to install. Set FORCE_INSTALL=1 to override."
  exit 1
fi

mkdir -p "$BACKUP_ROOT" /var/lib/macbook8.1-spi-fix /etc/systemd/sleep.conf.d /usr/local/sbin

echo "==> Backing up originals to $BACKUP_ROOT"
cp -a "$GRUB" "$BACKUP_ROOT/grub"
[ -f /boot/grub/grub.cfg ] && cp -a /boot/grub/grub.cfg "$BACKUP_ROOT/grub.cfg" || true
{
  echo "STAMP=$STAMP"
  echo "BACKUP_ROOT=$BACKUP_ROOT"
  echo "PRODUCT=$PRODUCT"
  echo "INSTALLED_AT=$(date -Is)"
} > "$STATE_FILE"
cp -a "$STATE_FILE" "$BACKUP_ROOT/install-state"

# Remove known-harmful rebind sleep hook if present.
OLD_HOOK=/usr/lib/systemd/system-sleep/applespi-resume-fix.sh
if [ -e "$OLD_HOOK" ]; then
  cp -a "$OLD_HOOK" "$BACKUP_ROOT/"
  rm -f "$OLD_HOOK"
  echo "Removed obsolete (harmful) rebind hook: $OLD_HOOK"
fi

echo "==> Installing boot retry helper"
install -m 0755 "$PKG_DIR/bin/applespi-boot-retry.sh" /usr/local/sbin/applespi-boot-retry.sh
install -m 0644 "$PKG_DIR/systemd/applespi-boot-retry.service" /etc/systemd/system/applespi-boot-retry.service
systemctl daemon-reload
systemctl enable applespi-boot-retry.service

echo "==> Installing systemd sleep drop-in (s2idle)"
install -m 0644 "$PKG_DIR/systemd/10-macbook8.1-s2idle.conf" \
  /etc/systemd/sleep.conf.d/10-macbook8.1-s2idle.conf

echo "==> Updating GRUB cmdline (mem_sleep_default=s2idle)"
# Ensure a short recoverable menu (does not change default boot entry).
if grep -q '^GRUB_TIMEOUT=0' "$GRUB"; then
  sed -i 's/^GRUB_TIMEOUT=0/GRUB_TIMEOUT=3/' "$GRUB"
  echo "Set GRUB_TIMEOUT=3 so you can recover from the menu if needed."
fi
if grep -q '^GRUB_TIMEOUT_STYLE=hidden' "$GRUB"; then
  sed -i 's/^GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' "$GRUB"
  echo "Set GRUB_TIMEOUT_STYLE=menu (hold Shift at boot if menu is skipped)."
fi

if grep -q "$PARAM" "$GRUB"; then
  echo "$PARAM already present in $GRUB"
else
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB"; then
    sed -i "s/^\\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\\)\"/\\1 $PARAM\"/" "$GRUB"
  else
    printf '%s\nGRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$MARKER_BEGIN" "$PARAM" >> "$GRUB"
    printf '%s\n' "$MARKER_END" >> "$GRUB"
  fi
fi

# Record post-edit grub for the revert helper.
cp -a "$GRUB" "$BACKUP_ROOT/grub.after-edit"

if command -v update-grub >/dev/null 2>&1; then
  update-grub
elif command -v grub-mkconfig >/dev/null 2>&1; then
  grub-mkconfig -o /boot/grub/grub.cfg
else
  echo "WARNING: could not find update-grub / grub-mkconfig" >&2
fi

# Apply s2idle for the *current* boot without reboot (lid test can work now).
if [ -w /sys/power/mem_sleep ]; then
  echo s2idle > /sys/power/mem_sleep
  echo "Switched live mem_sleep to s2idle for this session."
fi

echo
echo "Install complete."
echo "  Backup:  $BACKUP_ROOT"
echo "  Revert:  sudo bash $PKG_DIR/revert.sh"
echo "  Verify:  cat /sys/power/mem_sleep   # expect: [s2idle] deep"
echo "  Reboot recommended, then close/open the lid and test keyboard+trackpad."
