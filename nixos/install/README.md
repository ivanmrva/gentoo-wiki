# NixOS on the HP ZBook

A step-by-step guide to installing NixOS on the HP ZBook 8 G1i 14"
(**A3ZU5ET#ABD**: Core Ultra 9 285H, 2×32 GB DDR5, Arc 140T, Intel BE201
Wi-Fi 7). NixOS replaces the preinstalled Windows. The setup is flake-based,
with an impermanent root in RAM, btrfs on LUKS2 with TPM2+PIN, your own
Secure Boot keys, hibernation, and GNOME on Wayland.

It is the NixOS counterpart to the Gentoo guide in [gentoo/](../../gentoo/README.md).
The design follows the **live Gentoo machine**, not the older wiki pages:
the user is `ivmr`, `~/claude-code` stays where it is, and the data areas
are personal, work, media and backup.

| Component | Choice |
| --- | --- |
| Channel | nixos-unstable via flake, pinned in `flake.lock` |
| Disk | 2 GiB ESP + LUKS2 container with btrfs subvolumes |
| Root (`/`) | tmpfs; state declared in `/persist` via the Preservation module |
| Boot | lanzaboote (UKI, own Secure Boot keys, Microsoft keys kept) |
| Unlock | TPM2 bound to PCR 7 + PIN; recovery key offline |
| Kernel | `linuxPackages_latest`, stock config plus parameters (no custom build) |
| Hardware | nixos-facter report (automatic driver/firmware detection) |
| Time | ntpd-rs with NTS (authenticated time) |
| Desktop | GNOME without bundled apps, GDM, Wayland |
| Sleep | zswap + 64 GiB swapfile; suspend-then-hibernate after 90 min on battery |
| Backups | btrbk snapshots (local) + restic to Google Drive (offsite), split into backup/prune/check jobs |
| Monitoring | ntfy push on any failed unit, healthchecks.io dead-man's switch, daily quiet system report, `sysdiag` snapshot for Claude Code |

> [!NOTE]
> **How to use this guide.** Work through the chapters in order. Every
> configuration file is a starting point written for this design, not a
> tested image. Build-check it on Gentoo ([Phase 0](00-prepare-on-gentoo.md))
> before install day. NixOS option names change over time. If evaluation
> reports an unknown or renamed option, look it up in `man configuration.nix`
> or at search.nixos.org/options rather than guessing.

