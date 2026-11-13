# Secure Boot, TPM and hibernation

Phases E, F and G, in this order: the TPM binding measures the Secure Boot
state, so Secure Boot must be final before the TPM is enrolled.

## Phase E: Secure Boot with your own keys

1. Create your keys (stored in the persisted `/var/lib/sbctl`):
   `sudo sbctl create-keys`
1. Replace `modules/boot.nix` with the lanzaboote version below, then
   `sudo nixos-rebuild switch --flake ~/claude-code/nixos-config#zbook`
1. Check signatures: `sudo sbctl verify`. The lanzaboote EFI files must show
   as signed. Kernel images under `/boot/EFI/nixos` showing as unsigned is
   expected with lanzaboote.
1. Reboot into BIOS (F10) → Secure Boot Configuration: clear the Secure Boot
   keys so the firmware enters Setup Mode. Keep Secure Boot disabled for
   now. Confirm the HP code at the next boot.
1. Boot NixOS. `sudo sbctl status` must report Setup Mode enabled. Enroll
   your keys together with Microsoft's: `sudo sbctl enroll-keys --microsoft`
1. Reboot into BIOS, enable Secure Boot, save. Boot NixOS and confirm with
   `sudo sbctl status` (Secure Boot: enabled).
1. Back up `/var/lib/sbctl` (it is in restic via `@persist`) and keep a copy
   in your password manager.

### modules/boot.nix (lanzaboote version)

```nix
{ lib, ... }: {
  boot.loader.systemd-boot.enable = lib.mkForce false;   # lanzaboote replaces it
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 10;              # keeps the 2 GiB ESP from filling
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 1;
  boot.initrd.systemd.enable = true;
}
```

> [!NOTE]
> **Why `--microsoft`:** firmware components such as Thunderbolt option ROMs
> and firmware-update capsules are signed by Microsoft. Removing those keys
> can make the laptop fail to boot or block firmware updates. Also check that
> your sbctl version ships Microsoft's 2023 certificates (sbctl release
> notes), since the 2011 ones expire during 2026.

> [!TIP]
> If the laptop refuses to boot after enabling Secure Boot: enter BIOS,
> disable Secure Boot, boot NixOS, run `sudo sbctl verify` and fix what is
> unsigned, then retry. Nothing is lost.

## Phase F: TPM2 + PIN unlock

Only after Secure Boot is active, because the TPM binding measures the
Secure Boot state (PCR 7). BIOS updates normally do not change PCR 7, but a
Secure Boot database update (`db`/`dbx`) does: keep the recovery key at hand.

1. Confirm the partition label: `ls -l /dev/disk/by-partlabel/`. disko names
   it after the disk and partition (here `disk-main-luks`).
1. Create a recovery key and store it offline (password manager plus paper):
   `sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks --recovery-key`
1. Enroll the TPM with a PIN:

   ```bash
   sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks \
     --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes
   ```

1. In `disko.nix`, inside `settings`, add
   `crypttabExtraOpts = [ "tpm2-device=auto" ];` and rebuild.
1. Reboot: you are now asked for the TPM PIN instead of the passphrase. The
   passphrase and the recovery key remain valid fallbacks. The PIN is typed
   with the US console keymap.

> [!NOTE]
> **Upgrade path:** lanzaboote is adding Measured Boot via systemd-pcrlock,
> which binds the TPM to the exact measured boot chain instead of only the
> Secure Boot state (PCR 7). PCR 7 + PIN is a sound baseline; check the
> lanzaboote docs for pcrlock once it is released and documented.

## Phase G: Hibernation

1. Check the swapfile created on first boot: `swapon --show` lists
   `/swap/swapfile` (64G); `cat /sys/module/zswap/parameters/enabled` shows
   `Y`; `lsattr /swap/swapfile` must show the `C` (no copy-on-write) flag.
1. Get the physical offset:
   `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile`
1. In `power.nix`, add `boot.kernelParams = [ "resume_offset=N" ];` with that
   number, rebuild, reboot.
1. Test: `systemctl hibernate`. Power on, enter the TPM PIN; the session must
   come back intact.
1. Test the lid paths ([B8](03-system-modules.md#b8-modulespowernix)):
   * On battery: close the lid, wait more than 90 min (or temporarily set
     `HibernateDelaySec = "5min"`), open, and confirm resume from hibernation.
   * On AC: close the lid (screen locks, no suspend), then unplug: it must
     suspend, then hibernate after the delay.

> [!WARNING]
> Do not enable kernel lockdown mode (`lockdown=integrity`): it blocks
> hibernation. lanzaboote does not enable it by default.
