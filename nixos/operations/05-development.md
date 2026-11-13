# 5. Development environments: what to use when

The system itself carries almost no development tooling. Toolchains live with
the project that needs them, so every project is reproducible on its own,
different projects can use different versions side by side, and nothing
accumulates on the machine. Several mechanisms exist; each fits a different
situation.

| Situation | Use | Why |
| --- | --- | --- |
| Any project you work on regularly (default) | Project flake dev shell + direnv | Pinned, reproducible, loads automatically on `cd`, shared with CI and colleagues |
| Run a tool once or try something | `nix shell` / `,` (comma) | Nothing installed, nothing to clean up |
| Personal tools used in every project (editor, gh, jq, httpie) | home-manager | Your workstation, not the project's concern |
| Databases, queues, services a project needs | Containers (`docker compose`) | Same images as production; start and stop per project |
| Many services, wanted declaratively in Nix | devenv (devenv.sh) | Dev shell plus managed processes (Postgres, Redis) in one file |
| Tooling that assumes a classic distro (vendor SDK installers, .deb/.rpm only) | distrobox | A Debian/Ubuntu/Fedora userland with your home directory mounted |
| Python packages with prebuilt binary wheels | Dev shell + uv; nix-ld | Wheels find their system libraries through nix-ld |
| Client mandates a devcontainer | Docker + devcontainer CLI or VS Code | Follow the client's setup; Nix stays outside it |
| Testing a whole NixOS configuration (server, appliance) | `nixos-rebuild build-vm` / NixOS tests | Full system in a VM, nothing on the host |

## 5.1 Project dev shell with direnv (the default)

Start from a template or write the flake by hand. Templates exist for most
languages, e.g. the community collection `github:the-nix-way/dev-templates`:

```bash
cd ~/claude-code/myproject
nix flake init -t github:the-nix-way/dev-templates#python   # or #node, #rust, #go ...
echo "use flake" > .envrc
direnv allow                       # trust this .envrc (re-run after changes to it)
git add flake.nix flake.lock .envrc   # flakes only see git-tracked files
```

Or by hand, a typical full-stack project:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nodejs_22 pnpm              # frontend
          python313 uv ruff           # backend
          postgresql_17               # psql client only; server runs in a container
        ];
        shellHook = ''
          export UV_PYTHON_DOWNLOADS=never        # use the Nix Python, not uv's own
          export UV_PYTHON=${pkgs.python313}/bin/python
          [ -f .env ] && set -a && source .env && set +a   # local secrets, not committed
        '';
      };
    };
}
```

1. **Entering the directory** loads the environment into your current shell;
   leaving it unloads it. The first load builds or downloads; afterwards
   nix-direnv caches it, so it is instant.
1. **Pinning:** the project's own `flake.lock` pins its toolchain
   independently of your system. Update deliberately with `nix flake update`
   inside the project and commit the lock.
1. **Garbage collection:** nix-direnv registers the shell as a GC root and
   the system has `keep-outputs` enabled, so cleaning the store does not
   delete toolchains of projects you use.
1. **Without direnv:** `nix develop` enters the same shell manually;
   `nix develop -c pnpm test` runs one command in it.

## 5.2 Language notes

| Language | Recommended setup | Pitfalls |
| --- | --- | --- |
| Python | `python313` + `uv` in the shell; `uv sync` creates `.venv` in the project | Let uv use the Nix Python (`UV_PYTHON` as above). Binary wheels (numpy, torch) work via nix-ld; add missing libraries to `programs.nix-ld.libraries`. |
| Node / TS | `nodejs_22` + `pnpm` from nixpkgs | Do not use `corepack enable` or `npm install -g`: both try to write into the read-only Nix store. Put CLIs in the shell or use `npx`. |
| Rust | Simple: `cargo rustc rust-analyzer clippy rustfmt`. Pinned toolchain per `rust-toolchain.toml`: rustup in the shell | Native crates need their C libraries in the shell (e.g. `openssl pkg-config`). |
| Go | `go gopls golangci-lint` | CGO packages need their C libraries in the shell. |
| C / C++ | `pkgs.mkShell` with `cmake meson pkg-config` and libraries | Libraries must be in the shell, not installed system-wide; pkg-config then finds them automatically. |

## 5.3 Services: containers or devenv

Keep databases and other services out of the system configuration. Two good
options:

```yaml
# compose.yaml in the project - same images as production
services:
  db:
    image: postgres:17
    environment: { POSTGRES_PASSWORD: dev }
    ports: [ "5432:5432" ]
    volumes: [ "pgdata:/var/lib/postgresql/data" ]
volumes: { pgdata: {} }
```

```bash
docker compose up -d      # start
docker compose down       # stop
```

Docker is rootful, as on Gentoo ([dev.nix](../install/03-system-modules.md#b13-modulesdevnix)).
Images and volumes live in `/var/lib/docker` on the `@docker` subvolume: they
survive reboots but are not snapshotted or backed up, so anything valuable in
a volume needs its own export. `docker system prune` runs weekly via
`autoPrune`.

If you prefer services declared in Nix next to the toolchain, **devenv**
(devenv.sh) provides a `devenv.nix` with options like
`services.postgres.enable = true;` and starts them with `devenv up`.

## 5.4 distrobox: the escape hatch

For software that only ships as .deb/.rpm or whose installer assumes a
classic filesystem layout. It runs a container of another distribution (on
Docker here) with your home directory and Wayland session shared.

```bash
distrobox create -n ubuntu -i ubuntu:24.04
distrobox enter ubuntu                  # now inside Ubuntu: apt install whatever is needed
distrobox-export --app vendor-gui       # optional: add its app to the GNOME launcher
```

Add `distrobox` to `environment.systemPackages` in `dev.nix` when you first
need it. Use it sparingly: whatever runs inside is not reproducible from your
repo. Prefer nixpkgs, nix-ld or a Flatpak first.

## 5.5 Client projects that do not use Nix

A flake inside a git repository only sees files tracked by that repository,
so you cannot simply keep an untracked `flake.nix` in a client repo. Keep
your dev shells in a separate repository of your own and point direnv at it:

```bash
~/claude-code/devshells/flake.nix    # your repo: one devShell per client project
  devShells.x86_64-linux.clientx = pkgs.mkShell { packages = [ ... ]; };
  devShells.x86_64-linux.clienty = pkgs.mkShell { packages = [ ... ]; };

# in the client checkout:
echo "use flake ~/claude-code/devshells#clientx" > .envrc
echo ".envrc" >> .git/info/exclude   # local ignore, nothing changes in the client repo
direnv allow
```

## 5.6 Editors, Claude Code and CI

1. **Editors** must see the project environment, or language servers and
   formatters are missing. VS Code: install the direnv extension. Zed and
   Neovim: use their direnv integration. Or start the editor from a terminal
   inside the project directory.
1. **Claude Code** inherits the environment of the shell it is started from.
   Start it inside the project directory after direnv has loaded, and it uses
   exactly the pinned toolchain; mention the dev shell in the project's
   `CLAUDE.md` so it runs commands through it.
1. **CI** runs the identical toolchain with `nix develop -c <command>`, so
   "works on my machine" and "works in CI" become the same statement.

> [!NOTE]
> **Rule:** if a tool is needed to build or test the project, it belongs in
> the project's flake, not in your system or home configuration. If it is how
> you like to work regardless of project, it belongs in home-manager.
