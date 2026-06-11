# Final Arch Mini Sanders — Test & Standalone Deployment Plan

## Context

Goal: turn the Moto G5s Plus (`sanders`, MSM8953) into a **standalone** Arch
Mini Linux device — boots on its own (no host), brings up Wi-Fi (CASA_5G),
SSH, nginx, power-button screen toggle, emergency UI, cloudflared — with the
Arch rootfs persistent on eMMC.

Standing constraints (from the project prompt — **must hold**):
- **Do not flash automatically.** Show every command + a rollback first.
- **Show the diff before applying** any change.
- **Don't break Wi-Fi.**

Hard facts established during exploration:
- Host = WSL2 with **~1.8 GB RAM** → a plain `fastboot flash userdata` of the
  4 GB image OOMs. Rootfs goes on via **In-Linux `dd`** (user-chosen).
- **`fastboot flash boot` is rejected on sanders** (AVB/Motorola signing — see
  `docs/TROUBLESHOOTING.md:34`, `docs/LK2ND_SETUP.md:60`). So the literal
  "flash boot-sanders.img to boot" is impossible. Standalone boot is achieved
  instead via **lk2nd flashed to the dedicated `lk2nd` partition (512 KiB)** +
  **extlinux auto-boot** from the rootfs (user-chosen).
- **30s reset root cause (CONFIRMED):** `CONFIG_QCOM_WDT=m` (not in initramfs)
  and **no watchdog node** in `msm8953.dtsi`. Linux never exposes
  `/dev/watchdog`, so nothing pets the bootloader-armed watchdog and it bites
  at ~30s on every Linux boot. Must be fixed before anything else works.

Decisions locked in by the user:
- Boot strategy: **lk2nd partition + extlinux auto-boot**.
- Rootfs to eMMC: **In-Linux download + `dd`**.

---

## Phase 0 — Fix the watchdog (prerequisite), then rebuild

Without this, neither the In-Linux `dd` (Phase 1) nor the booted Arch rootfs
survives past ~30s.

