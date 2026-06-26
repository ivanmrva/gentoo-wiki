# Stage3 Installation

1. Create a directory for the new Gentoo installation and mount the root LVM volume to it:
   * `mkdir /mnt/gentoo`
   * `mount /dev/mapper/vg0-root /mnt/gentoo`
1. Download and unpack stage3:
   * `cd /mnt/gentoo`
   * Copy link of stage3 archive for _amd64_ architecture for _desktop_ and _systemd_ profile from https://distfiles.gentoo.org/
   * Download archive:
     * wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd/stage3-amd64-desktop-systemd-20240929T163611Z.tar.xz
   * Verify the signature of the downloaded archive (the DIGEST file can be found under the same folder, where the tar archive was downloaded): 
     * `openssl dgst -r -sha512 stage3-amd64-desktop-systemd-20240929T163611Z.tar.xz`
   * Unpack the archive:
     * `tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner`

# Chrooting

1. Copy DNS info (to ensure internet is working once chrooted to _/mnt/gentoo_):
   * `cp --dereference /etc/resolv.conf /mnt/gentoo/etc/`
1. Mount necessary file systems:
   * `mount --types proc /proc /mnt/gentoo/proc`
   * `mount --rbind /sys /mnt/gentoo/sys`
   * `mount --make-rslave /mnt/gentoo/sys`
   * `mount --rbind /dev /mnt/gentoo/dev`
   * `mount --make-rslave /mnt/gentoo/dev`
   * `mount --bind /run /mnt/gentoo/run`
   * `mount --make-slave /mnt/gentoo/run`
      * or as one command:
         * `sudo mount --types proc /proc /mnt/gentoo/proc && sudo mount --rbind /sys /mnt/gentoo/sys && sudo mount --make-rslave /mnt/gentoo/sys && sudo mount --rbind /dev /mnt/gentoo/dev && sudo mount --make-rslave /mnt/gentoo/dev && sudo mount --bind /run /mnt/gentoo/run && sudo mount --make-slave /mnt/gentoo/run`
   * If your distribution (Ubuntu Live USB) has _/dev/shm_ being a symbolic link to _/run/shm/_, you need to also execute:
      * `test -L /dev/shm && rm /dev/shm && mkdir /dev/shm`
      * `mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm`
      * `chmod 1777 /dev/shm /run/shm`
1. Enter the new environment:
   * Change the root location: `chroot /mnt/gentoo /bin/bash` 
   * Reload settings: `source /etc/profile`
   * Change primary prompt name: `export PS1="(chroot) ${PS1}"`
1. Mount boot partition:
   * Create _boot_ directory, if not exist yet: `mkdir /boot`
   * Check for EFI partition (it should be the fat32 filesystem, usually the first one on the disk) and mount it: `mount /dev/nvme0n1p1 /boot`

# Configure Portage

1. Update Gentoo ebuild repository:
   * `emerge --sync`
1. Set system profile:
   * Get the profile list: `eselect profile list`
   * Choose the correct profile: 
     * Select the latest profile version for deskop + gnome + systemd (e.g. _default/linux/amd64/23.0/desktop/gnome/systemd (stable)_): `eselect profile set 26`
