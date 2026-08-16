{
  lib,
  rustPlatform,
  btrfs-progs,
  libnotify,
  makeWrapper,
}:

rustPlatform.buildRustPackage {
  pname = "btrfs-pressure-monitor";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/btrfs-pressure-check \
      --prefix PATH : ${
        lib.makeBinPath [
          btrfs-progs
          libnotify
        ]
      }
  '';

  meta = with lib; {
    description = "Report Btrfs allocation pressure and notify while it persists";
    mainProgram = "btrfs-pressure-check";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
