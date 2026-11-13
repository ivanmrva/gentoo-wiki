# 4. Living with impermanence

`/` is a tmpfs. Only these survive a reboot: `/nix`, `/persist`, `/home`
(with the data volumes `~/Personal`, `~/Work`, `~/Media`), `/backup`,
`/var/log`, `/var/lib/docker` and `/swap`, plus everything declared in
`persistence.nix` (Preservation module). Your home directory is fully
persistent, so user apps behave normally; system-level state needs a
declaration.

## Before rebooting after setting something up

```bash
sudo find / -xdev -type f -newer /run/current-system 2>/dev/null
```

Lists files that exist only in RAM and will be lost. Typical findings: a new
service's `/var/lib` directory, a manually edited `/etc` file (move it into
the config), or junk that can go. Persist what matters, rebuild, then reboot.
The weekly `sysdiag` run records the same list in
`/var/lib/sysdiag/latest/50-not-persisted.txt`.

## Recovering something lost

```bash
sudo ls /mnt/btr_pool/@snapshots/       # hourly btrbk snapshots of @home, @persist and the data volumes
sudo cp -a /mnt/btr_pool/@snapshots/@home.20261107T1400/ivmr/doc.md ~/doc.md

sudo restic-offsite snapshots           # offsite backups (wrapper created by NixOS)
sudo restic-offsite restore latest --target /tmp/restore \
  --include /mnt/btr_pool/@snapshots/restic-home/ivmr/doc.md
```

restic backs up read-only snapshots, so paths inside the backup start with
`/mnt/btr_pool/@snapshots/restic-<volume>`:

| Path in restic | Live location |
| --- | --- |
| `restic-home` | `/home` (without the carve-outs: `~/.cache`, `~/Downloads`, pnpm store, Cowork VM) |
| `restic-personal` | `~/Personal` |
| `restic-work` | `~/Work` (including `~/claude-code`) |
| `restic-backup` | `/backup` |
| `restic-persist` | `/persist` |
| `restic-media` | `~/Media`, only if media goes offsite (**DECISION**) |

Snapshot names follow btrbk's timestamp format; list the directory to see the
actual names. State lost from the tmpfs root itself is not in any snapshot:
that is why the `find` check matters.
