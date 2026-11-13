# 13. Coming from Gentoo

What you lose with Nix compared to Portage, what replaces it, and which
Gentoo maintenance work disappears. The Gentoo setup itself is documented in
[gentoo/](../../gentoo/README.md).

## Portage features and their Nix counterparts

| Portage | NixOS | Assessment |
| --- | --- | --- |
| Global USE flags, `USE_EXPAND` (`VIDEO_CARDS`, `L10N`...) | Per-package `override { withFoo = false; }` or `overrideAttrs` on build flags | Loss of the global switch and `REQUIRED_USE` consistency checks; reach is complete ([chapter 6](06-patching.md)) |
| `package.accept_keywords` for one testing package | Overlay with newer `src`, or second input | Rarely needed on unstable |
| `emerge -1 foo` (upgrade one package) | Overlay or pin; `flake.lock` moves everything at once | Real loss; on unstable a full update is normally safe |
| `package.mask` | Exact pin ([chapter 3](03-updating-and-rollback.md#pinning-a-package-to-an-exact-version-the-mask-equivalent)) with `warnIf` reminder | Pin is stricter: exactly this version |
| `/etc/portage/patches` | Overlay `patches = ...` | Equivalent |
| `package.env` (per-package CFLAGS) | `stdenv` override per package | Equivalent |
| Live ebuilds (`-9999`) | Flake input with `flake = false` | Equivalent |
| SLOTs | Any versions coexist automatically | Nix is better |
| `eselect news` | nh evaluation warnings, release notes, Discourse announcements | Loss: nothing curated for unstable |
| GLSA / `glsa-check` | `vulnix --system` (CVE scan of the system) | Partial loss: less curated |
| `equery belongs` / `depends` | `nix-locate`, `nix why-depends` | Equivalent |
| `ACCEPT_LICENSE` | `allowUnfree` / `allowUnfreePredicate` | Equivalent |
| OpenRC, musl, hardened, SELinux profiles | systemd only, musl partial, no SELinux | Loss in breadth, irrelevant for this setup |
| FHS layout: any binary runs | nix-ld, distrobox | Loss, mitigated |
| Editing a file in `/usr` for a quick test | Read-only store: rebuild | Slower hacks; also what prevents drift |
| `::local` overlay with your own ebuilds (Claude Desktop, ChatGPT) | Flake inputs (`aaddrick/claude-desktop-debian`) or nixpkgs packages | No more manual bump scripts |
| Handbook + wiki | Manual, nix.dev, wiki (fragmented) | Loss in documentation |

## Gentoo maintenance that disappears

| Gentoo task | On NixOS |
| --- | --- |
| `dispatch-conf` / `etc-update` config merging | Gone: `/etc` is generated |
| Profile migrations (e.g. 17.1 to 23.0) | Gone: `stateVersion` plus option warnings |
| `PYTHON_TARGETS` bumps, `perl-cleaner`, `haskell-updater` | Gone: every package carries its exact interpreter |
| GCC upgrade procedure (`gcc-config`) | Gone: part of nixpkgs |
| Blockers, slot conflicts, circular USE deps | Gone: no shared mutable dependency graph |
| `@preserved-rebuild`, stale linking | Gone: the hash model rebuilds dependents |
| 44–80 min kernel builds | Gone: stock kernel from the binary cache |
| Rollback via snapshots or stage4 | Generations in the boot menu |
| Rebuilding a second machine for hours | `nixos-install --flake` |
| Config drift over years | Structurally impossible with a tmpfs root |

> [!NOTE]
> **Insurance against problems in Nix itself:** Lix is a community fork of
> the Nix implementation that is compatible with NixOS. If governance or
> bugs in Nix ever become a problem, switching is one line
> (`nix.package = pkgs.lix;`), without changing the distribution or the
> configuration.
