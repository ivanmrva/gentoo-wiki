# 11. Data volumes and Google Drive

Personal, work and media data live on separate btrfs subvolumes, mounted as
folders in your home directory. Each has its own snapshot, backup and sync
policy.

| Folder (subvolume) | Snapshots | restic to Google Drive | Two-way Drive sync |
| --- | --- | --- | --- |
| `~/Personal` (`@personal`) | Hourly, 48h/14d/6w | Daily, encrypted | Only `~/Personal/Drive` |
| `~/Work` (`@work`), incl. `~/claude-code` | Hourly, 48h/14d/6w | Daily, encrypted | Only `~/Work/Drive` |
| `~/Media` (`@media`) | Hourly, 7d/4w | **DECISION** (default: not offsite) | Optional, selected subfolders |
| `/backup` (`@backup`) | None | Daily, encrypted | No |
| rest of `/home`, `/persist` | Hourly | Daily, encrypted | No |
| `~/.cache`, `~/Downloads`, pnpm store, Cowork VM | None (carve-outs) | No | No |

## Typical tasks

```bash
systemctl --user start drive-sync          # sync now instead of waiting for the timer
journalctl --user -u drive-sync -n 50      # what the last sync did
rclone bisync ~/Personal/Drive gdrive:Personal \
  --workdir ~/.local/state/rclone-bisync --resync   # after an aborted/failed state
sudo restic-offsite snapshots              # backups on Google Drive
sudo restic-offsite restore latest --target /tmp/r \
  --include /mnt/btr_pool/@snapshots/restic-work/projectx
rclone about gdrive:                       # quota
```

1. **Adding a sync pair:** add a line to `home/drive-sync.nix`, create both
   folders and the `RCLONE_TEST` marker on both sides, run one `--resync`
   manually, then let the timer take over.
1. **A sync aborted because of `--max-delete`:** you (or something) deleted
   more than 25 % of the files. If intended, run once with `--force`; if not,
   restore from the btrbk snapshot first.
1. **Conflicts** produce a second copy with a conflict suffix; merge by hand
   and delete the loser.
1. **Synced folders are unencrypted on Drive** (needed for the Drive web and
   mobile apps); restic backups are encrypted client-side and Google holds no
   key.
1. **Google Docs, Sheets and Slides are not files:** bisync skips them, so
   they are in no backup. If you create them natively in Drive, export them
   periodically (Google Takeout into `/backup`, then restic picks them up).
1. **Deleting client data for good** (end of mandate, deletion request):
   delete it locally, let the sync remove it from Drive and empty the Drive
   trash; old btrbk snapshots expire within 6 weeks; in restic, remove it
   from all backups with `restic rewrite --exclude <path> --forget` followed
   by `restic prune`.

> [!NOTE]
> Two different things: restic to Google Drive is the **backup** (encrypted,
> versioned, restore any point in time). bisync is **access from other
> devices**: deleting a file locally deletes it on Drive at the next sync.
> Drive's 30-day trash and the local snapshots are the safety net for the
> synced folders.

> [!WARNING]
> **The Google account is now the most valuable credential you have:** it
> holds all synced data and the only offsite backup. Protect it with a
> passkey or hardware security key (not SMS), consider Google's Advanced
> Protection Program, and review third-party access in the account's
> security settings once a year. The two rclone tokens are scoped
> differently: the backup token (`drive.file`) sees only the restic
> repository, the sync token sees your Drive; the sync token's config file is
> encrypted with a password kept in the GNOME keyring.
