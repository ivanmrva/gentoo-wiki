# Gentoo Linux Documentation

A personal, opinionated guide to installing and configuring Gentoo Linux on a
laptop with full-disk encryption (LUKS + LVM), systemd, GNOME and an Intel
platform. Root is ext4 on LVM, with a Btrfs data pool (Snapper snapshots) and
zram swap — the machine was Btrfs-migrated, it is no longer pure ext4. The steps
reflect a working real-world setup rather than a generic handbook — adapt device
names, UUIDs, and hardware-specific flags to your own machine.

> These notes assume familiarity with the [official Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page).
> Where this guide intentionally diverges from the handbook, it says so.

## Conventions

Commands use `<placeholders>` for values you must substitute. For reference, the
concrete values this guide was written against (the author's machine — an HP
ZBook Firefly G9) are shown alongside as examples:

| Placeholder | Example (this guide) | How to find yours |
| --- | --- | --- |
| `<user>` | `ivmr` | your login username |
| `<hostname>` | `ivmr-laptop` | your chosen hostname |
| `<crypt-partition>` | `/dev/nvme0n1p3` | `fdisk -l` (the empty partition to encrypt) |
| `<efi-partition>` | `/dev/nvme0n1p1` | `fdisk -l` (the fat32 EFI partition) |
| disk/partition UUIDs | the values in the fstab/GRUB samples | `blkid` |

The fstab and GRUB samples keep the author's real UUIDs as a realistic example —
**replace them with the output of `blkid` on your own machine.**

## Contents

**Start here:** [Recreating this system — step by step](00-recreate-this-system.md)
is the ordered runbook, with two paths: a fresh install from scratch, or
migrating an existing Gentoo onto this configuration. The pages below are the
detailed reference it links into.

The guide follows the installation flow top to bottom:

1. [Before Installation](01-before-installation.md) — bootable USB, disk
   encryption, LVM, and filesystem preparation.
2. [Installation](02-installation.md) — stage3, chroot, Portage, kernel, fstab,
   systemd, bootloader, users, and GNOME.
3. [After Installation](03-after-installation.md) — sudo, services, GNOME
   tweaks, Intel VAAPI, power management, and Portage-over-git sync.
4. [Application Configuration](04-application-configuration.md) — Docker,
   IntelliJ IDEA, and other applications.
5. [Troubleshooting](05-troubleshooting.md) — fixes for common Wi-Fi and other
   issues.

### Reference

- **[System Reference](08-system-reference.md)** — a full snapshot of the actual
  running machine (hardware, verbatim `make.conf`, kernel tuning, partition
  layout, enabled services, and the complete installed-package list) so it can
  be recreated exactly.
- **[Backup, clone & restore](09-backup-restore.md)** — the backup architecture
  (restic system + `/data1` backup to a single cloud as two encrypted repos,
  Snapper local Btrfs snapshots of `/data1`, config versioning, bootstrap
  secrets — the old rclone data sync is retired) and step-by-step restore/clone
  procedures.
- **[Roadmap — the ideal next iteration](08-system-reference.md#roadmap--the-ideal-next-iteration)**
  (in the System Reference) ties together the planned improvements — root on
  Btrfs `@` with system snapshots, signed UKI + Secure Boot, and a second
  independent cloud backup — each detailed inline in the doc that owns it. The
  Btrfs data pool + Snapper are already implemented (2026-06-20 migration); these
  docs describe the current setup *and* where it's heading.
- [Access System from a Live USB](06-access-system-from-live-usb.md) — unlock
  an encrypted disk and chroot in for recovery.
- [Various Tasks](07-various-tasks.md) — fonts, BIOS updates, and other
  one-off tasks.

## Contributing

Found something out of date or have a better default? Open an issue or a pull
request — corrections and hardware-specific notes are welcome.
