# 9. Maintenance, debugging and Claude Code

## Maintenance

Most checks run by themselves: the daily
[system report](../install/05-backup-monitoring.md#b14d-modulessystem-reportnix)
pushes to ntfy when a reboot is needed, units failed, disks fill up, battery
or NVMe health drops, the kernel logs errors, or firmware updates exist.
Every failed system unit also pushes on its own, and healthchecks.io alerts
when the backup stops running. The table is for the checks you do by hand.

| Task | Command | How often |
| --- | --- | --- |
| Update system | `sysup` | Weekly |
| Store size | `du -sh /nix/store`; `nh clean all --keep 10` | Automatic via nh; check monthly |
| Disk usage overall | `sudo btrfs filesystem usage /persist` | Monthly |
| btrfs health | `sudo btrfs scrub status /persist` | After the monthly scrub |
| SSD health | `sudo smartctl -a /dev/nvme0n1` | Quarterly (system report watches wear) |
| Firmware | `fwupdmgr refresh && fwupdmgr get-updates` | Monthly |
| Backups working | `sudo restic-offsite snapshots`; `systemctl list-timers 'restic*'`; healthchecks.io dashboard | Monthly |
| Failed services | `systemctl --failed` | When something feels off |
| ESP space | `df -h /boot` | After many kernel updates |
| Reboot needed? | `[ "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)" ] \|\| echo reboot` | After each update (also in the system report) |
| Backup integrity | Automatic: weekly 5 % sample (`restic-offsite-check`) and weekly restore test; full `sudo restic-offsite check --read-data` yearly | Yearly (full) |
| Platform security | `fwupdmgr security`; `sudo ss -tulpn` | Quarterly |
| Time sync | `ntp-ctl status` (NTS sources, offset) | When clocks seem off |
| Google Drive quota | `rclone about gdrive:` | Monthly |
| Drive sync health | `systemctl --user status drive-sync`; conflict files: `find ~/Personal/Drive -name '*conflict*'` | Monthly |
| Known CVEs in the system | `vulnix --system` | Monthly |
| Recovery key test | Unlock once with the recovery key | Yearly |

## Debugging and introspection

| Question | Command |
| --- | --- |
| Why did evaluation fail? | `nix flake check --show-trace` |
| Why did a build fail? | `nh os switch . -- -L` or `nix log <drv>` for the full build log |
| What is the effective value of an option? | `nix repl`, then `:lf .`, then `nixosConfigurations.zbook.config.services.foo.enable` |
| Why is package X on my system? | `nix why-depends /run/current-system nixpkgs#X` |
| What takes space in the system closure? | `nix-tree /run/current-system` |
| What changed between two generations? | `nvd diff /nix/var/nix/profiles/system-41-link /run/current-system` |
| Logs of the previous boot | `journalctl -b -1 -p warning` |
| Logs of one service | `journalctl -u NetworkManager -b` |
| Kernel log (without root) | `journalctl -k` (`dmesg` is restricted) |
| Crashes | `coredumpctl list`; `coredumpctl info <pid>` (symbols via debuginfod) |
| Full system snapshot | `systemctl start sysdiag.service`, then `/var/lib/sysdiag/latest/` |
| Work inside a package's build environment | `nix develop nixpkgs#foo`, then `unpackPhase`, `patchPhase`, ... |

## Working on the repo with Claude Code

The repository is an ideal agent workspace: declarative, diffable, and every
change is verified by evaluation and build before it touches the running
system. Keep the human decision at the switch.

1. Claude Code edits the modules, following the repository's `CLAUDE.md`
   ([template](../install/10-operations.md#appendix-b-claudemd-for-the-repository)):
   no `/etc` edits, persistence for new state, single nixpkgs input, cite
   `docs/decisions.md` before reverting a decision.
1. It gathers data without sudo: `sysdiag.service` (allowed via polkit),
   the journal, `coredumpctl`, `nvd diff`.
1. It runs `nix flake check` and `nixos-rebuild build --flake .#zbook`. Both
   must pass.
1. You review the result: `git diff` for the config,
   `nvd diff /run/current-system ./result` for the package-level effect.
1. You run `nh os switch .` (or `nh os test .` for risky changes) and commit.

An example review prompt is in the
[installation guide](../install/10-operations.md#diagnostics-with-claude-code).

> [!WARNING]
> Do not give an agent passwordless sudo for switching. Building is safe and
> unprivileged; activating changes the running system and should stay your
> step.
