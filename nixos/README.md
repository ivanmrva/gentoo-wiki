# NixOS on the HP ZBook 8 G1i 14"

The NixOS setup that replaces the [Gentoo installation](../gentoo/README.md)
on the new laptop (HP ZBook 8 G1i 14", A3ZU5ET#ABD).

| Guide | What it covers |
| --- | --- |
| **[Installation guide](install/README.md)** | Phases 0 and A–I: preparing everything on Gentoo, the flake repository and all modules, BIOS, install, Secure Boot, TPM, hibernation, first-boot checks |
| **[Operations guide](operations/README.md)** | Daily work: the core loop, adding software, updating and rollback, impermanence, dev environments, patching, Flatpak, GNOME, maintenance, failure scenarios, performance, coming from Gentoo |

Open decisions are listed in the
[installation guide](install/README.md#open-decisions) and marked
**DECISION** in both guides.

## PDFs

```bash
nixos/tools/md2pdf.sh          # → nixos/build/NixOS-HP-ZBook-Install-Guide.pdf
                               #   nixos/build/NixOS-Daily-Operations-Guide.pdf
nixos/tools/md2pdf.sh <guide-dir> [out.pdf] [footer]   # one guide (also works for gentoo/)
```

It needs `pandoc` plus one PDF engine: WeasyPrint, Chromium/Chrome, or the
Chrome Flatpak. On NixOS:
`nix shell nixpkgs#pandoc nixpkgs#chromium -c nixos/tools/md2pdf.sh`.
`nixos/build/` is not committed.