1. **Add a watchdog DT node** to the sanders msm8953 device tree (the apps/KPSS
   watchdog). Show the diff before applying. Representative node (verify base
   address against the SoC's APCS/TCSR region in the existing dtsi):
   ```dts
   watchdog@b017000 {
       compatible = "qcom,apss-wdt-msm8953", "qcom,kpss-wdt";
       reg = <0xb017000 0x1000>;
       clocks = <&sleep_clk>;
       timeout-sec = <30>;
   };
   ```
   File: the sanders DTS/DTSI under `dts/` that 02-build-kernel.sh copies in.
2. **Make the driver builtin** so it is present in the initramfs too:
   in `kernel/sanders*.config.fragment`, set `CONFIG_QCOM_WDT=y`.
3. Rebuild: `02-build-kernel.sh` → `04-build-initramfs.sh` → `06-build-boot.sh`.
   Produces fresh `build/out/{boot-sanders.img,initramfs.cpio.gz,lk2nd.img}`.
4. Confirm `initramfs/init:152-156` already pets `/dev/watchdog` (it does);
   the rootfs already ships `RuntimeWatchdogSec` + `sanders-wdt-pet.service`.
5. **Smoke test (no rootfs needed):** `fastboot boot lk2nd.img` then
   `fastboot boot boot-sanders.img`; the device drops to initramfs fallback.
   **Success = device stays up > 2 min** (watchdog now petted). If it still
   resets, the DT node/address is wrong — fix before proceeding.

## Phase 1 — Put the rootfs on eMMC (In-Linux dd)

Prereq: rootfs image is built with WiFi creds (CASA_5G), watchdog services,
`/boot/{Image.gz,DTB,initramfs.cpio.gz}` and `/extlinux/extlinux.conf` already
baked in (handled by `05-build-rootfs.sh` + mini overlay). Re-run
`FLAVOR=mini ./scripts/05-build-rootfs.sh` if the kernel changed in Phase 0, so
`/boot` carries the new kernel/initramfs.

1. `fastboot boot build/out/lk2nd.img` → wait for lk2nd → `fastboot boot
   build/out/boot-sanders.img`. Device enters **initramfs fallback** (no valid
   rootfs yet): watchdog petted, `usb0` = `10.42.0.2/24`, shell on ttyGS0.
2. Host: `usbipd attach` the CDC ECM (1d6b:0104) into WSL; bring up host side
   `10.42.0.1/24`; serve the image: `cd build && python3 -m http.server 8080`.
3. On device (via ttyACM0 shell), identify the target partition by **partlabel**
   (robust, no guessing `p54`):
   ```sh
   ls -l /dev/disk/by-partlabel/userdata
   ```
4. Stream-download straight onto it (no device-side staging, RAM-safe both ends):
   ```sh
   wget -O - http://10.42.0.1:8080/rootfs-arch-mini.img \
     | dd of=/dev/disk/by-partlabel/userdata bs=4M
   sync
   ```
   The image is `mkfs.ext4 -L rootfs`, so after `dd` the partition is labeled
   `rootfs` + ext4 → `initramfs/init` auto-detects it next boot;
   `sanders-rootfs-expand.service` then `resize2fs` it to fill the partition.
5. Reboot back to fastboot for Phase 2.

## Phase 2 — Iterative feature testing (via `fastboot boot`, non-destructive)

Each cycle: `fastboot boot lk2nd.img` → `fastboot boot boot-sanders.img` →
initramfs finds `rootfs` → `switch_root` → Arch boots. Fix failures in the mini
overlay / scripts (commit-worthy, reproducible) or hot-patch on device for speed,
then re-bake. Verify in this order:

| # | Feature | Check | Current state |
|---|---------|-------|---------------|
| 0 | **Stability** | stays up > 2 min after switch_root | gated on Phase 0 watchdog fix |
| 1 | **Console/login** | getty on ttyGS0 / framebuffer | enabled |
| 2 | **Wi-Fi CASA_5G** | `wifi-setup --status`; wlan0 has DHCP IP; ping | creds baked; verify assoc |
| 3 | **SSH** | `ssh root@<wifi-ip>` (root/root) | sshd enabled |
| 4 | **nginx** | `curl http://<ip>/` → index.html | enabled, port 80 |
| 5 | **Power-btn toggle** | press power → backlight on/off | `screen-toggle.service` enabled |
| 6 | **cloudflared** | tunnel reachable | **PARTIAL — needs work (below)** |
| 7 | **Emergency UI** | weston on tty2 | unit exists, not enabled (below) |

**cloudflared (gap):** binary only, no service, no creds. Two paths — confirm
with user which:
- Quick tunnel (no account): `cloudflared tunnel --url http://localhost:80`
  → prints a `*.trycloudflare.com` URL. Wrap in a `cloudflared.service`.
- Named tunnel: needs the user's Cloudflare token/credentials JSON +
  `/etc/cloudflared/config.yml`. (Requires user input — not available yet.)

**Emergency UI:** `pacman -S weston` (needs working network from step 2), then
`systemctl enable --now emergency-ui.service` (runs Weston on tty2,
`WLR_RENDERER=pixman`). Bake the enable into the mini overlay once verified.

## Phase 3 — Final standalone deployment (lk2nd partition + extlinux)

Only after all of Phase 2 passes. **Nothing here runs automatically** — present
each command, get explicit go-ahead, keep the rollback ready.

1. **Backup first (rollback artifact).** From the **lk2nd** fastboot
   (lk2nd supports `fetch`):
   ```sh
   fastboot fetch lk2nd build/out/lk2nd-orig-backup.img
   ```
   (Fallback: from inside Linux, `dd if=/dev/disk/by-partlabel/lk2nd
   of=/root/lk2nd-orig-backup.img` and copy it off-device.)
2. **Confirm the rootfs on eMMC already has** `/extlinux/extlinux.conf` +
   `/boot/{Image.gz,msm8953-motorola-sanders.dtb,initramfs.cpio.gz}` (it does
   from Phase 1). This is what lk2nd will auto-load.
3. **Flash lk2nd permanently** (the one flash that *is* allowed on sanders):
   ```sh
   fastboot flash lk2nd build/out/lk2nd.img
   ```
   Show this command and wait for user confirmation — do not auto-run.
4. **Reboot with NO host attached.** Expected autonomous chain:
   `Motorola aboot → lk2nd (from lk2nd partition) → scan /extlinux/extlinux.conf
   → load /boot kernel+DTB+initramfs → switch_root → Arch → Wi-Fi (CASA_5G)`.
5. **Rollback if broken:** `fastboot flash lk2nd build/out/lk2nd-orig-backup.img`.
   The `boot` partition is never touched, so stock Motorola fastboot remains
   reachable via the hardware key combo regardless — the device cannot be
   bricked by this step.

---

## Critical files

- `dts/` sanders msm8953 dtsi — **add watchdog node** (Phase 0).
- `kernel/sanders*.config.fragment` — `CONFIG_QCOM_WDT=y` (Phase 0).
- `scripts/06-build-boot.sh`, `02/04` — rebuild kernel/initramfs/boot.
- `scripts/05-build-rootfs.sh` — rootfs build; `mkfs.ext4 -L rootfs` (l.37),
  `sanders-rootfs-expand.service` (l.232), sshd/nginx/networkd enable.
- `initramfs/init` — fallback usb-net + watchdog pet + rootfs auto-detect.
- `rootfs-overlay/mini/` — extlinux.conf, nginx, screen-toggle, emergency-ui,
  wpa_supplicant; add cloudflared.service + enable emergency-ui after verify.
- `build/out/{lk2nd.img,boot-sanders.img}`, `build/rootfs-arch-mini.img`.

## Verification (end-to-end)

1. Phase 0 smoke test: initramfs fallback survives > 2 min.
2. Phase 1: `dd` completes, `sync`, reboot, `blkid -L rootfs` resolves.
3. Phase 2: each table row passes (stability, wifi, ssh, nginx, power, cf, UI).
4. Phase 3: cold boot **with host unplugged** reaches Arch login and associates
   to CASA_5G unattended; rollback re-flash verified to restore prior state.
