{
  lib,
  rustPlatform,
}:

let
  # Built from the local checkout, so a rebuild picks up new commits.
  src = lib.cleanSourceWith {
    src = /home/philipp/program/mcp-zoo;
    filter = path: type: baseNameOf path != "target" && baseNameOf path != "plans";
  };
in
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
