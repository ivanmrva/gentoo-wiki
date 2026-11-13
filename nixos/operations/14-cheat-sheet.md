# 14. Cheat sheet

| Goal | Command |
| --- | --- |
| Apply config changes | `nh os switch .` |
| Try changes until next reboot | `nh os test .` |
| Update everything (with snapshot) | `sysup` |
| Roll back | `sudo nixos-rebuild switch --rollback` |
| Roll back an app's data | `cp -a /mnt/btr_pool/@snapshots/@home.<ts>/ivmr/<appdir> ~/` |
| Roll back a Flatpak app | `sudo flatpak update --commit=<hash> <app-id>` |
| What gets lost at reboot | `sudo find / -xdev -type f -newer /run/current-system` |
| Restore from snapshot | `/mnt/btr_pool/@snapshots/` |
| Restore from Google Drive backup | `sudo restic-offsite restore latest --target /tmp/r --include /mnt/btr_pool/@snapshots/restic-<volume>/<path>` |
| Sync Google Drive now | `systemctl --user start drive-sync` |
| System snapshot for review | `systemctl start sysdiag.service`; read `/var/lib/sysdiag/latest/` |
| Kernel log | `journalctl -k` |
| Security scan | `vulnix --system` |
| Run a tool once | `, tool` or `nix shell nixpkgs#tool` |
| Search packages | `nix search nixpkgs name` |
| Project shell | `echo 'use flake' > .envrc && direnv allow` |
| New project from template | `nix flake init -t github:the-nix-way/dev-templates#python` |
| Run one command in the dev shell | `nix develop -c pnpm test` |
| Project services | `docker compose up -d` |
| Clean old generations | `nh clean all --keep 10` |
| Capture a GNOME setting | `dconf watch /` |
| Why is X installed | `nix why-depends /run/current-system nixpkgs#X` |
