{
  lib,
  stdenv,
  python3,
  btrfs-progs,
  makeWrapper,
}:

let
  pythonEnv = python3.withPackages (p: [ p.btrfs ]);
in
stdenv.mkDerivation {
  pname = "btrfs-snap-scrub";
  version = "0.1.1";

  src = ./btrfs-snap-scrub.py;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  nativeCheckInputs = [ pythonEnv ];
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    python ${./test_mount_discovery.py} $src
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 $src $out/bin/btrfs-snap-scrub
    wrapProgram $out/bin/btrfs-snap-scrub \
      --prefix PATH : ${
        lib.makeBinPath [
          pythonEnv
          btrfs-progs
        ]
      }
    runHook postInstall
  '';

  meta = with lib; {
    description = "Remove a file or directory from all btrfs snapshots sharing its extents to reclaim disk space";
    mainProgram = "btrfs-snap-scrub";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
