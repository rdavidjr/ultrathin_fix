#!/bin/bash
# Revert macOS-like keyboard remapping installed by install-keyboard.sh.
# Does not touch SPI, speakers, or display fixes.
# Run: sudo bash revert-keyboard.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/var/lib/macbook8.1-keyboard/install-state"
KEYD_CONF_DST="/etc/keyd/macbook8.1.conf"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

BACKUP_ROOT=""
REAL_USER="${SUDO_USER:-}"
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

if [ -z "${REAL_USER:-}" ] || [ "$REAL_USER" = "root" ]; then
  REAL_USER="$(awk -F: '$3>=1000 && $1!="nobody" {print $1; exit}' /etc/passwd)"
fi
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
REAL_UID="$(id -u "$REAL_USER")"

run_as_user() {
  sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
    "$@"
}

echo "==> Removing keyd MacBook config"
rm -f "$KEYD_CONF_DST"

# If no other keyd configs remain, disable the service; otherwise just reload.
shopt -s nullglob
OTHER=(/etc/keyd/*.conf)
shopt -u nullglob
if [ "${#OTHER[@]}" -eq 0 ]; then
  systemctl disable --now keyd 2>/dev/null || true
else
  keyd reload 2>/dev/null || systemctl restart keyd 2>/dev/null || true
fi

echo "==> Restoring GNOME keybindings"
if [ -n "${BACKUP_ROOT:-}" ] && [ -d "/run/user/$REAL_UID" ]; then
  if [ -f "$BACKUP_ROOT/switch-applications.txt" ]; then
    run_as_user gsettings set org.gnome.desktop.wm.keybindings switch-applications \
      "$(cat "$BACKUP_ROOT/switch-applications.txt")"
  fi
  if [ -f "$BACKUP_ROOT/switch-applications-backward.txt" ]; then
    run_as_user gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward \
      "$(cat "$BACKUP_ROOT/switch-applications-backward.txt")"
  fi
elif [ -d "/run/user/$REAL_UID" ]; then
  # Fall back to GNOME defaults if no backup.
  run_as_user gsettings reset org.gnome.desktop.wm.keybindings switch-applications || true
  run_as_user gsettings reset org.gnome.desktop.wm.keybindings switch-applications-backward || true
else
  echo "NOTE: no session bus; restore gsettings after login if needed."
fi

rm -f "$STATE_FILE"
rmdir /var/lib/macbook8.1-keyboard 2>/dev/null || true

echo
echo "Keyboard remapping reverted."
if [ -n "${BACKUP_ROOT:-}" ]; then
  echo "Backup left at: $BACKUP_ROOT"
fi
echo "SPI / speakers / display installs were not modified."
echo "Optional: sudo apt remove keyd   # if you no longer need the package"
