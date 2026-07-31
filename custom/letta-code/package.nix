{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  git,
  ripgrep,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "letta-code";
  version = "0.29.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/@letta-ai/letta-code/-/letta-code-${version}.tgz";
    hash = "sha256-tssDQKdWs/v5bSkIjYtf2dIQcEFv/CCti9Sp7w/ewf8=";
  };

  # npm tarballs extract to a `package/` directory
  sourceRoot = "package";

  # The published tarball doesn't include a package-lock.json. Vendor one
  # (generated with `npm install --package-lock-only --legacy-peer-deps`).
  # Also remove the `prepare` script (runs `node .husky/install.mjs`) since
  # .husky/ isn't shipped in the tarball — it breaks `npm pack --dry-run`.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    sed -i '\|"prepare": "node .husky/install.mjs"|d' package.json
  '';

  npmDepsHash = "sha256-4XfHBKQ6VHdR0nqMYHdYJVcegcYRTrD3+j1WDzLPIUg=";

  # The published tarball is already built (letta.js + dist/ are included);
  # we only need `npm ci` for runtime dependencies (sharp, node-pty, etc.)
  dontNpmBuild = true;

  # react@18.2.0 conflicts with @pierre/diffs' peer dep (^18.3.1 || ^19.0.0)
  npmFlags = [ "--legacy-peer-deps" ];

  # The published tarball's `prepare` script runs `node .husky/install.mjs`,
  # but .husky/ isn't shipped. Skip scripts during `npm pack --dry-run`.
  npmPackFlags = [ "--ignore-scripts" ];

  nodejs = nodejs_22;

  nativeBuildInputs = [ makeWrapper ];

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
