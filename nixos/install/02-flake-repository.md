# Phase B: The flake repository

Write the configuration on any machine with Nix installed; here that is the
Gentoo laptop ([Phase 0](00-prepare-on-gentoo.md)). The repository is the
system: everything that defines the laptop lives here, in git.

## B1. Structure

```
nixos-config/
  flake.nix
  flake.lock                      # generated, commit it
  README.md                       # pre-wipe + BIOS steps (Phases A, C)
  CLAUDE.md                       # rules for coding agents (Phase I)
  docs/
    hardware.md                   # exact hardware, quirks, Phase H results
    decisions.md                  # choices made and WHY (agents must cite before reverting)
  hosts/zbook/
    default.nix                   # host entry point
    disko.nix                     # partitions, LUKS, btrfs, tmpfs root
    hardware.nix                  # imports the facter report
    facter.json                   # hardware report, generated in Phase A4
  hosts/zbook-vm/default.nix      # VM test host (Phase 0)
  modules/
    base.nix secrets.nix persistence.nix boot.nix power.nix hardware-intel.nix
    desktop-gnome.nix networking.nix security.nix dev.nix apps.nix
    backup.nix alerts.nix system-report.nix diagnostics.nix
  home/
    ivmr.nix common.nix gnome.nix dconf.nix vscode.nix drive-sync.nix
  secrets/zbook.yaml              # sops-encrypted
```

## B2. flake.nix

```nix
{
  description = "ivmr's NixOS systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };
    preservation.url = "github:nix-community/preservation";
    lanzaboote = {
      # pin to the latest release tag, e.g. github:nix-community/lanzaboote/v0.x.y
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, disko, preservation, lanzaboote, home-manager, sops-nix, ... }:
  let
    commonModules = [
      disko.nixosModules.disko
      preservation.nixosModules.preservation
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
      { nixpkgs.overlays = [
          inputs.claude-desktop.overlays.default        # pkgs.claude-desktop-fhs
          inputs.nix-vscode-extensions.overlays.default # pkgs.vscode-marketplace
        ]; }
    ];
  in {
    nixosConfigurations.zbook = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = commonModules ++ [ lanzaboote.nixosModules.lanzaboote ./hosts/zbook ];
    };
    # zbook-vm, installer and homeConfigurations.ivmr: see Phase 0
  };
}
```

Every input follows the single nixpkgs input. That guarantees one consistent
dependency set: no second, older nixpkgs can sneak into the system.

## B3. hosts/zbook/default.nix

```nix
{ ... }: {
  imports = [
    ./disko.nix
    ./hardware.nix
    ../../modules/base.nix
    ../../modules/secrets.nix
    ../../modules/persistence.nix
    ../../modules/boot.nix
    ../../modules/power.nix
    ../../modules/hardware-intel.nix
    ../../modules/desktop-gnome.nix
    ../../modules/networking.nix
    ../../modules/security.nix
    ../../modules/dev.nix
    ../../modules/apps.nix
    ../../modules/backup.nix
    ../../modules/alerts.nix
    ../../modules/system-report.nix
    ../../modules/diagnostics.nix
  ];

  networking.hostName = "zbook";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    users.ivmr = import ../../home/ivmr.nix;
  };

  # Set ONCE to the release the installer reports (e.g. "26.11"), never change it.
  system.stateVersion = "26.11";
}
```

### hosts/zbook/hardware.nix

```nix
{
  # Hardware report from nixos-facter (Phase A4). The NixOS facter module
  # configures from it: platform, firmware, microcode, initrd modules for storage
  # and input, graphics, Wi-Fi, Bluetooth, supported fingerprint readers.
  hardware.facter.reportPath = ./facter.json;
}
```

This replaces the classic `hardware-configuration.nix` from
`nixos-generate-config`. The report is plain data, and the logic that turns
it into configuration lives in nixpkgs and improves with updates.

If your pinned nixpkgs has no `hardware.facter` option yet, add the
`nixos-facter-modules` flake as an input and import its module instead.

## B4. hosts/zbook/disko.nix

Two partitions only. All other separation is btrfs subvolumes, which share
free space. Root is a tmpfs, so it is wiped by construction at every boot.

