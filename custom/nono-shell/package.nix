{
  lib,
  rustPlatform,
  src,
}:

# Built from the private matheus23/mcp-zoo repo, pinned via `inputs.mcp-zoo-src`
# in flake.nix.
rustPlatform.buildRustPackage {
  pname = "nono-shell";
  version = "0.1.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoBuildFlags = [
    "-p"
    "nono-shell"
  ];
  cargoTestFlags = [
    "-p"
    "nono-shell"
  ];

  meta = {
    description = "MCP server that runs shell commands and file edits inside a nono sandbox";
    mainProgram = "nono-shell";
    platforms = lib.platforms.linux;
  };
}
