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
         * `sudo mount --types proc /proc /mnt/gentoo/proc && sudo mount --rbind /sys /mnt/gentoo/sys && sudo mount --make-rslave /mnt/gentoo/sys && sudo mount --rbind /dev /mnt/gentoo/dev && sudo sudo mount --make-rslave /mnt/gentoo/dev && sudo mount --bind /run /mnt/gentoo/run && sudo mount --make-slave /mnt/gentoo/run`
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
   * Verify once all installed if hardware encoding/decoding is used with:
     * `emerge x11-apps/igt-gpu-tools`
     * `intel_gpu_top`
        * Video BUSY on 0% means that hardware decoding/encoding is not used.
1. Set INPUT_DEVICES in _/etc/portage/make.conf_ based on your graphic card (check the X wiki):
   * `INPUT_DEVICES="libinput"`
   * _libunput_ is used by Intel cards and should be portage default, therefore no entry is required.
   * Verify what portage is using: `portageq envvar INPUT_DEVICES`
1. Set ACCEPT_LICENSE in _/etc/portage/make.conf_:
   * `ACCEPT_LICENSE="*"` (accepting every license for every package at any version)
1. Set ACCEPT_KEYWORDS in _/etc/portage/make.conf_:
   * `ACCEPT_KEYWORDS="~amd64"` (allowing testing packages beeing installed, not just stable)
1. Set LINGUAS in _/etc/portage/make.conf_:
   * `LINGUAS=""` (setting to empty value, which is different than unset means only installing a default language for each package)
1. Save/preserve portage elogs:
   * `PORTAGE_ELOG_CLASSES="warn error info log qa"` (logs everything)
   * `PORTAGE_ELOG_SYSTEM="echo save"` (show messages after emerging and save them too)
1. Set EMERGE_DEFAULT_OPTS in _/etc/portage/make.conf_:
   * `EMERGE_DEFAULT_OPTS="--ask --verbose --deep --with-bdeps=y --tree --jobs 4 --load-average 14.4"`
      * `--jobs` is how many packages emerge builds **in parallel**, multiplied by `MAKEOPTS="-j16"` inside each — so keep `--jobs` modest (here `4`) to avoid 4×16 = 64 concurrent compiles exhausting RAM. `--load-average` caps total load regardless.
      * A rule of thumb for _--load-average_ is to set X.Y=N*0.9 which will limit the load to 90%, thus maintaining system  responsiveness, where N is the number of processor cores
1. Restrict Intel microcode to this CPU and enable binary package caching:
   * `MICROCODE_SIGNATURES="-s 0x000906a3"` (trims `intel-microcode` to this CPU's signature; find yours via `iucode_tool -S` or `grep microcode /proc/cpuinfo`)
   * `FEATURES="buildpkg"` (saves a binary package of everything built, so rebuilds/reinstalls are fast)

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
         * `make deconfig` (creates a default config for the given architecture, requires a lot of configuration afterwards)
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
   * Compile and install the kernel — `installkernel` builds the initramfs with dracut and installs both under `/boot`, then runs `grub-mkconfig` automatically:
      * `emerge gentoo-kernel`
   * If you need to regenerate GRUB config manually:
      * `grub-mkconfig -o /boot/grub/grub.cfg`

# Configure FSTAB

1. Edit _etc/fstab_ with:
   * ```  
     UUID=8330-6874				/boot			vfat	umask=0077		0 2
     UUID=501eeb58-907b-405a-91af-77f523c8d92e	none			swap	sw			0 0
     UUID=4384aae9-0956-4c11-a39d-374506d3e09c	/			ext4	defaults,noatime	0 1
     UUID=4eadf208-d701-489c-bf9f-74e90cba9df6	/data1			ext4	defaults,noatime	0 2
     UUID=65cf6a54-d5d7-4a8d-a6eb-e63ae39a15b5	/data2			ext4	defaults,noatime	0 2
     UUID=9adc7927-7432-47b6-b9cb-9a87b757784d  /data3			ext4	defaults,noatime	0 2
     UUID=a8b47f07-4b28-499f-aea0-47e168920f7a	/data4			ext4	defaults,noatime	0 2
     UUID=d470ac2b-8f98-4898-977e-525e56dfaff7	/data5			ext4	defaults,noatime	0 2
     tmpfs	/var/tmp/portage	tmpfs	size=32G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev	0 0
     ```
      * get UUIDs with `blkid`

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
   * Also set `GRUB_TIMEOUT=2` and `GRUB_DISTRIBUTOR="Gentoo"` as desired.
1. Generate the GRUB configuration:
   * `grub-mkconfig -o /boot/grub/grub.cfg`
      * This is correct, don't point to to _/boot/EFI/gentoo/_.

# User configuration

1. Set root user password:
   * `passwd`
1. Add personal user (this guide's example user is `ivmr`):
   * `useradd -m -G users,wheel,audio,video,usb,systemd-journal -s /bin/bash <user>`
   * `passwd <user>`

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
