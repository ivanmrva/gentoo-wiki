# Backup, clone & restore

This machine's resilience is **four independent layers**, each with a different
job. No single layer is a complete backup on its own; together they cover
file-level recovery, full-disk disaster recovery, and a versioned record of how
the system was configured.

> Substitute your own values for `<placeholders>` (see
> [Conventions](README.md#conventions)). Secret material — the restic password,
> cloud credentials, LUKS keys — is **never** written into this guide or any
> tracked repo; it lives in the [bootstrap-secrets kit](#layer-4--bootstrap-secrets-off-machine).

## The four layers

| Layer | Tool | Covers | Stored where | Cadence |
| --- | --- | --- | --- | --- |
| 1. System backup | `restic` (encrypted) | `/` minus data partitions, caches, transient state — OS, `/etc`, `/home`, **secrets** | local repo on `/data5` **+** copied to cloud | weekly |
| 2. Data backup | `rclone sync` | the bulk `/data1`–`/data5` partitions (excluded from restic) | cloud remote | daily |
| 3. Config versioning | `system-changes` → git | *what diverges from a stock install* (`/etc`, `/usr/local`, dotfiles) — **no secrets** | private git remote | real-time |
| 4. Bootstrap secrets | password manager + offline | the keys that decrypt everything else | **off the machine** | on change |

The split matters: **restic backs up the system, rclone mirrors the data,** so
neither duplicates the other. Layer 3 is for *reference and quick re-apply*, not
data recovery. Layer 4 is what makes layers 1–2 actually restorable.

---

## Layer 1 — System backup (restic, encrypted)

Driven by `/usr/local/sbin/restic-backup.sh` on a systemd timer
(`restic-backup.timer`, weekly). Each run:

1. **Backs up `/`** to the local repo (`/data5/restic-repo`), excluding the data
   partitions, caches, and transient state (`/proc`, `/sys`, `/tmp`, `/var/tmp`,
   `/var/cache`, `~/.cache`, browser locks, `/var/lib/{docker,systemd,…}`). Home,
   `/etc`, and `/root` — including their secrets — **are** included.
2. **Prunes** to the last few snapshots (`forget --keep-last N --prune`).
3. **Copies** the local repo to the cloud with `restic copy` (`--from-repo`
   local → `--repo rclone:<cloud-remote>:<path>`), same password — so the
   off-site copy is end-to-end encrypted.
4. **Emails a summary** (backup / prune / copy status) to `<you@example.com>`.

Everyday commands (`RESTIC_PASSWORD_FILE=/root/.restic-password` is set by the
script; export it yourself for ad-hoc use):

```bash
# run a backup now
sudo systemctl start restic-backup.service        # or: sudo /usr/local/sbin/restic-backup.sh

# list snapshots (local, then cloud)
sudo restic -r /data5/restic-repo snapshots
sudo restic -r rclone:<cloud-remote>:<path> snapshots

# integrity check (add --read-data-subset=10% to actually re-hash a sample)
sudo restic -r /data5/restic-repo check
```

> The local repo lives on `/data5` — the **same physical disk** as everything
> else. It's there for fast restores, **not** disaster recovery. The cloud copy
> is the real off-site backup.

## Layer 2 — Data backup (rclone sync)

`/usr/local/sbin/rclone-sync.sh` (timer `rclone-sync.timer`, daily) mirrors the
large data partitions (`/data1`–`/data5`, which restic excludes) to the cloud
remote with `rclone sync` followed by an `rclone check --checksum` verification
pass. This is a **mirror**, not versioned history: deletions propagate.

```bash
sudo systemctl start rclone-sync.service          # run a sync now
rclone check /data1 <cloud-remote>:/data1 --checksum   # verify one folder
```

## Layer 3 — Config versioning (system-changes)

The `system-changes` service auto-commits *system + home customizations* (not
secrets) to a private git repo in real time. It's documented in full under
[Application Configuration → Config tracking](04-application-configuration.md#config-tracking-changes-only-git-mirror).
Use it during a rebuild to **see and re-apply** what you'd changed (`make.conf`,
`package.use`, dotfiles, custom units, the `@world` set in
`var/lib/portage/world`) — it is *not* a data backup.

## Layer 4 — Bootstrap secrets (off-machine)

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
  The off-site backup is encrypted with it, and the only copies are on the
  (possibly dead) machine and *inside the backup it decrypts* — circular. Without
  an external copy, the cloud backup is unrecoverable.
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

---

## Restore scenarios

### A. Recover a file or directory (system healthy)

```bash
# browse a snapshot, then restore a path to a scratch location
sudo restic -r /data5/restic-repo snapshots
sudo restic -r /data5/restic-repo restore latest --target /tmp/restore --include /home/<user>/somefile
# (use -r rclone:<cloud-remote>:<path> if the local repo is gone)
```

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
   (partitions, LUKS+LVM, stage3, kernel, bootloader, GNOME).
2. Re-pull the [config repo](#layer-3--config-versioning-system-changes) and
   re-apply `make.conf`/`package.use`, then `emerge` the `@world` set from
   `var/lib/portage/world`.
3. Restore `/home` (and any `/etc` you didn't re-apply) from the cloud restic
   repo onto the running system.

**Route 2 — restore the whole system from the cloud.**
1. Boot a live USB; create the LUKS2 container + LVM exactly as in
   [Before Installation](01-before-installation.md), mount the new root.
2. Install/configure `rclone` (re-auth the remote) and set the restic password
   from your kit, then restore the latest snapshot onto the new root:
   ```bash
   export RESTIC_PASSWORD=...                       # from the bootstrap kit
   restic -r rclone:<cloud-remote>:<path> snapshots
   restic -r rclone:<cloud-remote>:<path> restore latest --target /mnt/gentoo
   ```
3. **Fix what's tied to the old disk** — the new LUKS/LVM have *new UUIDs*:
   - regenerate `/etc/fstab` from `blkid`,
   - update `GRUB_CMDLINE_LINUX` (`rd.luks.uuid=`, `resume=`) in
     `/etc/default/grub`,
   - chroot in (see [Access from a Live USB](06-access-system-from-live-usb.md)),
     then `grub-install`, `grub-mkconfig -o /boot/grub/grub.cfg`, and regenerate
     the initramfs (`emerge --config sys-kernel/gentoo-kernel` / `dracut --force`).
4. Reboot, then **re-sync data** (`rclone` the `/data*` partitions back down) and
   restore the bootstrap secrets into place.

> UUID/bootloader fix-up is the step people forget — a restored root with stale
> `fstab`/`grub` UUIDs won't boot. Do it before the first reboot.

---

## Verify — an untested backup is not a backup

Schedule yourself a recurring reminder to actually exercise these:

- `restic check` (periodically with `--read-data-subset`) on **both** repos.
- A **test restore** of a few files from the *cloud* repo (not just local) — it's
  the cloud copy you'll depend on in a real disaster.
- Confirm the **bootstrap kit still works**: `cryptsetup open --test-passphrase`
  with your stored passphrase/recovery key, and that `/root/.restic-password`
  matches what's in your password manager.
- After any LUKS key change, refresh the header backup (an old one still unlocks
  with the old key).

---

[← Documentation index](README.md) · Prev: [Various Tasks](07-various-tasks.md) · Ref: [System Reference](08-system-reference.md)
