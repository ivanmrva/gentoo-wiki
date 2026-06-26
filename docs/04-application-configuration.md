For the full list of installed applications see the
[System Reference → Installed applications](08-system-reference.md#installed-applications-the-world-set).
The notable per-app configuration steps are below.

# Package & install policy

This is the rule that explains *why* the apps below are sourced the way they
are: **Portage for almost everything; Flatpak only for selected self-contained
GUI apps; AppImage only when nothing better exists.** The order is a preference
ladder — drop to the next rung only when the one above can't deliver the app.

**Now:** almost everything on this machine is Portage. The desktop heavyweights
are deliberately the **`-bin`** Portage packages — `firefox-bin`,
`google-chrome`, `libreoffice-bin`, `thunderbird-bin`, plus `slack`, `zoom`, and
`vscode` — so they're still managed by `emerge` but don't cost hours of
from-source compile time. The **only** things outside Portage are three:
IntelliJ IDEA Ultimate (via JetBrains Toolbox, see
[Editors & IDE](#editors--ide)), the unofficial Claude Desktop AppImage, and the
npm-global CLIs `@anthropic-ai/claude-code`, `openclaw`, and `pnpm` (see
[Non-Portage AI tooling](#non-portage-ai-tooling)).
**Why:** keep dev-adjacent tools native so they share the system toolchain,
credential stores, Docker socket, SSH agent, and language servers — Portage gives
real dependency management and clean removal, which neither Flatpak nor AppImage
matches.

**VS Code stays native (`app-editors/vscode`), not Flatpak.** Flatpak sandboxing
breaks exactly what an IDE needs on this box: integrated terminals, SDKs/runtimes
on `$PATH`, Git credentials, the SSH agent, the Docker socket, language servers,
and dev containers. Same logic keeps Docker, Git, Node, `openjdk-bin`/`maven-bin`,
`terraform`/`helm`/`kubectl`, `restic`, and `rclone` in Portage.

### Planned improvement: when Flatpak would be reasonable

> **Now:** there are **no Flatpak apps** installed — the self-contained GUI apps
> (`slack`, `zoom`) are the `-bin` Portage packages.
> **Next iteration:** if a self-contained desktop app ever lags or breaks in
> Portage, Flatpak is the right second rung for it specifically — Slack and Zoom
> are the obvious candidates here, since they're sandbox-friendly GUI apps with
> no toolchain integration to lose. Prefer **verified/upstream** Flatpaks; an
> unverified Flatpak is not automatically safer than a Portage package.
> **Why:** reserve the sandbox for apps that gain isolation and lose nothing by
> it — never for dev-adjacent tools (above), where the sandbox is pure cost.

### Claude on Linux — provenance caveat

> **Claude Code** (the npm-global CLI + the VS Code `anthropic.claude-code`
> extension) is the **primary** tool for repo and coding work on this machine and
> is officially shipped for Linux.
> **Claude Desktop** here is an **unofficial AppImage**
> (`~/.local/opt/claude-desktop/claude-desktop.AppImage`) — Anthropic doesn't
> officially ship Desktop for Linux. Keep it only if you specifically want the
> GUI (Cowork-style workflows, desktop extensions, mobile handoff); plain chat is
> covered by the web/PWA.
> **Why:** the caveat is package **provenance**, not format — a Flatpak build
> wouldn't make Desktop any more official, so AppImage (the bottom rung, used
> only because nothing better exists) is fine here as long as you know it's
> unofficial and self-updating outside `emerge`.

# Docker

1. `sudo emerge docker docker-compose`
1. `sudo systemctl enable docker.service`
1. `sudo usermod -aG docker <user>` (this guide's example: `ivmr`) — log out/in for the group to take effect.

# Editors & IDE

* Primary editor: **VS Code** (`app-editors/vscode`); `vim` and `gedit` are also installed.
* **Extensions** (~16, in `~/.vscode/extensions/`) — Python/Pylance + debugpy,
  Docker + Containers + Remote-Containers, `anthropic.claude-code`, GitHub
  Actions, … These are **not** tracked by the config mirror; capture the list for
  a rebuild with `code --list-extensions` (and reinstall with
  `code --install-extension`). See the
  [rebuild ledger](00-recreate-this-system.md#what-these-docs-capture--and-what-you-must-bring-yourself).
* Dev toolchain installed alongside: `openjdk-bin` + `maven-bin` (Java),
  `nodejs` (with `npm` USE flag), `github-cli`, `git`, `meld`, plus
  cloud/infra CLIs `kubectl`, `helm`, `terraform`.

**VS Code user settings** (`~/.config/Code/User/settings.json`) — the non-default
keys that are tracked by the config mirror:

```json
{
  "claudeCode.preferredLocation": "panel",
  "workbench.colorTheme": "Visual Studio Light",
  "workbench.activityBar.compact": true,
  "workbench.editor.autoLockGroups": { "mainThreadWebview-markdown.preview": true },
  "workbench.editor.enablePreviewFromQuickOpen": true,
  "workbench.editor.enablePreviewFromCodeNavigation": true,
  "claudeCode.useTerminal": true,
  "terminal.integrated.fontSize": 16
}
```

Light theme, compact activity bar, the Claude Code extension docked in the
**panel** and driving the **integrated terminal**, and a 16 pt terminal font.

**IntelliJ IDEA Ultimate** is installed **outside Portage** — under
`/opt/idea-IU-261.24374.151/` via **JetBrains Toolbox**, not as a `dev-util/*`
ebuild. It registers a desktop entry (`IntelliJ IDEA Ultimate.desktop`) in
`~/.local/share/applications/`, and the Toolbox installs `jetbrainsd.desktop` as
the `x-scheme-handler/jetbrains` URL handler (used by IDE deep-links). Because
it's a Toolbox install, it self-updates outside `emerge` and won't appear in
`@world` or `qlist`.

# Browsers

* `firefox-bin`, `google-chrome` (with `chrome-binary-plugins`). For hardware
  video decode in Chrome/Firefox, verify VAAPI is working — see
  [After Installation → Intel Graphics: Vaapi](03-after-installation.md#intel-graphics-vaapi).
* **Chrome is the default** for `http`/`https`/`html`/`mailto` (set in
  `~/.config/mimeapps.list`; Firefox is registered only as a non-default HTML
  alternative).
* **Launcher override** — a local `~/.local/share/applications/google-chrome.desktop`
  shadows the packaged one and adds a feature flag:

  ```ini
  Exec=/usr/bin/google-chrome-stable --enable-features=AcceleratedVideoEncoder %U
  ```

  This turns on hardware **video encode** (complementing the VAAPI decode setup);
  the override lives in `$HOME`, so it is mirrored by the config tracker rather
  than owned by the `google-chrome` package.
* **profile-sync-daemon** (`www-misc/profile-sync-daemon`, "psd") keeps the
  Chrome profile on a tmpfs to spare the SSD and speed the browser up.
  `~/.config/psd/psd.conf`: `BROWSERS=(google-chrome)` (Chrome only),
  `USE_OVERLAYFS="yes"`, `USE_SUSPSYNC="yes"`. Enable per-user with
  `systemctl --user enable --now psd.service`.

# Non-Portage AI tooling

None of these are Portage packages — they're installed via `npm` (global prefix
`~/.npm-global`; Node itself is Portage's `net-libs/nodejs`) or as an AppImage, so
they don't show up in `@world`/`qlist` and they self-update outside `emerge`. The
full global-npm set is `@anthropic-ai/claude-code`, `openclaw`, and `pnpm`. Each
app registers a desktop entry under `~/.local/share/applications/` (so the
`.desktop` files *are* tracked by the config mirror) — but **the packages
themselves are not versioned anywhere**, so on a rebuild you reinstall them by
hand (see the [rebuild ledger](00-recreate-this-system.md#what-these-docs-capture--and-what-you-must-bring-yourself)).

* **Claude Code** — the CLI, installed globally as `@anthropic-ai/claude-code`
  (`~/.npm-global/lib64/node_modules/@anthropic-ai/claude-code`). It handles the
  `claude-cli://` deep-link scheme: `claude-code-url-handler.desktop` maps
  `x-scheme-handler/claude-cli` to it (mimeapps.list).
* **Claude Desktop** — the unofficial AppImage at
  `~/.local/opt/claude-desktop/claude-desktop.AppImage`. It handles the
  `claude://` scheme (`x-scheme-handler/claude` → `claude-desktop.desktop`).
* **OpenClaw** — also npm-global (`~/.npm-global/lib64/node_modules/openclaw`),
  run as a **user-scope** systemd service rather than a CLI:
  `openclaw-gateway.service` (`~/.config/systemd/user/`) runs
  `node …/openclaw/dist/index.js gateway --port 18789` with `Restart=always` and
  is **enabled + active**. `~/.bashrc` also sources its bash completion
  (`~/.openclaw/completions/openclaw.bash`). Manage it with
  `systemctl --user status openclaw-gateway`.
  * **Config gap:** OpenClaw's state lives under `~/.openclaw/` (`openclaw.json`
    plus `agents/`, `devices/`, `workspace/`, …) and is **not** in the
    `system-changes` allowlist, so it isn't versioned. Its `credentials/` and
    `identity/` are secrets (keep them off the mirror), but you may want to add
    `~/.openclaw/openclaw.json` to the
    [allowlist](#config-tracking-changes-only-git-mirror) so the gateway config is
    tracked.
* **pnpm** — the global npm package manager
  (`~/.npm-global/lib64/node_modules/pnpm`), installed the same way; no desktop
  entry (CLI only).

# Printing (HPLIP)

* `net-print/hplip` is installed for HP printers/scanners. CUPS and Avahi
  (mDNS discovery) are pulled in as dependencies; enable `cupsd` if you print.

# Backups

* **`restic`** is the active engine: two repos (root `/` and `/data1`) backed up
  **direct to the cloud over `rclone`** on systemd timers, plus on-disk `snapper`
  point-in-time snapshots on `/data1`. The full architecture and the
  restore/clone procedures are in **[Backup, clone & restore](09-backup-restore.md)**.
* **The old standalone rclone cloud-sync integration is retired** (post
  2026-06-21 migration). `rclone` is still installed, but it's now only the
  transport restic pushes through — not a standalone sync. The two user-scope
  cloud-storage mounts (`rclone-mount-*` units — one personal, one for a separate
  account) are **disabled** (one currently in a `failed` state) and **nothing is
  mounted**; the old daily push units (`rclone-sync-*`) have been parked under
  `~/.config/systemd/user-removed-*/` and are not loaded. `rdiff-backup` (the
  `app-backup/rdiff-backup` package) is **still installed and in `@world`** but is
  no longer wired to run — only a dangling `rdiff-backup-root.timer` symlink
  (pointing at a missing unit) survives; it's a `--deselect`/cleanup candidate.
  Treat doc 09 as the source of truth for the current target, not these
  leftovers.

# System maintenance automation

A set of root-run systemd timers handles housekeeping, firmware, and health
monitoring. They notify by **email**: `/usr/sbin/sendmail` is a symlink to
`mail-mta/msmtp`, and `/etc/aliases` routes `root`/`default` to a real inbox
(`<you@example.com>` here). The scripts live in `/usr/local/bin` (the health and
SMART scripts) and `/usr/local/sbin` (the firmware script).

* **`portage-maintenance.timer`** (`Sun 03:00`, `Persistent`,
  `RandomizedDelaySec=30min`; `Nice=19`, IO `idle`) — prunes and refreshes
  Portage caches: `eclean-dist --deep` → `eclean-pkg --deep` → `eix-update`.
  It deliberately does **not** run `emerge --sync` / `eix-sync`,
  `@preserved-rebuild`, or `@world` upgrades — those stay manual.
* **`fwupd-update-check.timer`** (`weekly`, `Persistent`; `After=fwupd.service`)
  — runs `fwupd-update-check.sh`: `fwupdmgr refresh --force` then
  `get-updates`. It sends an **HTML email** (per-device current→new version,
  urgency, changelog, LVFS link) **only when updates are available or on error**;
  silent otherwise. Applying firmware (`sudo fwupdmgr update`, on AC) stays
  manual.
* **`system-health-digest.timer`** (daily `08:00`, `Persistent`) — runs
  `system-health-digest.sh`, a plaintext roll-up email with subject
  `[health] <host>: OK` or `… N alert(s)`. Sections:
  * **ACTION NEEDED** — reboot-required (newer kernel staged than running),
    glibc/systemd/openssl updated since boot (restart advised), failed system
    **and user** units, disks ≥ 90 % full, and the result of each restic job.
  * **GENTOO MAINTENANCE** — available `@world` update count, GLSA security
    advisories, unread news, pending `._cfg` config merges, preserved-lib
    rebuilds.
  * **HEALTH TRENDS** — battery design-capacity %, NVMe SMART
    health/wear/power-on-hours + last self-test.
  * **BACKUPS** — restic job freshness from `/var/lib/restic-monitor/*.stamp`.
  * **LAST 24h EVENTS** — journal greps for thermal throttling, OOM kills,
    fs/IO errors, and suspend/resume failures.
* **`smartd.service`** + **`smartd-notify`** — real-time SMART monitoring, not a
  timer. The single custom line in `/etc/smartd.conf` is:

  ```
  DEVICESCAN -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,55,70 -m root -M exec /usr/local/bin/smartd-notify
  ```

  i.e. auto-detect all drives, daily **short** self-test (~02:00), weekly
  **long** self-test (Sat ~03:00), temp warn 55 °C / crit 70 °C. On an event,
  `smartd-notify` both pops a desktop notification (`notify-send -u critical` to
  every graphical user) **and** emails `root` via `sendmail`.

# Config tracking (changes-only git mirror)

System and per-user customizations are auto-committed to a **private** git repo
by a small **`system-changes`** service. It's a *changes-only* mirror: the repo
holds only what diverges from a stock install — not the whole filesystem. This
is the "personal helper service" referred to in the
[System Reference](08-system-reference.md#enabled-services); the mechanics are
generic, the repo URL is yours and stays private.

A systemd unit plus a few scripts under `/usr/local` (`sys-fs/inotify-tools` is
the only extra dependency):

* **`system-changes.service`** — `Restart=always`, `Nice=10`, IO `idle`; runs
  the watcher as root.
* **`system-changes-watch`** — syncs once at start, then runs two
  `inotifywait -m` watchers, coalescing ~3 s of quiet before re-syncing:
  * **recursive** on `/etc` and `/usr/local`;
  * **non-recursive** on a fixed set of `$HOME` dirs (`~/.config`, the VS Code
    user dir, `~/.config/dconf`, `~/.local/share/applications`, the user systemd
    dir, `gtk-3.0`, `gh`, `git`, `psd`, the gnome-shell **extensions** dir) **and
    `/var/lib/portage`** — so caches/state don't flood it.
* **`system-changes-sync`** — rebuilds the mirror and `git commit`/`git push`:
  * **`/etc` + `/usr/local`** — files **not owned by any package** (your
    additions) and package-owned files whose **MD5 differs** from install (your
    edits), discovered via `/var/db/pkg/*/*/CONTENTS`.
  * **`$HOME`** — an explicit **allowlist** of exact files: `.bashrc`,
    `.bash_profile`, `.gitconfig`, `.npmrc`, `.config/Code/User/settings.json`,
    `.config/mimeapps.list`, `.config/user-dirs.dirs`, `.config/monitors.xml`,
    `.config/git/ignore`, `.config/gtk-3.0/bookmarks`, `.config/gh/config.yml`
    (**not** `hosts.yml`, which holds the gh token), `.config/psd/psd.conf` —
    plus globs (`.local/share/applications/*.desktop`,
    `.config/systemd/user*/*`). `$HOME` has no package baseline, so you list what
    matters instead of diffing.
  * **`@world` set** — `/var/lib/portage/world` and `world_sets` are tracked
    directly (no package baseline), so additions/removals to the explicit set
    show up as diffs.
  * **GNOME** — a filtered `dconf` snapshot (via `system-changes-dconf`): keys
    that differ from their gschema default, with ephemeral state (window
    geometry, recents, file-chooser state) denylisted so resizing a window
    doesn't spam commits; plus a `gnome-extensions.list` of installed extension
    UUIDs.
  * **`_system-state.txt`** — a generated (non-file) summary: the Portage
    profile, the timezone, and the sorted list of **enabled** system units.
  * **Secrets held back** — a **path** regex *and* a **content** regex. The path
    denylist covers `NetworkManager/system-connections`, `shadow`/`gshadow`,
    `wpa_supplicant`/`openvpn` keys, any `*.{key,pem,p12,…}`, **`msmtprc`**, and
    the **netdata** `claim`/`health_alarm_notify` configs; the content filter
    catches PEM blocks and `ghp_`/`xoxb-`/`AKIA…` tokens and
    `password`/`api_key`/`secret`/`token` assignments. Held-back **names** (with
    `secret: path` / `secret: content` tag) go to `_EXCLUDED.txt`. Pure **noise**
    (`passwd-`/`group-` backups, `machine-id`, `resolv.conf`, cert stores,
    `*.bak`/`*.old`/`._cfg`) is **dropped silently** — not logged.

The repo lives at `/var/lib/<name>` and mirrors the fs layout (`etc/…`,
`usr/local/…`, `home/<user>/…`, `var/lib/portage/world`), pushed to a private
remote over SSH (a per-user deploy key). Recreate: `emerge sys-fs/inotify-tools`,
create the repo + private remote, drop in the scripts,
`systemctl enable --now system-changes.service`.

> Keep the remote **private** — even with filtering, a config mirror is
> sensitive. Check `_EXCLUDED.txt` after the first run to confirm nothing leaked.

---

[← Documentation index](README.md) · Prev: [After Installation](03-after-installation.md) · Next: [Troubleshooting →](05-troubleshooting.md)
