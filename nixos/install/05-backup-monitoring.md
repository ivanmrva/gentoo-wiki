# Backup and monitoring

Part of [Phase B](02-flake-repository.md). Backups and health checks fail
silently unless something reports them, so this chapter has two halves: the
jobs, and what tells you when they fail or never run.

| Layer | Tool | Protects against |
| --- | --- | --- |
| Local snapshots | btrbk, hourly | Mistakes, bad updates, app data migrations |
| Offsite | restic → Google Drive, daily | Disk loss, theft |
| Integrity | restic check (weekly, 5 %), restore test (weekly) | Silent repository corruption |
| Failure alert | global `OnFailure` → ntfy push | A job that ran and failed |
| Dead-man's switch | healthchecks.io | A job that never ran |
| Daily report | `system-report` → ntfy, only when something is wrong | Slow problems: disk full, battery wear, pending reboot |
| Deep snapshot | `sysdiag` (weekly + on demand) | Data for Claude Code reviews |

## B14. modules/backup.nix

restic backs up read-only btrfs snapshots, not the live filesystem. Every run
is an atomic point-in-time copy (consistent SQLite databases, browser
profiles, git repos). The snapshot paths are fixed. In a test with restic
0.19.1, a fixed path let the second run report 199 of 200 files unmodified;
a changing path made restic re-read everything.

The NixOS restic module runs `forget --prune` and `check` after **every**
backup when `pruneOpts`/`checkOpts` are set. That would download about 5 % of
the repository from Drive every day. So the work is split into three
instances. An instance with `paths = [ ]` only does maintenance.

```nix
{ config, pkgs, lib, ... }:
let
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
  snap = sv: "/mnt/btr_pool/@snapshots/restic-${sv}";
  # DECISION: media offsite. Default: media stays off Google Drive (local btrbk only,
  # or an external disk / B2 later). Add "media" here to upload it (seed over days:
  # Drive caps uploads at 750 GiB/day).
  svs = [ "home" "persist" "personal" "work" "backup" ];
  repo = {
    repository = "rclone:gdrive:restic/zbook";
    rcloneConfigFile = "/persist/secrets/rclone.conf";   # on /persist: rclone rewrites it
    passwordFile = config.sops.secrets."restic/password".path;
    rcloneOptions = { drive-stop-on-upload-limit = true; };   # fail cleanly at 750 GiB/day
  };
in {
  services.btrbk.instances.local = {
    onCalendar = "hourly";
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "2d";
      snapshot_preserve = "48h 14d 6w";
      volume."/mnt/btr_pool" = {
        snapshot_dir = "@snapshots";
        subvolume = {
          "@home" = { }; "@persist" = { }; "@personal" = { }; "@work" = { };
          "@media" = { snapshot_preserve = "7d 4w"; };   # large: shorter history
        };
      };
    };
  };

  services.restic.backups = {
    offsite = repo // {
      initialize = true;                                  # create the repo on first run
      paths = map snap svs;
      exclude = [ "${snap "home"}/*/.local/share/containers" ];
      extraBackupArgs = [ "--exclude-caches" "--pack-size" "64" ];
      inhibitsSleep = true;
      timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; };
      backupPrepareCommand = lib.concatMapStrings (sv: ''
        ${btrfs} subvolume delete ${snap sv} 2>/dev/null || true   # leftover from a crash
        ${btrfs} subvolume snapshot -r /mnt/btr_pool/@${sv} ${snap sv}
      '') svs;
      backupCleanupCommand = lib.concatMapStrings (sv: ''
        ${btrfs} subvolume delete ${snap sv}
      '') svs + ''
        # dead-man's switch: success ping, or explicit failure ping
        url=$(cat ${config.sops.secrets."hc/backup".path})
        if [ "$SERVICE_RESULT" = success ]; then s=""; else s="/fail"; fi
        ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 "$url$s" || true
      '';
    };

    offsite-prune = repo // {
      paths = [ ];
      pruneOpts = [ "--keep-daily 7" "--keep-weekly 5" "--keep-monthly 12" "--max-repack-size 10G" ];
      timerConfig = { OnCalendar = "Sun 11:00"; Persistent = true; };
    };

    offsite-check = repo // {
      paths = [ ];
      checkOpts = [ "--read-data-subset=5%" ];
      timerConfig = { OnCalendar = "Wed 11:00"; Persistent = true; };
    };
  };

  # Weekly restore test: restore a sample from the latest snapshot and verify the
  # restored content against the repository's hashes.
  systemd.services.restic-restore-test = {
    description = "Weekly restic restore test";
    path = [ pkgs.restic pkgs.rclone pkgs.findutils ];
    environment = {
      RESTIC_REPOSITORY = repo.repository;
      RESTIC_PASSWORD_FILE = repo.passwordFile;
      RCLONE_CONFIG = repo.rcloneConfigFile;
      RESTIC_CACHE_DIR = "/var/cache/restic-backups-offsite";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
      restic restore latest --target "$t" --include "${snap "personal"}/Documents" --verify
      n=$(find "$t" -type f | wc -l)
      [ "$n" -gt 0 ] || { echo "restore produced no files"; exit 1; }
      echo "restored and verified $n files"
    '';
    startAt = "Sat 11:00";
  };
}
```

