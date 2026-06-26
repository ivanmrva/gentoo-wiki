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
1. Create the logical volumes. This guide's current layout (after the **Stage 1 btrfs migration 2026-06-20**) is just **three** LVs — root, swap, and one big btrfs volume that holds all data areas as subvolumes:
   * `lvcreate -L 100G -n root vg0`
   * `lvcreate -L 32G -n swap vg0`
      * Swap stays a **separate LV** sized equal to RAM (32 GiB) to support **hibernation** — the compressed RAM image is written here, and it lives inside the LUKS container so the hibernation image is encrypted at rest. zram alone can't hold a hibernation image, so this disk swap is kept even though zram is the primary runtime swap. Without hibernation a smaller swap is fine.
   * `lvcreate -l 100%FREE -n btrfs vg0` (one large volume — ~820 GiB here — that takes the rest of the free space)
      * There used to be five fixed-size ext4 LVs here (`data1`–`data5`, 100 GiB each plus the remainder). Those are **gone**: `data1`–`data5` are now btrfs subvolumes inside this single LV, so they share one free-space pool instead of being pre-partitioned. The pre-migration fstab is preserved at `/var/lib/system-changes/etc/fstab.pre-btrfs.*` if you need the old extents.
   * There is no need to create a boot partition on laptops with Windows, since it already exists (fat32 file system, EFI + GPT partition table)
1. Create file systems on the previously created volumes
   * `mkfs.ext4 /dev/mapper/vg0-root`
   * `mkswap /dev/mapper/vg0-swap`
   * `mkfs.btrfs -L pool /dev/mapper/vg0-btrfs` (single-device btrfs; defaults give `data single`, `metadata DUP`)
1. Create the btrfs subvolumes inside the pool. Mount the new filesystem somewhere temporary, create the subvolumes, then unmount — fstab later mounts each one by `subvol=` at its real mountpoint:
   * `mkdir -p /mnt/pool && mount /dev/mapper/vg0-btrfs /mnt/pool`
   * `for n in 1 2 3 4 5; do btrfs subvolume create /mnt/pool/@data$n; btrfs subvolume create /mnt/pool/@data${n}_snapshots; done`
      * `@data1`–`@data5` → `/data1`–`/data5`; each `@dataN_snapshots` → `/dataN/.snapshots` (snapper's snapshot store — only `data1` actually gets a snapper config; the rest start empty).
   * `btrfs subvolume create /mnt/pool/@portage_build` → mounted at `/var/tmp/portage-big` (disk-backed Portage build area for builds that exceed the tmpfs)
   * `umount /mnt/pool`
   * **No per-area fixed sizing:** every subvolume draws from the same ~820 GiB pool, so any data area can grow until the whole pool is full — there are no per-`data*` capacity walls like the old ext4 LVs had. Mount options (compression, `nodatacow`, etc.) are set later in `/etc/fstab`, not here.
1. Verify LVM setup:
   * `lvdisplay`

# Open LVM volumes after reboot on live USB

To access an encrypted disk from a live USB, execute:

1. `cryptsetup luksOpen /dev/nvme0n1p3 lvm`
1. `vgscan --cache`
1. `vgchange -a y`

---

[← Documentation index](README.md) · Next: [Installation →](02-installation.md)
