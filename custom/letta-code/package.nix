{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  bun,
  cacert,
  git,
  ripgrep,
  makeWrapper,
  python3,
}:

let
  version = "0.34.63";
  src = fetchFromGitHub {
    owner = "letta-ai";
    repo = "letta-code";
    rev = "eadef1c6c3594d1bf81517efd4b68fce54644ad4";
    hash = "sha256-OLVW/kSyECnsJTd8MBrSffLv/jWuH/aQDfcAJlnsKJU=";
  };

  # FOD for node_modules (buildNpmPackage chokes on this release's dep graph)
  npmDeps = stdenv.mkDerivation {
    pname = "letta-code-npm-deps";
    inherit version src;
    nativeBuildInputs = [
      nodejs_22
      cacert
    ];
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR" npm_config_cache="$TMPDIR/npm-cache"
      cp ${./package-lock.json} package-lock.json
      npm_config_fetch_retries=0 npm_config_fetch_timeout=30000 \
        npm install --ignore-scripts --legacy-peer-deps \
          --no-audit --no-fund
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -a node_modules "$out/"
    '';

    dontPatchShebangs = true;
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-ost2Vki4+6cEMbejNywHT6SlOuuEC/qSlqXUpiMrqlY=";
  };
in
stdenv.mkDerivation {
  pname = "letta-code";
  inherit version src;

  patches = [
    # Drop oldest images on retry when local providers (e.g. Gufo) reject >16 images
    ./local-image-count-recovery.patch
    ./no-generated-attribution-03463.patch
  ];

  nativeBuildInputs = [
    bun
    nodejs_22
    makeWrapper
    python3
  ];
  buildPhase = ''
    export HOME="$TMPDIR" npm_config_cache="$TMPDIR/npm-cache"
    cp -a ${npmDeps}/node_modules .
    chmod -R u+w node_modules
    # Lifecycle scripts are disabled in the dependency fetch. Build the PTY
    # addon here with Nix's compiler and Node headers, without network access.
    npm rebuild node-pty --offline --nodedir=${nodejs_22}
    node scripts/postinstall-patches.js
    # Avoid bunx's network/cache lookup inside the Nix build.
    sed -i 's|bunx tsc|node node_modules/typescript/bin/tsc|' build.js
    bun run build.js
  '';
  installPhase = ''
    package="$out/lib/node_modules/@letta-ai/letta-code"
    mkdir -p "$package" "$out/bin"
    cp -a \
      letta.js image-resize.js image-resize-worker.js cursor-worker.js \
      dist assets docs skills vendor package.json node_modules \
      "$package/"
    makeWrapper ${nodejs_22}/bin/node "$out/bin/letta" \
      --add-flags "$package/letta.js" \
      --prefix PATH : ${lib.makeBinPath [ git ripgrep ]}
  '';

  meta = {
    description = "Letta Code is a CLI tool for interacting with stateful Letta agents from the terminal";
    homepage = "https://github.com/letta-ai/letta-code";
    license = lib.licenses.asl20;
    mainProgram = "letta";
    platforms = lib.platforms.unix;
  };
}
