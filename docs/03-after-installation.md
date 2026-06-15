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
   * `systemctl enable nftables.service` (firewall — remember to actually populate `/etc/nftables.conf`)
   * `systemctl enable fstrim.timer` (periodic SSD TRIM)

# Gnome Configuration

1. Open Gnome Settings and change
   * Displays -> Resolution / Scale
   * Displays -> Night Light = ON
   * Sound -> Alert Sound = None
   * Power -> Show battery percentage
   * Multitasking -> Fixed number of workspace = 2
   * Search -> Search Locations -> add custom locations as desired
      * TODO: where is index stored
   * Online accounts -> add accounts as desired
   * Mouse & Touchpad -> Pointer speed
   * Keyboard -> Input sources -> add Switzerland (German)
   * System -> Region & Language -> Language = English (US) + Formats = Switzerland (German)
   * System -> Date & Time -> Automatic Date & Time = ON,  Timezone = Zurich, Time Format = 24h, Week day + Date + seconds + week numbers = ON

1. Prevent grouping windows when Alt+Tab
   * Keyboard -> Shortcuts -> Switch windows - set to Alt+Tab

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
1. Verify HW encoding/decoding is used:
   * `emerge x11-apps/igt-gpu-tools`
   * `intel_gpu_top`
      * Video BUSY should be greater than zero:
       ```
       ENGINES     BUSY                                                                        MI_SEMA MI_WAIT
       Render/3D   23.92% |█████████████████████                                              |      0%      0%
       Blitter    0.00% |                                                                   |      0%      0%
       Video    7.98%
       ```
TODO: make sure rendering is used in chrome

See also https://wiki.gentoo.org/wiki/VAAPI

# Power Management

1. Make use of Intel's Linux thermal daemon:
   * `emerge thermald`
   * `systemctl enable thermald`
1. Install TLP:
   * `emerge sys-power/tlp`
      * Do not install _laptop-mode-tools_ to prevent conflicts (TLP is an alternative with safe, modern defaults OOTB).
   * Configure TLP for more consumption savings on battery:
      * Check https://linrunner.de/tlp/support/optimizing.html
   * `systemctl enable tlp`

Check also https://wiki.gentoo.org/wiki/Power_management/Guide

# Verify Kernel configuration

1. Verify microcode is loaded:
   * `dmesg | grep microcode`
      * It should contain a message like: _microcode: microcode updated early to revision 0xa4, date = 2010-10-02_
1. Verify loading of Intel Graphic firmware
   * dmc, guc, huc

# Verify Portage package logs

1. Fix warnings, suggestion or kernel configuration based on the logs of all installed packages:
   * Check portage logs with `elogv`

# modprobed-db

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
