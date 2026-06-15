# System Reference (current machine snapshot)

A point-in-time snapshot of the actual running system, captured so the machine
can be recreated from scratch. Where the step-by-step guide explains *how*, this
page records *exactly what* is installed and configured.

> **Privacy note:** machine-id, hardware serial/SKU, and the contents of
> personal automation (cloud-storage mounts, backup jobs, and personal helper
> services) are intentionally **not** published here. Recreate those privately.

## Hardware

| Component | Value |
| --- | --- |
| Model | HP ZBook Firefly 14 inch G9 Mobile Workstation |
| CPU | 12th Gen Intel Core i7-1270P (Alder Lake-P, 12 cores / 16 threads) |
| RAM | 32 GiB |
| GPU | Intel Iris Xe (integrated) |
| Storage | ~1 TB NVMe (`/dev/nvme0n1`) |
| Firmware | UEFI (HP `U70`), updated via `fwupd` |

## Disk layout

Full-disk encryption: a single LUKS2 container on `nvme0n1p3` holding an LVM
volume group `vg0`. `/boot` is the **unencrypted** EFI partition (GRUB loads the
kernel + initramfs directly from it; the initramfs then unlocks LUKS).

```
nvme0n1                       953.9G
├─nvme0n1p1  vfat     260M    /boot   (EFI System Partition, unencrypted)
├─nvme0n1p2           16M             (Microsoft reserved)
├─nvme0n1p3  LUKS2  952.7G            (encrypted container → vg0)
│ ├─vg0-root   ext4  100G    /
│ ├─vg0-swap   swap   32G    [SWAP]   (sized = RAM, for hibernation)
│ ├─vg0-data1  ext4  100G    /data1
│ ├─vg0-data2  ext4  100G    /data2
│ ├─vg0-data3  ext4  100G    /data3
│ ├─vg0-data4  ext4  100G    /data4
│ └─vg0-data5  ext4  420G    /data5   (lvcreate -l 100%FREE)
└─nvme0n1p4  ntfs    946M            (Windows recovery, left intact)
```

LUKS header: `aes-xts-plain64`, 512-bit key, PBKDF `pbkdf2` / `sha256`.
PBKDF is **pbkdf2 (not argon2id)** deliberately, so GRUB can open the container
— see [Installation → Bootloader](02-installation.md#configure-bootloader).

## Portage profile

```
default/linux/amd64/23.0/desktop/gnome/systemd
```

## /etc/portage/make.conf (verbatim)

```sh
COMMON_FLAGS="-march=alderlake -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

LC_MESSAGES=C.utf8

CPU_FLAGS_X86="aes avx avx2 avx_vnni bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 ssse3 vpclmulqdq"

USE="-branding -qt5 wayland -X vaapi cryptsetup lvm device-mapper cacert dist-kernel screencast gstreamer gles2 vulkan"

MAKEOPTS="-j16"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE BUSL-1.1 Microsoft-vscode all-rights-reserved google-chrome"
ACCEPT_KEYWORDS="~amd64"

LINGUAS=""

VIDEO_CARDS="intel"
LIBVA_DRIVER_NAME="iHD"

MICROCODE_SIGNATURES="-s 0x000906a3"

GRUB_PLATFORMS="efi-64"

PORTAGE_ELOG_SYSTEM="echo save"
PORTAGE_ELOG_CLASSES="warn error info log qa"

EMERGE_DEFAULT_OPTS="--ask --verbose --deep --with-bdeps=y --tree --jobs 4 --load-average 14.4"
FEATURES="buildpkg"
```

Regenerate `CPU_FLAGS_X86` with `cpuid2cpuflags`. `MICROCODE_SIGNATURES`
restricts `intel-microcode` to this CPU's signature (`0x000906a3` = Alder
Lake-P, family/model/stepping `06-9a-03`).

`ACCEPT_LICENSE` is the narrowed form: the free/redistributable license groups
plus the exact proprietary licenses the installed apps need — `BUSL-1.1`
(Terraform), `Microsoft-vscode`, `all-rights-reserved` (Slack, Zoom), and
`google-chrome`. This replaced a blanket `"*"`.

## Notable package.use

```
sys-kernel/installkernel grub dracut          # dist-kernel install via dracut + grub
net-wireless/wpa_supplicant tkip              # see Troubleshooting (some Wi-Fi APs)
net-libs/nodejs npm
media-video/obs-studio lua nvenc pulseaudio speex v4lc pipewire
# plus per-package X enables for a -X global build (cairo, gtk, mesa, nautilus, …)
```

