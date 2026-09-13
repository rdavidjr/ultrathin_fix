#!/bin/bash
# Retry Apple SPI keyboard/trackpad init if probe failed at boot.
# Safe: only reloads the applespi client module, never rebinds the GSPI PCI
# controller (that can wedge IRQ 21 and force a hard reboot).
set -eu

MARKER_NAME='Apple SPI Keyboard'
LOG_TAG='applespi-boot-retry'
MAX_ATTEMPTS=3
SLEEP_BETWEEN=2

has_keyboard() {
  grep -Fq "Name=\"${MARKER_NAME}\"" /proc/bus/input/devices 2>/dev/null
}

log() {
  logger -t "$LOG_TAG" -- "$*" || true
  echo "$*"
}

if has_keyboard; then
  log "Apple SPI Keyboard already present — nothing to do."
  exit 0
fi

log "Apple SPI Keyboard missing after boot — attempting applespi reload."

# Give the SPI master a moment if we raced early boot.
sleep 1

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  if has_keyboard; then
    log "Keyboard appeared before attempt ${attempt}."
    exit 0
  fi

  log "Reload attempt ${attempt}/${MAX_ATTEMPTS}…"
  # Ignore unload failure (module may not be loaded).
  modprobe -r applespi 2>/dev/null || true
  sleep 0.5
  if modprobe applespi; then
    sleep "$SLEEP_BETWEEN"
    if has_keyboard; then
      log "SUCCESS: Apple SPI Keyboard registered after attempt ${attempt}."
      exit 0
    fi
  else
    log "modprobe applespi failed on attempt ${attempt}."
  fi
  attempt=$((attempt + 1))
done

log "FAILED: Apple SPI Keyboard still missing after ${MAX_ATTEMPTS} attempts."
exit 1
