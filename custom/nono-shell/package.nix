{
  lib,
  rustPlatform,
}:

let
  src = import ../mcp-zoo-src.nix;
in
rustPlatform.buildRustPackage {
  pname = "nono-shell";
  version = "0.1.0";
  inherit src;
  # Remove when the pinned mcp-zoo revision includes --compaction-workspace.
  patches = [ ./compaction-workspace.patch ];

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
