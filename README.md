# My personal NixOS setup

I'm running [NixOS](https://nixos.org/) across a desktop (`philipps-desktop`) and a  laptop (`nixos`).

Both machines and shared Home Manager settings are defined declaratively via `flake.nix` (`nixosConfigurations`) and `common.nix`.

## Rebuilding

From anywhere (defaults to `switch`; accepts `test`, `boot`, `dry-build`, etc. plus extra `nixos-rebuild` flags):

```sh
rebuild          # nixos-rebuild switch --flake <repo> --sudo
rebuild test     # nixos-rebuild test --flake <repo> --sudo
rebuild boot     # nixos-rebuild boot --flake <repo> --sudo
```

Or directly from this repository:

```sh
nixos-rebuild switch --flake . --sudo
```

`nixos-rebuild` automatically selects the `nixosConfigurations.<hostname>` matching the current machine (`philipps-desktop` or `nixos`), evaluates/builds as your user (so your SSH agent is used directly for private inputs), and escalates with `sudo` only for activation. You can also target a host explicitly with `--flake .#philipps-desktop` or `--flake .#nixos`.

(If you add new files, remember to `git add` or `git add -N` them so Nix flake evaluation sees them.)

## Updating packages

Update all unpinned flake inputs (stable `nixpkgs`, `nixpkgs-unstable`, `home-manager`, `nixos-hardware`, etc.):

```sh
nix flake update
nixos-rebuild switch --flake . --sudo
```

Or update just a single input (for example, to pull newer packages from `nixpkgs-unstable`):

```sh
nix flake update nixpkgs-unstable
nixos-rebuild switch --flake . --sudo
```

## Major NixOS release upgrades

1. Bump the release branches in `flake.nix` for `nixpkgs` (e.g. `nixpkgs/nixos-26.11`) and `home-manager` (e.g. `github:nix-community/home-manager/release-26.11`).
2. Run `nix flake update`.
3. Rebuild with `nixos-rebuild switch --flake . --sudo` and reboot.

## Pinned private / hardware-qualified inputs

- `gufo`, `pigeons-src`, and `mcp-zoo-src` are pinned to explicit revisions in `flake.nix`.
- To bump one, update its `rev` in `flake.nix`, run `nix flake lock` (using your user SSH agent for the private repos), and rebuild.
