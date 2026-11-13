# SUDO users

1. Edit /etc/sudoers and uncomment the following line: `%wheel ALL=(ALL:ALL) NOPASSWD: ALL`
   * Make sure the user is part of the _wheel_ user group.

# Bash history

1. Add to _~/.bashrc_:

   ```
   # bash history memory size
   export HISTSIZE=20000
   # bash history file size
   export HISTFILESIZE=20000
   # append history from multiple opened terminals to one file (no overwriting on exit)
   shopt -s histappend
   # displays history commands from other terminals in real-time
   PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"
   ````

# Audio (PipeWire)

Audio is handled by **PipeWire** with **WirePlumber** as the session manager
(the modern replacement for PulseAudio; the GNOME profile pulls it in). Enable
the user services:

1. `systemctl --user enable wireplumber.service`
1. The `pipewire.socket` and `pipewire-pulse.socket` user sockets provide the
   PulseAudio-compatible API for apps that still expect it — they are enabled by
   default with the package; verify with `systemctl --user list-unit-files --state=enabled`.

# Systemd services

1. Enable useful system services as you install their packages:
   * `systemctl enable bluetooth.service`
   * `systemctl enable docker.service` (see [Application Configuration](04-application-configuration.md#docker))
   * `systemctl enable earlyoom.service` (kills runaway processes before the system OOM-freezes)
   * `systemctl enable smartd.service` (S.M.A.R.T. disk monitoring, from `smartmontools`)
   * `systemctl enable lm_sensors.service` (after running `sensors-detect`)
   * `systemctl enable nftables.service` (firewall — see [Networking & firewall](#networking--firewall) for the ruleset and where it lives)
   * `systemctl enable fstrim.timer` (periodic SSD TRIM)

   > **earlyoom vs. systemd-oomd.** On a systemd profile `systemd-oomd.service`
   > also ends up **enabled by preset**, so out of the box you run *both* OOM
   > guards. On this machine `/etc/systemd/oomd.conf` has only an empty `[OOM]`
   > stanza (no pressure limits, no `ManagedOOM*` properties on any slice), so
   > oomd is effectively inert and **earlyoom is the real guard** — a redundant
   > pair, not a deliberate split. Pick one: either configure oomd properly and
   > drop earlyoom, or `systemctl mask systemd-oomd.service` and keep earlyoom.

1. Custom system units this machine adds (see [System Reference](08-system-reference.md)
   for the full unit text):
   * `systemctl enable system-changes.service` — long-running inotify watcher that
     auto-commits `/etc`, `/usr/local`, a `$HOME` allowlist and the `world` set to a
     changes-only git mirror (the config-versioning layer; details in
     [Config tracking](04-application-configuration.md#config-tracking-changes-only-git-mirror)).
   * `systemctl enable inhibit-sleep-on-ac.service` — paired with a udev rule, it
     blocks all auto-sleep while on AC (see [Power Management → Sleep & hibernate](#sleep--hibernate)).

1. Scheduled-automation timers (backup + maintenance). These are enabled but their
   detail lives elsewhere — don't re-invent them here:
   * **restic backup/check stack** — `restic-backup.timer` (root FS, Fri 20:00),
     `restic-backup-data1.timer` (`/data1`, daily 21:00), `restic-prune.timer`
     (monthly), `restic-prune-data1.timer` (day-05 03:00),
     `restic-check@structure.timer` (Wed 22:00), `restic-check@readdata.timer`
     (day-10 02:00), `restic-restore-test.timer` (Mon 22:00). Full architecture in
     [Backup & Restore](09-backup-restore.md).
   * **maintenance/health** — `portage-maintenance.timer` (Sun 03:00:
     `eclean-dist`/`eclean-pkg`/`eix-update`, *not* `--sync` or `@world` upgrades),
     `system-health-digest.timer` (daily 08:00, the digest email),
     `fwupd-update-check.timer` (weekly). See [System Reference](08-system-reference.md#enabled-services).
   * **snapshots** — `snapper-timeline.timer` + `snapper-cleanup.timer` (both hourly,
     `/data1` only); `snapper-boot.timer` left disabled.

> **Heads-up on cruft.** The live system carries a few enable-list leftovers worth
> cleaning rather than copying: a **dangling** `timers.target.wants/rdiff-backup-root.timer`
> symlink pointing at a unit that no longer exists (rdiff-backup era), an unused
> `snapper-daily@` template superseded by the upstream `snapper-timeline`/`-cleanup`
> timers, and `*.bak.*-20260621` copies of the restic units left from the
> backup-target migration. They are harmless but not "clean".

# Gnome Configuration

The click-through below is the fast path. Each item is annotated with the resulting
**dconf key/value** so the same state can be restored non-interactively with
`dconf write` (or replayed from the `system-changes` dconf snapshot) instead of
clicking — useful when recreating the machine.

1. Open Gnome Settings and change:
   * **Appearance** → Accent colour = Blue, Style = Light
     → `/org/gnome/desktop/interface/accent-color='blue'`,
     `color-scheme='default'`
   * **Displays** → Resolution / Scale (eDP-1 is 2560×1600@120, scale 2; docking
     profiles for the Panasonic TV and Samsung 4K are saved in `~/.config/monitors.xml`)
   * **Displays** → Night Light = ON, Manual, 21:10 onward, 2700 K
     → `/org/gnome/settings-daemon/plugins/color/night-light-enabled=true`,
     `night-light-schedule-automatic=false`,
     `night-light-schedule-from=21.1666…` (= 21:10), `night-light-temperature=uint32 2700`
   * **Sound** → Alert Sound = None (and Terminal bell off, below)
   * **Power** → Show battery percentage
     → `/org/gnome/desktop/interface/show-battery-percentage=true`
   * **Power** → don't auto-suspend on battery (logind drives sleep instead — see
     [Sleep & hibernate](#sleep--hibernate))
     → `/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type='nothing'`
     (only the battery key is set; on AC, suspend is blocked by the
     [on-AC inhibitor](#never-auto-sleep-while-on-ac-custom), not a dconf key)
   * **Multitasking** → Fixed number of workspaces = 2
     → `/org/gnome/mutter/dynamic-workspaces=false`,
     `/org/gnome/desktop/wm/preferences/num-workspaces=2`
   * **Search** → Search Locations → add custom locations as desired
   * **Online accounts** → add accounts as desired
   * **Mouse & Touchpad** → two-finger scroll on, disable-while-typing off
     → `/org/gnome/desktop/peripherals/touchpad/two-finger-scrolling-enabled=true`,
     `disable-while-typing=false`
   * **Keyboard** → Input sources → US English + Switzerland (German)
     → `/org/gnome/desktop/input-sources/sources=[('xkb','us'),('xkb','ch')]`
   * **System → Region & Language** → Language = English (US), Formats = Switzerland
     (matches `locale.conf`: `LANG=C.UTF8` + `LC_TIME/…=en_GB.UTF-8`)
   * **System → Date & Time** → Automatic = ON, Timezone = Zurich, 24h, clock shows
     weekday + seconds
     → `/org/gnome/desktop/interface/clock-show-seconds=true`,
     `clock-show-weekday=true`

1. Prevent grouping windows when Alt+Tab (cycle individual windows, not app groups):
   * Keyboard → Shortcuts → Switch windows = Alt+Tab
     → `/org/gnome/desktop/wm/keybindings/switch-windows=['<Alt>Tab']`,
     `switch-windows-backward=['<Shift><Alt>Tab']`, and
     `switch-applications`/`switch-applications-backward` emptied (`@as []`)

1. Custom **media-key** bindings (`/org/gnome/settings-daemon/plugins/media-keys`):
   * On-screen keyboard = `<Super>k` → `on-screen-keyboard=['<Super>k']`
   * Brightness up = `<Super>F4` → `screen-brightness-up=['<Super>F4']`

1. **Nautilus** → list view + tree, small zoom
   → `/org/gnome/nautilus/preferences/default-folder-viewer='list-view'`,
   `list-view/use-tree-view=true`, `default-zoom-level='small'`.

1. **Terminal** (default profile) → scrollback 100000, audible bell off
   → `/org/gnome/terminal/legacy/profiles:/.../scrollback-lines=100000`,
   `audible-bell=false`.

## GNOME Shell extensions

Three extensions are installed under `~/.local/share/gnome-shell/extensions/` and
enabled:
* **Vitals** (`Vitals@CoreCoding.com`) — system sensors in the panel (user-installed).
* **Clipboard Indicator** (`clipboard-indicator@tudmotu.com`) — clipboard history
  (user-installed).
* **Removable Drive Menu** (`drive-menu@…`) — from `gnome-extra/gnome-shell-extensions`.

> Stale entry: dconf `enabled-extensions` also lists `gjsosk@vishram1123.com` (an
> on-screen keyboard) which is **not installed on disk** — a dead reference to prune,
> not something to install.

## Other XDG / Nautilus touches (optional)

* `~/.config/user-dirs.dirs` adds `XDG_PROJECTS_DIR="$HOME/Projects"`.
* `~/.config/gtk-3.0/bookmarks` (Nautilus sidebar): Documents/Music/Pictures/Videos/
  Downloads, `~/claude-code`, `/`, and `/data1`–`/data5`.
* `~/.config/git/ignore` (global gitignore): `**/.claude/settings.local.json`.

# Intel Graphics: Vaapi 

1. Make sure _/etc/portage/make.conf_ contains the `USE="vaapi"`.
1. Install vaapi driver for intel cards:
   * `emerge libva-intel-media-driver`
1. Verify correct driver usage:
   * `emerge media-video/libva-utils`
   * `vainfo`
      * It should like something like this: 
          ```
          vainfo: VA-API version: 0.35 (libva 1.3.1)
          vainfo: Driver version: Intel i965 driver - 1.3.0
          vainfo: Supported profile and entrypoints
          VAProfileMPEG2Simple            :	VAEntrypointVLD
          VAProfileMPEG2Simple            :	VAEntrypointEncSlice
          VAProfileMPEG2Main              :	VAEntrypointVLD
          VAProfileMPEG2Main              :	VAEntrypointEncSlice
          VAProfileH264ConstrainedBaseline:	VAEntrypointVLD
          VAProfileH264ConstrainedBaseline:	VAEntrypointEncSlice
          VAProfileH264Main               :	VAEntrypointVLD
          VAProfileH264Main               :	VAEntrypointEncSlice
          VAProfileH264High               :	VAEntrypointVLD
          VAProfileH264High               :	VAEntrypointEncSlice
          VAProfileVC1Simple              :	VAEntrypointVLD
          VAProfileVC1Main                :	VAEntrypointVLD
          VAProfileVC1Advanced            :	VAEntrypointVLD
          VAProfileNone                   :	VAEntrypointVideoProc
          VAProfileJPEGBaseline           :	VAEntrypointVLD
          ```
1. Verify HW encoding/decoding is actually being used during playback. Two options:
   * **`intel_gpu_top`** — ships with `x11-apps/igt-gpu-tools`, which is **not
     installed on this machine** (it was dropped from `@world`). Install it on
     demand if you want the live engine view; with a video playing, the `Video`
     engine line should be non-zero:
       ```
       ENGINES     BUSY                                                                        MI_SEMA MI_WAIT
       Render/3D   23.92% |█████████████████████                                              |      0%      0%
       Blitter    0.00% |                                                                   |      0%      0%
       Video    7.98%
       ```
   * **No extra package needed:** `vainfo` (from the already-installed
     `media-video/libva-utils`) confirms the driver loads and exposes
     encode/decode entrypoints — enough to verify the stack without `igt-gpu-tools`.

> Chrome is launched with `--enable-features=AcceleratedVideoEncoder` via the
> local `google-chrome.desktop` override (see [GNOME Configuration](#gnome-configuration)),
> and `LIBVA_DRIVER_NAME=iHD` is set in `make.conf` to pick the modern
> `intel-media-driver`.

See also https://wiki.gentoo.org/wiki/VAAPI

# Power Management

## thermald + TLP

1. Intel's thermal daemon:
   * `emerge thermald`
   * `systemctl enable thermald`
   * On this machine thermald runs **`--adaptive`** (DPTF adaptive policy). There
     is **no custom thermald XML** — the files under `/etc/thermald/` are the stock
     `sys-power/thermald` defaults, so nothing extra needs configuring.

1. TLP (AC vs. battery power tuning):
   * `emerge sys-power/tlp` — do **not** also install _laptop-mode-tools_
     (they conflict; TLP is the modern alternative with safe defaults OOTB).
   * `systemctl enable tlp` — and **mask `tlp-pd.service`** (the radio-device
     power-down helper); plain `tlp` is used here, `tlp-pd` is left masked.
   * Do **not** install `sys-power/power-profiles-daemon` — it conflicts with TLP.

The only non-default (uncommented) lines in `/etc/tlp.conf` on this machine —
performance-on-AC, frugal-on-battery:

```ini
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
CPU_HWP_DYN_BOOST_ON_BAT=1
CPU_MAX_PERF_ON_AC=100
CPU_MAX_PERF_ON_BAT=70
PCIE_ASPM_ON_BAT=powersave
WIFI_PWR_ON_BAT=on
NMI_WATCHDOG=0
```

Everything else is left at TLP's stock template. Two caveats specific to this
hardware:
- **Battery charge thresholds are NOT set** (`START_/STOP_CHARGE_THRESH_BAT*`
  stay commented). If the ZBook firmware exposes them, 75/80 would help longevity —
  verify with `tlp-stat -b`.
- **`platform_profile` is unavailable** on this machine, so any `PLATFORM_PROFILE_*`
  lines would be inert (they are left commented).

## UPower critical-battery action

`/etc/UPower/UPower.conf` is otherwise stock, but the critical-battery behaviour is
worth knowing: at **2%** battery UPower **hibernates** the machine.

```ini
UsePercentageForPolicy=true
PercentageAction=2.0
CriticalPowerAction=Hibernate
AllowRiskyCriticalPowerAction=false
```

## Sleep & hibernate

This laptop uses **suspend-then-hibernate** (s2idle suspend first, RTC-wake to a
real hibernate later). Hibernation writes to the 32 GiB encrypted `vg0-swap` LV
(sized = RAM); zram swap can't hold a hibernation image, so it isn't the resume
target. See [System Reference](08-system-reference.md) for the `resume=` cmdline
and dracut `resume` module.

> Note: when this policy was adopted, **`mem_sleep_default=deep` was removed** from
> `GRUB_CMDLINE_LINUX` (a `/etc/default/grub.bak-presuspend` backup preserves the old
> line). Forcing S3 deep-sleep is incompatible with the s2idle-then-hibernate flow,
> so don't re-add it.

**logind lid switch** — `/etc/systemd/logind.conf.d/10-lid.conf`:
```ini
HandleLidSwitch=suspend-then-hibernate          # on battery
HandleLidSwitchExternalPower=suspend            # on AC (shadowed by the AC inhibitor below)
HandleLidSwitchDocked=ignore                    # external monitor/dock: do nothing
```

**logind idle action** — `/etc/systemd/logind.conf.d/20-idle.conf`:
```ini
IdleAction=suspend-then-hibernate
IdleActionSec=25min
```
The 25-minute value plus a deliberate offset: logind's idle clock only starts once
GNOME flags the session idle, which happens at GNOME `idle-delay=300s` (5 min). So
`25min + ~5min ≈ 30 min` of real inactivity before the first suspend. **GNOME's own
auto-suspend on battery is disabled** (`sleep-inactive-battery-type='nothing'`; the
AC key is left at its default and handled by the on-AC inhibitor below instead), so
**logind is the sole idle driver** — if you change GNOME `idle-delay`, re-tune
`IdleActionSec`.

**sleep delay** — `/etc/systemd/sleep.conf.d/10-hibernate.conf`:
```ini
AllowSuspendThenHibernate=yes
SuspendState=mem
HibernateDelaySec=30min
```

Combined timeline (on battery), measured from last activity:

| Time | What happens |
|---|---|
| 0–5 min | GNOME blanks + locks the screen |
| ~30 min | suspend to RAM (s2idle) — `IdleActionSec=25min` + ~5 min GNOME offset |
| ~60 min | RTC wake → hibernate to the encrypted swap LV — `HibernateDelaySec=30min` after the suspend |

Lid-close on battery follows the same suspend-then-hibernate path.

## Never auto-sleep while on AC (custom)

A two-file mechanism (no helper script) holds a sleep inhibitor whenever the machine
is plugged in, so none of the idle/lid policy above fires on AC; unplug and the
battery suspend-then-hibernate policy resumes.

1. udev rule `/etc/udev/rules.d/99-inhibit-sleep-on-ac.rules` — starts/stops the
   service on AC plug/unplug:
   ```
   SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemctl --no-block start inhibit-sleep-on-ac.service"
   SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemctl --no-block stop  inhibit-sleep-on-ac.service"
   ```
2. service `/etc/systemd/system/inhibit-sleep-on-ac.service` (`ConditionACPower=true`,
   enabled, `WantedBy=multi-user.target`):
   ```
   ExecStart=/usr/bin/systemd-inhibit --what=sleep:idle --who=ac-power-policy \
     --why="On AC power: auto sleep disabled" --mode=block sleep infinity
   ```
   It holds a **block** inhibitor on `sleep:idle`, covering the logind idle action,
   explicit suspend/hibernate, and lid close. `ConditionACPower=true` makes a
   boot-on-AC start correctly and a stray start-on-battery a no-op.

Check also https://wiki.gentoo.org/wiki/Power_management/Guide

# Networking & firewall

Networking is **NetworkManager** (stock defaults — no custom `NetworkManager.conf`
drop-ins). Wi-Fi is `wlp0s20f3`, WWAN is `wwan0`. Saved Wi-Fi profiles live in
`/etc/NetworkManager/system-connections/*.nmconnection` (root-only, contain PSKs);
they are deliberately excluded from the config mirror.

## nftables (default-deny inbound)

> **Path gotcha:** the ruleset is `/etc/nftables/rules/main.nft`, **not** the legacy
> `/etc/nftables.conf`. Current Gentoo's `net-firewall/nftables` ships an
> `nftables.service` that hard-codes the new path (via `ConditionPathExists` +
> `ExecStart=/sbin/nft 'flush ruleset; include "/etc/nftables/rules/main.nft"'`).
> There is no `/etc/nftables.conf` here, and writing one would do nothing. Put your
> rules in `/etc/nftables/rules/main.nft`.

The ruleset is a host firewall: a single `inet filter` table (covers IPv4 + IPv6)
with one `input` chain at `policy drop`. It defines **no** `forward`/`output` chain,
so outbound traffic and Docker's own (iptables-legacy) chains are left untouched.

```nft
# Laptop host firewall: default-deny inbound, everything else open.
# Does NOT define forward/output chains -> Docker (iptables-legacy) and
# all outbound traffic are left completely untouched.
table inet filter {
	chain input {
		type filter hook input priority filter; policy drop;

		ct state established,related accept   # replies to our own traffic (DNS, HTTP, etc.)
		ct state invalid drop
		iif "lo" accept                       # loopback
		iifname "docker0" accept              # let containers reach host services

		meta l4proto ipv6-icmp accept         # IPv6 ND/RA - required or IPv6 breaks
		meta l4proto icmp accept              # ping / ICMP errors

		udp dport { 68, 546 } accept          # DHCP / DHCPv6 client (wifi lease)
		udp dport 5353 accept                 # mDNS (avahi local discovery)
		# To allow inbound SSH later: add ->  tcp dport 22 accept
	}
}
```

`net-firewall/iptables` is installed only for Docker's legacy chains; the nftables
ruleset intentionally doesn't touch them. There is no inbound SSH (the rule above is
left as a commented hint).

## DNS

`systemd-resolved` is enabled + active **but runs in `foreign` mode** — it is *not*
the resolver glibc uses. NetworkManager writes `/etc/resolv.conf` itself as a plain
file pointing straight at the upstream/router DNS:

```
# Generated by NetworkManager
nameserver <router-ip>
```

So the `127.0.0.53` resolved stub is **not** in the lookup path here. If you actually
want resolved's stub (split DNS, DNSSEC, caching), switch NetworkManager to
`dns=systemd-resolved` — otherwise resolved is running but bypassed.

## VPN

`net-vpn/networkmanager-openvpn` is the explicit VPN choice (it pulls in `openvpn` as
a dependency); VPNs are configured through the NetworkManager GUI. `/etc/hosts` is
stock/unmodified.

# Verify Kernel configuration

1. Verify microcode is loaded:
   * `dmesg | grep microcode`
      * It should contain a message like: _microcode: microcode updated early to revision 0xa4, date = 2010-10-02_
1. Verify loading of Intel Graphic firmware
   * dmc, guc, huc

# Verify Portage package logs

1. Fix warnings, suggestion or kernel configuration based on the logs of all installed packages:
   * Check portage logs with `elogv`

# modprobed-db (obsolete — not used on this machine)

> **Not installed.** This machine runs the **distribution kernel**
> (`gentoo-kernel`), which ships a generic config and its own initramfs — there is
> no hand-rolled `localmodconfig` build to trim, so `modprobed-db` buys nothing here
> and is not installed. The steps below are kept only for reference if you ever
> switch back to a manually-configured `sys-kernel/gentoo-sources` build.

1. `sudo emerge modprobed-db`
1. `modprobed-db store` (create db and store modules to file)
1. `systemctl --user enable modprobed-db` (auto-updates to modules file)
1. Next time use module DB for kernel compilation:
   * `make LSMOD=$HOME/.config/modprobed.db localmodconfig`

# Optional: Sync Portage over GIT

> This guide's machine currently uses the **default rsync sync**
> (`sync-type = rsync`, `rsync://rsync.gentoo.org/gentoo-portage`) that the
> stage3 ships with — it works fine and is OpenPGP-verified. The git method
> below is an optional alternative (full history, easy local diffs); switch to
> it only if you want those.

1. Create `/etc/portage/repos.conf/gentoo.conf` file with the following content

   ```
   [DEFAULT]
   main-repo = gentoo
 
   [gentoo]
   location = /var/db/repos/gentoo
   sync-type = git
   # Official "sync-friendly git mirror of repo/gentoo with caches and metadata"
   # sync-uri = https://anongit.gentoo.org/git/repo/sync/gentoo.git
   # GitHub mirror (saves the Gentoo project bandwidth - of *this* sync-friendly git mirror is preferred)
   sync-uri = https://github.com/gentoo-mirror/gentoo.git
   auto-sync = yes
   sync-rsync-verify-jobs = 1
   sync-rsync-verify-metamanifest = yes
   sync-rsync-verify-max-age = 24
   sync-openpgp-key-path = /usr/share/openpgp-keys/gentoo-release.asc
   sync-openpgp-key-refresh-retry-count = 40
   sync-openpgp-key-refresh-retry-overall-timeout = 1200
   sync-openpgp-key-refresh-retry-delay-exp-base = 2
   sync-openpgp-key-refresh-retry-delay-max = 60
   sync-openpgp-key-refresh-retry-delay-mult = 4

   sync-git-verify-commit-signature = yes
   ```

1. Before initial sync, remove _/var/db/repos/gentoo/_ directory.
1. Synchronise the repository tree as usual:
   * `emerge --sync`

---

[← Documentation index](README.md) · Prev: [Installation](02-installation.md) · Next: [Application Configuration →](04-application-configuration.md)
