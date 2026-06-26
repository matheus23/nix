{
  # Vendored pnpm store hash for the daemon workspace, matching upstream
  # nix/pnpm-deps.nix at the pinned tag. This is a lock artifact — do not
  # hand-edit. Refresh it whenever pnpm-lock.yaml changes:
  #   1. Temporarily set `hash = lib.fakeHash;` in package.nix
  #   2. Build (or `nix flake check`) and copy the expected hash from the
  #      failure output
  daemonHash = "sha256-QR49Ld0IP/3r89UIR+uzrTVYcvycQAYPXcBwzYWTfNE=";
  webHash = "sha256-Y9hspnCl3NGO7yTIIfqu2yBN0hYvfLEjiWRKxjasGmg=";
}
