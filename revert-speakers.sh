#!/bin/bash
# Revert MacBook8,1 speaker fix installed by install-speakers.sh.
# Does not touch SPI/s2idle or display mitigations.
# Run: sudo bash revert-speakers.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/var/lib/macbook8.1-speakers/install-state"
SRC_DIR="/usr/src/macbook8.1-speaker-driver"
UPSTREAM_URL="https://github.com/thomas-shirley/macbook8.1-speaker-driver.git"
UPSTREAM_SHA="fe54ad1aa7d8448fc49c0b5c8b353c50e2b1b8a1"

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

BACKUP_ROOT=""
REAL_USER="${SUDO_USER:-}"
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

ensure_src() {
  if [ -x "$SRC_DIR/install.sh" ]; then
    return 0
  fi
  echo "==> Re-cloning upstream to run uninstall @ ${UPSTREAM_SHA}"
  rm -rf "$SRC_DIR"
  git clone --filter=blob:none "$UPSTREAM_URL" "$SRC_DIR"
  git -C "$SRC_DIR" checkout --force "$UPSTREAM_SHA"
}

echo "==> Removing speaker DKMS stack via upstream uninstall"
ensure_src
if [ -n "${REAL_USER:-}" ] && [ "$REAL_USER" != "root" ]; then
  export SUDO_USER="$REAL_USER"
fi
bash "$SRC_DIR/install.sh" -r

rm -f "$STATE_FILE"
rmdir /var/lib/macbook8.1-speakers 2>/dev/null || true

echo
echo "Speaker fix reverted. Reboot to finish falling back to stock HDA drivers."
if [ -n "${BACKUP_ROOT:-}" ]; then
  echo "Backup left at: $BACKUP_ROOT"
fi
echo "SPI/s2idle and display installs (if any) were not modified."
echo "Optional: remove cloned sources with:  sudo rm -rf $SRC_DIR"
