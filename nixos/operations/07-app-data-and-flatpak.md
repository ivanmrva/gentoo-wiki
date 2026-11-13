# 7. Where apps keep their data, and Flatpak

Knowing where an app writes is what makes per-app restores
([chapter 3](03-updating-and-rollback.md#rolling-back-app-data-too)) and
persistence decisions possible. There is a standard, but it is a convention,
not an enforced rule.

## The XDG Base Directory standard

| Location | Meant for |
| --- | --- |
| `~/.config/<app>` | Settings you would want to keep and copy |
| `~/.local/share/<app>` | Valuable data: databases, mail, history |
| `~/.local/state/<app>` | State worth keeping but not important: logs, recent files |
| `~/.cache/<app>` | Anything safely deletable (a carve-out subvolume here: not snapshotted, not backed up) |
| `/run/user/<uid>` | Sockets and locks; gone at logout |

1. **Compliance is voluntary.** Many apps still use one legacy dot-directory
   for everything. Firefox only gained XDG support in version 147 (January
   2026) and keeps using `~/.mozilla` if it already exists.
1. **Categories get misused.** Electron apps (VS Code, Slack) typically mix
   configuration, state and large caches under `~/.config/<app>`.
1. **Reference:** the Arch Wiki page on XDG Base Directory lists per-app
   support and the actual paths used.
1. **Enforced separation exists in two places:** Flatpak apps (below) and
   system services using systemd's `StateDirectory=` / `CacheDirectory=`
   (`/var/lib/<name>`, `/var/cache/<name>`). That is why persisting
   `/var/lib/<service>` works reliably.

## Flatpak: when to use it

This setup installs apps natively from nixpkgs by default
([apps.nix](../install/03-system-modules.md#b13b-modulesappsnix)): 1Password's
browser integration does not work with Flatpak browsers, and native apps
integrate with dev shells and the desktop. Flatpak is the option when you
want a closed-source app sandboxed.

Flatpak confines each app to `~/.var/app/<app-id>/` with separate `config/`,
`data/` and `cache/` and sandboxes it. It **isolates** app data but does not
**version** it: a rolled-back Flatpak still faces data its newer version
migrated, so the `sysup` snapshot remains the real rollback for data.

| Category | Where | Why |
| --- | --- | --- |
| Closed-source GUI apps (Zoom, Teams, Slack, Spotify) | nixpkgs (default), or Flatpak for the sandbox | Flatpak limits what closed code sees and keeps all state in one directory |
| Standalone GUI apps (media, image tools) | Flatpak or nixpkgs | Either works; Flatpak if you want contained state |
| GNOME core, CLI tools, shells, compilers | nixpkgs | Part of the system or terminal workflow; Flatpak is built for GUI apps |
| Editors/IDEs (VS Code, Zed) | nixpkgs | The sandbox hides host toolchains, direnv and Nix dev shells |
| Deep integration (VPN clients, password-manager browser integration, browsers) | nixpkgs | Sandbox boundaries get in the way |

### Declarative Flatpak with nix-flatpak

```nix
# flake.nix inputs
nix-flatpak.url = "github:gmodena/nix-flatpak";
# modules list
nix-flatpak.nixosModules.nix-flatpak

# modules/flatpak.nix
{
  services.flatpak = {
    enable = true;
    packages = [ "us.zoom.Zoom" "com.slack.Slack" "com.spotify.Client" ];
    update.auto = { enable = true; onCalendar = "weekly"; };
  };
  preservation.preserveAt."/persist".directories = [ "/var/lib/flatpak" ];
}
```

If you install user Flatpaks (`flatpak --user`), add `~/.local/share/flatpak`
as another carve-out subvolume in `disko.nix`, as on Gentoo.

```bash
flatpak info --show-permissions com.slack.Slack            # what the app may access
flatpak override --user --nofilesystem=home com.slack.Slack  # restrict it
flatpak remote-info --log flathub com.slack.Slack          # list older versions (commits)
sudo flatpak update --commit=<hash> com.slack.Slack        # roll the app back
```

Two caveats: Flatpak app versions are outside `flake.lock`, so a reinstall
installs the same apps but not necessarily the same versions. And many apps
request broad home access, which undoes the clean separation; check and
restrict permissions (Flatseal is a GUI for this).
