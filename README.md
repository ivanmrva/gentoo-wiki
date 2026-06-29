# Gentoo Linux Documentation

A personal, opinionated guide to installing and configuring Gentoo Linux on a
laptop with full-disk encryption (LUKS + LVM), systemd, GNOME and an Intel
platform. A single **Btrfs pool** (on LUKS2 + LVM) holds **root (`@`) and data**
as subvolumes — with Snapper snapshots, `grub-btrfs` snapshot-boot, and zram swap.

📖 **Start here: [docs/](docs/README.md)** — or jump straight to the
[step-by-step recreate/migrate runbook](docs/00-recreate-this-system.md).

1. [Before Installation](docs/01-before-installation.md)
2. [Installation](docs/02-installation.md)
3. [After Installation](docs/03-after-installation.md)
4. [Application Configuration](docs/04-application-configuration.md)
5. [Troubleshooting](docs/05-troubleshooting.md)

Reference: [System Reference](docs/08-system-reference.md) (incl. the
[roadmap](docs/08-system-reference.md#roadmap--live-machine-status)) ·
[Backup, clone & restore](docs/09-backup-restore.md) ·
[Access System from a Live USB](docs/06-access-system-from-live-usb.md) ·
[Various Tasks](docs/07-various-tasks.md)

> Adapt device names, UUIDs, and hardware-specific flags to your own machine.
> Where this guide intentionally diverges from the
> [official Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page),
> it says so. Corrections and pull requests welcome.
