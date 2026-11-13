# 8. GNOME configuration as code

GNOME stores settings in dconf. Change them in the Settings app, capture the
keys, then make them declarative in home-manager so they survive a reinstall.

```bash
dconf watch /                                   # leave running, change a setting in GNOME,
                                                # it prints the key path and new value
dconf dump /org/gnome/desktop/ > desktop.ini    # or dump a whole subtree
dconf dump / | nix run nixpkgs#dconf2nix        # convert a dump to Nix syntax
```

```nix
# home/gnome.nix (or home/dconf.nix for the generated part)
dconf.settings = {
  "org/gnome/desktop/wm/preferences".button-layout = "appmenu:minimize,close";
  "org/gnome/mutter".dynamic-workspaces = false;
  "org/gnome/settings-daemon/plugins/power".power-button-action = "hibernate";
};

programs.gnome-shell = {
  enable = true;
  extensions = [ { package = pkgs.gnomeExtensions.vitals; } ];
};
```

Declared dconf keys are reapplied on every switch: changing them in the
Settings app is overwritten at the next activation. Either change the key in
the repo, or leave it undeclared if you want to keep changing it by hand.
Check the home-manager options for the exact extension syntax of your
version. The current setup is in
[home/gnome.nix](../install/04-home-manager.md#homegnomenix).