```nix
{ lib, ... }:
let
  o = [ "compress=zstd:1" "noatime" ];
  home = "/home/ivmr";
in {
  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [ "size=4G" "mode=755" ];
    };

    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";                   # confirm with lsblk in Phase D
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              passwordFile = "/tmp/luks.key";     # read only while formatting
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
                # Phase F adds: crypttabExtraOpts = [ "tpm2-device=auto" ];
              };
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@nix"       = { mountpoint = "/nix";      mountOptions = o; };
                  "@persist"   = { mountpoint = "/persist";  mountOptions = o; };
                  "@home"      = { mountpoint = "/home";     mountOptions = o; };
                  "@log"       = { mountpoint = "/var/log";  mountOptions = o; };
                  "@docker"    = { mountpoint = "/var/lib/docker"; mountOptions = [ "noatime" ]; };
                  "@snapshots" = { };                        # btrbk target, not mounted
                  "@swap"      = { mountpoint = "/swap";     mountOptions = [ "noatime" ]; };
                  # data volumes: separate snapshot, backup and sync policies
                  "@personal"  = { mountpoint = "${home}/Personal"; mountOptions = o; };
                  "@work"      = { mountpoint = "${home}/Work";     mountOptions = o; };
                  "@media"     = { mountpoint = "${home}/Media";    mountOptions = o; };
                  "@backup"    = { mountpoint = "/backup";          mountOptions = o; };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  # Claude Code project memory is keyed by path (~/.claude/projects/-home-ivmr-claude-code-*):
  # keep ~/claude-code as the path, with the data on @work, exactly as on Gentoo.
  fileSystems."${home}/claude-code" = {
    device = "${home}/Work/claude-code";
    options = [ "bind" "x-systemd.requires-mounts-for=${home}/Work" ];
  };

  systemd.tmpfiles.rules = [
    # ownership of the data volume roots (mount points are created root-owned)
    "d ${home}/Personal 0700 ivmr users -"
    "d ${home}/Work     0700 ivmr users -"
    "d ${home}/Media    0755 ivmr users -"
    "d ${home}/Work/claude-code 0755 ivmr users -"
    "d /backup          0750 ivmr users -"
    # Carve-outs: nested subvolumes inside @home are skipped by btrbk and restic
    # snapshots of @home. Same set as on Gentoo. ("v" creates a subvolume if missing.)
    "v ${home}/.cache                     0700 ivmr users -"
    "v ${home}/Downloads                  0755 ivmr users -"
    "v ${home}/.local/share/pnpm          0755 ivmr users -"
    "v ${home}/.config/Claude/vm_bundles  0700 ivmr users -"   # Cowork VM images
    "h ${home}/.config/Claude/vm_bundles  - - - - +C"          # no copy-on-write for VM images
  ];

  # Top level of the btrfs volume, used by btrbk and restic for snapshots
  fileSystems."/mnt/btr_pool" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvolid=5" "noatime" ];
  };
}
```

> [!NOTE]
> The `v` lines run before the user's home exists on a fresh install, so the
> parent directories (`.config`, `.local/share`) are created root-owned.
> Check ownership after the first boot (`ls -ld ~/.config ~/.local`) and fix
> it with additional `d` rules if needed. Verify this in the VM test.

Why separate subvolumes for data: each gets its own snapshot retention, can
be included in or excluded from backup and sync independently, and can be
restored or rolled back without touching the rest of `/home`. They are
mounted inside the home directory, so they behave like normal folders.

| Subvolume | Purpose | Snapshot / backup |
| --- | --- | --- |
| `@nix` | Nix store, rebuildable from the flake | No |
| `@persist` | Declared system state (keys, secrets, service state) | Hourly; daily restic |
| `@home` | User data (minus carve-outs) | Hourly; daily restic |
| `@log` | Logs survive crashes and reboots | No |
| `@docker` | Docker images and containers, rebuildable | No |
| `@snapshots` | btrbk snapshot target | - |
| `@swap` | 64 GiB swapfile for hibernation | No |
| `@personal` | `~/Personal`: private documents, finances, own projects | Hourly; daily restic |
| `@work` | `~/Work`: business and client work, `~/claude-code` | Hourly; daily restic |
| `@media` | `~/Media`: photos, videos, music (large, rarely changing) | Hourly, short retention; offsite: **DECISION** |
| `@backup` | `/backup`: archives (old machine dumps, phone/photo exports) | Not snapshotted; daily restic |
| carve-outs | `~/.cache`, `~/Downloads`, pnpm store, Cowork VM | No |

## B16. Build-check before install day

1. Copy `facter.json` from Phase A4 into `hosts/zbook/`; the real host's
   build needs it. Until then, build `zbook-vm`.
1. `git add -A` in the repository. Flakes only see files tracked by git.
1. `nix flake lock` creates `flake.lock`; commit it.
1. `nix flake check` evaluates every module. Fix unknown or renamed options
   now, not during the install.
1. `nix build .#nixosConfigurations.zbook.config.system.build.toplevel`
   builds the full system. Success here means install day only has to deal
   with hardware.
1. Push the repository so the installer can clone it.
