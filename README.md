# ultrathin_fix

Reversible Linux fixes for the **MacBook8,1** (2015 12" Retina / Ultrathin).

Tested on Ubuntu. The same hardware issues also show up on Fedora and other distros.

There are two independent installers:

| Script | What it targets |
|--------|-----------------|
| `install.sh` | SPI keyboard / trackpad after lid suspend |
| `install-display.sh` | IPS image retention (ghost letters on screen) |

---

## SPI keyboard / trackpad

### Problem

Closing the lid suspends into **deep S3** by default. On this MacBook the Intel GSPI controller (`00:15.4`) loses **IRQ 21** across that path, so `applespi` transfers time out and the built-in keyboard + trackpad stay dead until a hard reboot.

Boot can also race and leave SPI init half-broken (roughly 1 of 2 boots), often with CRC mismatch messages in the kernel log.

### What it installs

| Change | Purpose |
|--------|---------|
| Kernel cmdline `mem_sleep_default=s2idle` | Prefer suspend-to-idle so the SPI controller stays powered |
| systemd drop-in `MemorySleepMode=s2idle` | Same preference via systemd |
| `applespi-boot-retry.service` | If the Apple SPI keyboard is missing after boot, reload **only** the `applespi` module |
| GRUB menu timeout 3s | Recoverable boot menu if a kernel parameter misbehaves |

Backups: `/var/backups/macbook8.1-spi-fix-<timestamp>/`.

### Install

```bash
git clone https://github.com/rdavidjr/ultrathin_fix.git
cd ultrathin_fix
sudo bash install.sh
sudo reboot
```

After reboot:

```bash
cat /sys/power/mem_sleep
# expect: [s2idle] deep
```

Close the lid, wait a few seconds, open it, and confirm keyboard + trackpad still work.

Current session only (no reboot):

```bash
echo s2idle | sudo tee /sys/power/mem_sleep
```

### Revert

```bash
sudo bash revert.sh
sudo reboot
```

### Safety notes

- Do **not** add sleep hooks that unbind/rebind PCI `0000:00:15.4`. That can reproduce the IRQ timeout storm and force a hard power-off.
- The boot retry helper only reloads `applespi`, never the GSPI PCI controller.
- Install refuses to run unless DMI product name is `MacBook8,1` (override with `FORCE_INSTALL=1` if you know what you are doing).

---

## Display remanence (ghost letters)

### Diagnosis

If dark/black areas look mostly fine but you still see faint leftover letters or UI chrome:

1. Take a **screenshot** of the affected area.
2. If the ghosts are **not** in the screenshot, the framebuffer is correct. This is **LCD IPS image retention** (panel liquid-crystal lag), common on aging MacBook Retina panels — not a compositor bug.

Software cannot fully cure a worn panel. Mitigations reduce how strongly it shows and can temporarily clear residual charge.

**Do not** expect `i915.enable_psr=0` or `i915.enable_fbc=0` to fix this when screenshots are clean; those only affect the scanout path, not the panel itself, and they cost battery for no gain here.

### What helps

- Keep brightness lower (high backlight makes retention worse).
- Avoid leaving bright static UI on screen for long stretches before switching to a dark background.
- Run an occasional full-screen white clear to discharge residual image.

### What `install-display.sh` installs

| Change | Purpose |
|--------|---------|
| Soft brightness cap (default **70%**) | udev + oneshot service caps backlight (re-applies after login so GNOME cannot keep 100%) |
| `panel-clear` | Manual fullscreen white (then short black) to clear retention temporarily |

Backups: `/var/backups/macbook8.1-display-<timestamp>/`. Does **not** change GRUB or the SPI fix.

### Install

```bash
cd ultrathin_fix
sudo bash install-display.sh
```

Adjust the cap:

```bash
sudoedit /etc/macbook8.1-display/brightness-cap.conf
# BRIGHTNESS_CAP_PERCENT=50
sudo /usr/local/sbin/macbook-brightness-cap.sh
```

Clear the panel when ghosts build up (user session, no sudo):

```bash
panel-clear                 # ~5 min white, then ~30 s black
panel-clear --minutes 10
# Esc or q quits early
```

Needs `python3-gi` and GTK 3 (`gir1.2-gtk-3.0`), which Ubuntu desktop already has.

### Revert

```bash
sudo bash revert-display.sh
```

---

## Layout

```
install.sh / revert.sh                 # SPI / s2idle
install-display.sh / revert-display.sh # remanence mitigations
bin/applespi-boot-retry.sh
bin/macbook-brightness-cap.sh
bin/panel-clear.py
systemd/applespi-boot-retry.service
systemd/10-macbook8.1-s2idle.conf
systemd/macbook-brightness-cap.service
systemd/90-macbook-brightness-cap.rules
systemd/brightness-cap.conf
```
