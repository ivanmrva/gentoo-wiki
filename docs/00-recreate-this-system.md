# Recreating this system — step by step

This page is the **runbook**: the ordered, end-to-end procedure to arrive at the
exact setup documented here (encrypted LVM, systemd, GNOME/Wayland, dist-kernel
+ dracut, Intel laptop). The numbered pages (01–04) hold the detailed commands;
this page is the map that puts them in order and tells you *what each step
means*.

There are two ways to get here:

- **[Path A — Fresh install from scratch](#path-a--fresh-install-from-scratch)**
  on a new (or wiped) machine.
- **[Path B — Migrate an existing Gentoo](#path-b--migrate-an-existing-gentoo)**
  to converge it onto this configuration.

> Recovering a dead/lost machine from an existing backup instead of rebuilding
> from scratch? See **[Backup, clone & restore → Total loss](09-backup-restore.md#c-total-loss--clone-onto-new-hardware)**.

> Before anything, read the [Conventions](README.md#conventions): commands use
> `<placeholders>` (username, hostname, partitions, UUIDs) — substitute your
> own. The full target state is captured in the
> [System Reference](08-system-reference.md).

---

## What these docs capture — and what you must bring yourself

These docs plus the `system-changes` git mirror reproduce the machine's **software
state**: the OS and profile, the disk/encryption layout, Portage config, the
dist-kernel, the `@world` package set, the services + automation, and every
tracked `/etc` · `/usr/local` · dotfile customization. They deliberately do **not**
contain the items below — restore those from an off-machine vault or reinstall by
hand, or a "from scratch" rebuild will have *silent* gaps (no Wi-Fi, missing tools).

| Layer | Where it lives | On rebuild |
| --- | --- | --- |
| OS · disk · Portage · kernel · `@world` · services · tracked `/etc`,`/usr/local`,dotfiles | **these docs + the `system-changes` mirror** | follow Path A / B below |
| Secrets — LUKS passphrase + recovery key, restic repo password, rclone remote auth, msmtp SMTP creds, `gh` token, SSH/deploy keys, `~/.openclaw/credentials` | **off-machine vault** → [09 · Layer 5](09-backup-restore.md#layer-5--bootstrap-secrets-off-machine) | restore from the vault |
| **All saved Wi-Fi networks** — `/etc/NetworkManager/system-connections/` (~200 profiles + PSKs) | **off-machine only** — pure secrets, in *no* doc or mirror | re-add by hand, or back that dir up privately |
| Non-Portage apps — JetBrains IDEA Ultimate (`/opt/idea-*`, Toolbox), Claude Desktop AppImage (`~/.local/opt/claude-desktop`), global npm pkgs (`@anthropic-ai/claude-code`, `openclaw`, `pnpm`) under `~/.npm-global` | recorded **by name** in [04](04-application-configuration.md#non-portage-ai-tooling) / [08](08-system-reference.md#installed-outside-portage), **no versioned manifest** | reinstall manually |
| **VS Code extensions** (~16: Python/Pylance, Docker + remote-containers, `anthropic.claude-code`, GitHub Actions, …) | `~/.vscode/extensions/`, **not tracked** | `code --list-extensions` to dump, reinstall from the list |
| **Docker** runtime state — images (`pgvector`, `playwright`, `alpine`, …) + containers | re-pullable; daemon config is stock (no `/etc/docker/daemon.json`) | `docker pull` / recreate as needed |
| App config trees outside the tracker allowlist — notably `~/.openclaw/` (gateway config, agents, devices, workspace) | **not tracked** | reconstruct, or add to the [tracker allowlist](04-application-configuration.md#config-tracking-changes-only-git-mirror) |
| BIOS/UEFI firmware settings (boot order, Secure Boot, TPM) | **in firmware**, not on disk | re-set in the BIOS |

> **Close the biggest gaps first:** the saved Wi-Fi profiles and the bootstrap
> secrets. Everything else is reproducible from the runbook below.

---

## Path A — Fresh install from scratch

Roughly half a day, most of it unattended compiling. You need a wired or
wireless network and a USB stick.

### 1. Boot a live environment & prepare the disk → [01](01-before-installation.md)

What this means: you boot an Ubuntu live USB (any Linux with `cryptsetup` +
`lvm2` works), then carve the target disk into an **unencrypted EFI partition**
(`/boot`) and one big **LUKS2-encrypted partition** that holds an LVM volume
group.

1. Create the bootable USB and boot it.
2. Create the LUKS2 container — **use `--pbkdf pbkdf2`** so GRUB can open it.
3. Inside it, create the `vg0` volume group and just **two** logical volumes:
   `swap` (32G, = RAM, for hibernation) and one big `btrfs` LV (`~920G`,
   `lvcreate -l 100%FREE`). There is **no separate root LV** — root lives in the
   Btrfs pool as the `@` subvolume, so the whole system *and* all data share one
   pool and `/` gains snapshots.
4. `mkswap` the swap LV, `mkfs.btrfs -L pool` the big LV, then mount the pool once
   and create the subvolumes: `@` (root), `@home`, `@var_log` / `@var_cache` /
   `@var_tmp` (split out of the root snapshot), `@data1`…`@data5`, and
   `@portage_build` (on-disk overflow build dir). **Don't** create the
   `.snapshots` subvolumes by hand — snapper makes those itself (step 5.3).
   `/opt` and `/usr/local` stay inside `@`. See
   [Disk layout](08-system-reference.md#disk-layout) for the exact subvolume table
   and the reasoning behind each split.

### 2. Unpack stage3 and chroot → [02 · Stage3 / Chrooting](02-installation.md#stage3-installation)

What this means: you drop the base Gentoo system onto the new root and enter it
as if it were already booted.

1. Mount the `@` (root) subvolume — `mount -o subvol=@ /dev/mapper/vg0-btrfs
   /mnt/gentoo` — then download + verify + unpack the **amd64 desktop systemd**
   stage3.
2. Bind-mount `/proc /sys /dev /run`, copy `resolv.conf`, `chroot` in, mount the
   EFI partition at `/boot`.

### 3. Configure Portage → [02 · Configure Portage](02-installation.md#configure-portage)

What this means: this is where the machine's "personality" is set — compiler
flags, USE flags, licenses, keywords. Get this right before compiling anything.

1. `emerge --sync`, select the profile
   `default/linux/amd64/23.0/desktop/gnome/systemd`.
2. Write `/etc/portage/make.conf` — see the
   [verbatim file](08-system-reference.md#etcportagemakeconf-verbatim). Key
   decisions: `-march=alderlake` (use your CPU), the GNOME/Wayland USE set,
   `VIDEO_CARDS="intel"` + `LIBVA_DRIVER_NAME="iHD"`, the **narrowed**
   `ACCEPT_LICENSE`, and `FEATURES="buildpkg ccache"`. The updated
   `EMERGE_DEFAULT_OPTS` carries `--keep-going --changed-use --jobs 2
   --load-average 14.4` (was `--jobs 4`, no keep-going/changed-use).
3. **ccache:** `FEATURES="ccache"` plus `CCACHE_DIR="/var/cache/ccache"` and
   `CCACHE_SIZE="20G"`. Create that dir group-owned by `portage` and write its
   `ccache.conf` cap before the first big build — this is what speeds up
   recompiles after USE/toolchain changes (the unprivileged `~/.cache/ccache`
   is *not* what Portage uses).
4. **Two-tier build dirs:** the `tmpfs` build dir at `/var/tmp/portage` is now
   **20 GiB** (below RAM) in fstab (step 5). RAM-monster builds are routed to a
   disk-backed area instead: `/etc/portage/package.env` maps
   `webkit-gtk`, `llvm`, `clang`, `gcc`, `nodejs` (plus forward-looking
   `qtwebengine`/`chromium`/`rust`/`libreoffice`) to `env/bigbuild.conf`, which
   sets `PORTAGE_TMPDIR=/var/tmp/portage-big` (the `@portage_build` btrfs subvol
   from step 1, mounted `nodatacow`). Without this, those packages can blow past
   the tmpfs.
5. **package.mask:** mask the X.org stack to enforce Wayland-only —
   `x11-base/xorg-server`, `x11-drivers/xf86-input-evdev`,
   `xf86-input-libinput`, `xf86-video-intel` (matches the global `-X` USE flag).
6. **Keyword decision:** this machine runs `~amd64` (testing) globally on
   purpose, for the latest GNOME + dev tooling, taming the recompile churn with
   `-bin` packages, out-of-Portage runtime managers, `buildpkg` + `ccache`, and
   update cadence — see
   [Keyword strategy](08-system-reference.md#keyword-strategy-decided-stay-on-testing).
   A stable base is the lower-churn alternative if you don't need latest-everything.

### 4. Build the kernel (dist-kernel + dracut) → [02 · Configure Kernel](02-installation.md#configure-kernel)

What this means: instead of hand-configuring a kernel, you install the
distribution kernel and let `installkernel` build it, generate the initramfs
with **dracut** (which unlocks LUKS at boot), and wire up GRUB — all automatic.

1. Install firmware (`linux-firmware`, `sof-firmware`, `intel-microcode`).
2. `package.use`: `sys-kernel/installkernel grub dracut`.
3. Write `/etc/dracut.conf.d/10-local.conf` (crypt/dm/lvm/resume + nvme driver).
4. Add `/etc/kernel/config.d/` snippets (firmware + optional tuning).
5. `emerge gentoo-kernel` → builds, installs, generates initramfs, runs
   `grub-mkconfig`.

### 5. Finish the base system → [02](02-installation.md#configure-fstab)

1. **fstab** — everything by UUID (`blkid`): the EFI `/boot`, the LV swap, then
   the Btrfs pool mounted subvolume-by-subvolume — `@`→`/`, `@home`→`/home`,
   `@var_log`/`@var_cache`/`@var_tmp`, the `@dataN` areas, and
   `@portage_build`→`/var/tmp/portage-big` — plus the **20 GiB** portage tmpfs at
   `/var/tmp/portage`. **No `.snapshots` lines** — snapper creates those nested
   subvolumes itself (step 3). Compression: `zstd:1` on the system subvols (`@`,
   `@home`, `@var_*`), `zstd:3` on `data1`–`data4`, none on `data5`, `nodatacow`
   on `@portage_build`. The kernel auto-applies `ssd` + `space_cache=v2`; TRIM is
   via the `fstrim.timer`. There is **no `/etc/crypttab`**; dracut unlocks LUKS
   from the `rd.luks.uuid=` cmdline (step 3), and GRUB boots
   `root=UUID=<pool> rootflags=subvol=@`. See the
   [verbatim fstab](08-system-reference.md#disk-layout).
2. **zram swap** — `emerge sys-apps/zram-generator`, write
   `/etc/systemd/zram-generator.conf` (`zram-size = min(ram / 2, 8192)`,
   `compression-algorithm = zstd` → an 8 GiB device at priority 100, used before
   the LV swap) and `/etc/sysctl.d/99-zram.conf` (`vm.page-cluster = 0`). The
   32 GiB LV swap stays at priority -1 as the hibernation image target (zram
   can't hold one).
3. **snapper + snapshot boot** — `emerge app-backup/snapper sys-fs/btrfs-progs
   sys-fs/grub-btrfs`. Create configs for the snapshotted subvolumes:
   `snapper -c root create-config /`, `snapper -c home create-config /home`, and
   `snapper -c data1 create-config /data1`; list them in `/etc/conf.d/snapper`
   (`SNAPPER_CONFIGS="root home data1"`). Retention is per config — e.g. `root`
   light timeline + pre/post pairs around `@world` updates, `home` longer (user
   data is the most important), `data1` hourly 48 / daily 14 / weekly 4 / monthly
   0 (`ALLOW_USERS=ivmr`). `create-config` makes each `.snapshots` subvolume
   itself (don't pre-create them). Enable `snapper-timeline.timer` +
   `snapper-cleanup.timer` (leave `snapper-boot.timer` disabled); enable
   `grub-btrfsd.service` so `grub-btrfs` keeps the GRUB "boot a snapshot" submenu
   up to date. `data2`–`data5` have no config (scratch by default; add one to
   snapshot them too).
4. **systemd** — machine-id, hostname, **locale (`C.UTF8` + `en_GB` formats)**,
   timezone; enable `NetworkManager`, `systemd-resolved`, `systemd-timesyncd`,
   `lvm2-monitor`.
5. **GRUB** — `grub-install --efi-directory=/boot`, then a **dracut-style**
   `GRUB_CMDLINE_LINUX` (`rd.luks.uuid=`, `resume=`, backlight params).
6. **User** — create your account in the right groups; set passwords.
7. **GNOME** — `emerge gnome-light`, enable `gdm`.

### 6. Reboot, then post-install → [03](03-after-installation.md) & [04](04-application-configuration.md)

1. Exit chroot, unmount, reboot, remove the USB.
2. [After Installation](03-after-installation.md): sudo, PipeWire audio, VAAPI,
   power management (thermald + TLP), and the rest of the services.
3. [Application Configuration](04-application-configuration.md): install your
   app set (see the full [@world list](08-system-reference.md#installed-applications-the-world-set))
   and configure Docker, printing, backups, and the
   [config-tracking service](04-application-configuration.md#config-tracking-changes-only-git-mirror).
4. **Services & automation** — reinstate the custom services and timers that
   make this machine self-maintaining (none are pulled in by `emerge`; each must
   be enabled explicitly):
   * the **restic backup constellation** (two cloud repos: root + `/data1`, with
     prune/check/restore-test timers) and the **maintenance/health timers**
     (`portage-maintenance`, `system-health-digest`, `fwupd-update-check`) —
     see [After Installation → Systemd services](03-after-installation.md#systemd-services)
     and the full [Backup, clone & restore](09-backup-restore.md) architecture;
   * **`system-changes.service`** (the inotify config-versioning mirror) and
     **`inhibit-sleep-on-ac.service`** (udev-driven AC anti-sleep) — also under
     [Systemd services](03-after-installation.md#systemd-services).
5. Optional: rebuild everything against the final flags — `emerge -e @world`,
   then `emerge --depclean`.

---

## Path B — Migrate an existing Gentoo

If you already run Gentoo and want to converge it onto this configuration
(rather than reinstall). Do these on the running system; **none require a live
USB** unless you also want to change the disk/encryption layout (that needs a
reinstall — see Path A).

1. **Profile** — `eselect profile set …/desktop/gnome/systemd` (this is an
   OpenRC→systemd switch if you're on OpenRC; that is a larger migration — read
   the Gentoo systemd article first).
2. **make.conf** — converge USE, `CPU_FLAGS_X86` (`cpuid2cpuflags`),
   `VIDEO_CARDS`/`LIBVA_DRIVER_NAME`, `MICROCODE_SIGNATURES`,
   `FEATURES="buildpkg ccache"` (+ the ccache dir/size and shims),
   `ACCEPT_LICENSE`, the updated `EMERGE_DEFAULT_OPTS`
   (`--keep-going --changed-use --jobs 2`), the X.org `package.mask`, and the
   `package.env`/`env/bigbuild.conf` two-tier build-dir scheme. Decide on
   keywords (stable + accept_keywords vs global `~amd64`).
3. **Kernel** — move to the dist-kernel + dracut flow: set
   `installkernel[grub,dracut]`, add the dracut + `config.d` snippets, then
   `emerge sys-kernel/gentoo-kernel sys-kernel/installkernel sys-kernel/dracut`.
   Verify `/boot` has the new kernel + initramfs and `grub.cfg` references them
   **before** rebooting.
4. **Audio / network** — switch to PipeWire (enable `wireplumber` user service)
   and NetworkManager + `systemd-resolved`.
5. **Apply the flag changes** — rebuild affected packages:
   `emerge -uDN --changed-use --deep @world` (or a full `emerge -e @world` to
   rebuild everything against the new flags and kernel).
6. **Storage layout** — converge onto the Btrfs pool + zram + snapper. Two parts,
   different difficulty:
   * **Data areas → Btrfs subvols** (in-place): standing up `@data1`–`@data5` in
     one Btrfs LV touches only the data LVs, not the encrypted root or partition
     table — create the pool/subvols, copy data over, swap the fstab entries. Add
     **zram** (`sys-apps/zram-generator` + `zram-generator.conf` + `99-zram.conf`)
     as in Path A step 5.2.
   * **Root → Btrfs `@`** (the bigger move): getting `/` onto a snapshot-capable
     `@` subvolume means moving the root filesystem off its ext4 LV into the pool.
     The low-risk route is to fold it into the same Path-A pool: `btrfs send/receive`
     or `rsync` the ext4 root into a fresh `@` subvolume, repoint
     `root=UUID=<pool> rootflags=subvol=@` + the fstab, reinstall GRUB
     (`sys-fs/grub-btrfs` for snapshot boot), then drop the old `vg0-root` LV.
     Then add **snapper** configs for `root`, `home`, and `data1` as in Path A
     step 5.3. (If that's more surgery than you want, a clean Path-A reinstall
     onto the pool is simpler.) See [Disk layout](08-system-reference.md#disk-layout)
     for the exact subvolumes and mount options.
7. **Apps & services** — `emerge` the
   [@world set](08-system-reference.md#installed-applications-the-world-set);
   enable the [services](08-system-reference.md#enabled-services). Then bring up
   the backup + automation stack: the
   [restic backup constellation](09-backup-restore.md), the maintenance/health
   timers, `system-changes.service`, and `inhibit-sleep-on-ac.service` (see
   [After Installation → Systemd services](03-after-installation.md#systemd-services)).
8. **Clean up** — `emerge --depclean`, `eclean-kernel`, reboot, verify.

> Changing the **disk encryption itself** (e.g. moving an unencrypted install
> onto LUKS+LVM) can't be done in place — back up your data and follow Path A.
> The **data-LV → Btrfs** conversion in step 6 *is* in-place-doable (it leaves the
> LUKS container and root untouched); the **root → Btrfs `@`** move is doable in
> place too but is real surgery (rsync/send the root into the pool, repoint the
> cmdline + fstab, reinstall GRUB) — when in doubt, a clean Path-A reinstall onto
> the pool is the safer path to the same result.

---

[Documentation index →](README.md) · Next: [Before Installation →](01-before-installation.md)
