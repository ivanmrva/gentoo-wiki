# System Reference (current machine snapshot)

A snapshot of the running system, captured so the machine can be recreated from
scratch. Where the step-by-step guide explains *how*, this page records *exactly
what* is installed and configured. Live-audited **2026-06-26**. The **Disk
layout** below documents the **target** Btrfs-root layout these docs build; where
the author's live box is still mid-migration (root not yet on Btrfs), a
*"Live machine status"* note says so. Everything else (packages, services,
`make.conf`, kernel) is the verbatim current state.

> **Privacy note:** machine-id, hardware serial/SKU, WiFi SSIDs/PSKs, the private
> git-mirror remote, and the cloud backup target are **redacted** here. The
> automation itself (backup jobs, config-tracking service, helper timers) *is*
> documented generically below; recreate the secret bits privately.

## Hardware

| Component | Value |
| --- | --- |
| Model | HP ZBook Firefly 14 inch G9 Mobile Workstation |
| CPU | 12th Gen Intel Core i7-1270P (Alder Lake-P, 12 cores / 16 threads) |
| RAM | 32 GiB |
| GPU | Intel Iris Xe (integrated) |
| Storage | ~954 GB NVMe (`/dev/nvme0n1`) |
| Firmware | UEFI (HP), updated via `fwupd` |

## Disk layout

Full-disk encryption: a single LUKS2 container on `nvme0n1p3` holding an LVM
volume group `vg0`. `/boot` is the **unencrypted** EFI partition (GRUB loads the
kernel + initramfs directly from it; the initramfs then unlocks LUKS).

The partition table now has only **three** partitions. The old `nvme0n1p4`
(NTFS Windows-recovery, ~946 MB) that earlier revisions of this doc recorded is
**gone** — current `lsblk` shows only `p1`/`p2`/`p3`.

```
zram0                          8G  swap    [SWAP]   (zram, prio 100 — runtime swap, used first)
nvme0n1                    953.9G
├─nvme0n1p1   vfat        260M  /boot   (EFI System Partition, unencrypted)
├─nvme0n1p2                16M          (Microsoft reserved)
└─nvme0n1p3   crypto_LUKS 952.7G        (LUKS2 container; UUID 8b2c98eb-b644-40d8-8b6d-87bea26bcc8a)
  └─luks-8b2c98eb…  LVM2_member         (vg0)
    ├─vg0-swap   swap    32G  [SWAP]    (UUID 501eeb58-907b-405a-91af-77f523c8d92e; prio -1; = RAM, hibernation)
    └─vg0-btrfs  btrfs ~920G  (pool)    (UUID 048292a5-…) — @ (root) + system + data subvolumes
```

`vg0` holds just **two LVs**: the swap LV (for hibernation) and one big Btrfs
pool that holds the **entire system *and* all data** as subvolumes — `/` is the
`@` subvolume, not a separate ext4 LV. Putting `/` in Btrfs is what gives the
system **snapshots/rollback**; everything shares one free-space pool.

> **Live machine status (mid-migration).** The author's running box still has `/`
> on a separate **ext4 `vg0-root` LV** — its *data* areas are already Btrfs
> subvolumes, but the **root → Btrfs `@`** move is the one migration step not yet
> done. The layout documented here is what the
> [install runbook](00-recreate-this-system.md) builds and what this machine is
> converging to; the pre-Btrfs fstab is preserved at
> `/var/lib/system-changes/etc/fstab.pre-btrfs.<timestamp>`.

