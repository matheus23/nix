# NixOS Configuration Repo

This is a personal NixOS configuration repository, not an application codebase. It manages system config for a desktop and a laptop (Lenovo ThinkPad T14 Gen 3 AMD), plus shared home-manager settings and flake-based dev shells.

## Directory Structure

- `flake.nix` — Flake exporting `nixosConfigurations` (`philipps-desktop`, `nixos`) and `devShells`
- `common.nix` — Shared NixOS module imported by both machines (CA trust, GNOME/PipeWire, SSH/pigeons, Home Manager, nix settings)
- `desktop/configuration.nix` — Desktop-specific system config (stateVersion 25.11, Strix Halo GPU, Snapper, local LLM servers)
- `laptop/configuration.nix` — Laptop-specific system config (stateVersion 22.11, ThinkPad T14 Gen 3 AMD, TLP, agent container)
- `home-manager/home.nix` — Shared home-manager config (user: `philipp`)
- `custom/*` — Custom packages and overrides (pigeons, discord-archive, nono-shell, goose-desktop, letta-code, antigravity-cli, btrfs-pressure-monitor, btrfs-snap-scrub, etc.)
- `scripts/` — Helper scripts

## Rebuilding the System

Both machines are managed via `nixosConfigurations` in `flake.nix`, matched by hostname (`philipps-desktop` for desktop, `nixos` for laptop):

```sh
nixos-rebuild switch --flake . --sudo                    # rebuild current machine (auto-detects host)
nixos-rebuild switch --flake .#philipps-desktop --sudo   # explicit desktop target
nixos-rebuild switch --flake .#nixos --sudo              # explicit laptop target
```

Updating inputs:

```sh
nix flake update                    # update all unpinned flake inputs
nix flake update nixpkgs-unstable   # update a single input
```

Notes:
- **New files must be tracked by Git** (`git add` or `git add -N`) before Nix flake evaluation can see them.
- **Private SSH inputs (`pigeons-src`, `mcp-zoo-src`)** are pinned to explicit `rev` values in `flake.nix` and locked in `flake.lock`. To bump one, update its `rev` in `flake.nix` and run `nix flake lock`. Using `--sudo` runs evaluation/builds as your user (so your ssh-agent is used directly without `$HOME` warnings) and escalates only for activation.
- After a rebuild, reboot if kernel or bootloader changed.

## Flake Inputs

- `nixpkgs` → `nixos-26.05` (stable, also pinned as the system `nixpkgs` registry entry)
- `nixpkgs-unstable` → `nixos-unstable` (passed to modules as `unstable`)
- `home-manager` → `release-26.05` (follows `nixpkgs`)
- `nixos-hardware` → ThinkPad T14 Gen 3 AMD module
- `gufo` → pinned Gufo flake (keeps its own ROCm toolchain for Strix Halo)
- `pigeons-src`, `mcp-zoo-src` → pinned private SSH repos (`flake = false`)
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
- `boot.loader.systemd-boot.configurationLimit = 5` (511 MiB `/boot/efi` partition)
- Virtual camera/mic via `v4l2loopback` and `snd-aloop`
- `android-tools` installed for ADB (systemd 258 handles uaccess rules; `programs.adb` was removed in 26.05)
- `nix-ld` enabled with extra libraries for running downloaded binaries
- `containers.agent-box` + `pigeons-agent` service for the sandboxed laptop agent
- `letta-code` (`le-nono`) and `nono-shell` are currently desktop-only HM imports (`desktop/configuration.nix`); `custom.discord-archive.spkiHash` is set per host in each machine's `configuration.nix`

## Common Gotchas

- `unstable` is instantiated once per host in `flake.nix` from `inputs.nixpkgs-unstable` (with `allowUnfree = true`) and passed via `specialArgs` / `home-manager.extraSpecialArgs`.
- `home-manager.useGlobalPkgs = true` is set in `common.nix`, so do not set `nixpkgs.config` inside `home-manager/home.nix`.
- `bashInteractive` is included in most devShells to fix VS Code terminal issues on NixOS.
- Flakes and `nix-command` are enabled in `common.nix`.

## Custom lmstudio Package

`custom/lmstudio/package.nix` overrides the nixpkgs version (used in `home-manager/home.nix`). To update: find the latest version from `curl -ILs -o /dev/null -w '%{url_effective}' "https://lmstudio.ai/download/latest/linux/x64"`, compute the hash with `nix-prefetch-url --type sha256 "<url>"`, then update `version` and `hash` in the package file. The URL pattern is `https://installers.lmstudio.ai/linux/x64/<version>/LM-Studio-<version>-x64.AppImage`.

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

## Custom antigravity-cli Package

`custom/antigravity-cli/package.nix` packages Google's Antigravity CLI (binary: `agy`) from the
prebuilt tarball Google serves to its own installer, and `home-manager/antigravity-cli.nix` installs
it. nixpkgs has the same package (`antigravity-cli`, seen in `<nixos-unstable>`), but it lags and
leaves the self-updater on; this one is pinned and wraps `agy` with `AGY_CLI_DISABLE_AUTO_UPDATE`.

To bump: read `version` and the build id from
`https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json`
(the manifest the official installer reads), then recompute both tarball hashes with
`nix hash convert --hash-algo sha256 --to sri "$(curl -fsSL <url> | sha256sum | cut -d' ' -f1)"`.
Both `version` and `buildId` appear in the download path, so both must change.

Gotchas:
- The tarball member is `antigravity`; the installed command is `agy`.
- **The command sandbox needs store read grants.** `agy` runs agent commands in a new mount
  namespace whose root has only FHS directories plus its `read_file` grants. `autoPatchelfHook`
  repoints the binary's ELF interpreter at a glibc in the store, so after `pivot_root` the sandbox
  helper dies with `sbox: exec /proc/self/exe: no such file or directory` and every command fails
  with `connecting to sandbox server: ... connection reset by peer` — and `auto` mode turns the
  sandbox on by default. `home-manager/antigravity-cli.nix` merges `read_file(/nix/store)`,
  `read_file(/run/current-system/sw)` and `read_file(/etc/profiles)` into
  `~/.gemini/antigravity-cli/settings.json` to fix this. Tracked upstream as
  [google-antigravity/antigravity-cli#1753](https://github.com/google-antigravity/antigravity-cli/issues/1753);
  drop the grants once that ships.
- `agy` owns that `settings.json` and rewrites it from `/config`, so the module merges additively
  rather than managing the file. `agy-nix-sandbox-grants` (installed) re-applies the grants by hand.
- Sign-in uses the D-Bus secret-service; GNOME Keyring covers it on this desktop. Over SSH, agy
  prints an authorization URL instead of opening a browser.
- Do **not** run upstream's `curl .../install.sh | bash` alongside this: it writes `~/.local/bin/agy`,
  which is on `PATH` via `home.sessionPath` and would shadow the packaged binary.
