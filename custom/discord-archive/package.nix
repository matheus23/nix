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
