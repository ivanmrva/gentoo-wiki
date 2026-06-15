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

---

[← Documentation index](README.md) · Prev: [After Installation](03-after-installation.md) · Next: [Troubleshooting →](05-troubleshooting.md)
