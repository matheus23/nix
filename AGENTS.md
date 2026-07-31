# NixOS Configuration Repo

This is a personal NixOS configuration repository, not an application codebase. It manages system config for a desktop and a laptop (Lenovo ThinkPad T14 Gen 3 AMD), plus shared home-manager settings and flake-based dev shells.

## Directory Structure

- `flake.nix` — Flake with devShells for multiple projects
- `desktop/configuration.nix` — Desktop system config (stateVersion 25.11)
- `laptop/configuration.nix` — Laptop system config (stateVersion 22.11)
- `home-manager/home.nix` — Shared home-manager config (user: `philipp`)
- `custom/*.nix` — Custom package overrides (wesnoth, tracy, ideal-fonts, lmstudio, letta-code, mnemosyne)
- `scripts/` — Helper scripts

## Critical Path Differences

Desktop imports home-manager from `/home/philipp/program/nix/home-manager/home.nix`.
Laptop imports from `/home/philipp/program/nix/home/home-manager/home.nix`. These paths differ — be careful when editing which machine is active.

## Rebuilding the System

```sh
sudo -E nixos-rebuild switch          # rebuild current machine
sudo -E nixos-rebuild switch --upgrade  # also update nixpkgs channels
```

`-E` is required: the `pigeons` package (`custom/pigeons/package.nix`) uses `builtins.fetchGit` over SSH to fetch a private repo at evaluation time, which runs as root under `sudo` and needs `SSH_AUTH_SOCK` forwarded from your ssh-agent (GNOME keyring). If you ever drop the SSH-fetched pigeons source, you can go back to plain `sudo nixos-rebuild switch`.

After a rebuild, reboot if kernel or bootloader changed.

## Flake Inputs

- `nixpkgs` → `nixos-25.11` (stable)
- `nixpkgs-unstable` → `nixos-unstable`
- `nixpkgs-androidenv` → fork for NDK toolchain fix
- `rust-overlay`, `flake-utils`, `command-utils`

## Dev Shells (via `nix develop`)

Entry with shell name: `nix develop .#<name>`

| Shell | Purpose | Notes |
|---|---|---|
| `tauri` | Tauri/Rust + Android dev | Sets `ANDROID_SDK_ROOT`, `ANDROID_NDK_ROOT`, `JAVA_HOME`. Requires `jdk17`, NDK 26.x, webkitgtk. |
| `n0des` | Rust backend + Postgres | Auto-inits local PG in `./.pg`, runs sqlx migrations on entry. Uses `command-utils` for `db-start`/`db-stop`/`db-reset`. Set `PGURL` and `DATABASE_URL`. |
| `netsim` | Network simulation | Starts/stops Open vSwitch on entry/exit. Runs scripts as root via wrapper. |
| `egui` | egui (Rust GUI) | Sets `LD_LIBRARY_PATH` for X11/Wayland libs. |
| `iroh-live` | iroh + GPUI + AV | Needs ffmpeg, pipewire, clang/bindgen, vulkan, libva, nasm. |
| `playwright` | Playwright E2E | Sets `PLAYWRIGHT_BROWSERS_PATH` and skips host validation. Browser version must match npm package. |
| `dioxus` | Dioxus dev | Includes webkitgtk, gtk3, sqlite, xdo. Uses `unstable.dioxus-cli`. |
| `bevy` | Bevy game engine | Vulkan, ALSA, libudev, X11/Wayland. Sets `LD_LIBRARY_PATH`. |
| `gtk` | GTK4 development | gtk4, libadwaita, gtksourceview5, graphene. |
| `llama-cpp` | llama.cpp builds | Vulkan SDK, libclang 20, tracy, shaderc, renderdoc. Sets `LIBCLANG_PATH`, `VULKAN_SDK`, `VK_LAYER_PATH`. |

## n0des Dev Shell — Database Details

The `n0des` shell auto-manages a local PostgreSQL instance:
- Data directory: `./.pg` (relative to working dir)
- Connection: `postgres://philipp@localhost:5432/n0des`
- Unix socket: `/tmp` (set via `PGHOST`)
- Migrations live at `ips/backend/migrations` (relative to the project, not this repo)
- Commands: `db-start`, `db-stop`, `db-reset`

## Laptop-Specific Config

- Power management via `tlp` (not power-profiles-daemon)
- Virtual camera/mic via `v4l2loopback` and `snd-aloop`
- Docker enabled, user in `docker` and `adbusers` groups
- `nix-ld` enabled for running downloaded binaries
- Firewall allows TCP 1420/1421 (tauri/vite HMR)

## Common Gotchas

