# System modules

Part of [Phase B](02-flake-repository.md). Each section is one file under
`modules/`.

## B5. modules/base.nix

```nix
{ pkgs, ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];        # trusted users are root-equivalent: keep it to root
    keep-outputs = true;               # dev shells survive garbage collection
    keep-derivations = true;
  };
  nix.optimise.automatic = true;       # hard-link identical files in the store
  programs.nh = {                      # rebuild tool + garbage collection
    enable = true;
    flake = "/home/ivmr/claude-code/nixos-config";
    clean.enable = true;
    clean.extraArgs = "--keep-since 14d --keep 10";
  };
  nixpkgs.config.allowUnfree = true;

  boot.tmp = { useTmpfs = true; tmpfsSize = "50%"; };   # /tmp and Nix builds in RAM
  systemd.oomd = { enable = true; enableRootSlice = true; enableUserSlices = true; };

  services.journald.settings.Journal.SystemMaxUse = "1G";
  services.btrfs.autoScrub = { enable = true; interval = "monthly"; };
  services.smartd.enable = true;
  services.fwupd.enable = true;

  time.timeZone = "Europe/Zurich";
  # Time sync: ntpd-rs (memory-safe) with NTS (authenticated time); the module
  # disables systemd-timesyncd automatically
  services.ntpd-rs = {
    enable = true;
    useNetworkingTimeServers = false;    # default pool servers are plain NTP
    settings.source = [
      { mode = "nts"; address = "time.cloudflare.com"; }
      { mode = "nts"; address = "nts.netnod.se"; }
      { mode = "nts"; address = "ptbtime1.ptb.de"; }
    ];
  };
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {          # en_GB formats, as on Gentoo
    LC_TIME = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
  };
  # Keyboard: the LUKS passphrase and TPM PIN are typed with the console keymap.
  # The physical keyboard is German QWERTZ (#ABD); you type US and Swiss German.
  console.keyMap = "us";
  services.xserver.xkb.layout = "us,ch";   # GDM; does not start X. GNOME input sources: home-manager

  users.mutableUsers = false;          # passwords come only from sops (secrets.nix)
  users.users.ivmr = {
    isNormalUser = true;
    uid = 1000;                        # same as Gentoo: restored files keep their owner
    extraGroups = [ "wheel" "networkmanager" "video" "docker" ];
  };

  environment.defaultPackages = [ ];
  environment.systemPackages = with pkgs; [
    git vim sbctl btrfs-progs nix-output-monitor nvd vulnix pciutils usbutils
    # Update with a btrfs snapshot of @home/@persist taken BEFORE anything changes,
    # so app data can be restored if a new app version migrates it.
    (writeShellScriptBin "sysup" ''
      set -e
      cd ~/claude-code/nixos-config
      git pull --ff-only                       # CI merged the weekly flake.lock update
      sudo systemctl start btrbk-local.service
      nh os switch .
    '')
  ];
}
```

> [!TIP]
> Choose a LUKS passphrase whose characters sit on the same keys in US and
> German layouts (avoid `y`, `z` and most symbols). Then a wrong keymap at
> the boot prompt can never lock you out.

## B5b. modules/secrets.nix

```nix
{ config, ... }: {
  sops = {
    defaultSopsFile = ../secrets/zbook.yaml;
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];   # persisted path
    secrets."users/ivmr".neededForUsers = true;   # decrypted before users are created
    secrets."users/root".neededForUsers = true;
    secrets."restic/password" = { };
    secrets."ntfy/url" = { };
    secrets."hc/backup" = { };
  };
  users.users.ivmr.hashedPasswordFile = config.sops.secrets."users/ivmr".path;
  users.users.root.hashedPasswordFile = config.sops.secrets."users/root".path;
}
```

## B6. modules/persistence.nix (Preservation)

Preservation is the systemd-native successor to the older impermanence
module. It generates only static systemd-tmpfiles rules and mount units, with
no activation scripts, and it handles files needed very early (`machine-id`)
in the systemd initrd correctly. Ownership and mode must be stated where they
differ from root:root 0755.