Check after the first build that the cleanup command really runs as
`ExecStopPost` (it has to, for `$SERVICE_RESULT`):
`systemctl cat restic-backups-offsite`.

> [!NOTE]
> **Backup architecture:** btrbk snapshots on the same SSD give fast local
> restore after mistakes and bad updates. restic on Google Drive is the
> offsite backup for disk loss and theft. Google Drive is a single offsite
> copy with no immutability: the laptop's token could also delete it if the
> laptop were compromised.
>
> **DECISION:** add a second, immutable copy (Backblaze B2 with a no-delete
> key and Object Lock, or an append-only `rclone serve restic --append-only`
> / rest-server), and/or an external disk as a btrbk target.

### rclone and Google Drive

rclone's shared Google client ID stops working during 2026. Create your own
OAuth client in the Google Cloud console (free) and enter it in `rclone
config`. Setup steps: [D6](07-installation.md#d6-connect-google-drive).

## B14b. modules/alerts.nix

One drop-in for **every** system service sends the last journal lines of a
failed unit to your phone via ntfy. No unit needs its own `onFailure` line.
The ntfy URL (a long random topic, or a self-hosted server) comes from sops.

```nix
{ config, pkgs, ... }:
let
  notify = pkgs.writeShellScript "notify-failure" ''
    unit="$1"
    url=$(cat ${config.sops.secrets."ntfy/url".path})
    ${pkgs.curl}/bin/curl -fsS -m 15 --retry 3 \
      -H "Title: zbook: $unit failed" -H "Priority: high" \
      -d "$(${config.systemd.package}/bin/journalctl -u "$unit" -n 20 --no-pager -o cat)" \
      "$url"
  '';
in {
  systemd.services."notify-failure@" = {
    description = "Push notification for failed unit %i";
    serviceConfig = { Type = "oneshot"; ExecStart = "${notify} %i"; };
  };

  # Top-level drop-in: applies to all services. The second file stops the notifier
  # from triggering itself in a loop if ntfy is unreachable.
  systemd.packages = [
    (pkgs.writeTextDir "lib/systemd/system/service.d/10-notify-failure.conf" ''
      [Unit]
      OnFailure=notify-failure@%n.service
    '')
    (pkgs.writeTextDir "lib/systemd/system/notify-failure@.service.d/10-no-loop.conf" ''
      [Unit]
      OnFailure=
    '')
  ];

  # SMART warnings as desktop notifications
  services.smartd.notifications.systembus-notify.enable = true;
  services.systembus-notify.enable = true;
}
```

Test it in the VM: `sudo systemd-run --unit=fail-test false` must produce a
push. If some unit fails harmlessly at every boot, give it an empty
`OnFailure=` drop-in rather than ignoring all pushes.

User units (like `drive-sync`) are not covered by the system drop-in; they
use desktop notifications.

### healthchecks.io

1. Create a free account and one check named `zbook-backup`, period 1 day,
   grace 1 day. Put its ping URL in `secrets/zbook.yaml` as `hc/backup`.
1. Under Integrations, add ntfy (or e-mail). Missing pings then alert you
   even when the laptop is off, asleep or the timer is broken.

## B14d. modules/system-report.nix

Replaces Gentoo's daily health digest e-mail. It runs daily and pushes to
ntfy **only when something needs attention**. The GLSA and self-packaged app
version checks are gone: nixpkgs and the flakes handle updates.

```nix
{ config, pkgs, lib, ... }:
let
  report = pkgs.writeShellScript "system-report" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils gnugrep gawk curl smartmontools upower fwupd config.systemd.package ])}
    issues=""
    add() { issues="$issues- $1"$'\n'; }

    for p in kernel initrd kernel-modules; do
      [ "$(readlink -f /run/booted-system/$p)" = "$(readlink -f /run/current-system/$p)" ] \
        || { add "reboot needed ($p changed since boot)"; break; }
    done
    f=$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
    [ -z "$f" ] || add "failed units: $f"
    for m in /persist /boot; do
      p=$(df --output=pcent "$m" | tail -1 | tr -dc 0-9)
      [ "$p" -lt 90 ] || add "$m is $p% full"
    done
    cap=$(upower -i "$(upower -e | grep -m1 BAT)" | awk '/capacity:/{print int($2)}')
    [ -z "$cap" ] || [ "$cap" -ge 80 ] || add "battery health $cap%"
    wear=$(smartctl -A /dev/nvme0n1 | awk '/Percentage Used:/{print int($3)}')
    [ -z "$wear" ] || [ "$wear" -lt 80 ] || add "NVMe wear $wear%"
    k=$(journalctl -k -p err --since=-1d --no-pager -q | wc -l)
    [ "$k" -eq 0 ] || add "$k kernel errors in 24 h (journalctl -k -p err)"
    fwupdmgr get-updates --json 2>/dev/null | grep -q '"Releases"' && add "firmware updates available"

    if [ -n "$issues" ]; then
      printf '%s' "$issues"
      curl -fsS -m 15 --retry 3 -H "Title: zbook: daily report" -d "$issues" \
        "$(cat ${config.sops.secrets."ntfy/url".path})"
    else
      echo "all good"
    fi
  '';
in {
  systemd.services.system-report = {
    description = "Daily quiet system report";
    serviceConfig = { Type = "oneshot"; ExecStart = report; };
    startAt = "*-*-* 10:00";
  };
  systemd.timers.system-report.timerConfig.Persistent = true;
}
```

This is a sketch: it has not been built or run yet. Build it in the VM, then
make each check fail on purpose once (for example by lowering a threshold).

## B14e. modules/diagnostics.nix

One root job that snapshots everything an agent needs to review the system.
You, and Claude Code (which has no sudo), may **start** it via a polkit rule,
then read the result in `/var/lib/sysdiag/latest` (group `wheel`). It also
runs weekly, so there is history to compare against. The persistence entries
(`/var/lib/sysdiag`, pstore) are in [B6](03-system-modules.md#b6-modulespersistencenix-preservation).
How it is used: [Phase I](10-operations.md#diagnostics-with-claude-code).

```nix
{ config, pkgs, ... }:
let
  luks = "/dev/disk/by-partlabel/disk-main-luks";
  collect = pkgs.writeShellScript "sysdiag-collect" ''
    export PATH=${pkgs.lib.makeBinPath (with pkgs; [
      coreutils findutils gnugrep gnused util-linux procps iproute2 nftables
      pciutils usbutils lm_sensors smartmontools nvme-cli btrfs-progs btrbk
      cryptsetup sbctl fwupd bolt power-profiles-daemon upower libva-utils
      networkmanager nvd config.nix.package config.systemd.package
      config.boot.kernelPackages.turbostat
    ])}
    out=/var/lib/sysdiag/$(date +%F_%H%M); mkdir -p "$out"
    # every probe is best-effort: one failing command never stops the report
    run() { f=$1; shift; { echo "\$ $*"; timeout 180 "$@"; echo "[exit $?]"; } >"$out/$f.txt" 2>&1; }

    run 00-system        sh -c 'nixos-version; uname -a; cat /proc/cmdline; uptime'
    run 01-failed        sh -c 'systemctl --failed --no-pager; systemctl list-timers --all --no-pager'
    run 02-errors        journalctl -b -p err --no-pager
    run 03-kernel        journalctl -k -b -p warning --no-pager
    run 04-prev-boot     journalctl -b -1 -p warning -n 400 --no-pager
    run 05-boot-time     sh -c 'systemd-analyze; systemd-analyze blame | head -40; systemd-analyze critical-chain'
    run 06-hardening     systemd-analyze security --no-pager
    run 10-hardware      sh -c 'lspci -nnk; lsusb -t; lsmod'
    run 11-firmware      sh -c 'fwupdmgr get-devices; fwupdmgr security --force'
    run 12-sensors       sensors
    run 13-power         sh -c 'powerprofilesctl; upower -d; cat /sys/power/mem_sleep;
                                grep -r . /sys/kernel/debug/pmc_core/slp_s0_residency_usec \
                                  /sys/kernel/debug/pmc_core/package_cstate_show'
    run 14-turbostat     turbostat --quiet --interval 5 --num_iterations 6 \
                           --show Busy%,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,Pkg%pc2,Pkg%pc6,Pkg%pc10,SYS%LPI
    run 15-video         vainfo
    run 16-thunderbolt   boltctl list
    run 20-disk          sh -c 'smartctl -a /dev/nvme0n1; btrfs filesystem usage /persist;
                                btrfs device stats /persist; btrfs scrub status /persist'
    run 21-memory        sh -c 'free -h; swapon --show; grep -r . /sys/kernel/debug/zswap/;
                                cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io'
    run 22-snapshots     btrbk -c /etc/btrbk/local.conf list snapshots
    run 30-boot-security sh -c 'bootctl status; sbctl status; sbctl verify;
                                cryptsetup luksDump ${luks}; systemd-cryptenroll ${luks}'
    run 40-nix           sh -c 'nix path-info -Sh /run/current-system;
                                ls -d /nix/var/nix/profiles/system-*-link | wc -l;
                                nvd diff /run/booted-system /run/current-system'
    run 50-not-persisted find / -xdev -type f -newer /run/booted-system
    run 51-crashes       sh -c 'coredumpctl list --no-pager; ls -la /var/lib/systemd/pstore'
    run 60-network       sh -c 'nmcli general; nmcli device; resolvectl status;
                                nft list ruleset; ss -tulpn'

    ln -sfn "$out" /var/lib/sysdiag/latest
    find /var/lib/sysdiag -mindepth 1 -maxdepth 1 -type d -mtime +60 -exec rm -rf {} +
  '';
in {
  systemd.services.sysdiag = {
    description = "Collect system diagnostics for review";
    startAt = "weekly";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = collect;
      Group = "wheel";                 # report readable by wheel, not world
      UMask = "0027";
      StateDirectory = "sysdiag";
      StateDirectoryMode = "0750";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  # Allow ivmr (and therefore Claude Code) to start exactly this unit, nothing else.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "sysdiag.service" &&
          action.lookup("verb") == "start" &&
          subject.user == "ivmr") {
        return polkit.Result.YES;
      }
    });
  '';

  # Tools Claude Code can run unprivileged during a review
  environment.systemPackages = with pkgs; [
    nvd nix-tree nix-output-monitor lm_sensors powertop pciutils usbutils
    intel-gpu-tools libva-utils acpica-tools iw
  ];
  documentation.man.generateCaches = true;        # `man configuration.nix` offline
  services.nixseparatedebuginfod2.enable = true;  # symbolised coredump backtraces
}
```

Some probes report nothing until the related part is set up, for example
`sbctl` before Phase E or `btrbk` before the first snapshot. Each probe writes
its own file, so a missing tool leaves an error in that file and the rest of
the report still completes.

Already in place without extra config: the journal is persistent (`@log`),
`wheel` can read the full system journal, and coredumps are on by default.
