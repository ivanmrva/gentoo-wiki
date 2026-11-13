# 3. Updating, pinning and rollback

## Updating

Always update with `sysup` (defined in
[base.nix](../install/03-system-modules.md#b5-modulesbasenix)). It takes a
btrfs snapshot of `@home` and `@persist` **before** anything changes, so there
is always a copy of your app data from before any new app version could
migrate it.

```bash
sysup        # = git pull (CI merged the weekly flake.lock pull request)
             #   + snapshot @home/@persist (btrbk-local)
             #   + nh os switch . (shows diff, asks to confirm)
```

Without CI, update the lock yourself first: `nix flake update` (or
`nix flake update nixpkgs` for one input), commit and push, then run `sysup`.
Manual equivalent of `sysup`: `sudo systemctl start btrbk-local.service`, then
`nh os switch .`.

### Cadence and timing

1. Update weekly or when you want something new. Each update is one
   reversible step, so small frequent updates are easier to debug than rare
   large ones.
1. Check the channel before updating: status.nixos.org shows how old
   `nixos-unstable` is. The channel only advances after Hydra has built and
   tested it, so everything in it is in the binary cache.
1. If nh suddenly wants to compile something large (LLVM, a browser), that
   package is not cached for your configuration. Usually an override of yours
   touches its dependencies. Abort, find the cause with `nix why-depends`, or
   wait a day.
1. There is no curated news feed like Gentoo's `eselect news` for unstable.
   Read the warnings nh prints during evaluation and follow the
   "Announcements" category on discourse.nixos.org.

## Pinning a package to an exact version (the "mask" equivalent)

Three options, from most to least robust. Unlike `package.mask` ("up to
version Y"), a pin means "exactly this" and never moves, including no
security fixes, until you remove it.

| Option | How | Trade-off |
| --- | --- | --- |
| a) Package from an older nixpkgs commit (recommended) | Second flake input at a commit containing the wanted version (look it up on e.g. nixhub.io); take only that package from it | Exact version and build, usually still in the binary cache. Brings its own older dependencies. |
| b) Override the version in current nixpkgs | `overrideAttrs` with the old `version` and `src` (fakeHash trick) | Built locally against today's libraries; can fail if they moved on. |
| c) Freeze everything | Do not update `flake.lock`, or revert it | Whole system stays put, including security fixes. |

```nix
# flake.nix: option a)
inputs.nixpkgs-foo.url = "github:NixOS/nixpkgs/<commit-with-foo-1.9>";
# (specialArgs = { inherit inputs; } is already set, so modules can use `inputs`)

# any module
{ inputs, lib, ... }:
let pinnedFoo = inputs.nixpkgs-foo.legacyPackages.x86_64-linux.foo; in {
  nixpkgs.overlays = [ (final: prev: {
    # warn on every rebuild once nixpkgs has moved past the problem version
    foo = lib.warnIf (lib.versionAtLeast prev.foo.version "2.0")
      "foo pinned to 1.9; nixpkgs has ${prev.foo.version}: check whether the pin can go"
      pinnedFoo;
  }) ];
  # if a NixOS module runs the program, point it at the pin too:
  # services.foo.package = pinnedFoo;
}
```

## Generations, rollback and recovery

```bash
nixos-rebuild list-generations                     # all system generations with dates
sudo nixos-rebuild switch --rollback               # back to the previous generation
nvd diff /run/booted-system /run/current-system    # what changed since boot
```

### When an update breaks something

| Situation | Action | Time |
| --- | --- | --- |
| System runs, something misbehaves | `sudo nixos-rebuild switch --rollback` | Seconds, no reboot |
| System does not boot, or the desktop fails | Reboot, press a key during the 1 s boot menu, choose the previous generation | About 1 minute |
| Boot menu itself broken (ESP/bootloader, rare) | Installer USB, unlock LUKS, mount, `nixos-enter`, switch to a previous generation | About 15 minutes |

1. Make the rollback permanent: `git checkout HEAD~1 -- flake.lock`, switch,
   commit. The next update then starts from the good state.
1. Find the cause: search the nixpkgs GitHub issues for the package; there is
   usually already an issue and often a fix in progress.
1. Wait a few days and update again, or pin just the broken package (above).

> [!NOTE]
> **Not yet automatic:** systemd's Automatic Boot Assessment (boot counting:
> a generation that fails to boot is skipped in favour of the previous one)
> exists in NixOS for plain systemd-boot (`boot.loader.systemd-boot.bootCounting`).
> Whether lanzaboote supports it was not verifiable; until then, choosing the
> previous generation in the boot menu is a manual step.

### Rolling back app data too

A system rollback restores programs and declared configuration (including
home-manager files), but **not data apps wrote themselves** in `/home` and
`/persist`. If a new app version already migrated its database or profile,
the old version may refuse it after the rollback (Firefox, for example,
refuses a profile used by a newer version). Then restore that app's
directories from the snapshot `sysup` took before the update:

```bash
sudo ls /mnt/btr_pool/@snapshots/                  # find the pre-update snapshot
# close the app first, then restore only its directories
# (see chapter 7 for where apps keep their data):
cp -a /mnt/btr_pool/@snapshots/@home.<timestamp>/ivmr/.mozilla ~/
cp -a /mnt/btr_pool/@snapshots/@home.<timestamp>/ivmr/.config/Slack ~/.config/
```

Restore only the affected app, not all of `/home`: documents and other apps
changed since the snapshot stay as they are.

### What generations keep on disk

1. **A generation is not a copy of the OS.** The Nix store holds every
   package exactly once, under a hash of its complete build inputs. A
   generation is a small list of store paths; generations share every package
   that did not change, and `nix.optimise` hard-links identical files across
   packages.
1. **Extra disk per generation = the delta.** But on unstable, when a
   low-level component (glibc, compiler) changes, every package above it gets
   a new hash: that generation is then nearly a full second copy. Measure with
   `nix path-info -Sh /run/current-system`.
1. **Why keep them although the config is in git?** Git holds the recipe, a
   generation holds the built result: instant and offline. Rebuilding an old
   commit relies on the binary cache still serving those builds or on all old
   sources still being downloadable: usually fine, slow at best, not
   guaranteed years later.
1. **How many?** One previous generation is enough for an immediate
   rollback, but breakage often surfaces days later. nh keeps at least 10
   generations and everything from the last 14 days: with weekly updates
   about 2–4 real system states plus small config changes. If disk gets
   tight, reduce `--keep-since`, not below about 7 days.

> [!WARNING]
> Avoid `nix-collect-garbage -d`: it deletes all old generations, i.e. every
> rollback point.
