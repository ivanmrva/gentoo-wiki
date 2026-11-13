# Phase I: Operating the system

The essentials for the first weeks. Day-to-day work (adding software, dev
shells, pinning, Flatpak, GNOME, maintenance, performance) is in the
[operations guide](../operations/README.md).

## Updates

```bash
sysup        # git pull (CI merged the weekly flake.lock PR) + snapshot of @home/@persist
             # + nh os switch (diff, build, activate)
```

Without CI, update the lock locally instead: `nix flake update`, commit, push,
then `sysup`. Either way, `flake.lock` in git is the history of every system
version.

When the daily report says "reboot needed", the kernel, initrd or kernel
modules changed since boot. Everything else is active right after the
switch.

## Rollback

Boot menu: choose an older generation (press a key during the 1 s timeout).
From a running system: `sudo nixos-rebuild switch --rollback`. Revert the git
commit to make it permanent.

Rollback does not undo data that apps wrote in `/home` or `/persist`. If a
new app version migrated its data, restore that app's directory from the
snapshot `sysup` took before the update (`/mnt/btr_pool/@snapshots`).

## Before rebooting: what would be lost?

```bash
sudo find / -xdev -type f -newer /run/current-system 2>/dev/null
```

Lists files that exist only on the tmpfs root. Anything you want to keep
belongs in `persistence.nix`. Run it regularly during the first weeks; the
weekly `sysdiag` run records it in `50-not-persisted.txt`.

## Diagnostics with Claude Code

Claude Code has no sudo. It gathers root-level data by starting
`sysdiag.service` (allowed by a polkit rule for exactly that unit) and reads
everything else as `ivmr`:

* `/var/lib/sysdiag/latest/*.txt` and the older runs next to it
* `journalctl -b`, `-b -1`, `-k` (not `dmesg`, which is restricted),
  `-u <unit>`, `--user -b`
* `systemctl --failed`, `systemctl --user --failed`, `coredumpctl list`
* `nvd diff /run/booted-system /run/current-system`

It changes only the Nix config, builds, and hands you the diff. You run the
switch. Example prompt:

> Run `systemctl start sysdiag.service` and read `/var/lib/sysdiag/latest`,
> plus the previous run for comparison. Also check
> `journalctl --user -b -p warning` and `systemctl --user --failed`. Review
> the system against `docs/hardware.md` and `docs/decisions.md`: errors,
> battery and suspend (s0ix residency, power draw), thermals, boot time,
> security (Secure Boot, firewall, services), disk and backup health,
> unpersisted state, Nix store bloat. Give me a ranked list with evidence
> from the reports and a confidence for each. For the top items, make one
> commit per change and run `nix flake check` and `nixos-rebuild build`.
> Don't switch. Give me the `nvd diff` and what to test after I switch.

Optional: the `mcp-nixos` MCP server lets Claude Code look up packages and
option names directly instead of searching the web.

## Recovery drill (once, in the first weeks)

1. In a VM: boot the installer, run disko, `nixos-install --flake`.
1. Restore `/persist` and `/home` from restic.
1. Unlock the real laptop once with the recovery key to prove it works.

## Firmware updates

