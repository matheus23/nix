# My personal NixOS setup

I'm running [NixOS](https://nixos.org/) across a desktop (`philipps-desktop`) and a  laptop (`nixos`).

Both machines and shared Home Manager settings are defined declaratively via `flake.nix` (`nixosConfigurations`) and `common.nix`.

## Rebuilding

From this repository:

```sh
sudo -E nixos-rebuild switch --flake .
```

`nixos-rebuild` automatically selects the `nixosConfigurations.<hostname>` matching the current machine (`philipps-desktop` or `nixos`). You can also target a host explicitly with `--flake .#philipps-desktop` or `--flake .#nixos`.

(If you add new files, remember to `git add` or `git add -N` them so Nix flake evaluation sees them.)

## Updating packages

Update all unpinned flake inputs (stable `nixpkgs`, `nixpkgs-unstable`, `home-manager`, `nixos-hardware`, etc.):

```sh
nix flake update
sudo -E nixos-rebuild switch --flake .
```

Or update just a single input (for example, to pull newer packages from `nixpkgs-unstable`):

```sh
nix flake update nixpkgs-unstable
sudo -E nixos-rebuild switch --flake .
```

## Major NixOS release upgrades

1. Bump the release branches in `flake.nix` for `nixpkgs` (e.g. `nixpkgs/nixos-26.11`) and `home-manager` (e.g. `github:nix-community/home-manager/release-26.11`).
2. Run `nix flake update`.
3. Rebuild with `sudo -E nixos-rebuild switch --flake .` and reboot.

## Pinned private / hardware-qualified inputs

- `gufo`, `pigeons-src`, and `mcp-zoo-src` are pinned to explicit revisions in `flake.nix`.
- To bump one, update its `rev` in `flake.nix`, run `nix flake lock` (using your user SSH agent for the private repos), and rebuild.
