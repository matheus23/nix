{
  lib,
  stdenv,
  nodejs_24,
  fetchFromGitHub,
  fetchurl,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  makeWrapper,
  python3,
  gnumake,
  pkg-config,
}:

let
  version = "0.11.0";

  repoSrc = fetchFromGitHub {
    owner = "nexu-io";
    repo = "open-design";
    rev = "open-design-v${version}";
    hash = "sha256-rSJVKNK0d2n5bS0ZvnF9i2LocEue2VmDYBUtEzXbf+I=";
  };

  # Daemon workspace packages in build order (matches upstream flake.nix)
  daemonWorkspacePaths = [
    "packages/contracts"
    "packages/registry-protocol"
    "packages/agui-adapter"
    "packages/plugin-runtime"
    "packages/sidecar-proto"
    "packages/sidecar"
    "packages/platform"
    "packages/diagnostics"
    "apps/daemon"
  ];

  daemonIncludePaths = [
    "package.json"
    "pnpm-lock.yaml"
    "pnpm-workspace.yaml"
    "tsconfig.json"
    "assets"
    "plugins"
    "skills"
    "design-systems"
    "design-templates"
    "craft"
    "prompt-templates"
  ] ++ daemonWorkspacePaths;

  pnpmDepsIncludePaths = [
    "package.json"
    "pnpm-lock.yaml"
    "pnpm-workspace.yaml"
  ] ++ (map (p: "${p}/package.json") daemonWorkspacePaths);

  # Filtered copy of repoSrc so fetchPnpmDeps matches upstream's hash
  filterSrc =
    includePaths:
    stdenv.mkDerivation {
      pname = "open-design-src";
      inherit version;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (p: ''
          if [ -e "${repoSrc}/${p}" ]; then
            mkdir -p "$out/$(dirname "${p}")"
            cp -r --no-preserve=mode "${repoSrc}/${p}" "$out/${p}"
          fi
        '') includePaths}
        runHook postInstall
      '';
    };

  daemonSrc = filterSrc daemonIncludePaths;
  pnpmDepsSrc = filterSrc pnpmDepsIncludePaths;

  # package.json requires pnpm >=10.33.2 <11
  pnpm = pnpm_10.overrideAttrs (_: rec {
    version = "10.33.2";
    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
      hash = "sha256-envPE9f2zrOUbAOXg3PZm+n94cr8MAC9/tTE95EWdhA=";
    };
  });

  nodejs = nodejs_24;

  pnpmDepsHash = (import ./pnpm-deps.nix).daemonHash;
  pnpmWorkspaceFilters = map (workspacePath: "./${workspacePath}") daemonWorkspacePaths;

  # Next.js static export served by the daemon from apps/web/out
  webWorkspacePaths = [
    "packages/components"
    "packages/contracts"
    "packages/host"
    "packages/platform"
    "packages/sidecar"
    "packages/sidecar-proto"
    "apps/web"
  ];
  webIncludePaths = [
    "package.json"
    "pnpm-lock.yaml"
    "pnpm-workspace.yaml"
    "tsconfig.json"
  ] ++ webWorkspacePaths;
  pnpmDepsIncludePathsWeb = [
    "package.json"
    "pnpm-lock.yaml"
    "pnpm-workspace.yaml"
  ] ++ (map (p: "${p}/package.json") webWorkspacePaths);
  webWorkspaceFilters = map (workspacePath: "./${workspacePath}") webWorkspacePaths;
  dependencyBuildPathsWeb = lib.filter (p: p != "apps/web") webWorkspacePaths;
  webPnpmDepsHash = (import ./pnpm-deps.nix).webHash;

  webPkg = stdenv.mkDerivation (finalAttrs: {
    pname = "open-design-web";
    inherit version;
    src = filterSrc webIncludePaths;

    pnpmWorkspaces = webWorkspaceFilters;

    nativeBuildInputs = [
      nodejs
      pnpm
      pnpmConfigHook
    ];

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs) pname version;
      src = filterSrc pnpmDepsIncludePathsWeb;
      hash = webPnpmDepsHash;
      inherit pnpm;
      pnpmWorkspaces = webWorkspaceFilters;
      fetcherVersion = 3;
    };

    env = {
      NODE_ENV = "production";
      OD_DAEMON_URL = "";
    };

    buildPhase = ''
      runHook preBuild
      for target in ${lib.escapeShellArgs dependencyBuildPathsWeb}; do
        pnpm -C "$target" run --if-present build
      done
      pnpm --filter @open-design/web run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r apps/web/out/. $out/
      runHook postInstall
    '';
  });
