# 1. Mental model and core loop

## The mental model

On this system, **the git repository is the system**. Every package, service,
setting and user preference is a line in the flake. The running machine is
only the latest build of that repository. Three consequences follow:

1. **Never change the system imperatively.** No editing files in `/etc`, no
   `nix profile install`, no manual service setup. On a tmpfs root most of
   that would vanish at the next boot anyway; the rest would silently diverge
   from the repo.
1. **Every change is edit, build, switch, commit.** The commit history is the
   exact history of your machine, and every state is reproducible from it.
1. **Mistakes are cheap.** Each switch creates a new generation; the previous
   one stays bootable until garbage collection removes it.

### Where software belongs

| Need | Put it in | Example |
| --- | --- | --- |
| System-wide tool or service | a module in `modules/` (NixOS) | Docker, tailscale, fwupd, GNOME |
| Your user tools and settings | `home/` (home-manager) | shell config, git config, GNOME dconf, editors |
| Project toolchain | the project's own `flake.nix` dev shell | Node 22 + pnpm for one client project |
| Try something once | nothing: run it ad hoc | `nix shell nixpkgs#foo` or `, foo` |
| Closed-source GUI app | `modules/apps.nix` (nixpkgs), or Flatpak if you want the sandbox | Zoom, Teams, Slack |

> [!NOTE]
> Rule of thumb: if you would need it on a reinstall, it goes in the repo. If
> you need it for one project, it goes in that project's flake. If you need
> it for five minutes, run it ad hoc.

## The core loop

```bash
cd ~/claude-code/nixos-config
$EDITOR modules/dev.nix                          # 1. edit
nix flake check                                  # 2. evaluate everything (fast)
nh os switch .                                   # 3. build, show diff, activate
git add -A && git commit -m "dev: add ripgrep"   # 4. record
git push
```

### Rebuild variants

| Command | Effect | Use when |
| --- | --- | --- |
| `nixos-rebuild build` | Builds into `./result`, changes nothing | Checking that a change compiles |
| `nixos-rebuild test` | Activates now, not added to the boot menu | Risky changes: a reboot reverts them |
| `nixos-rebuild switch` | Activates now and becomes the boot default | Normal changes |
| `nixos-rebuild boot` | Becomes the boot default, activates at next boot | Kernel, initrd, systemd or bootloader changes |
| `nixos-rebuild build-vm` | Builds a QEMU VM of the configuration | Testing big changes in isolation |

All of these take `--flake ~/claude-code/nixos-config#zbook` and need sudo
for anything that activates. `nh os switch .` wraps `switch` with a readable
package diff and build progress; `nh os test .` and `nh os boot .` exist too.

### nh configuration

Configured in [base.nix](../install/03-system-modules.md#b5-modulesbasenix):
`programs.nh` with the flake path set, so plain `nh os switch` works from any
directory, and automatic cleanup that keeps at least 10 generations and
everything from the last 14 days.
