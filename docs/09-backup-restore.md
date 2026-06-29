# Backup, clone & restore

This machine's resilience is **five layers**, each with a different job. No single
layer is a complete backup on its own; together they cover off-site disaster
recovery, fast local point-in-time rollback, and a versioned record of how the
system was configured.

> Substitute your own values for `<placeholders>` (see
> [Conventions](README.md#conventions)). Secret material — the restic password,
> the cloud (rclone) remote name, LUKS keys — is **never** written into this guide
> or any tracked repo; it lives in the
> [bootstrap-secrets kit](#layer-5--bootstrap-secrets-off-machine).

## The layers

| Layer | Tool | Covers | Stored where | Cadence |
| --- | --- | --- | --- | --- |
| 1. System backup | `restic` (encrypted) | `/` minus `/data1`–`/data5`, caches, transient state — OS, `/etc`, `/home`, **secrets** | cloud repo (direct, via rclone) | weekly |
| 2. `/data1` backup | `restic` (encrypted, **separate repo**) | `/data1` minus `.snapshots` / `lost+found` | a **second** cloud repo (direct, via rclone) | daily |
| 3. Local snapshots | `snapper` (btrfs) | `/data1` only — hourly point-in-time | on-disk `/data1/.snapshots` subvolume | hourly |
| 4. Config versioning | `system-changes` → git | *what diverges from a stock install* (`/etc`, `/usr/local`, dotfiles) — **no secrets** | private git remote | real-time |
| 5. Bootstrap secrets | password manager + offline | the keys that decrypt everything else | **off the machine** | on change |

The split matters. **restic is the only off-site layer** — it backs up the system
(layer 1) and `/data1` (layer 2) *directly to the cloud*, deduplicated, versioned,
and encrypted. **snapper** (layer 3) is the fast on-disk undo for `/data1` — same
NVMe, no disaster-recovery value, but instant. Layer 4 is for *reference and quick
re-apply*, not data recovery. Layer 5 is what makes layers 1–2 actually restorable.

> **This is a single-disk machine.** Everything is one NVMe (`nvme0n1`, ~954 GB) →
> LUKS2 → LVM `vg0`. `/data1`–`/data5` are **btrfs subvolumes** (`@data1`…`@data5`)
> on one `vg0-btrfs` LV — there is **no separate `/data5` disk** and **no local
> restic repo**. The cloud repo is the *only* repo: if the disk dies, the cloud is
> all you have. (For the full disk layout see
> [System Reference](08-system-reference.md).)

> **Off-site coverage is `/data1` only.** `/data2`–`/data5` are restic-excluded,
> have no snapper config, and are not synced anywhere — **they have no off-site
> backup of any kind.** Treat them as scratch / reproducible. Only `/data1` is
> snapshotted *and* backed up off-site.

---

## Layer 1 — System backup (restic, encrypted)

Driven by `/usr/local/bin/restic-backup.sh` on a systemd timer
(`restic-backup.timer`, **weekly, Fri 20:00**). It backs up **`/` directly to the
cloud** over an `rclone:` remote — there is **no local repo and no `restic copy`
step** (that two-stage "local repo on `/data5` + copy to cloud" design was the 2025
architecture and survives only in a pre-migration `restic-backup.sh.*.bak`).

Each run:

1. **Backs up `/`** to the cloud repo
   (`RESTIC_REPOSITORY=rclone:<cloud-remote>:backup/restic-backup`,
   `--pack-size 64`), excluding the data partitions, caches, and transient state
   (`/data1`–`/data5`, `/proc`, `/sys`, `/run`, `/tmp`, `/var/tmp`, `/var/cache`,
   `/var/log`, many `/var/lib/*` runtime dirs — docker, systemd, NetworkManager,
   gdm — browser caches/locks, `~/.cache`, `~/.npm`, `/root/.cache`). Home, `/etc`,
   and `/root` — **including their secrets** — are included, which is exactly why
   the repo is encrypted and the password lives off-machine (layer 5).
2. **Forgets** to the retention policy (metadata-only, *no* prune — see below).
3. **Emails a summary** to `<you@example.com>` via `mail`/msmtp and, on success,
   writes a stamp under `/var/lib/restic-monitor/` consumed by the daily health
   digest.

Everyday commands (`RESTIC_PASSWORD_FILE=/root/.restic-password` is set by the
script; export it yourself for ad-hoc use):

```bash
# run a backup now
sudo systemctl start restic-backup.service        # or: sudo /usr/local/bin/restic-backup.sh

# list snapshots (there is only the one cloud repo)
sudo restic -r rclone:<cloud-remote>:backup/restic-backup snapshots

# integrity check (add --read-data-subset=10% to actually re-hash a sample)
sudo restic -r rclone:<cloud-remote>:backup/restic-backup check
```

## Layer 2 — `/data1` backup (restic, separate repo)

`/usr/local/bin/restic-backup-data1.sh` (timer `restic-backup-data1.timer`,
**daily 21:00**, +10 min jitter) backs up **`/data1`** to a **separate** cloud
repo (`rclone:<cloud-remote>:backup/restic-data1`), excluding only
`/data1/.snapshots` and `/data1/lost+found`. Same encryption, same retention, same
`--pack-size 64`, same mail-on-failure + stamp behaviour as layer 1.

This **replaces the old `rclone sync` "data mirror."** `rclone-sync.timer` is now
**disabled and retired**: a destructive one-way mirror (deletions propagate, no
history) was swapped for a deduplicated, versioned, encrypted restic repo. The
legacy `rclone-sync.sh` only ever synced `/data1` anyway (never data2–5).

```bash
sudo systemctl start restic-backup-data1.service                       # run now
sudo restic -r rclone:<cloud-remote>:backup/restic-data1 snapshots     # list snapshots
```

### Retention & prune (both repos)

Retention runs **inline after each backup** and is deliberately decoupled from
pruning:

- `restic forget --keep-last 8 --keep-weekly 8 --keep-monthly 12` — cheap,
  metadata-only; it marks snapshots unreferenced but does **not** reclaim space.
- **Prune is a separate monthly job** so the slow, throttle-prone repack never
  blocks a backup: `restic-prune.sh` (root repo) and `restic-prune-data1.sh`
  (data1 repo) each run `restic prune --max-repack-size 10G` — capping repack per
  run so a large backlog is worked down over several months instead of one
  marathon. Timers: `restic-prune.timer` = monthly; `restic-prune-data1.timer` =
  `*-*-05 03:00`.

## Layer 3 — Local snapshots (snapper, btrfs)

`/data1` is a btrfs subvolume, so it also gets **hourly on-disk point-in-time
snapshots** via snapper — the fast "undo" layer that the off-site restic repo
can't be (downloading from the cloud is slow; a snapshot rollback is instant).

- Only **one** snapper config exists, `data1` → `/data1`
  (`SNAPPER_CONFIGS="data1"` in `/etc/conf.d/snapper`). `/data2`–`/data5` have
  empty `.snapshots` subvolumes but **no snapper config**, so nothing snapshots
  them.
- Snapshotting is driven by the **upstream** `snapper-timeline.timer` (hourly) +
  `snapper-cleanup.timer` (hourly), both enabled. Retention: hourly 48 / daily 14
  / weekly 4 / monthly 0. (`snapper-boot.timer` is disabled; the custom
  `snapper-daily@` template in the config mirror is disabled/superseded and is
  effectively dead code.)
- restic **excludes** `/data1/.snapshots`, so the off-site repo doesn't re-store
  the snapshots.

```bash
snapper -c data1 list                                  # browse hourly snapshots
sudo snapper -c data1 undochange <pre>..<post> <path>  # selectively roll back
```

Snapper is local-only: it shares the disk with the data it protects, so it does
**nothing** for a dead-disk scenario. That is layer 2's job.

## Layer 4 — Config versioning (system-changes)

The `system-changes` service auto-commits *system + home customizations* (not
secrets) to a private git repo in real time. It's documented in full under
[Application Configuration → Config tracking](04-application-configuration.md#config-tracking-changes-only-git-mirror).
Use it during a rebuild to **see and re-apply** what you'd changed (`make.conf`,
`package.use`, dotfiles, custom units, the `@world` set in
`var/lib/portage/world`) — it is *not* a data backup.

<a id="layer-5--bootstrap-secrets-off-machine"></a>

## Layer 5 — Bootstrap secrets (off-machine)

Everything above is encrypted or excludes secrets. The keys that unlock it all
**cannot** live only on the machine — store them in a password manager and/or
offline:

- **LUKS unlock** — your boot passphrase, and ideally a dedicated **recovery
  key** in a spare key slot so recovery never depends on memory:
  ```bash
  RK=$(head -c 32 /dev/urandom | base64); echo "$RK"   # ← store in password manager
  printf '%s' "$RK" > /dev/shm/rk
  sudo cryptsetup luksAddKey <crypt-partition> /dev/shm/rk   # prompts for current passphrase
  shred -u /dev/shm/rk
  ```
- **restic repo password** (`/root/.restic-password`) — **the** critical secret.
  Both cloud repos are encrypted with it, and the only copies are on the (possibly
  dead) machine and *inside the backups it decrypts* — circular. Without an
  external copy, the cloud backups are unrecoverable. **Confirm it is in your
  password manager.**
- **Cloud (`rclone`) access** — re-authable interactively (`rclone config
  reconnect`), so note the remote name/type rather than storing tokens.
- **LUKS header backup** *(optional, narrow use)* — protects against header
  corruption on an otherwise-intact disk; not needed for cloud restore. It's a
  ~16 MiB **incompressible** binary (high-entropy key material), so keep it as a
  file on an encrypted USB / cloud, **not** as a password-manager entry:
  ```bash
  sudo cryptsetup luksHeaderBackup <crypt-partition> --header-backup-file luks-header.img
  gpg -c luks-header.img && shred -u luks-header.img   # encrypt, then remove plaintext
  ```

### Recovery-artifact export — what to stash off-machine

The bullets above are the *secrets*; this is the small set of **non-secret
descriptors** that make a cloud restore go fast instead of being archaeology.
Without them you can still recover, but you'd be reconstructing the disk layout
and Gentoo state by hand. Dump them to a file, drop the file alongside the LUKS
header backup on the encrypted USB / cloud, and refresh after any disk-layout or
`@world` change. They're cheap to keep and the one thing you can't regenerate
once the machine is gone.

**LUKS header** — the one hard dependency (repeated here as the export form;
without it, encrypted blocks can be unrecoverable even if the disk is fine):

```bash
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
  --header-backup-file luks-header-nvme0n1p2.img
```

**Disk / system layout** — so a fresh install can be partitioned to match
(the new container/pool will have *new* UUIDs, but the shape and the old fstab
are the map):

```bash
lsblk -f                       > system-layout-lsblk.txt   # vg0 LVs, @data1…@data5 subvols
blkid                          > system-layout-blkid.txt
sfdisk -d /dev/nvme0n1         > partition-table.sfdisk    # ESP + LUKS2 partition geometry
cat /etc/fstab                 > fstab.txt
cat /etc/crypttab              > crypttab.txt
mount                          > mounts.txt
```

**Gentoo state** — the inputs to rebuilding the same userland (this overlaps
[Layer 4](#layer-4--config-versioning-system-changes), which already mirrors
`world`/`/etc/portage` to git; the export is the offline, self-contained copy
for when you *can't* reach that git remote):

```bash
cp /var/lib/portage/world      gentoo-world
cp /var/lib/portage/world_sets gentoo-world_sets
tar -czf etc-portage.tar.gz /etc/portage
emerge --info                  > emerge-info.txt
eselect profile show           > gentoo-profile.txt
```

Also keep, off-machine, with the above: the kernel `.config`, the GRUB config,
the restic repo password and cloud recovery codes (see the secret bullets
above), and the `rclone` config backup. The cloud remote name/URL stays
**redacted** — note the remote *type* so you know what to `rclone config
reconnect` against, not the credentials.

---

## Cloud target & the 2026-06-21 backup-target migration

Both restic repos live on a **single cloud provider**, reached through one rclone
remote (the remote name and repo URL are kept `<redacted>` — this is a public
doc). On **2026-06-21** the backup target was migrated to a **new cloud remote**
(retiring the previous one), and the **same** change split the system backup into
two repos (root `+` `/data1`). The pre-migration units and scripts are preserved
as timestamped `*.bak.*-20260621` copies under `/etc/systemd/system/` and
`/usr/local/bin/`.

> Cosmetic leftover: the migration updated the restic *service* Descriptions to
> the new target but a couple of **timer** Descriptions still name the **old**
> provider (e.g. `restic-prune.timer` Description). The text is stale; the scripts
> those timers invoke target the current remote. Harmless, worth a tidy-up.

---

## Planned improvement: second cloud provider + wider coverage

Everything above is the **current** architecture. This section is the **target**
it's evolving toward — folded in so the gap is explicit. The one-line shape of
the whole thing is:

```text
LUKS2 + LVM + Btrfs + Snapper + restic
```

Recovery is layered, and each layer covers a *different* failure. The current
machine has three of these rows; the **secondary off-site** row is the piece not
yet built:

| Layer | Tool | Job | Status on this machine |
| --- | --- | --- | --- |
| Local snapshots | Snapper | accidental-delete recovery, bad-update rollback | **built** — `/data1` only (layer 3) |
| Primary off-site | restic → cloud object storage | disaster recovery (SSD failure / loss) | **built** — root + `/data1` repos (layers 1–2) |
| Secondary off-site | `restic copy` → second provider | provider / account / repo failure | **planned** (below) |

> The layer dropped versus a belt-and-braces setup is `btrbk → encrypted
> external Btrfs SSD`. **Trade-off:** less hardware to maintain, but a slower
> full restore — acceptable *only* because the rebuild is documented (the
> [recreate runbook](00-recreate-this-system.md)) and the plan keeps **two
> independent cloud repos**. That second repo is what this section adds.

### Planned improvement: a second, independent cloud provider

> **Now:** both restic repos (root + `/data1`) live on a **single** cloud
> provider, reached through **one** rclone remote, backing up **directly** to the
> cloud. There is no `restic copy` and no local repo (that two-stage design
> survives only in a pre-migration `restic-backup.sh.*.bak`). If that one account is
> suspended, the remote is wiped, or the repo is corrupted at the provider, every
> off-site copy is gone at once.
>
> **Next iteration:** keep `restic backup` writing to the **primary** repo, then
> add a `restic copy` step into a **second repo on a different provider/account**
> (S3-compatible object storage is the strongest primary; Google Drive / OneDrive
> via rclone are acceptable secondaries for a 50–100 GB backup). Copy after the
> primary run so local files aren't scanned twice. Both repo URLs stay
> **redacted** here.
>
> **Why:** a single cloud account/provider is a single point of failure — the
> [coverage table](#recovery-coverage) below shows "primary cloud repo broken" and
> "cloud account / provider issue" are the two rows the current setup *cannot*
> answer. The 2025 design already had the two-stage `backup → copy` shape; this
> restores the *second target* it lost in the 2026-06-21 migration.

### Planned improvement: snapshot + off-site coverage for `data2`–`data5`

> **Now:** only `/data1` is both snapshotted (snapper) and backed up off-site
> (restic). `/data2`–`/data5` (`@data2`…`@data5`) are restic-excluded, have empty
> `.snapshots` subvolumes but **no snapper config**, and are synced nowhere — so
> they have **no off-site backup of any kind**.
>
> **Next iteration:** for each of `@data2`–`@data5` that actually holds
> non-reproducible data, add a snapper config (mirroring `data1`'s
> `hourly 48 / daily 14 / weekly 4`) and include it in the off-site restic scope
> (its own repo, or folded into the data repo). For the ones that are genuinely
> scratch, **consciously declare them scratch** in this doc rather than leaving
> the gap ambiguous.
>
> **Why:** "no backup" should be a *decision*, not an accident — right now the
> coverage difference between `data1` and `data2`–`data5` is silent. Per-subvolume
> snapper policies are exactly why the data lives on Btrfs subvolumes in the first
> place.

### Planned improvement: root (`@`) snapshots + rollback

> **Now:** root `/` is still **ext4 on its own `vg0` LV**, so there is **no `@`
> root subvolume and no system-rollback**. A bad `@world` update is recoverable
> only by restic-restoring `/etc` and reinstalling packages — there's no instant
> local undo for the OS.
>
> **Next iteration:** once root moves to a Btrfs `@` subvolume (the
> [next-laptop direction](08-system-reference.md)), add a snapper config on `@`
> with `pre/post + daily 7 / weekly 4 / monthly 3`, and wrap large `@world`
> updates in a pre/post snapshot pair.
>
> **Why:** this turns "bad system update" from a cloud-restore job into a one-step
> local rollback — the same instant-undo property snapper already gives `/data1`.

### Restic scope (target)

The current scripts already encode most of this (layer 1's exclude list); the
target is to make the scope explicit and keep the recovery artifacts inside it:

- **Back up:** `/home`, the data subvolumes, `/opt`, `/usr/local`, `/etc`,
  `/root`, boot config, `/etc/portage`, `/var/lib/portage/world{,_sets}`, kernel
  `.config`, the **LUKS header backup**, and the partition-layout exports (see
  [Recovery-artifact export](#recovery-artifact-export--what-to-stash-off-machine)).
- **Exclude:** `/tmp`, `/var/tmp` (Portage builds — `@portage_build` /
  `/var/tmp/portage-big`), `/var/cache`, `/var/log`, `/var/db/repos`,
  `node_modules`, build dirs, browser caches, Docker layers, VM images. Databases
  / Docker volumes / VM images get *special* handling — don't blindly back up
  reproducible runtime dirs.

### Schedule (target)

| Action | Cadence | Status on this machine |
| --- | --- | --- |
| Primary backup | daily (root weekly, `/data1` daily today) | **built** (layers 1–2) |
| Secondary `restic copy` | weekly (daily if critical) | **planned** |
| `forget` / `prune` | weekly or monthly | **built** (forget inline, prune monthly) |
| `check` | weekly; `check --read-data-subset` monthly | **built** (Verify section) |
| Test restore | quarterly | **built** — runs weekly here (Mon 22:00) |

Target primary retention: `daily 14 / weekly 8 / monthly 12 / yearly 3` (the
current policy is `--keep-last 8 --keep-weekly 8 --keep-monthly 12`; adding the
yearly tier is the small delta).

> Restic encrypts and deduplicates **locally before upload**, sends only changed
> chunks after the first run, and keeps a local cache (not a full duplicate). A
> backup that is never test-restored is not a backup — which is why the Verify
> timers above already do it automatically.

### Recovery coverage

What each layer actually buys you. The last two rows are the ones the
[second-provider improvement](#planned-improvement-a-second-independent-cloud-provider)
adds; everything else is already covered today:

| Scenario | Recovery method | Covered now? |
|---|---|---|
| Deleted file in `/data1` | snapper snapshot (layer 3) | yes |
| Deleted file elsewhere | restic restore from cloud repo | yes |
| Bad system update | restic `/etc` restore + reinstall (snapper `@` rollback once root is Btrfs) | partial |
| Broken config | snapper, or restic `/etc` restore | yes |
| Internal SSD failure | reinstall/rebuild + restic cloud restore | yes |
| Laptop stolen / lost | restic cloud restore | yes |
| Primary cloud repo broken | secondary restic repo | **planned** |
| Cloud account / provider issue | second provider | **planned** |
| LUKS header damaged | LUKS header backup (restore scenario B) | yes |
| Full rebuild | `world` + `/etc/portage` + `/etc` + `/home` + data | yes |
| Forgot disk layout | saved `lsblk` / `sfdisk` / `fstab` / `crypttab` exports | yes (artifact export) |

---

## Verify — an untested backup is not a backup

This is automated, not a "remember to do it" chore. Three timers exercise the
repos for you, all emailing only on failure and writing
`/var/lib/restic-monitor/*.stamp` (the health digest flags a stale stamp):

- **Structure check** — `restic-check@structure.timer` (weekly, **Wed 22:00**)
  runs `restic check` (metadata/index) over **both** repos.
- **Read-data check** — `restic-check@readdata.timer` (monthly, `*-*-10 02:00`)
  runs `restic check --read-data-subset=10%` — downloads and re-hashes a rotating
  10 % of packs — over **both** repos.
- **Restore test** — `restic-restore-test.timer` (weekly, **Mon 22:00**) does an
  end-to-end restore: it pulls a fixed file from the root repo and the smallest
  eligible file from the `/data1` repo into a scratch dir, confirms they're
  non-empty, and sha256-compares against the live copy when it's unchanged since
  the snapshot (a mismatch on an unchanged file = real corruption → fail). It
  never touches live data.

Manual spot-checks still worth doing:

```bash
sudo systemctl start restic-check@readdata.service    # force a read-data check now
sudo systemctl start restic-restore-test.service      # force the restore test now
```

- Confirm the **bootstrap kit still works**: `cryptsetup open --test-passphrase`
  with your stored passphrase/recovery key, and that `/root/.restic-password`
  matches what's in your password manager.
- After any LUKS key change, refresh the header backup (an old one still unlocks
  with the old key).

---

## Restore scenarios

### A. Recover a file or directory (system healthy)

Pick the source by what you lost:

```bash
# recent /data1 change → roll back from a local snapper snapshot (fast, on-disk)
snapper -c data1 list
sudo snapper -c data1 undochange <pre>..<post> <path>

# anything else (or an older state) → restore from the cloud repo
sudo restic -r rclone:<cloud-remote>:backup/restic-backup snapshots
sudo restic -r rclone:<cloud-remote>:backup/restic-backup \
     restore latest --target /tmp/restore --include /home/<user>/somefile

# a /data1 file from off-site → use the data1 repo
sudo restic -r rclone:<cloud-remote>:backup/restic-data1 \
     restore latest --target /tmp/restore --include /data1/somefile
```

> There is **no local restic repo** to fall back to — the cloud repo is the only
> repo. snapper is the only on-disk layer, and it covers `/data1` only.

### B. LUKS header corrupted, disk otherwise intact

Symptom: the disk no longer unlocks though the data is physically fine. Restore
the header backup from your kit, then unlock normally:

```bash
sudo cryptsetup luksHeaderRestore <crypt-partition> --header-backup-file luks-header.img
sudo cryptsetup open --test-passphrase <crypt-partition>   # confirm it unlocks
```

### C. Total loss → clone onto new hardware

Two routes — pick by how much you want to rebuild vs. restore wholesale.

**Route 1 — reinstall, then restore data (cleaner, recommended).**
1. Follow the [recreate runbook](00-recreate-this-system.md) to a bootable base
   (partitions, LUKS+LVM, the Btrfs pool with `@` root + system + data
   subvolumes, stage3, kernel, bootloader, GNOME).
2. Re-pull the [config repo](#layer-4--config-versioning-system-changes) and
   re-apply `make.conf`/`package.use`, then `emerge` the `@world` set from
   `var/lib/portage/world`.
3. Restore `/home` (and any `/etc` you didn't re-apply) from the cloud root repo
   onto the running system, then restore `/data1` from the data1 repo:
   ```bash
   export RESTIC_PASSWORD=...                       # from the bootstrap kit
   restic -r rclone:<cloud-remote>:backup/restic-backup restore latest \
          --target / --include /home --include /etc
   restic -r rclone:<cloud-remote>:backup/restic-data1 restore latest --target /
   ```
   `/data2`–`/data5` have **no off-site copy** — there is nothing to restore for
   them (recreate or re-fetch their contents from source).

**Route 2 — restore the whole system from the cloud.**
1. Boot a live USB; create the LUKS2 container + LVM + Btrfs pool exactly as in
   [Before Installation](01-before-installation.md) (the `@` root + `@home` +
   `@var_*` + `@data1`…`@data5` subvolumes), then mount `@` (and the others).
2. Install/configure `rclone` (re-auth the remote) and set the restic password
   from your kit, then restore the latest system snapshot onto the new root:
   ```bash
   export RESTIC_PASSWORD=...                       # from the bootstrap kit
   restic -r rclone:<cloud-remote>:backup/restic-backup snapshots
   restic -r rclone:<cloud-remote>:backup/restic-backup restore latest --target /mnt/gentoo
   ```
3. **Fix what's tied to the old disk** — the new LUKS/LVM and the new btrfs pool
   have *new UUIDs*:
   - regenerate `/etc/fstab` from `blkid` (root LV, swap LV, `/boot`, the btrfs
     subvolume lines, the portage tmpfs),
   - update `GRUB_CMDLINE_LINUX` (`rd.luks.uuid=`, `resume=`) in
     `/etc/default/grub`,
   - chroot in (see [Access from a Live USB](06-access-system-from-live-usb.md)),
     then `grub-install`, `grub-mkconfig -o /boot/grub/grub.cfg`, and regenerate
     the initramfs (`emerge --config sys-kernel/gentoo-kernel` / `dracut --force`).
4. Reboot, then **restore `/data1`** from the data1 repo
   (`restic -r rclone:<cloud-remote>:backup/restic-data1 restore latest --target /`)
   and restore the bootstrap secrets into place. (Again, `/data2`–`/data5` have no
   off-site copy.)

> UUID/bootloader fix-up is the step people forget — a restored root with stale
> `fstab`/`grub` UUIDs won't boot. Do it before the first reboot.

---

[← Documentation index](README.md) · Prev: [Various Tasks](07-various-tasks.md) · Ref: [System Reference](08-system-reference.md)
