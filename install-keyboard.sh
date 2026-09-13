#!/bin/bash
# Install reversible macOS-like modifier remapping for MacBook8,1.
# Uses keyd (Command↔Control). Independent of SPI / speakers / display.
# Run: sudo bash install-keyboard.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/var/backups/macbook8.1-keyboard-${STAMP}"
STATE_FILE="/var/lib/macbook8.1-keyboard/install-state"
KEYD_CONF_DST="/etc/keyd/macbook8.1.conf"
KEYD_CONF_SRC="$PKG_DIR/keyd/macbook8.1.conf"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$PRODUCT" != "MacBook8,1" ] && [ "${FORCE_INSTALL:-}" != "1" ]; then
  echo "This machine reports product_name='$PRODUCT' (expected MacBook8,1)."
  echo "Refusing to install. Set FORCE_INSTALL=1 to override."
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
if [ -z "$REAL_HOME" ] || [ "$REAL_USER" = "root" ]; then
  REAL_USER="$(logname 2>/dev/null || true)"
  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER="$(awk -F: '$3>=1000 && $1!="nobody" {print $1; exit}' /etc/passwd)"
  fi
  REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
fi
REAL_UID="$(id -u "$REAL_USER")"

run_as_user() {
  sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
    "$@"
}

mkdir -p "$BACKUP_ROOT/keyd" /var/lib/macbook8.1-keyboard /etc/keyd

echo "==> Backing up existing keyd configs and GNOME keybindings to $BACKUP_ROOT"
if [ -d /etc/keyd ]; then
  cp -a /etc/keyd/. "$BACKUP_ROOT/keyd/" 2>/dev/null || true
fi
if [ -d "/run/user/$REAL_UID" ]; then
  run_as_user gsettings get org.gnome.desktop.wm.keybindings switch-applications \
    > "$BACKUP_ROOT/switch-applications.txt" 2>/dev/null || true
  run_as_user gsettings get org.gnome.desktop.wm.keybindings switch-applications-backward \
    > "$BACKUP_ROOT/switch-applications-backward.txt" 2>/dev/null || true
  run_as_user dconf dump /org/gnome/desktop/wm/keybindings/ \
    > "$BACKUP_ROOT/wm-keybindings.dconf" 2>/dev/null || true
else
  echo "NOTE: no active session bus for $REAL_USER; GNOME bindings will be set after next login if needed."
fi

{
  echo "STAMP=$STAMP"
  echo "BACKUP_ROOT=$BACKUP_ROOT"
  echo "PRODUCT=$PRODUCT"
  echo "REAL_USER=$REAL_USER"
  echo "REAL_HOME=$REAL_HOME"
  echo "INSTALLED_AT=$(date -Is)"
} > "$STATE_FILE"
cp -a "$STATE_FILE" "$BACKUP_ROOT/install-state"

echo "==> Installing keyd"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq keyd >/dev/null

# Prefer binding only the Apple SPI keyboard when keyd can see it.
CONF_TMP="$(mktemp)"
cp "$KEYD_CONF_SRC" "$CONF_TMP"
if command -v keyd >/dev/null 2>&1; then
  # keyd may need to be started once to list devices; try best-effort id discovery.
  systemctl start keyd 2>/dev/null || true
  sleep 0.5
  APPLE_ID="$(keyd -a 2>/dev/null | awk -F'[()]' '
    tolower($0) ~ /apple/ && tolower($0) ~ /keyboard/ {
      if (match($0, /[0-9a-f]+:[0-9a-f]+/)) { print substr($0, RSTART, RLENGTH); exit }
    }' || true)"
  if [ -n "${APPLE_ID:-}" ]; then
    echo "==> Scoping keyd remap to Apple keyboard id $APPLE_ID"
    awk -v id="$APPLE_ID" '
      BEGIN { done=0 }
      /^\[ids\]/ { print; print id; done=1; next }
      done && /^\[/ { done=0 }
      done && NF { next }
      { print }
    ' "$KEYD_CONF_SRC" > "$CONF_TMP"
  else
    echo "==> Could not resolve Apple keyboard id; using [ids] * (all keyboards)"
  fi
fi

install -m 0644 "$CONF_TMP" "$KEYD_CONF_DST"
rm -f "$CONF_TMP"

echo "==> Enabling keyd"
systemctl enable --now keyd
keyd reload 2>/dev/null || systemctl restart keyd

echo "==> Setting GNOME app switcher to Ctrl+Tab (physical Command+Tab)"
if [ -d "/run/user/$REAL_UID" ]; then
  run_as_user gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Control>Tab']"
  run_as_user gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward "['<Shift><Control>Tab']"
else
  echo "Skipped gsettings (no session). After login run:"
  echo "  gsettings set org.gnome.desktop.wm.keybindings switch-applications \"['<Control>Tab']\""
  echo "  gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward \"['<Shift><Control>Tab']\""
fi

echo
echo "Keyboard remapping installed."
echo "  Config:  $KEYD_CONF_DST"
echo "  Backup:  $BACKUP_ROOT"
echo "  Revert:  sudo bash $PKG_DIR/revert-keyboard.sh"
echo
echo "Verify in a GUI editor: physical Command+C / Command+V (copy/paste)."
echo "App switch: physical Command+Tab."
echo "Note: in terminals, Command still sends Ctrl (Ctrl+C = interrupt)."
echo "      Use Ctrl+Shift+C/V for copy/paste in the terminal."
