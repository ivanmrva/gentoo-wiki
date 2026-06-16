For the full list of installed applications see the
[System Reference → Installed applications](08-system-reference.md#installed-applications-the-world-set).
The notable per-app configuration steps are below.

# Docker

1. `sudo emerge docker docker-compose`
1. `sudo systemctl enable docker.service`
1. `sudo usermod -aG docker <user>` (this guide's example: `ivmr`) — log out/in for the group to take effect.

# Editors & IDE

* Primary editor: **VS Code** (`app-editors/vscode`); `vim` and `gedit` are also installed.
* Dev toolchain installed alongside: `openjdk-bin` + `maven-bin` (Java),
  `nodejs` (with `npm` USE flag), `github-cli`, `git`, `meld`, plus
  cloud/infra CLIs `kubectl`, `helm`, `terraform`.

# Browsers

* `firefox-bin`, `google-chrome` (with `chrome-binary-plugins`). For hardware
  video decode in Chrome/Firefox, verify VAAPI is working — see
  [After Installation → Intel Graphics: Vaapi](03-after-installation.md#intel-graphics-vaapi).

# Printing (HPLIP)

* `net-print/hplip` is installed for HP printers/scanners. CUPS and Avahi
  (mDNS discovery) are pulled in as dependencies; enable `cupsd` if you print.

# Backups

* `restic` (snapshots) and `rdiff-backup`, plus `rclone` for cloud storage,
  are installed and driven by personal systemd timers (not documented here —
  recreate privately).

# Config tracking (changes-only git mirror)

System and per-user customizations are auto-committed to a **private** git repo
by a small **`system-changes`** service. It's a *changes-only* mirror: the repo
holds only what diverges from a stock install — not the whole filesystem. This
is the "personal helper service" referred to in the
[System Reference](08-system-reference.md#enabled-services); the mechanics are
generic, the repo URL is yours and stays private.

Three pieces under `/usr/local/sbin` plus a systemd unit (`sys-fs/inotify-tools`
is the only extra dependency):

* **`system-changes.service`** — `Restart=always`; runs the watcher as root.
* **`system-changes-watch`** — `inotifywait` on `/etc` and `/usr/local`
  (recursive) plus selected `$HOME` dirs (**non-recursive**, so caches/state
  don't flood it); coalesces bursts, then calls the sync.
* **`system-changes-sync`** — rebuilds the mirror and `git commit`/`git push`:
  * **`/etc` + `/usr/local`** — files **not owned by any package** (your
    additions) and package-owned files whose **MD5 differs** from install (your
    edits), discovered via `/var/db/pkg/*/*/CONTENTS`.
  * **`$HOME`** — an explicit **allowlist** (`.bashrc`, `.gitconfig`,
    `~/.config/Code/User/settings.json`, `mimeapps.list`, …) plus globs
    (`~/.local/share/applications/*.desktop`). `$HOME` has no package baseline,
    so you list what matters instead of diffing.
  * **GNOME** — a filtered `dconf` text snapshot: keys that differ from their
    gschema default, with ephemeral state (window geometry, recents, …)
    denylisted so resizing a window doesn't spam commits.
  * **Secrets held back** — path + content regexes skip
    `NetworkManager/system-connections`, `shadow`, private keys, tokens, etc.;
    held-back names (only) are logged to `_EXCLUDED.txt`.

The repo lives at `/var/lib/<name>` and mirrors the fs layout (`etc/…`,
`usr/local/…`, `home/<user>/…`), pushed to a private remote over SSH (a per-user
deploy key). Recreate: `emerge sys-fs/inotify-tools`, create the repo + private
remote, drop in the three scripts, `systemctl enable --now system-changes.service`.

> Keep the remote **private** — even with filtering, a config mirror is
> sensitive. Check `_EXCLUDED.txt` after the first run to confirm nothing leaked.

---

[← Documentation index](README.md) · Prev: [After Installation](03-after-installation.md) · Next: [Troubleshooting →](05-troubleshooting.md)
