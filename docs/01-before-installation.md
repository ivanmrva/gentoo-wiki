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
   * Encrypt the partition: `cryptsetup -c aes-xts-plain64 -s 512 luksFormat /dev/nvme0n1p3` (modify _-c_ and _-s_ values according to the benchmark if needed)
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
1. Create logical volume for _/root_ and other logical partitions (i.e. _/data_, etc.):
   * `lvcreate -L 100G -n root vg0`
   * `lvcreate -L 32G -n swap vg0`
      * Recommended size for swap: Nowadays, having systems with plenty of memory, it may be sufficient to create a swap partition smaller than the available memory. When using hibernation, storing a compressed RAM image inside the swap partition, it's a good idea to have a swap partition with the size of the installed memory.
   * `lvcreate -L 100G -n data1 vg0`
   * `lvcreate -l 100%FREE -n data2 vg0` (using rest of free space)
   * There is no need to create a boot partition on laptops with Windows, since it already exists (fat32 file system, EFI + GPT partition table)
1. Create file systems on the previously created partitions
   * `mkfs.ext4 /dev/mapper/vg0-root`
   * `mkfs.ext4 /dev/mapper/vg0-data1`
   * `mkfs.ext4 /dev/mapper/vg0-data2`
   * `mkswap /dev/mapper/vg0-swap`
1. Verify LVM setup:
   * `lvdisplay`

# Open LVM volumes after reboot on live USB

To access an encrypted disk from a live USB, execute:

1. `cryptsetup luksOpen /dev/nvme0n1p3 lvm`
1. `vgscan --cache`
1. `vgchange -a y`

---

[← Documentation index](README.md) · Next: [Installation →](02-installation.md)
