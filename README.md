# Laptop setup: Gentoo and NixOS

Personal, opinionated documentation of the author's laptop setups.

| Folder | What |
| --- | --- |
| **[gentoo/](gentoo/README.md)** | The current Gentoo Linux installation (HP ZBook Firefly G9): full-disk encryption (LUKS + LVM), a single Btrfs pool, systemd, GNOME, Snapper and restic backups. Includes the step-by-step [recreate/migrate runbook](gentoo/00-recreate-this-system.md), the [System Reference](gentoo/08-system-reference.md), [backup & restore](gentoo/09-backup-restore.md), and the `::local` overlay in [gentoo/local-overlay/](gentoo/local-overlay/). |
| **[nixos/](nixos/README.md)** | Its successor on the HP ZBook 8 G1i 14": the [installation guide](nixos/install/README.md) and the [daily operations guide](nixos/operations/README.md), plus `nixos/tools/md2pdf.sh` to render them as PDFs. |

> Adapt device names, UUIDs, and hardware-specific flags to your own machine.
> Where the Gentoo guide intentionally diverges from the
> [official Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page),
> it says so. Corrections and pull requests welcome.