in
stdenv.mkDerivation (finalAttrs: {
  pname = "open-design";
  inherit version;
  src = daemonSrc;

  pnpmWorkspaces = pnpmWorkspaceFilters;

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    makeWrapper
    # For building better-sqlite3 from source
    python3
    gnumake
    pkg-config
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version;
    src = pnpmDepsSrc;
    hash = pnpmDepsHash;
    inherit pnpm;
    pnpmWorkspaces = pnpmWorkspaceFilters;
    fetcherVersion = 3;
  };

  env.NODE_ENV = "production";

  buildPhase = ''
    runHook preBuild

    # better-sqlite3 has no Node 24 prebuild
    export npm_config_nodedir=${nodejs}
    export npm_config_build_from_source=true
    export PATH="${nodejs}/lib/node_modules/npm/bin/node-gyp-bin:$PATH"

    bsq_dir=$(find node_modules/.pnpm -mindepth 2 -maxdepth 4 \
      -type d -path '*/better-sqlite3@*/node_modules/better-sqlite3' \
      -print -quit)
    if [ -z "$bsq_dir" ]; then
      echo "ERROR: better-sqlite3 not found under node_modules/.pnpm — pnpm install may have failed" >&2
      exit 1
    fi

    echo "Building better-sqlite3 from source at $bsq_dir"
    ( cd "$bsq_dir" && node-gyp rebuild --release --build-from-source )

    if [ ! -f "$bsq_dir/build/Release/better_sqlite3.node" ]; then
      echo "ERROR: better_sqlite3.node was not produced at $bsq_dir/build/Release/" >&2
      find "$bsq_dir" -name '*.node' -print >&2 || true
      exit 1
    fi

    for target in ${lib.escapeShellArgs daemonWorkspacePaths}; do
      pnpm -C "$target" run --if-present build
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/open-design $out/bin

    # Keep workspace tree for pnpm's relative symlinks
    cp -r . $out/lib/open-design/

    for target in ${lib.escapeShellArgs daemonWorkspacePaths}; do
      if [ "$target" = "apps/daemon" ]; then
        find "$out/lib/open-design/$target" -mindepth 1 -maxdepth 1 \
          ! -name dist \
          ! -name bin \
          ! -name node_modules \
          ! -name package.json \
          -exec rm -rf {} +
      else
        find "$out/lib/open-design/$target" -mindepth 1 -maxdepth 1 \
          ! -name dist \
          ! -name node_modules \
          ! -name package.json \
          -exec rm -rf {} +
      fi
    done

    # Remove dangling symlinks to non-daemon workspaces
    rm -f \
      $out/lib/open-design/node_modules/@open-design/components \
      $out/lib/open-design/node_modules/@open-design/tools-dev \
      $out/lib/open-design/node_modules/@open-design/tools-pack \
      $out/lib/open-design/node_modules/@open-design/tools-release \
      $out/lib/open-design/node_modules/@open-design/tools-serve \
      $out/lib/open-design/node_modules/.bin/tools-dev \
      $out/lib/open-design/node_modules/.bin/tools-pack \
      $out/lib/open-design/node_modules/.bin/tools-release \
      $out/lib/open-design/node_modules/.bin/tools-serve

    mkdir -p $out/lib/open-design/apps/web/out
    cp -r ${webPkg}/. $out/lib/open-design/apps/web/out/

    chmod +x $out/lib/open-design/apps/daemon/dist/cli.js

    makeWrapper ${nodejs}/bin/node $out/bin/od \
      --add-flags $out/lib/open-design/apps/daemon/dist/cli.js \
      --run 'export OD_DATA_DIR="''${OD_DATA_DIR:-$HOME/.od}"' \
      --set NODE_ENV production
    runHook postInstall
  '';

  passthru = {
    inherit nodejs;
    pnpmDeps = finalAttrs.pnpmDeps;
  };

  meta = with lib; {
    description = "Open Design — local-first, open-source design agent daemon (od CLI)";
    homepage = "https://github.com/nexu-io/open-design";
    license = licenses.asl20;
    mainProgram = "od";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
