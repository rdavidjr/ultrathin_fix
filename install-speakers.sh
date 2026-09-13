#!/bin/bash
# Install reversible MacBook8,1 built-in speaker fix (CS4208 TDM).
# Wraps https://github.com/thomas-shirley/macbook8.1-speaker-driver at a pinned commit.
# Independent of SPI (install.sh) and display (install-display.sh).
# Run: sudo bash install-speakers.sh
set -eu

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/var/backups/macbook8.1-speakers-${STAMP}"
STATE_FILE="/var/lib/macbook8.1-speakers/install-state"
SRC_DIR="/usr/src/macbook8.1-speaker-driver"
UPSTREAM_URL="https://github.com/thomas-shirley/macbook8.1-speaker-driver.git"
# Pin for reproducibility (update intentionally when bumping).
UPSTREAM_SHA="fe54ad1aa7d8448fc49c0b5c8b353c50e2b1b8a1"

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
  # Prefer the graphical seat owner when invoked via pkexec.
  REAL_USER="$(logname 2>/dev/null || true)"
  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER="$(awk -F: '$3>=1000 && $1!="nobody" {print $1; exit}' /etc/passwd)"
  fi
  REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
fi

mkdir -p "$BACKUP_ROOT" /var/lib/macbook8.1-speakers

echo "==> Installing build dependencies (dkms wget gcc make)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq dkms wget gcc make "linux-headers-$(uname -r)" >/dev/null

echo "==> Backing up any existing speaker-fix files to $BACKUP_ROOT"
mkdir -p "$BACKUP_ROOT/modprobe.d" "$BACKUP_ROOT/pipewire" "$BACKUP_ROOT/wireplumber"
for f in /etc/modprobe.d/mb81-*.conf; do
  [ -e "$f" ] && cp -a "$f" "$BACKUP_ROOT/modprobe.d/" || true
done
PW_DIR="$REAL_HOME/.config/pipewire/pipewire.conf.d"
WP_DIR="$REAL_HOME/.config/wireplumber/wireplumber.conf.d"
for f in "$PW_DIR"/51-macbook81-speaker.conf \
         "$WP_DIR"/51-mb81-rawpcm-speaker.conf \
         "$WP_DIR"/51-mb81-disable-iec958.conf; do
  [ -e "$f" ] || continue
  case "$f" in
    */pipewire/*) cp -a "$f" "$BACKUP_ROOT/pipewire/" ;;
    *)            cp -a "$f" "$BACKUP_ROOT/wireplumber/" ;;
  esac
done

{
  echo "STAMP=$STAMP"
  echo "BACKUP_ROOT=$BACKUP_ROOT"
  echo "PRODUCT=$PRODUCT"
  echo "UPSTREAM_SHA=$UPSTREAM_SHA"
  echo "SRC_DIR=$SRC_DIR"
  echo "REAL_USER=$REAL_USER"
  echo "REAL_HOME=$REAL_HOME"
  echo "INSTALLED_AT=$(date -Is)"
  echo "KERNEL=$(uname -r)"
} > "$STATE_FILE"
cp -a "$STATE_FILE" "$BACKUP_ROOT/install-state"

echo "==> Fetching upstream speaker driver @ ${UPSTREAM_SHA}"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" fetch --depth 1 origin "$UPSTREAM_SHA"
  git -C "$SRC_DIR" checkout --force "$UPSTREAM_SHA"
else
  rm -rf "$SRC_DIR"
  git clone --filter=blob:none "$UPSTREAM_URL" "$SRC_DIR"
  git -C "$SRC_DIR" checkout --force "$UPSTREAM_SHA"
fi

echo "==> Running upstream installer (DKMS + PipeWire + resume recover)"
# Ensure PipeWire configs land in the real user's home, not root's.
export SUDO_USER="$REAL_USER"
set +e
bash "$SRC_DIR/install.sh"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "ERROR: upstream install failed (exit $rc). Rolling back…" >&2
  bash "$SRC_DIR/install.sh" -r || true
  echo "Rollback attempted. Speakers fix was NOT left half-installed." >&2
  exit "$rc"
fi

echo
echo "Speaker fix installed."
echo "  Upstream:  $UPSTREAM_URL @ $UPSTREAM_SHA"
echo "  Source:    $SRC_DIR"
echo "  Backup:    $BACKUP_ROOT"
echo "  User cfgs: $REAL_USER ($REAL_HOME)"
echo "  Revert:    sudo bash $PKG_DIR/revert-speakers.sh"
echo
echo "REBOOT REQUIRED, then verify:"
echo "  wpctl status | grep -i speaker"
echo "  dmesg | grep -i 'without reset'"
echo "  speaker-test -c2 -t sine -f 440 -D pipewire"
