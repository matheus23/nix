{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  bun,
  git,
  ripgrep,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "letta-code";
  version = "0.31.12-pr4237";

  src = fetchFromGitHub {
    owner = "letta-ai";
    repo = "letta-code";
    rev = "2df34493575dfdf8293e8fa9666509af9980a02a";
    hash = "sha256-aOVCOhzONY4GM5PSl8JmRoRsT5GtWraLebdwhz3klzI=";
  };

  # The directory input is unpacked below the standard `source` directory.
  sourceRoot = "source";

  # The repository uses Bun's lockfile, while buildNpmPackage uses npm. Vendor
  # an npm lockfile generated from this exact source revision.
  # Remove the prepare script because it installs Git hooks during the build.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    sed -i '\|"prepare": "node .husky/install.mjs"|d' package.json
  '';

  npmDepsHash = "sha256-2AqFuI5pRaBppMKbobvAHdLUMZ7Kjx4K1hgDU2Y9LVk=";
  npmBuildScript = "build";

  # react@18.2.0 conflicts with @pierre/diffs' peer dep (^18.3.1 || ^19.0.0)
  npmFlags = [ "--legacy-peer-deps" ];

  # Avoid running package scripts while npm inspects the source archive.
  npmPackFlags = [ "--ignore-scripts" ];

  nodejs = nodejs_22;

  nativeBuildInputs = [ bun makeWrapper ];

  # The CLI shells out to git and ripgrep at runtime
  postInstall = ''
    wrapProgram $out/bin/letta \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          ripgrep
        ]
      }
  '';

  meta = {
    description = "Letta Code is a CLI tool for interacting with stateful Letta agents from the terminal";
    homepage = "https://github.com/letta-ai/letta-code";
    license = lib.licenses.asl20;
    mainProgram = "letta";
    platforms = lib.platforms.unix;
  };
}
