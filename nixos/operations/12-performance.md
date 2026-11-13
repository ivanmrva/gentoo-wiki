# 12. Performance

The operating-system side is already tuned (zswap, RAM-backed `/tmp` and
builds, lazy RCU, BBR, btrfs options, minimal services). The remaining
levers, ordered by real-world impact. Measure before and after every change.

## Measuring

| Question | Tool |
| --- | --- |
| How fast is a task? | `hyperfine '<command>'` |
| Where does boot time go? | `systemd-analyze blame`, `critical-chain` |
| CPU frequency, power, idle states | `sudo turbostat` (also in the `sysdiag` report) |
| What drains the battery? | `powertop` (measure only, no `--auto-tune`) |
| Is the GPU / video engine used? | `intel_gpu_top` |
| Where does a program spend time? | `perf top`, `perf record` |

## 12.1 Development builds (biggest gain)

Compile and link times dominate waiting time far more than OS tuning. In
project dev shells:

```nix
packages = with pkgs; [ mold sccache ];
shellHook = ''
  export RUSTFLAGS="-C link-arg=-fuse-ld=mold"   # mold: much faster linking
  export RUSTC_WRAPPER=sccache                   # cache compiled crates across projects
'';
```

## 12.2 Power profile on AC

Use "Performance" in GNOME's quick settings when plugged in, "Balanced" on
battery. If `cat /sys/firmware/acpi/platform_profile_choices` lists profiles,
the power daemon also switches HP's firmware thermal profile: higher
sustained power limits for long builds and local AI, paid with fan noise and
heat. (**DECISION**: power-profiles-daemon or TLP with `pd.enable`; GNOME's
switch works with both.)

## 12.3 CPU-specific builds (-march=arrowlake): currently none

| Software in this setup | Why a CPU-tuned build gains nothing |
| --- | --- |
| Chrome, Slack, Zoom, Claude Desktop | Prebuilt binaries from the vendors: cannot be recompiled |
| glibc, OpenSSL, ffmpeg, zstd | Already select optimised code paths for the running CPU at runtime |
| llama.cpp, whisper.cpp | nixpkgs builds all CPU variants and picks the best at runtime (`GGML_CPU_ALL_VARIANTS`), so AVX-VNNI is already used. The real lever is the iGPU: `llama-cpp.override { vulkanSupport = true; }` |
| restic, rclone, Docker (Go) | Network- and disk-bound; Go uses runtime-dispatched assembly for hashing and encryption |
| GNOME, mutter, GTK apps | Interactive, rendering on the GPU; not CPU-bound |
| Kernel | A tuned kernel rebuilds on every update and is not portable to a binary cache; gains are marginal |

Keep the overlay mechanism ([chapter 6](06-patching.md)) for your own
compute-heavy code, and use it only where `hyperfine` shows a gain.

## 12.4 Chrome: hardware video acceleration

Video calls and streaming decoded in software cost noticeable CPU and
battery. The nixpkgs Chrome wrapper already enables native Wayland (via
`NIXOS_OZONE_WL`); hardware video decoding must be checked separately:

1. Open `chrome://gpu`: "Video Decode" must read "Hardware accelerated". Play
   a video and run `intel_gpu_top`: the Video engine must be busy.
1. If it is not, enable it via the package override in `apps.nix` (replace
   `google-chrome` in `systemPackages`):

   ```nix
   (pkgs.google-chrome.override {
     commandLineArgs = "--enable-features=AcceleratedVideoDecodeLinuxGL,"
       + "AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder";
   })
   ```

1. Verify in `chrome://version` (shows the effective command line) and again
   in `chrome://gpu`. Feature names change between Chrome versions: if it
   does not take effect, check the current Arch Wiki page on Chromium
   hardware video acceleration.

## 12.5 Scheduler (optional, measure)

```nix
services.scx-loader = {                  # sched_ext: alternative CPU schedulers
  enable = true;
  config.default_sched = "scx_lavd";     # latency-oriented, for interactive desktops
};                                       # switch/stop live with: scxctl
```

Gains, if any, show as a smoother desktop and video calls while compiling.
Keep it only if it measurably helps.

## 12.6 Display

On the 120 Hz display, 60 Hz on battery (Settings → Displays) saves
noticeable power with little perceived difference.

## Deliberately not done

| Tweak | Why not |
| --- | --- |
| `mitigations=off` | Disables defences against CPU vulnerabilities; unacceptable with client data |
| System-wide `-march` | Loses the binary cache: multi-hour rebuilds every update |
| `powertop --auto-tune` | Aggressive USB autosuspend makes input devices laggy |
| `btrfs filesystem defragment` | Breaks extent sharing with snapshots; space explodes |
| Sysctl / I/O scheduler guides | NVMe defaults are already optimal; most guides target spinning disks |
