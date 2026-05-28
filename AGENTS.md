# NixOS Configuration Repo

This is a personal NixOS configuration repository, not an application codebase. It manages system config for a desktop and a laptop (Lenovo ThinkPad T14 Gen 3 AMD), plus shared home-manager settings and flake-based dev shells.

## Directory Structure

- `flake.nix` — Flake with devShells for multiple projects
- `desktop/configuration.nix` — Desktop system config (stateVersion 25.11)
- `laptop/configuration.nix` — Laptop system config (stateVersion 22.11)
- `home-manager/home.nix` — Shared home-manager config (user: `philipp`)
- `custom/*.nix` — Custom package overrides (wesnoth, tracy, ideal-fonts)
- `scripts/` — Helper scripts

## Critical Path Differences

Desktop imports home-manager from `/home/philipp/program/nix/home-manager/home.nix`.
Laptop imports from `/home/philipp/program/nix/home/home-manager/home.nix`. These paths differ — be careful when editing which machine is active.

## Rebuilding the System

```sh
sudo nixos-rebuild switch          # rebuild current machine
sudo nixos-rebuild switch --upgrade  # also update nixpkgs channels
```

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