`package.mask`: `>app-arch/zstd-1.5.5` — **review this; it looks stale** (see
[Best-practice notes](#best-practice-notes)).

## Repository sync

Default rsync sync (set by the stage3), verified via OpenPGP:

```
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
```

Plus a `local` overlay at `/var/db/repos/local` (currently empty). Syncing over
git is a valid alternative — see [After Installation](03-after-installation.md#optional-sync-portage-over-git).

## Kernel

Distribution kernel (`sys-kernel/gentoo-kernel`), built locally and installed by
`installkernel` with **dracut** generating the initramfs. Customised via drop-in
snippets in `/etc/kernel/config.d/`:

- `10-firmware.config` — builds Intel microcode into the image
  (`CONFIG_EXTRA_FIRMWARE="intel-ucode/06-9a-03"`).
- `90-ivmr-laptop.config` — local performance/battery tuning:
  `CONFIG_X86_NATIVE_CPU`, `NR_CPUS=16`, zstd image+module compression,
  drop AMD/iwlwifi-debug paths, `ZSWAP_DEFAULT_ON` + zstd compressor, strip
  debug-info/BTF, BBR+fq network defaults, RCU lazy/nocb for battery.

dracut config (`/etc/dracut.conf.d/10-local.conf`):

```
hostonly="yes"
hostonly_cmdline="no"
add_dracutmodules+=" crypt dm lvm resume "
force_drivers+=" nvme "
```

## Enabled services

**System** (`systemctl`): `NetworkManager`, `systemd-resolved`,
`systemd-timesyncd`, `lvm2-monitor`, `gdm`, `bluetooth`, `docker`, `thermald`,
`tlp`, `earlyoom`, `smartd`, `lm_sensors`, `nftables`, `fstrim.timer`.

**User** (`systemctl --user`): `wireplumber`, `pipewire`/`pipewire-pulse`
sockets. (Audio is **PipeWire**, not PulseAudio.)

> Personal automation — cloud-storage mounts (`rclone`), scheduled backups
> (`restic`), and a personal helper service — is enabled but intentionally not
> documented here.

## Locale & time

```
LANG=C.UTF8   with LC_TIME/LC_PAPER/LC_MEASUREMENT/… = en_GB.UTF-8
keymap = us
timezone = Europe/Zurich   (NTP via systemd-timesyncd)
```

## Installed applications (the @world set)

These are the explicitly-installed packages (`/var/lib/portage/world`). Their
dependencies (~1000 packages total) are pulled in automatically.

- **Browsers:** `firefox-bin`, `google-chrome` (+ `chrome-binary-plugins`)
- **Comms / mail:** `slack`, `zoom`, `thunderbird-bin`, `mailx`, `msmtp`
- **Office / docs:** `libreoffice-bin`, `pandoc-bin`, `dos2unix`, `graphviz`, `imagemagick`
- **Dev:** `vscode`, `vim`, `gedit`, `git`, `github-cli`, `meld`, `openjdk-bin`,
  `maven-bin`, `nodejs`, `docker` (+ `docker-compose`), `kubectl`, `helm`,
  `terraform`, `jq`, `evtest`
- **Media:** `ffmpeg`, `libva-intel-media-driver`, `libva-utils`,
  `gst-plugins-libav`, `cheese`, `gthumb`, `igt-gpu-tools`
- **Desktop (GNOME):** `gnome-light`, `dconf-editor`, `gnome-browser-connector`
- **Networking:** `networkmanager-openvpn`, `rclone`, `socat`, `telnet-bsd`, `whois`
- **Backup:** `restic`, `rdiff-backup`
- **Printing:** `hplip`
- **System / firmware:** `gentoo-kernel`, `installkernel`, `linux-firmware`,
  `intel-microcode`, `sof-firmware`, `grub`, `sudo`, `dmidecode`, `fwupd`,
  `etckeeper`, `earlyoom`, `smartmontools`, `lm-sensors`, `pciutils`,
  `usbutils`, `eclean-kernel`
- **Power:** `powertop`, `thermald`, `tlp`
- **Filesystems:** `dosfstools`, `ntfs3g`, `7zip`
- **Portage tooling:** `gentoolkit`, `eix`, `elogv`, `genlop`, `portage-utils`,
  `cpuid2cpuflags`, `eselect-repository`, `pkgdev`

## User account

`ivmr` — groups: `wheel audio video usb users systemd-journal plugdev docker mail`.
Passwordless sudo for `%wheel` (`/etc/sudoers`).

## Best-practice notes

**Applied** (already changed on this machine):

- ✅ **`ACCEPT_LICENSE`** narrowed from `"*"` to free/redistributable groups +
  the four proprietary licenses actually in use (see make.conf above).
- ✅ **Portage tmpfs** capped at **16 GiB** (was 32 GiB, larger than RAM). Builds
  that need more than 16 GiB of `$PORTAGE_TMPDIR` should fall back to a
  disk-backed tmpdir via `/etc/portage/env` + `package.env` (the big apps here
  are `-bin`, so this is rarely hit).

**Open** (worth revisiting on the next rebuild):

- **`ACCEPT_KEYWORDS="~amd64"` globally** — full testing branch system-wide is
  higher-maintenance than a stable base with per-package `~amd64`. If switching
  to stable, the only installed packages with **no stable version** (so they
  *must* be keyworded) are:

  ```
  # /etc/portage/package.accept_keywords  — required (no stable version exists)
  net-im/slack          ~amd64
  net-im/zoom           ~amd64
  x11-apps/igt-gpu-tools ~amd64
  ```

  Recommended to *also* keyword (stable lags and these are security/hardware- or
  fast-moving): `sys-firmware/intel-microcode`, `sys-kernel/linux-firmware`,
  `sys-firmware/sof-firmware`, `sys-apps/fwupd`, `sys-power/tlp`,
  `sys-power/thermald`, `app-containers/docker`, `app-containers/docker-compose`,
  `sys-cluster/kubectl`, `app-admin/terraform`. Everything else installed from
  testing has a stable version and would simply downgrade.

- **`>app-arch/zstd-1.5.5` mask** — stale: it pins zstd to 1.5.5 while 1.5.7-r1
  is available. Drop the line and `emerge -1 zstd` unless a specific reason is
  found.
- **Unencrypted kernel + initramfs on the EFI partition** — fine for most
  threat models, but Secure Boot + a signed Unified Kernel Image (UKI) would
  close the evil-maid gap if desired.

---

[← Documentation index](README.md)
