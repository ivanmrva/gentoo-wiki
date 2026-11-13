# 2. Finding and adding software

## Find it

```bash
nix search nixpkgs ripgrep              # name/description search
# Web: search.nixos.org/packages (packages) and search.nixos.org/options (options)
, rg --version                          # run without installing (nix-index + comma)
nix shell nixpkgs#ripgrep nixpkgs#fd    # temporary shell with both
nix run nixpkgs#cowsay -- hello         # run a package's main program once
```

For `,` (comma), add the `nix-index-database` flake and enable
`programs.nix-index-database.comma.enable`, or install `comma` and run
`nix-index` once to build the file index.

## Add it permanently

```nix
# system-wide, e.g. in modules/dev.nix
environment.systemPackages = with pkgs; [ ripgrep fd jq ];

# for your user only, in home/common.nix
home.packages = with pkgs; [ httpie yq-go ];
```

> [!NOTE]
> Prefer a module's `enable` option over just adding a package when one
> exists (`programs.git.enable`, `services.tailscale.enable`): the module also
> wires up services, groups, udev rules and defaults. Search
> search.nixos.org/options (or `man configuration.nix`) for the program name
> first.

## Enabling a service: the impermanence check

Every new service that keeps state needs its state directory persisted, or it
starts from scratch after each reboot:

```nix
services.tailscale.enable = true;                                  # modules/networking.nix
preservation.preserveAt."/persist".directories =
  [ { directory = "/var/lib/tailscale"; mode = "0700"; } ];        # modules/persistence.nix
```

Lists from different modules merge, so adding a directory in a second place is
fine. To find a service's state directory: `systemctl cat tailscaled` (look
for `StateDirectory=`) or check where it writes under `/var/lib` after it
runs. Preservation creates directories as root:root 0755 unless you state
user, group and mode: match what the service expects (check with `ls -la`
after a first run).