1. Set compilation flags/option in _/etc/portage/make.conf_ (or copy them from the previous Gentoo installation):
   * `COMMON_FLAGS="-march=alderlake -O2 -pipe"`
      * Use this script to find out CPU architecture: 
         * `gcc -v -E -x c /dev/null -o /dev/null -march=native 2>&1 | grep /cc1 | grep mtune`
   * `CPU_FLAGS_X86="aes avx avx2 avx_vnni bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 ssse3 vpclmulqdq"` (this guide's value, for an Alder Lake i7-1270P)
      * Use `cpuid2cpuflags` command to print out the CPU flags for the current architecture
      * Install it if not present with: `emerge cpuid2cpuflags`
   * `MAKEOPTS="-j16"` (enables parallel compilation)
      * Use the number of CPU threads here that can be checked with the command: `nproc`
      * A good choice is the smaller of: the number of threads the CPU has, or the total amount of system RAM divided by 2 GiB (so, e.g. -j16 requires at least 32 GiB RAM)
1. Set USE flags in _/etc/portage/make.conf_ - configure reasonable global defaults (adapt the list as you install other packages to your needs):
   * `USE="-branding -qt5 wayland -X vaapi cryptsetup lvm device-mapper cacert dist-kernel screencast gstreamer gles2 vulkan"`
      * `dist-kernel` keeps the initramfs/bootloader in sync when the distribution kernel updates; `wayland -X` builds for a Wayland GNOME session (with per-package `X` enables where a package still needs it); `screencast gstreamer gles2 vulkan` cover GNOME screen sharing and GPU acceleration.
   * First, check the current USE flag list coming from the selected profile with: `emerge --info | grep ^USE` and adapt the list to your needs with. You might want to check Gnome and Wayland documentation first.
1. Set VIDEO_CARDS in _/etc/portage/make.conf_ based on your graphic card (check the corresponding Wiki doc):
   * `VIDEO_CARDS="intel"`
   * Also set `LIBVA_DRIVER_NAME="iHD"` for hardware video acceleration on Gen9+ Intel GPUs (used by `media-libs/libva-intel-media-driver`).
   * Identify your graphic card:
      * `lspci | grep -i VGA`
   * New intel graphic cards require a firmware:
      * `emerge sys-kernel/linux-firmware`
      * A corresponding firmware binary needs to be afterwards build into a kernel binary (check the Kernel guide).
   * Enable Vaapi via global use flag and install
      * `emerge media-libs/libva-intel-media-driver`
   * Verify the driver loads with `vainfo` (from `media-video/libva-utils`, already
     installed for VAAPI) — no extra package needed.
     * Optional live engine view: `emerge x11-apps/igt-gpu-tools` then `intel_gpu_top`
       (Video BUSY > 0% under playback confirms HW decode). This machine does **not**
       keep igt-gpu-tools installed — install it on demand if you want that view.
1. Set INPUT_DEVICES in _/etc/portage/make.conf_ based on your graphic card (check the X wiki):
   * `INPUT_DEVICES="libinput"`
   * _libunput_ is used by Intel cards and should be portage default, therefore no entry is required.
   * Verify what portage is using: `portageq envvar INPUT_DEVICES`
1. Set ACCEPT_LICENSE in _/etc/portage/make.conf_:
   * `ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE BUSL-1.1 Microsoft-vscode all-rights-reserved google-chrome"`
   * This accepts free + binary-redistributable licenses, plus the specific proprietary licenses needed by the installed apps (Terraform, VS Code, Slack/Zoom, Chrome). It is deliberately **not** a blanket `"*"`, so any *new* non-free package surfaces its license for an explicit decision. Add tokens as you install more proprietary software.
1. Set ACCEPT_KEYWORDS in _/etc/portage/make.conf_:
   * `ACCEPT_KEYWORDS="~amd64"` — this machine **deliberately runs the testing branch globally**, for the latest GNOME and developer tooling.
   * It's a conscious trade-off (more frequent updates for newest software). The recompile churn is kept manageable **without** going stable — via `-bin` packages for the heavyweights, managing language runtimes outside Portage (e.g. `mise`), `FEATURES="buildpkg ccache"`, and a weekly/biweekly update cadence. See [System Reference → Keyword strategy](08-system-reference.md#keyword-strategy-decided-stay-on-testing).
   * A stable base with per-package `~amd64` is the lower-churn alternative if you don't need latest-everything.
1. Set LINGUAS in _/etc/portage/make.conf_:
   * `LINGUAS=""` (setting to empty value, which is different than unset means only installing a default language for each package)
1. Save/preserve portage elogs:
   * `PORTAGE_ELOG_CLASSES="warn error info log qa"` (logs everything)
   * `PORTAGE_ELOG_SYSTEM="echo save"` (show messages after emerging and save them too)
1. Set EMERGE_DEFAULT_OPTS in _/etc/portage/make.conf_:
   * `EMERGE_DEFAULT_OPTS="--ask --verbose --deep --with-bdeps=y --tree --keep-going --changed-use --jobs 2 --load-average 14.4"`
      * `--jobs` is how many packages emerge builds **in parallel**, multiplied by `MAKEOPTS="-j16"` inside each — so keep `--jobs` modest (here `2`) to avoid `--jobs`×16 concurrent compiles exhausting RAM. `--load-average` caps total load regardless.
      * `--keep-going` lets a large `@world` run skip a failed package and finish the rest (rather than aborting the whole set), and `--changed-use` rebuilds packages whose effective USE flags changed even when the version didn't — both matter on a `~amd64` box with frequent updates.
      * A rule of thumb for _--load-average_ is to set X.Y=N*0.9 which will limit the load to 90%, thus maintaining system  responsiveness, where N is the number of processor cores
1. Restrict Intel microcode to this CPU and enable binary package caching:
   * `MICROCODE_SIGNATURES="-s 0x000906a3"` (trims `intel-microcode` to this CPU's signature; find yours via `iucode_tool -S` or `grep microcode /proc/cpuinfo`)
   * `FEATURES="buildpkg ccache"`
      * `buildpkg` saves a binary package of everything built (to `/var/cache/binpkgs`), so rebuilds/reinstalls are fast. This is the **active** local binpkg mechanism — the stock `binrepos.conf` binhost stub is inert (`getbinpkg` is not enabled and `PORTAGE_BINHOST` is empty).
      * `ccache` caches object files so recompiles after USE-flag or toolchain changes are much faster. It needs `dev-util/ccache` installed; compiler shims live in `/usr/lib/ccache/bin`.
1. Configure ccache, build niceness, and the install mask in _/etc/portage/make.conf_:
   * `CCACHE_DIR="/var/cache/ccache"` and `CCACHE_SIZE="20G"` — a shared, group-writable cache capped at 20 GiB (Portage also writes `/var/cache/ccache/ccache.conf` with `max_size = 20G`). Note that running `ccache -p`/`ccache -s` as a normal user shows the *unprivileged* default (`~/.cache/ccache`, 5 GiB) — that is **not** what Portage uses.
   * `PORTAGE_NICENESS=15` — nices builds so the desktop stays responsive while compiling.
   * `INSTALL_MASK="/usr/share/gtk-doc /usr/share/doc/*/html"` — skips bulky API HTML docs (man pages and licenses are kept).

# Configure Kernel

1. Install firmware:
   * `emerge sys-kernel/linux-firmware`
      * Required by most graphic cards incl. Intel, but can be also required for WIFI card to work, etc.
      * Firmware binaries need to be built into kernel by configuring the _CONFIG_EXTRA_FIRMWARE_ option. Latest Intel firmware is however installed automatically and doesn't any specific firmware configuration in the kernel config file.
      * Check also https://wiki.gentoo.org/wiki/Intel
   * `emerge sys-firmware/sof-firmware`
      * sound driver required by Intel devices
   * `emerge sys-firmware/intel-microcode`
      * CPU firmware updates for Intel CPUs
      * Check https://wiki.gentoo.org/wiki/Intel_microcode
1. Option 1: Full manual configuration and compilation (old, not recommended):
   * Install kernel sources:
      * `emerge --ask sys-kernel/gentoo-sources`
   * Set /usr/src/linux symlink to the installed kernel:
      * `eselect kernel list`
      * `eselect kernel set 1`
   * Check the PC hardware and what drivers are currently in use on Ubuntu live OS:
      * `emerge sys-apps/pciutils` (contains _lspci_ utility)
      * `lspci -k` (displays the HW with kernel drivers in use)
      * `emerge usbutils` (contains _lsusb_ utility)
      * `lsusb` (displays more HW info to USB)
      * `lsmod` (displays currently loaded kernel modules)
         * TODO: check: A very easy way to manage the kernel is to first install [sys-kernel/gentoo-kernel-bin (https://packages.gentoo.org/packages/sys-kernel/gentoo-kernel-bin) and use the [sys-kernel/modprobed-db (https://packages.gentoo.org/packages/sys-kernel/modprobed-db) to collect information about what the system requires.
   * Configure kernel:
      * Copy .config file from previous system or Ubuntu live (found under _/boot/_ directory or use _zcat /proc/config.gz_):
         * `cp /usr/src/linux/.config /mnt/gentoo/usr/src/linux/.config`
      * Or create a new config from:
         * `make defconfig` (creates a default config for the given architecture, requires a lot of configuration afterwards)
         * `make allmodconfig` (creates a config with all modules enabled, should work always theoretically, but in practice, it probably won't)    
      * Afterwards execute one of (choose as you like):
         * `make olddefconfig` (takes the existing config file as its and applies default values for new entries)
         * `make oldconfig` (takes the existing config file as its and prompts/ask for new or changed entries)
         * `make localmodconfig` (creates a config based on the currently loaded modules, needs an existing config file as a base, might not work perfectly)
         * `make nconfig` (for additional manual configuration)
   * Compile kernel and modules:
      * `make && make modules_install`
   * Install kernel (to /boot/):
      * `emerge sys-kernel/installkernel` (this is now required so that make install will create a "versioned" image under /boot during installation)
      * `make install`
   * Generate initrams
      * `emerge genkernel`
      * `genkernel --luks --lvm initramfs` (required parameters for an encrypted root fs)
1. Option 2 (preferred, and what this guide uses): Distribution kernel with dracut:
   * Set up `installkernel` to drive GRUB + dracut. In `/etc/portage/package.use`:
      * `sys-kernel/installkernel grub dracut`
   * Configure dracut for the encrypted LVM root in `/etc/dracut.conf.d/10-local.conf`:
      * ```
        hostonly="yes"
        hostonly_cmdline="no"
        add_dracutmodules+=" crypt dm lvm resume "
        force_drivers+=" nvme "
        ```
      * `crypt dm lvm` pull in LUKS/LVM unlocking; `resume` enables hibernation from swap; `force_drivers+=" nvme "` guarantees the NVMe driver is in the initramfs.
   * Customize the kernel config via drop-in snippets in `/etc/kernel/config.d/` (each file is a diff against the dist-kernel default config):
      * `10-firmware.config` — build Intel microcode into the image:
        * ```
          CONFIG_EXTRA_FIRMWARE="intel-ucode/06-9a-03"
          CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"
          ```
      * Optional local tuning (e.g. `90-<hostname>.config`) — `CONFIG_X86_NATIVE_CPU`, `NR_CPUS=16`, zstd image/module compression, `ZSWAP_DEFAULT_ON`, BBR+fq networking, RCU lazy/nocb for battery. See [System Reference](08-system-reference.md#kernel) for the full snippet.
        * To make `NR_CPUS=16` actually take effect you must **also** disable MAXSMP in the same snippet (`# CONFIG_MAXSMP is not set`); the dist-kernel sets `CONFIG_MAXSMP=y`, which force-locks `NR_CPUS=8192` and silently overrides your value.
   * Compile and install the kernel — `installkernel` builds the initramfs with dracut and installs both under `/boot`, then runs `grub-mkconfig` automatically:
      * `emerge gentoo-kernel`
   * If you need to regenerate GRUB config manually:
      * `grub-mkconfig -o /boot/grub/grub.cfg`

# Configure FSTAB

1. Edit _etc/fstab_ with:
   * ```
     UUID=E782-4A0E					/boot			vfat	umask=0077		0 2
     UUID=501eeb58-907b-405a-91af-77f523c8d92e	none			swap	sw			0 0
     UUID=4384aae9-0956-4c11-a39d-374506d3e09c	/			ext4	defaults,noatime	0 1
     tmpfs	/var/tmp/portage	tmpfs	size=20G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev	0 0

     # btrfs pool on vg0-btrfs (UUID 048292a5-…) — Stage 1 migration 2026-06-20
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data1			btrfs	noatime,compress=zstd:3,subvol=@data1			0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data1/.snapshots	btrfs	noatime,compress=zstd:3,subvol=@data1_snapshots		0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data2			btrfs	noatime,compress=zstd:3,subvol=@data2			0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data2/.snapshots	btrfs	noatime,compress=zstd:3,subvol=@data2_snapshots		0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data3			btrfs	noatime,compress=zstd:3,subvol=@data3			0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data3/.snapshots	btrfs	noatime,compress=zstd:3,subvol=@data3_snapshots		0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data4			btrfs	noatime,compress=zstd:3,subvol=@data4			0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data4/.snapshots	btrfs	noatime,compress=zstd:3,subvol=@data4_snapshots		0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data5			btrfs	noatime,subvol=@data5					0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/data5/.snapshots	btrfs	noatime,subvol=@data5_snapshots				0 0
     UUID=048292a5-5607-449a-9247-92aad183be1f	/var/tmp/portage-big	btrfs	noatime,nodatacow,subvol=@portage_build			0 0
     ```
      * get UUIDs with `blkid`
      * `data1`–`data5` are **not separate ext4 LVs** anymore — they are Btrfs subvolumes (`@data1`…`@data5`) sharing a single large LV (`vg0-btrfs`, label `pool`), with a sibling `@dataN_snapshots` subvolume per area for snapper. This replaced the old five-ext4-LV layout in the 2026-06-20 migration (the pre-migration fstab is preserved, e.g. `/var/lib/system-changes/etc/fstab.pre-btrfs.*`). Btrfs tooling and the snapshot/swap layers (`sys-fs/btrfs-progs`, `app-backup/snapper` on `data1`, and `sys-apps/zram-generator` for compressed RAM swap) are installed in the [recreate runbook](00-recreate-this-system.md), with the verbatim config recorded in the [System Reference → Disk layout](08-system-reference.md#disk-layout).
      * `compress=zstd:3` is set on `data1`–`data4` (and their `.snapshots`). `data5` deliberately omits `compress=` in fstab (for already-compressed/incompressible data); the kernel still reports `compress=zstd:3` there only because the fs-wide mount established it. The kernel also applies `ssd,discard=async,space_cache=v2` automatically — those are **not** written in fstab.
      * The `tmpfs` line builds packages in RAM for speed. Keep `size` **below** total RAM (20 GiB here, on a 32 GiB machine) so a large build can't exhaust memory.
      * `/var/tmp/portage-big` is a disk-backed Btrfs subvolume (`@portage_build`, mounted `nodatacow` to avoid CoW churn during builds). Packages whose build dir exceeds the tmpfs are routed here by setting `PORTAGE_TMPDIR=/var/tmp/portage-big` in `/etc/portage/env/bigbuild.conf` and listing them in `/etc/portage/package.env` (webkit-gtk, llvm, clang, gcc, nodejs, plus forward-looking qtwebengine/chromium/rust/libreoffice).

# Configure Systemd

1. Basic system configuration:
   * `systemd-machine-id-setup` 
   * `systemd-firstboot --prompt` 
   * `systemctl preset-all`
   * `hostnamectl set-hostname <hostname>` (this guide's example: `ivmr-laptop`)
   * `localectl set-keymap us`
   * `localectl set-locale LANG=C.UTF8 LC_TIME=en_GB.UTF-8 LC_PAPER=en_GB.UTF-8 LC_MEASUREMENT=en_GB.UTF-8 LC_MONETARY=en_GB.UTF-8 LC_NUMERIC=en_GB.UTF-8`
      * This guide uses a C/UTF-8 base locale with `en_GB` formats (24h clock, metric, ISO dates). Make sure the chosen locales are uncommented in `/etc/locale.gen`, then run `locale-gen`.
   * `timedatectl set-timezone Europe/Zurich`
1. Networking is managed by **NetworkManager** (with `systemd-resolved` for DNS). Install and enable it:
   * `emerge net-misc/networkmanager`
   * `systemctl enable NetworkManager.service`
   * `systemctl enable systemd-resolved.service`
1. Enable additional core services:
   * `systemctl enable lvm2-monitor.service` (LVM monitoring)
   * `systemctl enable systemd-timesyncd.service` (time synchronization)
   * (Further desktop/power/hardware services — `gdm`, `bluetooth`, `thermald`, `tlp`, `earlyoom`, `smartd`, `lm_sensors`, `docker`, `nftables` — are enabled in [After Installation](03-after-installation.md) as their packages are installed.)

Note: _/etc/crypttab_ configuration is not required — dracut unlocks LUKS from the kernel command line (`rd.luks.uuid=`).

# Configure Bootloader

1. Install grub package:
   * `emerge sys-boot/grub`
      * Make sure _GRUB_PLATFORMS="efi-64"_ is enabled. If not execute: `echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf`
1. Install grub to the EFI partition:
   * `grub-install --efi-directory=/boot`
   * In this layout `/boot` **is** the unencrypted EFI System Partition, and it holds the kernel + initramfs. GRUB loads them directly — it does **not** need to decrypt anything. The dracut-generated initramfs then unlocks the LUKS container at boot. (Because GRUB never touches the encrypted volume here, the earlier LUKS2/argon2id GRUB limitation is irrelevant for `/boot` itself — but it is still why the root container uses `pbkdf2`; see [Disk Preparation](01-before-installation.md#encrypt-a-partition-for-target-os).)
1. Update the GRUB configuration in _/etc/default/grub_ with a **dracut-style** kernel command line:
   * `GRUB_CMDLINE_LINUX="dolvm rd.luks.options=discard rd.luks.uuid=<luks-container-uuid> root=/dev/mapper/vg0-root init=/usr/lib/systemd/systemd resume=UUID=<swap-uuid> acpi_backlight=native i915.enable_dpcd_backlight=1"`
      * `rd.luks.uuid=` tells dracut which LUKS container to unlock (use the UUID of the **encrypted partition itself**, e.g. `nvme0n1p3`); `resume=UUID=` points at the swap volume for hibernation; the two backlight params fix display brightness control on this HP/Intel laptop.
      * Get all UUIDs with `blkid`. (Note the older `crypt_root=`/`crypt_swap=` form is for genkernel initramfs — this guide uses dracut, so use `rd.luks.*`.)
      * **Do not** add `mem_sleep_default=deep` here. An earlier iteration of this cmdline carried it, but it was deliberately dropped (2026-06-16) when switching to **suspend-then-hibernate** (s2idle first, RTC-wake to hibernate later — see `/etc/systemd/sleep.conf.d/10-hibernate.conf`); forcing `deep` (S3) is incompatible with that flow. A `/etc/default/grub.bak-presuspend` backup preserves the old line.
   * Also set `GRUB_TIMEOUT=2` and `GRUB_DISTRIBUTOR="Gentoo"` as desired.
1. Generate the GRUB configuration:
   * `grub-mkconfig -o /boot/grub/grub.cfg`
      * This is correct, don't point to to _/boot/EFI/gentoo/_.

### Planned improvement: signed UKI + Secure Boot (drop GRUB)

The current boot chain has one structural weakness: GRUB loads an **unsigned** kernel + dracut initramfs from the **unencrypted** ESP, and there is no Secure Boot. Anyone with brief physical access could tamper with those boot artifacts (an "evil-maid" attack) and the machine would boot the modified image without complaint. This is also *why* the root LUKS2 container uses `pbkdf2` rather than the stronger `argon2id` — GRUB can only open a `pbkdf2` header (see [Before Installation → Encrypt](01-before-installation.md#encrypt-a-partition-for-target-os)).

> **Now:** GRUB on the unencrypted ESP loads an unsigned `gentoo-kernel` + dracut initramfs; the initramfs then unlocks the `pbkdf2` LUKS2 container from `rd.luks.uuid=`. No Secure Boot. The `generic-uki` and `secureboot` dist-kernel USE flags are **OFF**.
>
> **Next iteration:** build a **signed Unified Kernel Image** (kernel + initramfs + cmdline in one PE binary on the ESP) instead of separate files under GRUB — either via `sys-kernel/installkernel` configured for a UKI/secureboot setup, or by enabling the dist-kernel `generic-uki` + `secureboot` USE flags on `sys-kernel/gentoo-kernel`. Enroll your own Secure Boot keys (MOK/db), sign the UKI, and turn Secure Boot **on** in firmware. Optionally add TPM2 auto-unlock via `systemd-cryptenroll --tpm2-device=auto` so the disk opens automatically when the boot chain is unmodified — but keep the **passphrase mandatory** and enroll a **mandatory recovery key** as well, so a firmware update or TPM PCR change can never lock you out. With GRUB gone, the `pbkdf2` constraint disappears too, so the LUKS header can be re-keyed to **`argon2id`** (`cryptsetup luksConvertKey --pbkdf argon2id`).
>
> **Why:** closes the unsigned-boot / evil-maid gap — Secure Boot refuses to run a tampered image, and TPM2 will only release the unlock secret if the measured boot chain is unchanged. The passphrase + recovery key stay mandatory so TPM2 is a *convenience*, never a single point of failure. The target shape is: FAT32 ESP holding only a **signed UKI** (no separate `/boot`), LUKS2 (`argon2id`) over LVM over Btrfs, Secure Boot enabled.

# User configuration

1. Set root user password:
   * `passwd`
1. Add personal user (this guide's example user is `ivmr`):
   * `useradd -m -G users,wheel,audio,video,usb,systemd-journal,plugdev,docker,mail -s /bin/bash <user>`
   * `passwd <user>`
   * `plugdev`, `docker`, and `mail` line up with packages installed later — `plugdev` for removable-device access (also added by the GNOME step below), `docker` for rootless/socket access to the Docker daemon, and `mail` for the local mail path (msmtp/sendmail). Add them now or `gpasswd -a <user> <group>` once those packages exist.

# Reemerge @world

1. Optional: Recompile all packages (@world and @system) with the current portage parameters and against the new kernel configuration:
   * `emerge -e --newuse @world`
   * `emerge --depclean`

# Install Gnome

1. `emerge gnome-light`
1. `env-update && source /etc/profile`
1. `gpasswd -a <user> plugdev` (this guide's example: `ivmr`)
1. `systemctl enable gdm.service`

---

[← Documentation index](README.md) · Prev: [Before Installation](01-before-installation.md) · Next: [After Installation →](03-after-installation.md)
