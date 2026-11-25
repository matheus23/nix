{
  lib,
  rustPlatform,
  src,
}:

# Built from the private matheus23/mcp-zoo repo, pinned via `inputs.mcp-zoo-src`
# in flake.nix.
rustPlatform.buildRustPackage {
  pname = "discord-archive";
  version = "0.1.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoBuildFlags = [
    "-p"
    "discord-archive"
  ];
  cargoTestFlags = [
    "-p"
    "discord-archive"
  ];

  meta = {
    description = "Archive Discord messages from the desktop client and serve them over MCP";
    mainProgram = "discord-archive";
    platforms = lib.platforms.linux;
  };
}