LUKS header (per the original install, root-only — **not** re-verified this pass):
`aes-xts-plain64`, 512-bit key, PBKDF `pbkdf2` / `sha256`. PBKDF is **pbkdf2
(not argon2id)** deliberately, so GRUB can open the container — see
[Installation → Bootloader](02-installation.md#configure-bootloader).

### vg0 logical volumes

| LV | Size | FS | Mount | Options |
| --- | --- | --- | --- | --- |
| `vg0-swap` | 32 G | swap | `[SWAP]` | priority -1; hibernation resume target |
| `vg0-btrfs` | ~920 G | btrfs | the `pool` filesystem | all subvolumes below (incl. `@` → `/`) |

There is **no** `vg0-root` LV (root is the `@` subvolume) and no `vg0-data1`…
`vg0-data5` LVs (the data areas are subvolumes too).

### Btrfs pool (`vg0-btrfs`, label `pool`)

One single-device btrfs filesystem (UUID `048292a5-…`), metadata/system **DUP**,
data **single** (the single-disk default). Root, home, the carved-out system
areas, all `/dataN`, and the on-disk Portage build dir live here as subvolumes:

| Subvolume | Mountpoint | fstab mount options | Snapshotted? |
| --- | --- | --- | --- |
| `@` | `/` | `noatime,compress=zstd:1` | **yes** (`root` config) |
| `@home` | `/home` | `noatime,compress=zstd:1` | **yes** (`home` config) |
| `@var_log` | `/var/log` | `noatime,compress=zstd:1` | no (keep logs across rollback) |
| `@var_cache` | `/var/cache` | `noatime,compress=zstd:1` | no (disposable) |
| `@var_tmp` | `/var/tmp` | `noatime` | no (build/scratch) |
| `@data1` | `/data1` | `noatime,compress=zstd:3` | **yes** (`data1` config) |
| `@data2`–`@data4` | `/data2`–`/data4` | `noatime,compress=zstd:3` | no |
| `@data5` | `/data5` | `noatime` (**no `compress=`**) | no |
| `@portage_build` | `/var/tmp/portage-big` | `noatime,nodatacow` (CoW off for build churn) | no |

The `.snapshots` stores are **not** separate top-level subvolumes or fstab
entries — Snapper creates a nested `.snapshots` subvolume inside each configured
subvol (`@`, `@home`, `@data1`); Btrfs snapshots are non-recursive, so a nested
`.snapshots` is automatically excluded from its parent's snapshots.

**Compression by area:** `zstd:1` on the hot, churny system subvolumes (`@`,
`@home`, `@var_*`) where latency matters; `zstd:3` on the largely-static
`data1`–`data4`; `data5` omits `compress=` (already-compressed data). The kernel
auto-applies `ssd` + `space_cache=v2`; TRIM is via the weekly `fstrim.timer`
(continuous `discard=async` optional). **What's split out of `@`:** `@home` and
the `@var_*`/`@data*` areas — everything you *don't* want reverted by a root
rollback (logs, caches, build scratch, user data, bulk data). `/opt` and
`/usr/local` stay **inside** `@`. There is **no `/etc/crypttab`**; LUKS is
unlocked by dracut via `rd.luks.uuid=`, and GRUB boots
`root=UUID=<pool> rootflags=subvol=@`.

### Swap: 32 G LV + 8 G zram (prioritised)

Two swap devices, ordered so compressed RAM swap is consumed first and the disk
LV is reserved for hibernation:

| Device | Size | Priority | Role |
| --- | --- | --- | --- |
| `/dev/zram0` | 8 GiB | **100** | fast compressed RAM swap (used first) |
| `vg0-swap` | 32 GiB | **-1** | encrypted disk swap + **hibernation image target** |

zram is managed by `sys-apps/zram-generator` via
`/etc/systemd/zram-generator.conf`:

```ini
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
```

With 32 GiB RAM, `min(ram/2, 8192)` = 8192 MiB → the 8 GiB device. The 32 GiB
LV swap stays at priority -1 because **zram cannot hold a hibernation image**;
`resume=` points at the LV (encrypted, so the image is encrypted at rest).

zram tunables:

- `/etc/sysctl.d/99-zram.conf` → `vm.page-cluster = 0` (disable swap read-ahead,
  recommended for zram).
- `/etc/sysctl.d/99-local.conf` → `vm.swappiness = 100`, `vm.max_map_count = 1048576`.

### Snapper (per subvolume)

Snapper runs a config per snapshotted subvolume, listed in `/etc/conf.d/snapper`
(`SNAPPER_CONFIGS="root home data1"`). Retention is tuned per area — `/home`
keeps the deepest history (accidental-file recovery is the whole point), `/` gets
a light timeline plus a pre/post pair around every `@world` update (so a bad
update rolls back in seconds), and `/data1` keeps the docs/projects timeline:

| Config | Subvolume | Purpose | Retention (hourly/daily/weekly/monthly) |
| --- | --- | --- | --- |
| `root` | `/` | system rollback (+ pre/post on `@world`) | light timeline + `NUMBER` pre/post pairs |
| `home` | `/home` | accidental file recovery (most important) | 48 / 14 / 8 / 6 |
| `data1` | `/data1` | docs/projects | 48 / 14 / 4 / 0 (`ALLOW_USERS=ivmr`) |

The upstream `snapper-timeline.timer` + `snapper-cleanup.timer` (hourly) are
enabled; `snapper-boot.timer` is **disabled**. `sys-fs/grub-btrfs` adds a GRUB
submenu to boot any snapshot read-only for rollback (enable `grub-btrfsd.service`
to keep it current). `data2`–`data5` have no config — scratch by default; add a
config to snapshot them too (snapper makes the `.snapshots` subvolume itself).

> **Live machine status.** On the author's running (pre root→Btrfs) box, only the
> **`data1`** config exists today (`48 / 14 / 4 / 0`, `ALLOW_USERS=ivmr`, no
> pre/post wrap); the `root`/`home` configs land with the root→Btrfs move. The
> config files under `/etc/snapper/configs/` are root-only `0640`, so even the
> mirror copies are unreadable as `ivmr`.

### Design notes (Btrfs layout)

Rationale behind the subvolume choices above:

- **What to split off `@`:** only things you *don't* want a root rollback to
  revert — `/home`, the `/dataN` areas, `/var/log` (keep logs across a rollback),
  `/var/cache` and `/var/tmp` (disposable / build scratch). `/opt`, `/usr/local`,
  and `/etc` stay **inside** `@` so they roll back together with the packages and
  config they belong to (`/etc` is also in the restic backup, since both recovery
  paths need it). Add a `/var/lib/*` subvolume (e.g. `@docker → /var/lib/docker`)
  **only if** that workload actually hammers it; otherwise it's just noise.
- **Mount paths (deliberate):** the data subvolumes mount at top-level
  `/data1`…`/data5`, *not* under a `/data/dataN` tree — to avoid churning every
  path/script/bind-mount that already
  references `/data1`.
- **Hibernate swap sizing:** `vg0-swap` is sized **= RAM** (32 G here), the safe
  floor for a full hibernation image. Bump it if RAM ever grows:

  | RAM | Swap LV for hibernate |
  |---:|---:|
  | 16 GB | 24–32 GB |
  | 32 GB | 40–48 GB |
  | 64 GB | 64–80 GB |

### Portage build directories (two-tier)

The migration created two distinct build areas:

- **tmpfs** at `/var/tmp/portage`, sized **20 GiB** (was 16 GiB pre-migration) —
  RAM-backed scratch for the common case.
- **disk-backed** btrfs `@portage_build` at `/var/tmp/portage-big`
  (`nodatacow`) — for builds that would overflow the tmpfs. See
  [package.env routing](#etcportagepackageenv--two-tier-build-dirs) below.

## Portage profile

```
default/linux/amd64/23.0/desktop/gnome/systemd
```

## /etc/portage/make.conf (verbatim)

```sh
# These settings were set by the catalyst build script that automatically
# built this stage.
COMMON_FLAGS="-march=alderlake -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

LC_MESSAGES=C.utf8

CPU_FLAGS_X86="aes avx avx2 avx_vnni bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 ssse3 vpclmulqdq"

USE="-branding -qt5 -X wayland vaapi cryptsetup lvm device-mapper cacert dist-kernel screencast gstreamer gles2 vulkan"

MAKEOPTS="-j16"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE BUSL-1.1 Microsoft-vscode all-rights-reserved google-chrome"
ACCEPT_KEYWORDS="~amd64"

LINGUAS=""

VIDEO_CARDS="intel"
LIBVA_DRIVER_NAME="iHD"

MICROCODE_SIGNATURES="-s 0x000906a3"

GRUB_PLATFORMS="efi-64"

# Show messages after emerging *and* save
PORTAGE_ELOG_SYSTEM="echo save"
PORTAGE_ELOG_CLASSES="warn error info log qa"

EMERGE_DEFAULT_OPTS="--ask --verbose --deep --with-bdeps=y --tree --keep-going --changed-use --jobs 2 --load-average 14.4"
FEATURES="buildpkg ccache"

# ccache: speed up recompiles (USE changes, toolchain rebuilds)
CCACHE_DIR="/var/cache/ccache"
CCACHE_SIZE="20G"

# nice builds so the desktop stays responsive
PORTAGE_NICENESS=15

# don't install bulky API html docs (man pages/licenses kept)
INSTALL_MASK="/usr/share/gtk-doc /usr/share/doc/*/html"
```

Notes on the non-obvious knobs:

- `EMERGE_DEFAULT_OPTS` now carries `--keep-going --changed-use` and runs
  `--jobs 2` at `--load-average 14.4` (was `--jobs 4`, no keep-going) — fewer
  parallel package builds but each gets `MAKEOPTS=-j16`, and a stuck package no
  longer aborts the whole run.
- `FEATURES="buildpkg ccache"` — every build is cached as a binpkg
  (`/var/cache/binpkgs`, see [binhost](#binreposconf--inert-stock-binhost)) **and**
  compiled through ccache.
- `PORTAGE_NICENESS=15` keeps the desktop responsive during builds.
- `INSTALL_MASK` drops `gtk-doc` HTML and per-package API HTML (man pages and
  licenses are kept).
- Regenerate `CPU_FLAGS_X86` with `cpuid2cpuflags`. `MICROCODE_SIGNATURES`
  restricts `intel-microcode` to this CPU's signature (`0x000906a3` = Alder
  Lake-P, `06-9a-03`).
- `ACCEPT_LICENSE` is the narrowed form: the free/redistributable groups plus the
  exact proprietary licenses the installed apps need — `BUSL-1.1`, `Microsoft-vscode`,
  `all-rights-reserved` (Slack, Zoom), `google-chrome`. This replaced a blanket `"*"`.

## ccache (FEATURES=ccache)

`dev-util/ccache-4.13.5`, fully wired into Portage:

- Cache at **`/var/cache/ccache`**, capped **20G** (`/var/cache/ccache/ccache.conf`
  carries `max_size = 20G`).
- Compiler shims live in `/usr/lib/ccache/bin/`.
- **Caveat:** running `ccache -s` *as your user* shows the unprivileged default
  (`~/.cache/ccache`, 5 GiB) — that is **not** what Portage uses. Portage's cache
  is the 20G `/var/cache/ccache`.

## /etc/portage/package.use (verbatim)

```
sys-kernel/installkernel grub dracut
net-wireless/wpa_supplicant tkip
net-libs/nodejs npm
# conflict resolution for the global -X (per-package X re-enables)
x11-libs/cairo X
gui-libs/gtk X
x11-libs/gtk+ X
x11-libs/libxkbcommon X
media-libs/mesa X
media-libs/vulkan-loader X
# dependency-driven flags
>=media-libs/freetype-2.14.0 harfbuzz
>=net-dns/avahi-0.9_rc3 python
>=net-libs/ngtcp2-1.20.0-r1 gnutls
>=sys-libs/zlib-1.3.2-r1 minizip
net-analyzer/netdata -python
app-portage/pfl -network-cron
sys-apps/zram-generator -man
```

The global `USE="… -X …"` keeps X.org out of the system; the per-package `X`
re-enables above are the minimum needed to resolve the GNOME/Wayland build chain
(cairo, gtk, mesa, vulkan-loader, libxkbcommon).

## /etc/portage/package.mask (verbatim)

```
x11-base/xorg-server
x11-drivers/xf86-input-evdev
x11-drivers/xf86-input-libinput
x11-drivers/xf86-video-intel
```

A **Wayland-only enforcement mask** — it blocks the X.org server and its input/
video drivers, consistent with the global `-X`. (The old `>app-arch/zstd-1.5.5`
mask is **gone**.)

## /etc/portage/package.accept_keywords

**Empty.** No per-package keyword pins — the global `~amd64` covers everything.

## /etc/portage/package.env — two-tier build dirs

Routes RAM-monster builds off the tmpfs onto the disk-backed `@portage_build`
subvolume (added 2026-06-26):

```
# Build these RAM-monsters on NVMe (/var/tmp/portage-big) instead of tmpfs
net-libs/webkit-gtk     bigbuild.conf
llvm-core/llvm          bigbuild.conf
llvm-core/clang         bigbuild.conf
sys-devel/gcc           bigbuild.conf
net-libs/nodejs         bigbuild.conf
# forward-looking (harmless if not installed; -bin variants used today):
dev-qt/qtwebengine      bigbuild.conf
www-client/chromium     bigbuild.conf
dev-lang/rust           bigbuild.conf
app-office/libreoffice  bigbuild.conf
```

`/etc/portage/env/bigbuild.conf` is a one-liner:

```
PORTAGE_TMPDIR="/var/tmp/portage-big"
```

(A stale in-file comment still says "19G tmpfs"; the fstab is actually 20G.)

## binrepos.conf — inert stock binhost

`/etc/portage/binrepos.conf/gentoobinhost.conf` is the **stock catalyst stub**
pointing at `distfiles.gentoo.org/.../binpackages/23.0/x86-64`. It is **inert**:
`getbinpkg` is not in `FEATURES` and `PORTAGE_BINHOST` is empty, so no remote
binpkgs are fetched. The *active* binpkg mechanism is the **local** `FEATURES=buildpkg`
cache at `/var/cache/binpkgs` (≈ 2.4 GB).

## Repository sync

Sync is still **rsync**, OpenPGP/metamanifest-verified (set by the stage3):

```
sync-type = rsync
sync-uri  = rsync://rsync.gentoo.org/gentoo-portage
```

Overlays: `eselect repository list -i` shows only `gentoo` + an empty `local`
overlay (`/var/db/repos/local`). The system `/etc/gitconfig` still carries a
`safe.directory` entry for a **GURU** overlay (`/var/db/repos/guru`), but that
directory does **not** currently exist and GURU is not an enabled repo — the
entry is a **stale leftover** (a removed/never-finished overlay; harmless, a
cleanup candidate). Syncing over git is a valid alternative — see
[After Installation](03-after-installation.md#optional-sync-portage-over-git).

## Kernel

Distribution kernel **`sys-kernel/gentoo-kernel-7.0.12`** (running
`7.0.12-gentoo-dist`), built locally and installed by `sys-kernel/installkernel-68`
with **dracut** (`sys-kernel/dracut-111-r1`) generating the initramfs.
`sys-kernel/linux-firmware-20260622`.

Kernel USE: `debug initramfs strip` — **`secureboot`/`generic-uki`/`modules-sign`
are OFF**, i.e. a plain (non-UKI, unsigned) kernel plus a separate initramfs on
the unencrypted ESP.

Customised via drop-in snippets in `/etc/kernel/config.d/`:

**`10-firmware.config`** (builds Intel microcode into the image):

```
CONFIG_EXTRA_FIRMWARE="intel-ucode/06-9a-03"
CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"
```

**`90-ivmr-laptop.config`** — local perf/battery tuning:

- `CONFIG_X86_NATIVE_CPU=y` — compile for this exact CPU.
- `# CONFIG_MAXSMP is not set` **+** `CONFIG_NR_CPUS=16` — the dist config enables
  MAXSMP, which force-locks `NR_CPUS=8192`; **disabling MAXSMP is required** for
  `NR_CPUS=16` to actually take effect (frees per-CPU static memory).
- `CONFIG_KERNEL_ZSTD=y` + `CONFIG_MODULE_COMPRESS_ZSTD=y` — zstd image + module
  compression.
- Drop AMD-only paths (`X86_AMD_PSTATE`, `X86_MCE_AMD`) and iwlwifi debug/debugfs/
  kunit-test branches.
- `CONFIG_ZSWAP_DEFAULT_ON=y` + `ZSWAP_COMPRESSOR_DEFAULT_ZSTD` — zswap on by
  default with zstd.
- `CONFIG_DEBUG_INFO_NONE=y` + no `DEBUG_INFO_BTF` — strips debug info/BTF.
  **Caveat:** this disables eBPF CO-RE, so `bpftrace`/`bcc` break — drop these two
  lines if you need eBPF tooling.
- `# CONFIG_KUNIT is not set` — drop the in-kernel test framework.
- `CONFIG_HZ_1000` is **present but commented-out/disabled** — the dist default
  `HZ=300` stays in effect; the snippet keeps the line as documentation only.
- BBR + fq network defaults (`TCP_CONG_BBR`, `DEFAULT_BBR`, `NET_SCH_FQ`,
  `DEFAULT_FQ`).
- `RCU_NOCB_CPU_DEFAULT_ALL` + `RCU_LAZY` — offload + lazy RCU callbacks for
  battery (LAZY only acts on offloaded CPUs, so nocb-all is required).

### dracut config (`/etc/dracut.conf.d/10-local.conf`)

```
hostonly="yes"
hostonly_cmdline="no"
add_dracutmodules+=" crypt dm lvm "
force_drivers+=" nvme "
add_dracutmodules+=" resume "
```

`crypt dm lvm` unlock LUKS + activate LVM in the initramfs; `resume` enables
hibernation/resume from swap; `force_drivers+=" nvme "` guarantees the NVMe driver
is present; `hostonly="yes"` with `hostonly_cmdline="no"` builds a host-specific
initramfs without baking in the cmdline (the cmdline comes from GRUB).

### Boot cmdline / resume (GRUB)

`/etc/default/grub` non-default lines:

```
GRUB_DISTRIBUTOR="Gentoo"
GRUB_TIMEOUT=2
GRUB_DISABLE_LINUX_PARTUUID=false
GRUB_CMDLINE_LINUX="dolvm rd.luks.options=discard rd.luks.uuid=8b2c98eb-b644-40d8-8b6d-87bea26bcc8a root=UUID=048292a5-5607-449a-9247-92aad183be1f rootflags=subvol=@ init=/usr/lib/systemd/systemd acpi_backlight=native i915.enable_dpcd_backlight=1 resume=UUID=501eeb58-907b-405a-91af-77f523c8d92e"
```

(`root=UUID=<pool> rootflags=subvol=@` boots the `@` subvolume. The author's live,
mid-migration box still boots `root=/dev/mapper/vg0-root` — that flips to the form
above with the root→Btrfs move.)

- `dolvm` + `rd.luks.options=discard` + `rd.luks.uuid=…` — activate LVM, pass TRIM
  to LUKS, and name the encrypted partition (`nvme0n1p3`) for dracut to unlock.
- `acpi_backlight=native` + `i915.enable_dpcd_backlight=1` — fix display
  brightness on this HP/Intel laptop.
- `resume=UUID=501eeb58-…` — hibernation resume device = the **`vg0-swap` LV**
  (32 G, inside LUKS, so the hibernation image is encrypted at rest). zram cannot
  be a resume device.
- **`mem_sleep_default=deep` was removed (2026-06-16)** when switching to
  **suspend-then-hibernate** — forcing S3 is incompatible with the s2idle-then-
  hibernate flow. A `/etc/default/grub.bak-presuspend` backup preserves the old
  line. (The *running* `/proc/cmdline` may still show `mem_sleep_default=deep`
  until the next reboot regenerates `grub.cfg`.)

No UKI, no Secure Boot, no module signing — see the
[Roadmap](#roadmap--live-machine-status).

## Enabled services

42 enabled system unit files (`systemctl list-unit-files --state=enabled`),
grouped below. For the *why* behind each, see
[After Installation → Systemd services](03-after-installation.md#systemd-services),
[Application Configuration](04-application-configuration.md#config-tracking-changes-only-git-mirror),
and [Backup, clone & restore](09-backup-restore.md).

**Stock daemons:** `NetworkManager` (+ `-dispatcher`, + `-wait-online`),
`systemd-resolved`, `systemd-timesyncd`, `lvm2-monitor`, `gdm`, `bluetooth`,
`docker`, `thermald`, `tlp`, `smartd`, `lm_sensors`, `nftables`, `earlyoom`,
`systemd-oomd`.

**Stock timers:** `fstrim.timer` (weekly), `fwupd-refresh.timer` (hourly metadata
refresh — `OnCalendar=*-*-* *:00:00`, +1h randomized delay),
`snapper-timeline.timer` + `snapper-cleanup.timer` (hourly),
`systemd-tmpfiles-clean.timer`.

**Custom services:**

| Unit | Role |
| --- | --- |
| `system-changes.service` | Long-running inotify config tracker (`Restart=always`, `Nice=10`, IO idle) → auto-commits `/etc`, `/usr/local`, a `$HOME` allowlist, and `@world`/extension state to a private git mirror. See [Application Configuration](04-application-configuration.md#config-tracking-changes-only-git-mirror). |
| `inhibit-sleep-on-ac.service` | udev-driven (`99-inhibit-sleep-on-ac.rules`) holder that blocks all sleep paths while on AC (`ConditionACPower=true`). See [Power & sleep](#power--sleep). |

**Backup + maintenance timers** (all enabled, `Persistent=true`):

| Timer | Schedule | Activates |
| --- | --- | --- |
| `restic-backup.timer` | Fri 20:00 | root FS → restic (cloud) |
| `restic-backup-data1.timer` | daily 21:00 | `/data1` → separate restic repo |
| `restic-prune.timer` | monthly | prune root repo |
| `restic-prune-data1.timer` | day-05 03:00 | prune `/data1` repo |
| `restic-check@structure.timer` | Wed 22:00 | metadata integrity check |
| `restic-check@readdata.timer` | day-10 02:00 | `check --read-data-subset=10%` |
| `restic-restore-test.timer` | Mon 22:00 | end-to-end restore + verify |
| `portage-maintenance.timer` | Sun 03:00 | `eclean-dist/pkg --deep`, `eix-update` |
| `system-health-digest.timer` | daily 08:00 | daily health/maintenance digest email |
| `fwupd-update-check.timer` | weekly | firmware update check, email if any |

Full backup architecture (two restic repos, retention, integrity jobs) is in
[Backup, clone & restore → Layer 1](09-backup-restore.md#layer-1--system-backup-restic-encrypted).

**Masked units** (→ `/dev/null`): `systemd-networkd` (`.service`/`.socket`/
`-resolve-hook.socket`) — NetworkManager owns networking; `tlp-pd.service` —
TLP power-down helper disabled in favour of plain `tlp`.

**Cleanup candidates** (documented as-is, *not* fixed):

- **`earlyoom` + `systemd-oomd` are both enabled+active** — redundant.
  `oomd.conf` has only an empty `[OOM]` stanza and no `ManagedOOM*` properties on
  the root slice, so oomd is effectively inert; `earlyoom` is the real OOM guard.
- **Dangling `rdiff-backup-root.timer`** — a `timers.target.wants/` symlink to a
  `.timer` unit file that no longer exists. Leftover from the old rdiff era: the
  `app-backup/rdiff-backup` package is still installed and in `@world`, but nothing
  wires it to a timer/service anymore — an unused `--deselect` candidate.
- **`snapper-daily@` template** — present but static/disabled with no enabled
  instance; superseded by the upstream `snapper-timeline`/`snapper-cleanup`.
- **Stale provider wording** — the 2026-06-21 backup-target migration updated the
  restic *service* Descriptions to the new cloud remote but not the *timer*
  Descriptions (a couple still name the old provider); the pre-migration
  `*.bak.*-20260621` unit copies also linger.

User-scope units (the OpenClaw gateway, retired rclone-mount leftovers) live
under `~/.config/systemd/user` and are out of scope for this system-level table.

## Networking & firewall

- **NetworkManager** with stock defaults (no custom conf). Devices: `wlp0s20f3`
  (WiFi) and `wwan0` (WWAN). **206 saved WiFi profiles** in
  `/etc/NetworkManager/system-connections/` (root-only secrets — correctly
  excluded from the config mirror; heavy travel use).
- **nftables**: the ruleset path is `/etc/nftables/rules/main.nft` (the **package
  default** — the `nftables.service` unit hard-codes it; there is **no**
  `/etc/nftables.conf` and writing one would have no effect). One `inet filter`
  table; the input chain policy is **drop** (default-deny inbound). It accepts
  established/related, `lo`, `docker0`, ICMP/ICMPv6, DHCP/DHCPv6 (udp 68/546) and
  mDNS (udp 5353), and drops invalid conntrack. No forward/output chains
  (outbound is open; Docker's iptables chains are untouched). **No inbound SSH.**
- **DNS:** `systemd-resolved` is enabled+active but resolv.conf mode is **foreign**
  — NetworkManager writes `/etc/resolv.conf` itself (plain file, `nameserver=<router>`),
  so the `127.0.0.53` stub is *not* in the glibc path.
- VPN: `net-vpn/networkmanager-openvpn` is the explicit choice. `/etc/hosts` is stock.

## Power & sleep

Detail and rationale live in
[After Installation → Power Management](03-after-installation.md#power-management);
the current shape:

- **TLP** (`/etc/tlp.conf`) non-defaults: `CPU_ENERGY_PERF_POLICY_ON_AC=performance`
  / `_ON_BAT=balance_power`; `CPU_BOOST_ON_AC=1` / `_ON_BAT=0`;
  `CPU_HWP_DYN_BOOST_ON_BAT=1`; `CPU_MAX_PERF_ON_AC=100` / `_ON_BAT=70`;
  `PCIE_ASPM_ON_BAT=powersave`; `WIFI_PWR_ON_BAT=on`; `NMI_WATCHDOG=0`. Battery
  charge thresholds are **not** set; `platform_profile` is unavailable on this
  machine. `thermald` runs `--adaptive` (no custom XML).
- **suspend-then-hibernate** timeline:
  `logind` `10-lid.conf` → `HandleLidSwitch=suspend-then-hibernate` (battery),
  `HandleLidSwitchExternalPower=suspend` (AC), `HandleLidSwitchDocked=ignore`.
  `20-idle.conf` → `IdleAction=suspend-then-hibernate`, `IdleActionSec=25min`
  (+ GNOME idle-delay 5 min ≈ 30 min real). `sleep.conf.d/10-hibernate.conf` →
  `AllowSuspendThenHibernate=yes`, `SuspendState=mem`, `HibernateDelaySec=30min`
  (→ hibernate ~60 min after last activity). GNOME auto-suspend is disabled, so
  logind is the sole idle driver.
- **`inhibit-sleep-on-ac`** — the udev rule `99-inhibit-sleep-on-ac.rules` toggles
  `inhibit-sleep-on-ac.service` on AC plug/unplug, so the machine never
  auto-sleeps on AC (no helper script — the unit's ExecStart is just
  `systemd-inhibit --what=sleep:idle --mode=block sleep infinity`).
- **UPower:** `CriticalPowerAction=Hibernate` at `PercentageAction=2.0`.

## Locale & time

```
LANG=C.UTF8     # literally — no hyphen — intentional
LC_TIME / LC_PAPER / LC_MEASUREMENT / LC_MONETARY / LC_NUMERIC = en_GB.UTF-8
KEYMAP=us
hostname  = ivmr-laptop
timezone  = Europe/Zurich   (NTP via systemd-timesyncd)
```

## Misc /etc tunables

- `/etc/sysctl.d/99-local.conf`: `vm.swappiness=100`, `vm.max_map_count=1048576`.
- `/etc/modules-load.d/lm_sensors.conf`: `coretemp`.
- `/etc/subuid` + `/etc/subgid`: `ivmr:100000:65536` (user-namespace ID mapping
  for rootless containers — though no rootless runtime is installed; Docker here
  is rootful, so this mapping is currently unused).
- `/etc/gitconfig` (system): `[safe] directory = /var/db/repos/guru` — a **stale**
  leftover; that overlay is not present (see [Repository sync](#repository-sync)).
- Mail: `/usr/sbin/sendmail` → `mail-mta/msmtp`; `/etc/aliases` routes
  `root`/default mail to a real inbox (**redacted**). `smartd` and the health/
  backup timers all email on failure via this path.

## Installed applications (the @world set)

**1089 packages installed** total; the explicit **@world set is 83 packages**
(`/var/lib/portage/world`). Dependencies (~1006 packages) are pulled in
automatically.

- **Browsers:** `firefox-bin`, `google-chrome` (+ `chrome-binary-plugins`)
- **Comms / mail:** `slack`, `zoom`, `thunderbird-bin`, `msmtp`
- **Office / docs:** `libreoffice-bin`, `pandoc-bin`, `dos2unix`, `graphviz`, `imagemagick`
- **Dev:** `vscode`, `vim`, `gedit`, `git`, `github-cli`, `meld`, `pkgdev`,
  `openjdk-bin`, `maven-bin`, `nodejs`, `docker` (+ `docker-compose`), `kubectl`,
  `helm`, `terraform`, `jq`, `evtest`, `ccache`
- **Media:** `ffmpeg`, `libva-intel-media-driver`, `libva-utils`,
  `gst-plugins-libav`, `cheese`, `gthumb`
- **Desktop (GNOME):** `gnome-light`, `dconf-editor`, `gnome-browser-connector`
- **Networking:** `networkmanager-openvpn`, `rclone`, `socat`, `whois`
- **Backup:** `restic`, `rdiff-backup`, `snapper`
- **Printing:** `hplip`
- **System / firmware:** `gentoo-kernel`, `installkernel`, `linux-firmware`,
  `intel-microcode`, `sof-firmware`, `grub`, `sudo`, `dmidecode`, `fwupd`,
  `earlyoom`, `smartmontools`, `lm-sensors`, `pciutils`, `usbutils`, `eclean-kernel`
- **Filesystems / btrfs:** `btrfs-progs`, `dosfstools`, `ntfs3g`, `7zip`
- **Memory / power:** `zram-generator`, `thermald`, `tlp`
- **Monitoring:** `btop`, `htop`
- **Config tracking / browser perf:** `inotify-tools` (backs `system-changes`),
  `profile-sync-daemon` (psd)
- **Portage tooling:** `gentoolkit`, `eix`, `elogv`, `genlop`, `portage-utils`,
  `cpuid2cpuflags`, `eselect-repository`, `flaggie`, `pfl`

**Flagged accidental world entry:** `app-xemacs/emerge-1.13` — this is the
**XEmacs** interactive-merge tool (an `emerge.el` front-end), *not* Portage's
`emerge`. It was almost certainly added by accident (`emerge emerge`) and pulls
XEmacs as a dependency. **`emerge --deselect app-xemacs/emerge`** candidate.

> Packages that **dropped off** the old list because they are no longer in @world
> (or not installed): `mailx` (now only a dependency), `telnet-bsd`,
> `igt-gpu-tools`, `powertop`, `etckeeper` (replaced by `system-changes`),
> `obs-studio`.

### Installed outside Portage

These won't appear in `@world`/`qlist`, and the **config mirror tracks only their
`.desktop` entries, not the packages** — reinstall by hand on a rebuild (see the
[rebuild ledger](00-recreate-this-system.md#what-these-docs-capture--and-what-you-must-bring-yourself)):

- **IntelliJ IDEA Ultimate** — `/opt/idea-IU-261.24374.151`, via JetBrains Toolbox.
- **Claude Desktop** — unofficial AppImage at `~/.local/opt/claude-desktop`
  (handles `claude://`).
- **Claude Code** — npm-global `@anthropic-ai/claude-code` (handles `claude-cli://`).
- **OpenClaw** — npm-global; runs as a user-scope service
  (`openclaw-gateway.service`, gateway on port 18789). Its config tree
  `~/.openclaw/` is **not** in the tracker allowlist (untracked gap).
- **pnpm** — npm-global package manager (CLI only, no desktop entry).

(Node is Portage's `net-libs/nodejs`; only the *global npm packages* above sit
outside Portage.)

## User account

`ivmr` — groups: `wheel audio video usb users systemd-journal plugdev docker mail`.
Passwordless sudo for `%wheel` (`/etc/sudoers`). Several **decommissioned-service
groups still linger** (e.g. `netdata`, `nullmail`, `openvpn`) — harmless, but
candidates for cleanup.

## Best-practice notes

**Applied** (already changed on this machine):

- ✅ **`ACCEPT_LICENSE`** narrowed from `"*"` to free/redistributable groups + the
  four proprietary licenses actually in use (see make.conf above).
- ✅ **Portage tmpfs** is now **20 GiB** (was 16 GiB during the ext4 era).
- ✅ **Disk-backed big-build dir implemented** — the historical "fall back to a
  disk-backed tmpdir for huge builds" note is now real: `@portage_build` at
  `/var/tmp/portage-big`, routed via [`package.env`](#etcportagepackageenv--two-tier-build-dirs).
- ✅ **ccache enabled** (`FEATURES=ccache`, 20G at `/var/cache/ccache`) — cuts
  recompile time on USE/toolchain churn.
- ✅ **Stale `>app-arch/zstd-1.5.5` mask removed**; `package.mask` now enforces
  Wayland-only (masks the X.org stack) instead.

## Keyword strategy (decided: stay on testing)

This machine runs **`ACCEPT_KEYWORDS="~amd64"` globally on purpose** — the goal
is the latest GNOME and the latest developer tooling, and trying to pin a stable
base would mean hand-keywording most of the system anyway (latest GNOME alone
drags in a large testing-library cascade). It's a conscious trade-off: more
frequent updates in exchange for newest software.

The downside of global testing — frequent recompiles — is managed **without**
dropping to stable:

- **`-bin` packages** for the heavyweights (browsers, office, editor, JDK) so
  they never compile.
- **Language runtimes managed outside Portage** (a version manager such as
  `mise`/`asdf` for Node, Python, …) so new releases don't trigger rebuilds.
- **`FEATURES="buildpkg"`** for instant rollback/reinstall from the local
  binary-package cache, plus **`ccache`** to speed the recompiles that do happen.
- **Batched update cadence** (weekly/biweekly, not daily) — you choose when to
  `emerge -uDN`, so churn is a cadence decision, not something the branch forces.
- Keep USE flags stable (USE changes cause mass rebuilds) and avoid `**`/`-9999`
  live ebuilds (they rebuild every sync).

**If you ever did want a stable base instead**, the only installed packages with
no stable version (so they'd *have* to be keyworded) are `net-im/slack` and
`net-im/zoom`; you'd likely also keyword the security/hardware/fast-moving ones
(`intel-microcode`, `linux-firmware`, `sof-firmware`, `fwupd`, `tlp`, `thermald`,
`docker`, `kubectl`, `terraform`). Everything else installed from testing has a
stable version and would downgrade.

## Roadmap & live-machine status

These docs describe the **target** setup — root on Btrfs `@` with system
snapshots, the full subvolume layout, two-tier builds, the backup constellation.
This section tracks the two gaps that remain: where the author's **running
machine** still has to catch up to the documented layout, and the genuinely
**optional** hardening left to consider. *Derived from the current setup, not a
clean-slate redesign.*

Target architecture, in one line:

```text
LUKS2 + LVM + Btrfs (root on @) + Snapper + restic   (+ optional: 2nd cloud, signed UKI)
```

Recovery stays layered with **no external-SSD layer** — a deliberate trade-off
(less hardware, slower full restore), acceptable *only* because the rebuild is
documented and (target) two independent cloud repos are kept.

| Item | State on the live machine | Where it's detailed | Status |
| --- | --- | --- | --- |
| **Root on Btrfs `@` + system snapshots** | documented layout; the live box is **mid-migration** — still ext4 `vg0-root`, data already on Btrfs | [Disk layout](#disk-layout) | converging |
| **2nd independent cloud + wider data coverage** | one cloud provider, `/data1`-only off-site → `restic copy` to a 2nd provider; off-site + snapshots for `data2`–`data5` (or declare them scratch) | [09 → second cloud provider + wider coverage](09-backup-restore.md#planned-improvement-second-cloud-provider--wider-coverage) | planned |
| **Signed UKI + Secure Boot** | GRUB + unsigned kernel on the ESP (pbkdf2); UKI/Secure Boot + TPM2 unlock is optional evil-maid hardening | [02 → signed UKI + Secure Boot](02-installation.md#planned-improvement-signed-uki--secure-boot-drop-grub) | optional |
| **Package & install policy** | Portage default · `-bin` heavyweights · npm/AppImage only for the 3 non-Portage tools | [04 → Package & install policy](04-application-configuration.md#package--install-policy) | done |

### Cleanup candidates

Loose ends worth tidying (none urgent, none affecting function):

- `earlyoom` + `systemd-oomd` run **redundantly** (oomd is effectively inert) —
  mask one.
- Dangling `rdiff-backup-root.timer` symlink (no backing unit) and the unused
  `snapper-daily@` template are dead. `app-backup/rdiff-backup` and
  `app-xemacs/emerge` are installed-but-unused `emerge --deselect` candidates.
- `*.bak.*-20260621` unit copies + stale old-provider timer Descriptions left from
  the 2026-06-21 backup-target migration.
- Decommissioned-service groups (`netdata`, `nullmail`, `openvpn`) linger in
  `/etc/group`/`passwd`; the system `/etc/gitconfig` `safe.directory` points at a
  GURU overlay that isn't present (see [Repository sync](#repository-sync)).

---

[← Documentation index](README.md)
