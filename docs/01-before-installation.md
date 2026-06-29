# Create a bootable Ubuntu USB

1. Download Ubuntu Desktop ISO from Ubuntu webpage.
1. `fdisk -l`
   * check for USB device name
1. Make sure the USB is unmounted:
   * `sudo umount /dev/sdb`
1. `sudo dd if=~/Downloads/ubuntu.iso of=/dev/sdb bs=4M status=progress oflag=sync`
   * Refer to a whole drive here, not a partition (e.g., _/dev/sdb_ instead of _/dev/sdb1_)
1. Eject the device:
   * `sudo eject /dev/sdb`

# Live Linux OS Installation Prerequisites 

1. Make sure the current kernel supports dm-crypt
   * https://wiki.gentoo.org/wiki/Dm-crypt#Configuration
1. Install _cryptsetup_ and _lvm2_ (Ubuntu usually already have this pre-installed)

# Disk Preparation

* This setup assumes an already present boot EFI partition (currently in use). If setting up a new system, you will need to create this partition too (unencrypted) -> see the Gentoo handbook.

### Encrypt a Partition for Target OS

1. Prepare an empty unformatted partition (for example on _/dev/sda10_ or _/dev/nvme0n1p3_)
   * Check for available existing devices/partitions with `fdisk -l`
1. Encrypt the selected (empty) partition
   * Might be a good idea to perform a check before choosing the right encryption mechanism for the disk: `cryptsetup benchmark`
   * Encrypt the partition: `cryptsetup --pbkdf pbkdf2 -c aes-xts-plain64 -s 512 luksFormat /dev/nvme0n1p3` (modify _-c_ and _-s_ values according to the benchmark if needed)
      * **Important:** `--pbkdf pbkdf2` is required because GRUB cannot open a LUKS2 container that uses the modern default `argon2id` KDF. This is the trade-off for keeping `/boot` decryptable by GRUB. (This guide's actual header: LUKS2, `aes-xts-plain64`, 512-bit key, `pbkdf2`/`sha256`.)
   * Provide a passphrase
1. Verify created partition:
   * `cryptsetup luksDump /dev/nvme0n1p3`

### Setup LVM

1. Open the partition ("lvm" is our name, use the previous passphrase)
   * `cryptsetup luksOpen /dev/nvme0n1p3 lvm`
   * When the command finishes successfully, then a new device file called _/dev/mapper/lvm_ will be made available.
1. create physical volume group
   * `lvm pvcreate /dev/mapper/lvm`
1. Create volume group vg0:
   * `vgcreate vg0 /dev/mapper/lvm`
1. Create the logical volumes. This layout uses just **two** LVs — a swap LV for hibernation, and one big Btrfs pool that holds the **entire system *and* all data areas** as subvolumes (root included). There is **no separate root LV**:
   * `lvcreate -L 32G -n swap vg0`
      * Swap is a **separate LV sized = RAM** (32 GiB) so the machine can **hibernate**: the compressed RAM image is written here, inside the LUKS container, so it is encrypted at rest. zram can't hold a hibernation image, so this disk swap is kept even though zram is the primary runtime swap. Drop or shrink it if you never hibernate.
   * `lvcreate -l 100%FREE -n btrfs vg0` (one large volume — ~920 GiB here — taking the rest of the free space)
      * **Why no root LV:** the OS root lives in this same pool as the `@` subvolume, so root, `/home`, and every `/dataN` share one free-space pool instead of fixed-size partitions — and, crucially, the **root filesystem gains Btrfs snapshots** (a bad `emerge` or config edit rolls back in seconds instead of a reinstall).
   * There is no need to create a boot partition on laptops with Windows, since it already exists (fat32 file system, EFI + GPT partition table).
1. Create the filesystems:
   * `mkswap /dev/mapper/vg0-swap`
   * `mkfs.btrfs -L pool /dev/mapper/vg0-btrfs` (single-device btrfs; defaults give `data single`, `metadata DUP`)
1. Create the Btrfs subvolumes. Mount the pool somewhere temporary, create every subvolume, then unmount — `/etc/fstab` mounts each one by `subvol=` at its real mountpoint later:
   * `mkdir -p /mnt/pool && mount /dev/mapper/vg0-btrfs /mnt/pool`
   * **System + home** (these get Snapper snapshots):
      * `btrfs subvolume create /mnt/pool/@`               → `/` (the OS root)
      * `btrfs subvolume create /mnt/pool/@home`           → `/home`
      * `btrfs subvolume create /mnt/pool/@snapshots`      → `/.snapshots` (root snapshot store)
      * `btrfs subvolume create /mnt/pool/@home_snapshots` → `/home/.snapshots`
   * **Split deliberately *out* of the root snapshot** — so they are *not* rolled back with `/` (you keep logs across a rollback, and caches/build scratch never bloat a snapshot):
      * `btrfs subvolume create /mnt/pool/@var_log`        → `/var/log`
      * `btrfs subvolume create /mnt/pool/@var_cache`      → `/var/cache`
      * `btrfs subvolume create /mnt/pool/@var_tmp`        → `/var/tmp`
   * **Data areas** (only `data1` gets a Snapper config by default; the rest start with an empty `.snapshots`):
      * `for n in 1 2 3 4 5; do btrfs subvolume create /mnt/pool/@data$n; btrfs subvolume create /mnt/pool/@data${n}_snapshots; done`
   * **On-disk Portage build area** for builds that exceed the RAM tmpfs:
      * `btrfs subvolume create /mnt/pool/@portage_build`  → `/var/tmp/portage-big`
   * `umount /mnt/pool`
   * `/opt` and `/usr/local` are intentionally **not** split out — they stay inside `@` so they roll back together with the system. The rule: split a subvolume off `@` only for things you *don't* want reverted by a root rollback (logs, caches, build scratch, `/home`, bulk data).
   * **No per-area sizing:** every subvolume draws from the same ~920 GiB pool, so `/`, `/home`, and each `/dataN` grow until the whole pool is full — no fixed capacity walls. Mount options (compression, `nodatacow`) are set in `/etc/fstab`, not here.
1. Verify LVM setup:
   * `lvdisplay`

# Open LVM volumes after reboot on live USB

To access an encrypted disk from a live USB, execute:

1. `cryptsetup luksOpen /dev/nvme0n1p3 lvm`
1. `vgscan --cache`
1. `vgchange -a y`

---

[← Documentation index](README.md) · Next: [Installation →](02-installation.md)
