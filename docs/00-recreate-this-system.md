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

> Before anything, read the [Conventions](README.md#conventions): commands use
> `<placeholders>` (username, hostname, partitions, UUIDs) — substitute your
> own. The full target state is captured in the
> [System Reference](08-system-reference.md).

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
3. Inside it, create the `vg0` volume group and logical volumes: `root` (100G),
   `swap` (= RAM, for hibernation), and `data1`–`data5`.
4. `mkfs.ext4` the volumes; `mkswap` the swap.

### 2. Unpack stage3 and chroot → [02 · Stage3 / Chrooting](02-installation.md#stage3-installation)

What this means: you drop the base Gentoo system onto the new root and enter it
as if it were already booted.

1. Mount `vg0-root` at `/mnt/gentoo`, download + verify + unpack the
   **amd64 desktop systemd** stage3.
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
   `ACCEPT_LICENSE`, and `FEATURES="buildpkg"`.
3. **Keyword decision:** this machine runs `~amd64` globally; the recommended
   alternative is a stable base + a short
   [`package.accept_keywords`](08-system-reference.md#best-practice-notes) list.
4. Set the `tmpfs` build dir to **16 GiB** (below RAM) in fstab (step 5).

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

1. **fstab** — all volumes by UUID (`blkid`) + the 16 GiB portage tmpfs.
2. **systemd** — machine-id, hostname, **locale (`C.UTF8` + `en_GB` formats)**,
   timezone; enable `NetworkManager`, `systemd-resolved`, `systemd-timesyncd`,
   `lvm2-monitor`.
3. **GRUB** — `grub-install --efi-directory=/boot`, then a **dracut-style**
   `GRUB_CMDLINE_LINUX` (`rd.luks.uuid=`, `resume=`, backlight params).
4. **User** — create your account in the right groups; set passwords.
5. **GNOME** — `emerge gnome-light`, enable `gdm`.

### 6. Reboot, then post-install → [03](03-after-installation.md) & [04](04-application-configuration.md)

1. Exit chroot, unmount, reboot, remove the USB.
2. [After Installation](03-after-installation.md): sudo, PipeWire audio, VAAPI,
   power management (thermald + TLP), and the rest of the services.
3. [Application Configuration](04-application-configuration.md): install your
   app set (see the full [@world list](08-system-reference.md#installed-applications-the-world-set))
   and configure Docker, printing, backups, etc.
4. Optional: rebuild everything against the final flags — `emerge -e @world`,
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
   `VIDEO_CARDS`/`LIBVA_DRIVER_NAME`, `MICROCODE_SIGNATURES`, `FEATURES`,
   `ACCEPT_LICENSE`. Decide on keywords (stable + accept_keywords vs global
   `~amd64`).
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
6. **Apps & services** — `emerge` the
   [@world set](08-system-reference.md#installed-applications-the-world-set);
   enable the [services](08-system-reference.md#enabled-services).
7. **Clean up** — `emerge --depclean`, `eclean-kernel`, reboot, verify.

> Migrating the **disk encryption / partition layout** (e.g. moving an
> unencrypted install onto LUKS+LVM) can't be done in place — back up your data
> and follow Path A.

---

[Documentation index →](README.md) · Next: [Before Installation →](01-before-installation.md)
