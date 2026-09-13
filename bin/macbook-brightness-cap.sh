#!/bin/bash
# Soft-cap laptop backlight to reduce IPS image retention.
# Default: 70% of max. Override with BRIGHTNESS_CAP_PERCENT=50.
set -eu

PERCENT="${BRIGHTNESS_CAP_PERCENT:-70}"
CONF="/etc/macbook8.1-display/brightness-cap.conf"

if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
  PERCENT="${BRIGHTNESS_CAP_PERCENT:-$PERCENT}"
fi

case "$PERCENT" in
  ''|*[!0-9]*) PERCENT=70 ;;
esac
if [ "$PERCENT" -lt 1 ]; then PERCENT=1; fi
if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi

applied=0
for dev in /sys/class/backlight/*; do
  [ -d "$dev" ] || continue
  [ -w "$dev/brightness" ] || continue
  max="$(cat "$dev/max_brightness")"
  target=$(( max * PERCENT / 100 ))
  if [ "$target" -lt 1 ]; then target=1; fi
  cur="$(cat "$dev/brightness")"
  if [ "$cur" -gt "$target" ]; then
    echo "$target" > "$dev/brightness"
    logger -t macbook-brightness-cap -- "Capped $(basename "$dev") from $cur to $target (max=$max, ${PERCENT}%)" || true
    applied=1
  fi
done

if [ "$applied" -eq 0 ]; then
  logger -t macbook-brightness-cap -- "No backlight needed capping (percent=${PERCENT})" || true
fi
