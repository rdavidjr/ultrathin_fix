# ultrathin_fix

Reversible Linux fixes for the **MacBook8,1** (2015 12" Retina / Ultrathin).

Tested on Ubuntu. The same hardware issues also show up on Fedora and other distros.

Independent installers:

| Script | What it targets |
|--------|-----------------|
| `install.sh` | SPI keyboard / trackpad after lid suspend |
| `install-speakers.sh` | Built-in speakers (CS4208 TDM) |
| `install-keyboard.sh` | macOS-like Command / Option / Control |
| `install-display.sh` | IPS image retention (optional; see warning) |

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

## Speakers (built-in)

### Problem

The Apple boot chime works, and Linux detects the Cirrus **CS4208**, but the built-in speakers stay silent. This is **not** a mute/mixer issue.

EFI brings up a working **4-channel TDM** path into the class-D amp. Stock `snd-hda-intel` / `snd-hda-codec-cs420x` reset that fragile clock state on bring-up and break speaker output.

### What `install-speakers.sh` installs

A thin wrapper around [thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver) at a pinned commit (`fe54ad1aa7d8448fc49c0b5c8b353c50e2b1b8a1`):

- DKMS-patched `snd-hda-intel`, `snd-hda-codec-cs420x`, `snd-hda-codec-generic`
- `/etc/modprobe.d/mb81-singlecmd.conf`
- PipeWire / WirePlumber speaker routing for the installing user
- Resume recover + jack-switch helpers from upstream

Backups: `/var/backups/macbook8.1-speakers-<timestamp>/`. Does **not** change the SPI/s2idle fix.

### Install

```bash
cd ultrathin_fix
sudo bash install-speakers.sh
sudo reboot
```

Needs network on first install (clones upstream + may fetch kernel source for the DKMS build).

### Verify (after reboot)

```bash
wpctl status | grep -i speaker
dmesg | grep -i 'without reset'
speaker-test -c2 -t sine -f 440 -D pipewire
```

Upstream headphone jack switching is still imperfect. After suspend, if audio is silent, upstream provides `sudo mb81-resume-recover` (complements s2idle; does not replace it).

### Revert

```bash
sudo bash revert-speakers.sh
sudo reboot
```

---

## Keyboard (macOS modifiers)

### Problem

The MacBook’s physical **Command / Option / Control** row does not match Linux defaults. Linux apps expect **Ctrl** for copy/paste and most shortcuts, while muscle memory from macOS uses **⌘ Command**.

`hid_apple` modprobe options do **not** apply here: the built-in keyboard is driven by **applespi**, not USB `hid_apple`.

### What `install-keyboard.sh` installs

| Change | Purpose |
|--------|---------|
| [keyd](https://github.com/rvaiya/keyd) + `/etc/keyd/macbook8.1.conf` | Swap Command↔Control system-wide (Wayland + TTY) |
| GNOME `switch-applications` → Ctrl+Tab | Physical Command+Tab switches apps like macOS |

| Physical key | After install |
|--------------|---------------|
| Command (⌘) | **Ctrl** (⌘C / ⌘V work in GUI apps) |
| Control (⌃) | **Super** |
| Option (⌥) | **Alt** (unchanged — keeps `us-mac` / `fr` special characters) |

Backups: `/var/backups/macbook8.1-keyboard-<timestamp>/`. Does not change SPI, speakers, or display fixes.

### Install

```bash
cd ultrathin_fix
sudo bash install-keyboard.sh
```

No reboot required (`keyd reload`).

### Notes

- **GUI apps:** physical Command+C/V match macOS.
- **Terminals:** physical Command still sends Ctrl, so Command+C is **interrupt** (SIGINT), not copy. Use **Ctrl+Shift+C/V** for copy/paste in the terminal (common Linux/Mac-on-Linux compromise).
- If you use `caps:ctrl_modifier`, Caps Lock becomes Ctrl and then Super after the swap.

### Revert

```bash
sudo bash revert-keyboard.sh
```

---

## Display remanence (ghost letters) — optional

### Warning

An earlier brightness soft-cap that **re-applied in a loop** caused screen blinking on this machine. Prefer **manual** brightness reduction and occasional `panel-clear` only if you still want these helpers. Do not reinstall the looping brightness service variant.

### Diagnosis

If dark/black areas look mostly fine but you still see faint leftover letters or UI chrome:

1. Take a **screenshot** of the affected area.
2. If the ghosts are **not** in the screenshot, the framebuffer is correct. This is **LCD IPS image retention** (panel liquid-crystal lag), common on aging MacBook Retina panels — not a compositor bug.

Software cannot fully cure a worn panel.

**Do not** expect `i915.enable_psr=0` or `i915.enable_fbc=0` to fix this when screenshots are clean.

### Install / revert (optional)

```bash
sudo bash install-display.sh
# …
sudo bash revert-display.sh
```

`panel-clear` (after install): fullscreen white then black to temporarily clear retention.

---

## Layout

```
install.sh / revert.sh                     # SPI / s2idle
install-speakers.sh / revert-speakers.sh   # CS4208 speakers (wraps upstream DKMS)
install-keyboard.sh / revert-keyboard.sh   # macOS-like modifiers (keyd)
install-display.sh / revert-display.sh     # remanence helpers (optional)
keyd/macbook8.1.conf
bin/applespi-boot-retry.sh
bin/macbook-brightness-cap.sh
bin/panel-clear.py
systemd/…
```
