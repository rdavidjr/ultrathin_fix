# ultrathin_fix

Reversible Linux fixes for the **MacBook8,1** (2015 12" Retina / Ultrathin) SPI keyboard and trackpad.

Tested on Ubuntu. The same hardware issues also show up on Fedora and other distros.

## Problem

Closing the lid suspends into **deep S3** by default. On this MacBook the Intel GSPI controller (`00:15.4`) loses **IRQ 21** across that path, so `applespi` transfers time out and the built-in keyboard + trackpad stay dead until a hard reboot.

Boot can also race and leave SPI init half-broken (roughly 1 of 2 boots), often with CRC mismatch messages in the kernel log.

## What this installs

| Change | Purpose |
|--------|---------|
| Kernel cmdline `mem_sleep_default=s2idle` | Prefer suspend-to-idle so the SPI controller stays powered |
| systemd drop-in `MemorySleepMode=s2idle` | Same preference via systemd |
| `applespi-boot-retry.service` | If the Apple SPI keyboard is missing after boot, reload **only** the `applespi` module |
| GRUB menu timeout 3s | Recoverable boot menu if a kernel parameter misbehaves |

Backups are written under `/var/backups/macbook8.1-spi-fix-<timestamp>/`. Nothing replaces your kernel, initramfs, or bootloader binary.

## Install

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

### Current session only (no reboot)

```bash
echo s2idle | sudo tee /sys/power/mem_sleep
```

## Revert

```bash
sudo bash revert.sh
sudo reboot
```

## Safety notes

- Do **not** add sleep hooks that unbind/rebind PCI `0000:00:15.4`. That can reproduce the IRQ timeout storm and force a hard power-off.
- The boot retry helper only reloads `applespi`, never the GSPI PCI controller.
- Install refuses to run unless DMI product name is `MacBook8,1` (override with `FORCE_INSTALL=1` if you know what you are doing).

## Layout

```
install.sh
revert.sh
bin/applespi-boot-retry.sh
systemd/applespi-boot-retry.service
systemd/10-macbook8.1-s2idle.conf
```