`/home`, `/var/log` and `/var/lib/docker` are their own subvolumes and need
no entry here.

```nix
{
  preservation = {
    enable = true;
    preserveAt."/persist" = {
      commonMountOptions = [ "x-gvfs-hide" ];     # hide bind mounts in Files
      directories = [
        { directory = "/var/lib/nixos"; inInitrd = true; }   # UID/GID map: must persist
        "/var/lib/systemd/timers"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/pstore"                  # kernel crash records
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/backlight"
        { directory = "/var/lib/sbctl"; mode = "0700"; }      # Secure Boot keys
        { directory = "/var/lib/bluetooth"; mode = "0700"; }
        { directory = "/var/lib/fprint"; mode = "0700"; }
        "/var/lib/boltd"                           # Thunderbolt device authorisations
        "/var/lib/fwupd"
        "/var/lib/upower"
        "/var/lib/power-profiles-daemon"
        "/var/lib/colord"
        "/var/lib/AccountsService"
        { directory = "/var/lib/gdm"; user = "gdm"; group = "gdm"; }
        "/var/lib/NetworkManager"                  # secret_key: keeps per-network MACs stable
        { directory = "/etc/NetworkManager/system-connections"; mode = "0700"; }
        "/var/lib/btrbk"
        "/var/cache/restic-backups-offsite"        # restic caches: avoid re-downloading
        "/var/cache/restic-backups-offsite-prune"  #   the index from Drive after every boot
        "/var/cache/restic-backups-offsite-check"
        { directory = "/var/lib/sysdiag"; group = "wheel"; mode = "0750"; }
      ];
      files = [
        { file = "/etc/machine-id"; inInitrd = true; }
        { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
        { file = "/etc/ssh/ssh_host_ed25519_key.pub"; how = "symlink"; configureParent = true; }
        { file = "/var/lib/systemd/random-seed"; how = "symlink"; inInitrd = true;
          configureParent = true; }
      ];
    };
  };
  # machine-id is persisted from the initrd; the commit service is not needed
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
}
```

## B7. modules/boot.nix (install-time version)

The first install uses plain systemd-boot.
[Phase E](08-secure-boot-tpm-hibernation.md) replaces this file with the
lanzaboote version once your Secure Boot keys exist.

```nix
{ ... }: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 1;
  boot.initrd.systemd.enable = true;
}
```

## B8. modules/power.nix

Behaviour, ported from Gentoo's `inhibit-sleep-on-ac` setup but with native
mechanisms:

| Situation | Result |
| --- | --- |
| Idle on AC | Never suspends (GNOME dconf, [home-manager](04-home-manager.md)) |
| Idle on battery | GNOME suspends; after 90 min it hibernates |
| Lid closed on battery | Suspend, then hibernate after 90 min |
| Lid closed on AC | Lock only; unplug later and logind re-evaluates → suspend-then-hibernate |
| Lid closed with external monitor | GNOME inhibits the lid action |
| Battery at 5 % | Hibernate |

```nix
{ config, ... }: {
  swapDevices = [ {
    device = "/swap/swapfile";
    size = 64 * 1024;                       # MiB = RAM size; created on first boot
  } ];

  boot.resumeDevice = "/dev/mapper/cryptroot";
  # Phase G adds: boot.kernelParams = [ "resume_offset=<N>" ];

  # zswap: compressed RAM cache in front of the disk swapfile. With a disk swapfile
  # needed for hibernation anyway, zswap fits better than zram.
  boot.zswap.enable = true;                 # defaults: zstd, max 20-25 % of RAM

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "lock";  # default would be the battery action
    HandleLidSwitchDocked = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "90min";            # explicit: firmware battery estimates are unreliable
    HibernateOnACPower = false;             # countdown pauses while on AC
  };

  # GNOME calls plain Suspend via logind: make every suspend hibernate after the delay
  systemd.services.systemd-suspend.serviceConfig.ExecStart = [
    ""
    "${config.systemd.package}/lib/systemd/systemd-sleep suspend-then-hibernate"
  ];

  services.upower = {
    enable = true;
    criticalPowerAction = "Hibernate";      # NixOS default: HybridSleep at 2 %
    percentageLow = 10;
    percentageCritical = 7;
    percentageAction = 5;                   # 64 GB image needs a margin
  };

  # thermald: off by default. Enable only if Phase H shows throttling under
  # sustained load (an Arrow Lake throttling regression was reported in 2026).
  services.thermald.enable = false;

  # DECISION: power daemon. Default: power-profiles-daemon (GNOME enables it).
  # Alternative, keeps the Gentoo battery tuning (boost off, 70 % cap) and
  # GNOME's power-mode switch via TLP's PPD-compatible interface:
  #   services.power-profiles-daemon.enable = false;
  #   services.tlp = {
  #     enable = true;
  #     pd.enable = true;
  #     settings = { CPU_BOOST_ON_BAT = 0; CPU_MAX_PERF_ON_BAT = 70; };
  #   };
}
```

