# Open LVM volumes after reboot on live USB

To access an encrypted disk from a live USB, execute:

1. `cryptsetup luksOpen /dev/nvme0n1p3 lvm`
1. `vgscan --cache`
1. `vgchange -a y`

# Chrooting

1. Create a directory for the new Gentoo installation and mount the root LVM volume to it:
   * `mkdir /mnt/gentoo`
   * `mount /dev/mapper/vg0-root /mnt/gentoo`
1. Copy DNS info (to ensure Internet is working once chrooted to _/mnt/gentoo_):
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
   * `mount /dev/nvme0n1p1 /boot`

---

[← Documentation index](README.md)