If `fwupdmgr get-devices` lists the BIOS, `fwupdmgr update` can apply it.
With your own Secure Boot keys, fwupd's EFI updater must be signed with your
keys. This is **unverified** for lanzaboote: check the lanzaboote and NixOS
fwupd documentation before the first BIOS update. Until then, use HP's
update option inside BIOS setup (F10, from network or USB), which needs no
operating system. Keep the LUKS recovery key at hand: a Secure Boot `dbx`
update can change PCR 7 and make the TPM ask for it.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Cannot log in after reboot | sops could not decrypt the password hashes: the host key is missing from `/persist/etc/ssh`. Boot the installer, unlock LUKS, mount `@persist`, copy the key back ([D4](07-installation.md#d4-prepare-persist-before-the-first-boot)). |
| Setting or file gone after reboot | Not persisted. Add the path to `persistence.nix`, rebuild. Recover it from btrbk snapshots under `@snapshots`. |
| Boot fails after an update | Choose the previous generation in the boot menu; revert the `flake.lock` commit. |
| Secure Boot violation at boot | Disable Secure Boot in BIOS, boot, run `sbctl verify`, rebuild, re-enable. |
| TPM PIN no longer accepted / not offered | Unlock with the passphrase or recovery key. Re-enroll: `systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes` on the LUKS partition. |
| Hibernation returns to a fresh boot | Wrong or missing `resume_offset`; repeat [Phase G](08-secure-boot-tpm-hibernation.md#phase-g-hibernation) step 2. The swapfile must be at least as large as RAM in use. |
| Lid close only suspends | Check that the systemd-suspend override is active: `systemctl cat systemd-suspend.service`. |
| Suspend aborts immediately | `journalctl -b -k \| grep -iE 'spd5118\|PM:'`; the `spd5118` blacklist must be active (`lsmod \| grep spd`). |
| Prebuilt binary fails with "not found" | It needs a dynamic loader: nix-ld is enabled; add missing libraries via `programs.nix-ld.libraries`. |
| No push for a failed unit | `systemctl status notify-failure@<unit>.service`; check the ntfy URL secret. |

## Appendix A: Restoring the factory state

1. BIOS (F10) → Secure Boot Configuration: reset Secure Boot keys to factory
   defaults. Confirm the HP code.
1. Clear the TPM.
1. Boot the HP recovery USB from [Phase A](01-windows-preparation.md) (F9)
   and restore, or restore the Clonezilla image.
1. Windows activates automatically from the license stored in the firmware.

## Appendix B: CLAUDE.md for the repository

```markdown
# Rules for agents working in this repository

This repo fully defines the NixOS system "zbook" (HP ZBook 8 G1i 14, A3ZU5ET#ABD).
You have no sudo. Never try `sudo`; use the paths below.

## Context to read first
- docs/hardware.md   — exact hardware, known quirks, what was tested (Phase H results)
- docs/decisions.md  — choices already made and WHY (e.g. wpa_supplicant not iwd,
                       rootful Docker not Podman). Do not propose reverting a decision
                       unless new evidence contradicts its stated reason; cite it.
- hosts/zbook/facter.json — hardware report

## Gathering data (no root needed)
- Root-level snapshot: `systemctl start sysdiag.service`, then read
  /var/lib/sysdiag/latest/*.txt. Older runs sit next to it: compare against them.
- Logs: `journalctl -b`, `-b -1` (previous boot), `-k` (kernel; `dmesg` is
  restricted), `-u <unit>`, `--user -b`. `systemctl --failed`, `systemctl --user --failed`.
- Crashes: `coredumpctl list` / `coredumpctl info <pid>`.
- What changed: `nvd diff /run/booted-system /run/current-system`; git log of this repo.
- Option names: `man configuration.nix` or the NixOS MCP server. Never guess an option.

## Changing the system
- Edit the Nix config only. Never edit /etc or /var on the machine.
- Verify: `nix flake check` and `nixos-rebuild build --flake .#zbook`. Both must pass.
- Do NOT switch or reboot. Hand the user the diff + `nvd diff` of the build
  (`nvd diff /run/current-system ./result`) and what to test after switching.
- Root is a tmpfs: new state needs an entry in modules/persistence.nix.
  /var/lib/sysdiag/latest/50-not-persisted.txt lists files that would be lost.
- Never put secrets in the repo in plain text; they go into secrets/zbook.yaml (sops).
- Keep a single nixpkgs input; every new flake input uses
  `inputs.nixpkgs.follows = "nixpkgs"`.
- Do not enable kernel lockdown or security.protectKernelImage (break hibernation).
- Every finding states evidence (file + line from the sysdiag report or a command
  output) and confidence. One change per commit. Format with nixfmt.
```

## Appendix C: docs/decisions.md (seed)

Start the file with the decisions from this guide, each with its reason:

| Decision | Reason |
| --- | --- |
| wpa_supplicant, not iwd | NixOS default; iwd labelled experimental in nixpkgs; no gain |
| Rootful Docker, not Podman | Dev Containers, Testcontainers, compose, Playwright images assume Docker |
| Stock kernel, no custom config | No binary cache for custom kernels; Gentoo builds took 44–80 min |
| `spd5118` blacklisted | DDR5 SO-DIMM suspend abort; fix only in Linux ≥ 7.4 |
| thermald off | Reported Arrow Lake throttling regression; enable only on evidence |
| No auto-suspend on AC; lid on AC locks | Ported Gentoo behaviour (`inhibit-sleep-on-ac`) |
| restic split into backup / prune / check | Module runs prune+check after every backup otherwise |
| Fixed restic snapshot paths | Changing paths make restic re-read every file |
| `~/claude-code` path kept | Claude Code project memory is keyed by path |
| Power daemon, offsite copy, 1Password, terminal | **Open**: fill in when decided |
