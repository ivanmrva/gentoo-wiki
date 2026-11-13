# Phase H: First boot

Hardware tests first, then data. Record every result in `docs/hardware.md`
of the repository: it is the context Claude Code reads before changing
anything ([Phase I](10-operations.md#diagnostics-with-claude-code)).

## H1. Hardware checklist

| Check | How | Pass |
| --- | --- | --- |
| Baseline | `systemctl start sysdiag.service`, keep `/var/lib/sysdiag/latest` | Report complete |
| Suspend (spd5118) | `systemctl suspend`, resume; `journalctl -b -k \| grep -i spd5118` | Resumes; no suspend abort with `-6` |
| Suspend drain | Suspend 1 h on battery, compare battery % | About 1–2 %/h or less; check `13-power.txt` (s0ix residency) if worse |
| Hibernation | [Phase G](08-secure-boot-tpm-hibernation.md#phase-g-hibernation) tests | Session restored after PIN |
| Lid on AC | Close lid on AC, then unplug | Locks on AC; suspends after unplug |
| Audio | `wpctl status`; speakers, built-in mics | Speakers and mic array listed and working |
| Mute LEDs | Press mute and mic-mute | If the LEDs stay off: enable the `model=103c:8d91` line in [B9](03-system-modules.md#b9-moduleshardware-intelnix), rebuild, reboot, retest |
| Camera | GNOME Snapshot or a browser test page | Picture works (USB UVC camera) |
| Fingerprint | `lsusb \| grep -i goodix` vs the libfprint list; `fprintd-enroll` | Enrolls and unlocks, or documented as unsupported |
| Brightness | Brightness keys and the GNOME slider | Full range, no flicker (no backlight kernel params set) |
| Video decode | `vainfo`; `chrome://gpu`; `intel_gpu_top` during a video call | Codecs listed; Chrome "Video Decode: Hardware accelerated"; video engine busy (if not: [operations guide 12.4](../operations/12-performance.md#124-chrome-hardware-video-acceleration)) |
| Displays/dock | USB-C/Thunderbolt monitor, dock USB; `boltctl list` | All work; dock stays authorised after a reboot |
| Thermals | Sustained load (a large build), watch `turbostat` | No heavy throttling; else try `services.thermald.enable = true` |
| Cowork | Start a Cowork session in Claude Desktop | VM starts (`/dev/kvm`, `/dev/vhost-vsock` are mode 0666) |
| restic | Run `restic-backups-offsite` twice | Second run reports most files "unmodified" |
| Alerts | `sudo systemd-run --unit=fail-test false` | ntfy push arrives |
| Platform security | `fwupdmgr security` (Host Security ID) | Note the HSI level; fix BIOS settings it flags |
| DMA protection | `cat /sys/bus/thunderbolt/devices/domain0/iommu_dma_protection` | `1` |
| Open ports | `sudo ss -tulpn` | No unexpected listeners |
| Time sync | `ntp-ctl status` | NTS sources reachable, clock synchronized (NTS needs TCP port 4460 outbound; some captive-portal or corporate networks block it) |
| Firmware | `fwupdmgr get-devices` | Note whether the BIOS is listed as updatable (LVFS) |

Anything failing goes into `hardware-intel.nix` as a fix, or into
`docs/hardware.md` as a documented limitation.

## H2. Restore data

The Gentoo restic repositories are documented in the Gentoo guide:
[Backup, clone & restore](../../gentoo/09-backup-restore.md). Use the Gentoo
repository's own password and rclone remote. Restore **selectively**; do not
restore old dotfiles that home-manager now manages (`.bashrc`, `.gitconfig`,
`.config/Code/User/settings.json` if declared).

```bash
export RESTIC_REPOSITORY=<gentoo-repo> RESTIC_PASSWORD_FILE=<file>   # see ../docs/09-backup-restore.md

# personal data: /data/personal → ~/Personal
restic restore latest:/data/personal --target ~/Personal

# selected parts of the old home
restic restore latest:/home/ivmr --target ~/ \
  --include /.ssh --include /.gnupg --include /.claude --include /.claude.json \
  --include /.config/gh --include /.local/share/keyrings \
  --include /.config/monitors.xml --include /.cert
```

Run each restore with `--dry-run -v` first: check that the include
patterns match (with the `snapshot:subfolder` form they are relative to the
subfolder) and that nothing lands where home-manager owns a file.

Then:

1. `~/Work`: restore what you backed up in
   [0.7](00-prepare-on-gentoo.md#07-export-checklist-before-the-wipe), and
   clone the repositories under `~/claude-code` from GitHub.
1. Browser and mail profiles: copy them from the restored Flatpak paths
   (`.var/app/...`) to the native locations listed in 0.7, then start each
   app once.
1. Log in: Google (Chrome sync), Firefox sync, Thunderbird accounts, Slack,
   Zoom, GitHub (`gh auth status`), Claude Desktop, ChatGPT, Claude Code.
1. Bluetooth devices: pair again.
1. Fingerprint: enroll with `fprintd-enroll` (if supported).

## H3. Re-tune machine budgets

The 285H (16 cores: 6 performance, 8 efficient, 2 low-power, about 45 W)
is much stronger than the old i7-1270P at 30 W. The "Machine budget" section
in `~/.claude/CLAUDE.md` and the parallelism caps in `~/.claude/settings.json`
(subagents, Vitest forks) were sized for the old laptop.

1. Run a real workload (a full test suite, a large build).
1. During it, run `systemctl start sysdiag.service` and keep the turbostat
   output (`14-turbostat.txt`).
1. Ask Claude Code to propose new limits from that data.

> [!TIP]
> **Done when:** every row in H1 passes or is documented, your data is back,
> and `docs/hardware.md` describes the machine as it really behaves.
