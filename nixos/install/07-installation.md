# Phase D: Install

No chroot, unlike Gentoo. `nixos-install` builds the system from the flake
and sets up the bootloader, users and `/etc` itself. Everything is
downloaded from cache.nixos.org; nothing is copied from the Gentoo laptop.

What you bring on the installer USB stick (or a second stick):

* the pre-generated SSH host key pair from
  [0.5](00-prepare-on-gentoo.md#05-secrets-with-sops-nix)
  (`ssh_host_ed25519_key`, `.pub`)
* a read-only GitHub token for the private repository (or a copy of the
  repository itself)
* the files from the [export checklist](00-prepare-on-gentoo.md#07-export-checklist-before-the-wipe)
  that are not in restic

> [!NOTE]
> **Alternative:** nixos-anywhere installs the same flake remotely over SSH
> from the Gentoo laptop: it runs facter, disko and `nixos-install` for you,
> and Wi-Fi is enough. The manual steps below do the same thing and show what
> happens.
>
> ```bash
> nix run github:nix-community/nixos-anywhere -- --flake .#zbook \
>   --generate-hardware-config nixos-facter hosts/zbook/facter.json \
>   --extra-files ./staging root@<ip>     # ./staging/persist/etc/ssh/ssh_host_ed25519_key*
> ```

## D1. Boot the installer

1. Plug in the [custom installer](00-prepare-on-gentoo.md#08-custom-installer-iso)
   USB stick, power on, press F9, choose the USB device.
1. Become root: `sudo -i`
1. Connect Wi-Fi (no Ethernet here):
   * `nmcli device wifi connect "<SSID>" --ask`
   * Verify: `ping -c 2 nixos.org`
   * If Wi-Fi does not come up: USB-tether a phone, then check again.

## D2. Partition and format

1. Get the repository:
   * `git clone https://github.com/<you>/nixos-config /tmp/nixos-config`
     (username + the read-only token as password)
1. Identify the disk: `lsblk`. It should be `nvme0n1`; if not, correct
   `device` in `disko.nix`.
1. Write the LUKS passphrase for formatting. Use a long passphrase; it stays
   your fallback unlock. The keyboard is US here, and also at the boot
   prompt later.
   * `read -s P; echo -n "$P" > /tmp/luks.key`
1. Erase and format. **This destroys Windows:**

   ```bash
   nix --experimental-features "nix-command flakes" \
     run github:nix-community/disko/latest -- \
     --mode destroy,format,mount --flake /tmp/nixos-config#zbook
   ```

1. Verify the layout: `findmnt -R /mnt`. Expect tmpfs on `/mnt`, vfat on
   `/mnt/boot` and btrfs subvolumes on `/mnt/nix`, `/mnt/persist`,
   `/mnt/home`, `/mnt/var/log`, `/mnt/var/lib/docker`, `/mnt/swap` and the
   data volumes.
1. Remove the key file: `shred -u /tmp/luks.key`

If the disko version rejects `destroy,format,mount`, older releases used
`--mode disko` for the same operation.

## D3. Refresh the hardware report

Only needed if `facter.json` from Phase A4 is missing or the hardware
changed. Disks are not taken from the report: disko declares all mounts.

```bash
nixos-facter -o /tmp/nixos-config/hosts/zbook/facter.json
cd /tmp/nixos-config && git add -A      # flakes ignore untracked files
```

## D4. Prepare /persist before the first boot

On a tmpfs root, these files must exist on `/persist` before the system
starts. Without the host key, sops cannot decrypt the password hashes and you
cannot log in.

```bash
mkdir -p /mnt/persist/etc/ssh
cp /path/to/usb/ssh_host_ed25519_key* /mnt/persist/etc/ssh/
chmod 600 /mnt/persist/etc/ssh/ssh_host_ed25519_key
systemd-machine-id-setup --root=/mnt/persist
```

Passwords, the restic password, ntfy and healthchecks URLs all come from
`secrets/zbook.yaml`.

Restore the Wi-Fi and VPN profiles now, so the first boot is online:

```bash
mkdir -p /mnt/persist/etc/NetworkManager/system-connections
cp /path/to/usb/system-connections/* /mnt/persist/etc/NetworkManager/system-connections/
chmod 700 /mnt/persist/etc/NetworkManager/system-connections
chmod 600 /mnt/persist/etc/NetworkManager/system-connections/*
```

## D5. Install and reboot

```bash
nixos-install --flake /tmp/nixos-config#zbook --no-root-passwd
mkdir -p /mnt/home/ivmr/Work/claude-code
cp -r /tmp/nixos-config /mnt/home/ivmr/Work/claude-code/
chown -R 1000:100 /mnt/home/ivmr
reboot                                   # remove the USB stick
```

1. At boot, enter the LUKS passphrase. GDM appears; log in as `ivmr`.
1. Check: `findmnt /` shows tmpfs, and `~/claude-code/nixos-config` exists
   (bind mount onto `~/Work/claude-code`).
1. Commit the refreshed `facter.json` (if any) and push.

## D6. Connect Google Drive

rclone's built-in Google client is shared by all rclone users, rate-limited,
and stops working during 2026. Create your own OAuth client ID in the Google
Cloud console (free) and enter it during setup. If the Gentoo `rclone.conf`
files already use your own client ID, restore them from restic instead
([H2](09-first-boot.md#h2-restore-data)).

```bash
# 1. remote for backups (root, config on /persist):
sudo rclone config --config /persist/secrets/rclone.conf   # new remote "gdrive", type drive
#    scope: choose "drive.file" - this token can then only see files rclone itself
#    created (the restic repository), not the rest of your Drive (least privilege)
sudo chmod 600 /persist/secrets/rclone.conf
sudo systemctl start restic-backups-offsite     # first run initializes the repository

# 2. remote for folder sync (your user):
rclone config                                     # same: remote "gdrive", type drive,
#     scope "drive" (sync needs your existing folders); then in the main menu choose
#     "Set configuration password" to encrypt the file (it holds a full-Drive token)
secret-tool store --label="rclone config" service rclone    # same password, into the
                                                  # GNOME keyring: the timer reads it there
for d in Personal Work; do                        # one pair per synced folder
  rclone mkdir gdrive:$d && mkdir -p ~/$d/Drive
  rclone touch gdrive:$d/RCLONE_TEST && touch ~/$d/Drive/RCLONE_TEST
  rclone bisync ~/$d/Drive gdrive:$d --workdir ~/.local/state/rclone-bisync \
     --resync --dry-run                           # check the plan, then without --dry-run
done
systemctl --user start drive-sync                 # afterwards the timer runs every 15 min
```

> [!TIP]
> **Done when:** the system boots with the passphrase, you can log in,
> `findmnt /` shows tmpfs, and Wi-Fi connects by itself.
