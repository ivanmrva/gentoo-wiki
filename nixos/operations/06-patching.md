# 6. Patching and customizing packages

```nix
nixpkgs.overlays = [ (final: prev: {
  # add a patch
  foo = prev.foo.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/foo-fix.patch ];
  });
  # different version or your fork
  bar = prev.bar.overrideAttrs (old: {
    version = "2.1-git";
    src = prev.fetchFromGitHub {
      owner = "you"; repo = "bar"; rev = "<sha>";
      hash = prev.lib.fakeHash;          # build once, copy the real hash from the error
    };
  });
  # CPU-tuned build of one package (only after measuring a gain, see chapter 12)
  mytool = prev.mytool.override {
    stdenv = prev.stdenvAdapters.withCFlags [ "-march=arrowlake" "-O3" ] prev.stdenv;
  };
}) ];
```

1. Overriding a **library** rebuilds everything that depends on it. Check the
   blast radius first: `nix-tree` or `nix why-depends`.
1. Rust and Go packages pin dependencies by hash: if a patch changes
   `Cargo.lock` or `go.mod`, update `cargoHash` / `vendorHash` with the
   fakeHash trick.
1. Wrapped packages (firefox, mpv) are patched via their `-unwrapped` variant.
1. A failing patch after an update stops the build with an error: rebase or
   drop the patch once the fix is upstream.

## Named parameters vs. full control

1. **Named feature parameters** (`withX`, `enableX`, `xSupport`) are the
   convenient, maintainer-tested subset. Measured on nixpkgs 26.11 for 71
   typical GNOME desktop packages: about 70 % expose at least one (ffmpeg 153,
   systemd 58, qemu 33, mpv 25, Firefox 23, gtk3/gtk4 7 each); the GNOME
   components themselves (gnome-shell, mutter, GDM, Settings, Nautilus) expose
   none.
1. **Every upstream build option is still reachable** without a named
   parameter, via `overrideAttrs` on the build flags, e.g.
   `mesonFlags = old.mesonFlags ++ [ "-Dfoo=false" ];`. Missing parameters
   mean less convenience, not less control.
1. **No consistency check:** Gentoo's `REQUIRED_USE` stops contradictory
   combinations up front; in Nix, removing something another package needs
   shows up as a build failure.

## Your own binary cache

Push what you build (patched or tuned packages, the whole system from CI) to
a cache such as Cachix or attic, so it is built once for all machines:

```nix
nix.settings = {
  extra-substituters = [ "https://your-cache.example.org" ];
  extra-trusted-public-keys = [ "your-cache:BASE64KEY=" ];
};
```

Your user is deliberately **not** a Nix trusted user: trusted users can add
any binary cache and signing key, which is equivalent to root. Consequence:
caches that a project flake declares in its `nixConfig` are ignored; add the
ones you trust system-wide as above.

`extra-` keeps cache.nixos.org as well; setting `substituters` directly would
replace it.