> [!WARNING]
> **Point of no return:** [Phase D, step D2](07-installation.md#d2-partition-and-format)
> erases the entire SSD, including Windows and the HP recovery partition. Do
> not run it before [Phase A](01-windows-preparation.md) is complete.

## Phases

| Phase | Where | What |
| --- | --- | --- |
| 0 | Current machine (Gentoo) | Nix, repo, VM test, home-manager, secrets, CI, installer ISO, pre-wipe export |
| A | Windows + live USB | Firmware updates, recovery media, live test, hardware report |
| B | Any machine with Nix | Write and build-check the flake repository |
| C | HP BIOS (F10) | Storage mode, TPM, Secure Boot off, supervisor password |
| D | NixOS installer USB | Partition, prepare `/persist`, install |
| E | Installed system + BIOS | Own Secure Boot keys with lanzaboote |
| F | Installed system | TPM2+PIN unlock, recovery key |
| G | Installed system | Hibernation resume offset |
| H | Installed system | First-boot hardware checklist, data restore |
| I | Ongoing | Updates, rollback, diagnostics, recovery drill |

## Contents

0. [Prepare everything on Gentoo](00-prepare-on-gentoo.md): Phase 0.
1. [Windows preparation](01-windows-preparation.md): Phase A.
2. [The flake repository](02-flake-repository.md): Phase B (structure,
   `flake.nix`, host, disk layout, build-check).
3. [System modules](03-system-modules.md): base, persistence, boot, power,
   hardware, desktop, networking, security, dev, apps.
4. [home-manager](04-home-manager.md): user config, GNOME/dconf, VS Code,
   Google Drive sync.
5. [Backup and monitoring](05-backup-monitoring.md): btrbk, restic, alerts,
   system report, diagnostics.
6. [BIOS settings](06-bios-settings.md): Phase C.
7. [Installation](07-installation.md): Phase D.
8. [Secure Boot, TPM and hibernation](08-secure-boot-tpm-hibernation.md):
   Phases E, F and G.
9. [First boot](09-first-boot.md): Phase H (hardware checklist, data restore).
10. [Operating the system](10-operations.md): Phase I, troubleshooting,
    factory reset, `CLAUDE.md`.

## Conventions

| Placeholder | Value in this guide |
| --- | --- |
| user | `ivmr` |
| host | `zbook` |
| repository | `~/claude-code/nixos-config` (GitHub, private) |
| LUKS partition | `/dev/disk/by-partlabel/disk-main-luks` (named by disko) |
| keyboard | US (console, LUKS/TPM PIN) and Swiss German (`ch`) in GNOME |

## Open decisions

These are marked **DECISION** where they appear in the chapters. Until you
decide, the guide uses the default listed first.

1. **Power daemon:** power-profiles-daemon (GNOME default, simple), or TLP
   with `services.tlp.pd.enable` (keeps the Gentoo battery tuning: boost
   off, 70 % CPU cap). See [power.nix](03-system-modules.md#b8-modulespowernix).
2. **Second offsite copy and media:** Google Drive only, with media kept off
   Drive; or add an immutable copy (Backblaze B2 with Object Lock, or an
   append-only rest-server). See [backup](05-backup-monitoring.md).
3. **1Password:** adopt it (SSH agent, `op` for secrets), or use the GNOME
   keyring plus sops-nix. See [desktop](03-system-modules.md#b10-modulesdesktop-gnomenix).
4. **Terminal:** GNOME Terminal (what you use today) or Ptyxis.

## Changes from the original PDF guide

The first version of this guide was a PDF. This Markdown version applies the
decisions settled since then (2026-11-08):

- User `ivmr` instead of `ivan`; `~/claude-code` kept at that path, because
  Claude Code's project memory is keyed by path.
- Keyboard: console `us`; GNOME input sources US + Swiss German.
- Nix on Gentoo comes from the upstream installer (`::gentoo` has no
  `sys-apps/nix` ebuild).
- Wi-Fi only, no Ethernet: a custom installer ISO with the latest kernel and
  NetworkManager ([0.8](00-prepare-on-gentoo.md#08-custom-installer-iso)).
- Wi-Fi backend: wpa_supplicant (NixOS default), not iwd.
- Containers: rootful Docker on its own subvolume, not Podman.
- Kernel tuning for this model: `spd5118` blacklist, audio quirk test, BBR,
  lazy RCU, ModemManager off (no WWAN in this SKU).
- Sleep: no auto-suspend on AC, lid on AC locks, `HibernateOnACPower=false`,
  90 min hibernate delay, UPower hibernates at 5 %.
- thermald off by default; enable only if Phase H shows throttling.
- More persisted state: boltd, NetworkManager, colord, btrbk, restic caches,
  pstore, sysdiag.
- Unsnapshotted carve-out subvolumes for caches, Downloads, pnpm and Docker.
- restic split into three jobs; healthchecks.io dead-man's switch; a global
  failure alert for every unit; a daily quiet system report; weekly restore
  test.
- Apps from nixpkgs instead of Flatpak and npm globals; Claude Desktop from
  the `aaddrick/claude-desktop-debian` flake.
- Observability for Claude Code: `sysdiag` service, debuginfod, offline
  option docs, and a stricter `CLAUDE.md`.

## Building the PDF

`nixos/tools/md2pdf.sh` builds this guide and the
[operations guide](../operations/README.md) as PDFs into `nixos/build/`; see
[nixos/README.md](../README.md#pdfs).
