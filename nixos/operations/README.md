# Working with NixOS

The daily operations guide for the ZBook setup: flake repository, impermanent
root, GNOME, nixos-unstable. It is the companion to the
[installation guide](../install/README.md).

> [!NOTE]
> This guide follows the decisions recorded in the installation guide: user
> `ivmr`, the repository at `~/claude-code/nixos-config`, rootful Docker,
> native apps from nixpkgs, and restic split into backup, prune and check
> jobs. Where something is still open (power daemon, offsite copy,
> 1Password), it is marked **DECISION**, as in the installation guide.

## Contents

1. [Mental model and core loop](01-mental-model.md): the repository is the
   system; edit, build, switch, commit; rebuild variants.
2. [Finding and adding software](02-software.md): search, add, and the
   impermanence check for new services.
3. [Updating, pinning and rollback](03-updating-and-rollback.md): `sysup`,
   cadence, exact pins, generations, rolling back app data.
4. [Living with impermanence](04-impermanence.md): what survives a reboot,
   and recovering lost files.
5. [Development environments](05-development.md): dev shells with direnv,
   language notes, services in containers, distrobox, client projects.
6. [Patching and customizing packages](06-patching.md): overlays, build
   flags, your own binary cache.
7. [Where apps keep their data, and Flatpak](07-app-data-and-flatpak.md).
8. [GNOME configuration as code](08-gnome.md).
9. [Maintenance, debugging and Claude Code](09-maintenance-and-debugging.md).
10. [Failure scenarios](10-failure-scenarios.md): what protects you, how fast
    you recover.
11. [Data volumes and Google Drive](11-data-and-google-drive.md).
12. [Performance](12-performance.md).
13. [Coming from Gentoo](13-coming-from-gentoo.md).
14. [Cheat sheet](14-cheat-sheet.md).