- `home-manager/home.nix` uses `<nixos-unstable>` channel for `unstable` pkgs binding — this resolves from the system's nix-channel, not the flake input.
- `bashInteractive` is included in most devShells to fix VS Code terminal issues on NixOS.
- `permittedInsecurePackages` includes old electron and openssl versions — required by some packages.
- Flakes are enabled via `nix.settings.experimental-features = "nix-command flakes"` in both machine configs.

## Custom lmstudio Package

`custom/lmstudio/package.nix` overrides the nixpkgs version (used in `home-manager/home.nix`). To update: find the latest version from `curl -ILs -o /dev/null -w '%{url_effective}' "https://lmstudio.ai/download/latest/linux/x64"`, compute the hash with `nix-prefetch-url --type sha256 "<url>"`, then update `version` and `hash` in the package file. The URL pattern is `https://installers.lmstudio.ai/linux/x64/<version>/LM-Studio-<version>-x64.AppImage`.

## Custom mnemosyne Package

`custom/mnemosyne/package.nix` packages [AxDSan/mnemosyne](https://github.com/AxDSan/mnemosyne) (PyPI `mnemosyne-memory`) as a `buildPythonApplication`, exposing the `mnemosyne` CLI. It's installed via `home-manager/home.nix`. Feature scope is **core + MCP + embeddings**; the `llm` (ctransformers) and `openclaw` extras are intentionally omitted since those deps aren't in nixpkgs.

To bump the version:
1. Update `version` in the package file to the new release tag (without the `v` prefix).
2. Recompute the source hash:
   ```sh
   nix-prefetch-url --unpack "https://github.com/AxDSan/mnemosyne/archive/refs/tags/v<version>.tar.gz"
   nix hash convert --to sri --hash-algo sha256 <hash-from-above>
   ```
3. Update `hash` in the package file with the resulting `sha256-...` value.
4. Check `pyproject.toml` for new/changed dependencies and adjust `dependencies` accordingly.

Gotchas:
- Importing `mnemosyne` eagerly runs `init_db()`, which tries to create a DB dir under `$HOME` (unwritable `/homeless-shelter` in the sandbox). The package works around this by setting `MNEMOSYNE_DATA_DIR` to a temp dir in `postFixup` (the `pythonImportsCheck` runs right after `fixupPhase`).
- At first runtime use, `fastembed` downloads the `bge-small-en-v1.5` embedding model from HuggingFace into the data dir (default `~/.hermes/mnemosyne/data`, override with `MNEMOSYNE_DATA_DIR`). It is not bundled in the Nix package.
- For MCP clients (Cursor, Claude Code, Codex, etc.), point them at `command: "mnemosyne", args: ["mcp"]`.

## Custom letta-code Package

`custom/letta-code/package.nix` packages [letta-ai/letta-code](https://github.com/letta-ai/letta-code) (npm `@letta-ai/letta-code`) as a `buildNpmPackage`, exposing the `letta` CLI. It's installed via `home-manager/home.nix`. The package fetches the pre-built npm tarball (no source build needed), installs runtime dependencies via `npm ci`, and wraps the `letta` binary with `git` and `ripgrep` on PATH.

To bump the version:
1. Update `version` in the package file.
2. Recompute the tarball hash:
   ```sh
   nix-prefetch-url --type sha256 "https://registry.npmjs.org/@letta-ai/letta-code/-/letta-code-<version>.tgz"
   nix hash convert --to sri --hash-algo sha256 <hash-from-above>
   ```
3. Update `hash` in the package file.
4. Regenerate the vendored `package-lock.json`:
   ```sh
   cd /tmp && mkdir lc && cd lc
   curl -sL "https://registry.npmjs.org/@letta-ai/letta-code/-/letta-code-<version>.tgz" | tar xz
   cd package
   nix-shell -p nodejs_22 --run "npm install --package-lock-only --ignore-scripts --legacy-peer-deps --cache /tmp/lc-cache"
   cp package-lock.json /home/philipp/program/nix/custom/letta-code/package-lock.json
   ```
5. Set `npmDepsHash = lib.fakeHash`, build with `nix-build -E 'with import <nixpkgs> {}; callPackage ./custom/letta-code/package.nix {}'`, and paste the `got: sha256-...` from the error.

Gotchas:
- The npm tarball doesn't ship a `package-lock.json` — one is vendored at `custom/letta-code/package-lock.json` and copied in via `postPatch`.
- The tarball's `prepare` script (`node .husky/install.mjs`) references `.husky/` which isn't shipped; it's stripped from `package.json` in `postPatch` to prevent `npm pack --dry-run` from failing.
- `react@18.2.0` conflicts with `@pierre/diffs`'s peer dep (`^18.3.1 || ^19.0.0`); `--legacy-peer-deps` is passed via `npmFlags`.
- Native modules (`sharp`, `node-pty`) are compiled during `npm rebuild` in the build sandbox.
- The CLI creates `~/.letta/` at first run for settings and agent state.