Battery charge cap: set it in the BIOS (Battery Health Manager,
[Phase C](06-bios-settings.md)). Mainline `hp-wmi` has no charge-threshold
control for ZBooks.

## B9. modules/hardware-intel.nix

Stock NixOS kernel, no custom build. A custom kernel config means compiling
every kernel update locally (the binary cache can't help); on Gentoo that
was 44–80 min per build. The Gentoo compile-time tweaks (native CPU,
`NR_CPUS`, driver trims, stripped BTF) are dropped. NixOS keeps BTF, so
eBPF tools like `bpftrace` work.

```nix
{ pkgs, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "rcu_nocbs=all" ];          # lazy RCU (RCU_LAZY is built in): battery
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # DDR5 SO-DIMM SPD hub driver aborts every suspend (same bug as on the Gentoo box).
  # Fixed upstream in 7.4 (commit bf31dd72f0d5). Drop once on >= 7.4 AND a suspend test passes.
  boot.blacklistedKernelModules = [ "spd5118" ];

  # TEST in Phase H: board 103c:8d94 is missing from the kernel's quirk table.
  # Borrow the ZBook Firefly 14 G12 quirk (103c:8d91) for mute / mic-mute LEDs.
  # If it works, send a one-line quirk patch to the ALSA maintainers.
  # boot.extraModprobeConfig = "options snd-hda-intel model=103c:8d91";

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver     # VA-API video decode/encode
      vpl-gpu-rt             # oneVPL / Quick Sync
      intel-compute-runtime  # OpenCL + Level Zero
    ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  services.hardware.bolt.enable = true;    # Thunderbolt device authorisation

  # Graphics: Arc 140T stays on i915. xe needs force-probe for Arrow Lake: don't.
  # Backlight: no acpi_backlight / i915.enable_dpcd_backlight params (Gentoo had them
  # for the old laptop); test brightness keys in Phase H.
  # Fingerprint: supported readers are enabled by the facter module; check the Goodix ID.
}
```

## B10. modules/desktop-gnome.nix

```nix
{ pkgs, ... }: {
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;
  services.gnome.core-apps.enable = false;              # "gnome-light"

  # Background services not needed (GNOME enables them by default)
  services.gnome.localsearch.enable = false;           # file indexer (CPU/battery)
  services.gnome.tinysparql.enable = false;            # indexer database
  services.gnome.gnome-remote-desktop.enable = false;
  services.gnome.rygel.enable = false;                 # DLNA media server
  services.gnome.gnome-initial-setup.enable = false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.gnome-browser-connector.enable = false; # extensions via home-manager
  services.dleyna.enable = false;
  services.avahi.enable = false;     # mDNS; enable for printer/cast discovery
  services.geoclue2.enable = false;  # location service; time zone is fixed in base.nix

  environment.systemPackages = with pkgs; [
    nautilus
    gnome-terminal       # DECISION: what you use today; alternative: ptyxis
    gnome-text-editor
    loupe                # images
    papers               # PDF and documents
    gthumb               # default image app on Gentoo
  ];
  programs.gnome-disks.enable = true;
  services.gnome.sushi.enable = true;   # quick preview in Files (space bar)

  # DECISION: 1Password. If adopted: desktop app + CLI, browser integration
  # (native browsers only, not Flatpak), optionally the SSH agent.
  # programs._1password.enable = true;
  # programs._1password-gui = { enable = true; polkitPolicyOwners = [ "ivmr" ]; };
  # Without it: GNOME keyring (restored login.keyring) + sops-nix for system secrets.

  environment.gnome.excludePackages = with pkgs; [ gnome-tour gnome-user-docs ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";   # native Wayland for Electron/Chromium
  services.pipewire = { enable = true; pulse.enable = true; };
}
```

## B11. modules/networking.nix

```nix
{ pkgs, ... }: {
  networking.networkmanager = {
    enable = true;
    # Wi-Fi backend: wpa_supplicant (NixOS default). iwd is labelled experimental
    # in nixpkgs and gains nothing here.
    wifi.macAddress = "stable";        # per-network random MAC, stable across reboots
    plugins = [ pkgs.networkmanager-openvpn ];   # VPN profiles; certs in ~/.cert/nm-openvpn
    settings.connectivity = {          # captive-portal detection (unset by default)
      uri = "http://nmcheck.gnome.org/check_network_status.txt";
      interval = 300;
    };
  };
  networking.modemmanager.enable = false;   # no WWAN in this SKU
  services.resolved = {
    enable = true;
    settings.Resolve.DNSOverTLS = "opportunistic";
  };
  systemd.services.NetworkManager-wait-online.enable = false;
  networking.firewall.enable = true;
  networking.nftables.enable = true;
}
```

## B12. modules/security.nix

```nix
{
  security.sudo-rs.enable = true;     # with password (Gentoo: passwordless sudo)
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;              # hide kernel addresses
    "kernel.dmesg_restrict" = 1;             # dmesg for root only: use `journalctl -k`
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.kexec_load_disabled" = 1;
    "kernel.yama.ptrace_scope" = 1;          # ptrace only own children (gdb -p needs sudo)
  };
  # Deliberately NOT enabled:
  #   security.protectKernelImage -> adds "nohibernate" (would break hibernation)
  #   kernel lockdown             -> blocks hibernation
  #   security.lockKernelModules  -> breaks hot-plugged USB/Thunderbolt devices
}
```

## B13. modules/dev.nix

```nix
{ ... }: {
  programs.direnv = { enable = true; nix-direnv.enable = true; };
  programs.nix-ld.enable = true;      # run prebuilt binaries, pip wheels, vendor CLIs

  # Rootful Docker, as on Gentoo: Dev Containers, Testcontainers, compose and the
  # Playwright images all assume it. Storage on the @docker subvolume.
  # The docker group is root-equivalent.
  virtualisation.docker = {
    enable = true;
    autoPrune = { enable = true; dates = "weekly"; flags = [ "--all" "--filter" "until=720h" ]; };
  };
}
```

Docker 29 defaults new installs to the containerd image store. Check where it
stores data with `docker info | grep -i root` after the first start. If
anything lands outside `/var/lib/docker`, add that path to
[persistence](#b6-modulespersistencenix-preservation).

## B13b. modules/apps.nix

Native packages from nixpkgs instead of Flatpaks and npm globals. Claude Code,
Codex and pnpm come from nixpkgs (auto-updaters disabled; updated almost
daily) and live in [home-manager](04-home-manager.md).

```nix
{ pkgs, ... }: {
  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    google-chrome            # default browser and mailto handler (Gmail)
    thunderbird
    slack
    zoom-us
    libreoffice
    gnome-network-displays   # Miracast (Flatpak on Gentoo); check the attribute exists
    claude-desktop-fhs       # aaddrick flake: official .deb, FHS env with qemu/virtiofsd for Cowork
    chatgpt
    jetbrains.idea           # idea-ultimate was renamed
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
  ];
}
```

Cowork (Claude Desktop's VM) needs no `kvm` group on NixOS: systemd leaves
`/dev/kvm` and `/dev/vhost-vsock` at mode 0666. Test it in
[Phase H](09-first-boot.md).
