# Phase 0: Prepare everything on Gentoo

Everything except the hardware-specific steps can be written, built and
tested on the current Gentoo laptop before the ZBook is touched. Install day
then shrinks to: live test, hardware report, install, key enrollment, data
restore.

Nothing is copied from Gentoo to the new laptop. The system comes from this
repository plus cache.nixos.org, and personal data comes from the restic
backup ([Phase H](09-first-boot.md#h2-restore-data)).

| Can be prepared now | Needs the ZBook |
| --- | --- |
| Flake repository, all modules, home-manager configuration, dev shells, secrets (sops-nix), CI with weekly updates, VM test of the install, custom installer ISO, export of settings | `facter.json`, Secure Boot key enrollment, TPM enrollment, hibernation `resume_offset`, hardware tests |

## 0.1 Nix on Gentoo

`::gentoo` has no `sys-apps/nix` ebuild (checked 2026-11-08), so use the
upstream multi-user installer. It needs root, so run it yourself, not through
Claude Code.

1. Put the store on the btrfs pool, not on the ext4 root. The root has about
   47 GB free, the pool over 600 GB, and a GNOME system closure plus VM
   images takes 20–40 GB.
   * `sudo mount -o subvolid=5 /dev/mapper/vg0-btrfs /mnt && sudo btrfs subvolume create /mnt/@nix && sudo umount /mnt`
   * Add to `/etc/fstab`, then `sudo mkdir /nix && sudo mount /nix`:
     ```
     UUID=048292a5-5607-449a-9247-92aad183be1f  /nix  btrfs  noatime,compress=zstd:3,subvol=@nix  0 0
     ```
1. Install Nix: `sh <(curl -L https://nixos.org/nix/install) --daemon`
1. Enable flakes in `/etc/nix/nix.conf`, then `sudo systemctl restart nix-daemon`:
   ```
   experimental-features = nix-command flakes
   ```
1. Check: `nix run nixpkgs#hello`

From then on the complete NixOS configuration can be evaluated and built on
Gentoo.

## 0.2 Repository with a real host and a VM host

Create the private GitHub repository `nixos-config` and clone it to
`~/claude-code/nixos-config`. The full layout is in
[Phase B](02-flake-repository.md#b1-structure). Next to the real host, add a
VM host that uses the same modules:

```
nixos-config/
  hosts/zbook/           # the real laptop (Phase B)
  hosts/zbook-vm/        # same modules, VM overrides
  hosts/installer/       # custom installer ISO (0.8)
  modules/  home/  secrets/  docs/  .sops.yaml  .github/workflows/  CLAUDE.md  README.md
```

```nix
# hosts/zbook-vm/default.nix
{ lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../zbook/disko.nix
    ../../modules/base.nix ../../modules/persistence.nix ../../modules/desktop-gnome.nix
    ../../modules/networking.nix ../../modules/security.nix ../../modules/dev.nix
    ../../modules/apps.nix ../../modules/secrets.nix ../../modules/alerts.nix
    ../../modules/diagnostics.nix
  ];
  networking.hostName = "zbook-vm";
  disko.devices.disk.main.device = lib.mkForce "/dev/vda";
  disko.devices.disk.main.imageSize = "40G";
  boot.loader.systemd-boot.enable = true;        # no lanzaboote / Secure Boot in the VM
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  nixpkgs.hostPlatform = "x86_64-linux";         # no facter report in the VM
  system.stateVersion = "26.11";
}
```

```nix
# flake.nix: add next to zbook
nixosConfigurations.zbook-vm = nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs; };
  modules = commonModules ++ [ ./hosts/zbook-vm ];
};
```

```bash
nix run -L .#nixosConfigurations.zbook-vm.config.system.build.vmWithDisko
```

This boots the whole design in QEMU on Gentoo: partitioning, LUKS, tmpfs
root, Preservation, secrets, GNOME login, `sysup`. It needs KVM, and `ivmr`
is in the `kvm` group. The VM's LUKS passphrase and TPM differ from the real
machine; that is expected.

Users have reported problems combining `vmWithDisko` with impermanence-style
setups (double evaluation). If it resists, `nixos-rebuild build-vm` without
disko still tests everything above the disk layer.

What to check in the VM:

1. Reboot twice and confirm that state in `/persist` survives (Wi-Fi
   profile, `machine-id`, SSH host key) and that everything else is gone.
1. Log in to GNOME: extensions, input sources (US + CH), dconf settings.
1. `systemctl --failed` is empty.
1. Run `sudo systemd-run --unit=fail-test false` and confirm the ntfy push
   arrives ([alerts](05-backup-monitoring.md#b14b-modulesalertsnix)).
1. `systemctl start sysdiag.service` as `ivmr` works without a password.

## 0.3 home-manager on Gentoo, starting now

home-manager runs standalone on any Linux. Split the user configuration into
`home/common.nix` (shell, git, editor, CLI tools, SSH client config) and
`home/gnome.nix` (dconf, extensions; NixOS only). Apply `common.nix` on
Gentoo and use it daily. The same file becomes the NixOS module, already
proven in use.

```nix
# flake.nix outputs: standalone home-manager for Gentoo
homeConfigurations.ivmr = home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  modules = [ ./home/common.nix ];
};
```

```bash
nix run home-manager/master -- switch --flake .#ivmr
```

home-manager refuses to overwrite existing dotfiles (`.bashrc`,
`.gitconfig`). Move them aside first, or set `home-manager.backupFileExtension`.

## 0.4 Dev shells, starting now

Convert active projects to `flake.nix` + `.envrc` (direnv). They work
identically on Gentoo and NixOS, so development continues unchanged across
the switch. Language runtimes (Go, Python/uv, Rust, Java/Maven, Node) move
into per-project dev shells instead of global installs.

## 0.5 Secrets with sops-nix

The decryption identity at boot is the laptop's SSH host key. Generate it now
and encrypt secrets for it before the machine exists.

```bash
mkdir -p ~/zbook-hostkeys
ssh-keygen -t ed25519 -N "" -C zbook -f ~/zbook-hostkeys/ssh_host_ed25519_key
nix shell nixpkgs#ssh-to-age -c ssh-to-age < ~/zbook-hostkeys/ssh_host_ed25519_key.pub
mkdir -p ~/.config/sops/age
nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt   # personal key
```

> [!IMPORTANT]
> Store both private keys (the host key and the personal age key) in your
> password manager and on the installer USB stick. Never commit them. The
> personal key lets you edit secrets from any machine; the host key is copied
> onto the ZBook at install time ([D4](07-installation.md#d4-prepare-persist-before-the-first-boot)).

```yaml
# .sops.yaml (public keys: output of ssh-to-age, and the "Public key" line of age-keygen)
keys:
  - &ivmr age1...personal
  - &zbook age1...host
creation_rules:
  - path_regex: secrets/zbook\.yaml$
    key_groups: [ { age: [ *ivmr, *zbook ] } ]
```

```bash
nix shell nixpkgs#sops -c sops secrets/zbook.yaml
# contents (YAML), e.g.:
#   users:   { ivmr: <yescrypt hash>, root: <yescrypt hash> }
#   restic:  { password: ... }
#   ntfy:    { url: "https://ntfy.sh/<long-random-topic>" }
#   hc:      { backup: "https://hc-ping.com/<uuid>" }
#   (rclone.conf stays a file on /persist: rclone must be able to rewrite it)
```

Create the password hashes with `nix shell nixpkgs#mkpasswd -c mkpasswd -m yescrypt`.
The module that consumes these secrets is
[modules/secrets.nix](03-system-modules.md#b5b-modulessecretsnix).

Wi-Fi profiles are not declared here: you have about 200 saved networks.
They are copied once as files ([0.7](#07-export-checklist-before-the-wipe)).

## 0.6 CI: build check and weekly updates

```yaml
# .github/workflows/build.yml (check action versions for current releases)
on: [push, pull_request, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: wimpysworld/nothing-but-nix@main      # frees runner disk space
      - uses: cachix/install-nix-action@v31
      - run: nix flake check
      - run: nix build .#nixosConfigurations.zbook-vm.config.system.build.toplevel
      # once facter.json is committed, also build the real host:
      # - run: nix build .#nixosConfigurations.zbook.config.system.build.toplevel
```

```yaml
# .github/workflows/update.yml
on: { schedule: [ { cron: "0 3 * * 1" } ], workflow_dispatch: {} }
jobs:
  lock:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v31
      - uses: DeterminateSystems/update-flake-lock@main
        with: { pr-title: "flake: weekly update" }
```

1. The weekly update arrives as a pull request, and the build workflow runs
   on it. Green means the new lock evaluates and builds.
1. Merge it, then on the laptop run `sysup`
   ([Phase I](10-operations.md#updates)). With CI, `sysup` uses `git pull`
   instead of `nix flake update`.
1. Binary cache: start without one; nixpkgs packages come from
   cache.nixos.org anyway. Add Cachix or a self-hosted attic only once your
   own overrides need building.

CI never needs the secrets: evaluation and builds only reference their paths,
and decryption happens on the laptop at boot.

## 0.7 Export checklist before the wipe

The Gentoo laptop stays untouched for 2–4 weeks as a fallback, but anything
that is in neither the repository nor restic is lost for the new machine.

1. **Software inventory.** `/var/lib/portage/world` misses everything
   installed outside Portage: the Flatpaks, the npm globals (Claude Code,
   Codex, pnpm), IntelliJ via Toolbox, `~/google-cloud-sdk`,
   `~/.local/bin/office-viewer`. Let Claude Code map all of it to nixpkgs
   names, sorted into system module, home-manager, dev shell or drop.
1. **Generate config from the live system** (into the repo, then prune):
   * `dconf dump / | nix run nixpkgs#dconf2nix > home/dconf.nix`, then remove
     window state and `nm-applet/eap` entries
   * `code --list-extensions > home/vscode-extensions.txt`
   * `~/.config/mimeapps.list` → `xdg.mimeApps` in home-manager
   * `~/.config/environment.d/10-xdg-tidy.conf` → `home.sessionVariables`
1. **Copy once to the installer USB stick or into restic** (secret material,
   never into git):
   * `/etc/NetworkManager/system-connections/` (mode 0600; strip
     `interface-name=` and `mac-address=` lines) and `~/.cert/nm-openvpn/`
   * `~/.local/share/keyrings/login.keyring` (Wi-Fi PSKs stored with
     `psk-flags=1` only work once this is restored)
   * user and root `rclone.conf`, the restic password
   * `~/.ssh` (including the replit key and config), `~/.gnupg`, `~/.config/gh`
   * `~/.claude` and `~/.claude.json`
   * `~/.config/monitors.xml`, JetBrains settings
   * the browser profiles: Flatpak paths `~/.var/app/org.mozilla.firefox/config/mozilla/firefox`,
     `~/.var/app/com.google.Chrome/config/google-chrome`,
     `~/.var/app/org.mozilla.thunderbird/.thunderbird` map to the native
     `~/.mozilla/firefox`, `~/.config/google-chrome` and `~/.thunderbird`
     (works when the native version is the same or newer; confirm Firefox's
     target directory with `about:profiles` after its first start)
1. **Fix on Gentoo now** (both independent of the migration):
   * `sudo grep client_id /root/.config/rclone/rclone.conf`: if it is
     empty, root's restic remote uses rclone's shared Google client ID,
     which stops working during 2026.
   * Claude Desktop ebuild stuck at 2.9939.4 while upstream is 4.23118.0:
     check why the health digest did not flag it.
1. **Close the backup gap.** Gentoo's restic covers only `/` (which includes
   `/home`) and `/data/personal`. **`/data/work`, `/data/media` and
   `/data/backup` are not offsite.** Before the wipe, either run one-off
   restic backups of `/data/work` and `/data/backup` (and `/data/media` if
   you want it back) into the same repository, or copy them to an external
   disk. Code under `/data/work/claude-code` that is pushed to GitHub can
   simply be cloned again.
1. **Run a final restic backup, then do a test restore** of a few
   directories to a scratch folder.

## 0.8 Custom installer ISO

There is no Ethernet, only Wi-Fi. The BE201 Wi-Fi 7 card needs a recent
kernel. Rather than depending on the stock ISO's kernel, build your own
installer from the flake: latest kernel, NetworkManager, and your SSH key.

```nix
# flake.nix → nixosConfigurations.installer
installer = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ({ pkgs, lib, ... }: {
      boot.kernelPackages = pkgs.linuxPackages_latest;   # same kernel as the real system
      hardware.enableRedistributableFirmware = true;
      networking.wireless.enable = lib.mkForce false;    # NetworkManager instead
      networking.networkmanager.enable = true;
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA… ivmr@gentoo" ];
      environment.systemPackages = with pkgs; [ git nixos-facter sbctl ];
    })
  ];
};
```

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot it once in a VM (`nix run nixpkgs#qemu -- -enable-kvm -m 4G -cdrom result/iso/*.iso`)
to catch config mistakes. Do not bake the Wi-Fi password into the image.

If Wi-Fi does not come up on the ZBook, USB-tether a phone (works out of the
box) or use a USB-C Ethernet adapter.

## Install day after Phase 0

1. [Phase A](01-windows-preparation.md): Windows prep, live test,
   `facter.json`. Commit and push it, and CI builds the real host.
1. [Phases C](06-bios-settings.md) and [D](07-installation.md), with D4
   reduced to copying the pre-generated host key.
1. First boot: secrets decrypt and home-manager applies your proven
   configuration.
1. [Phases E to H](08-secure-boot-tpm-hibernation.md), then restore data from
   restic.
