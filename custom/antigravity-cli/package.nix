# Antigravity CLI (`agy`), Google's terminal agent client. Upstream ships one
# prebuilt Go binary per platform and hands it out through a bootstrapper that
# writes it to ~/.local/bin and then rewrites it on a timer. That self-updater
# is the reason this is a local derivation rather than `unstable.antigravity-cli`:
# nixpkgs carries the same thing under pkgs/by-name/an, but it lags upstream and
# leaves the updater switched on, so the binary keeps trying to write into the
# read-only store.
#
# Differences from nixpkgs' antigravity-cli:
#   - pinned here, so bumps are explicit (see "To bump" at the bottom);
#   - wrapped with AGY_CLI_DISABLE_AUTO_UPDATE, the opt-out upstream documents,
#     which stops the updater spawning and stranding update.lock in ~/.gemini.
#
# The command sandbox needs read grants for /nix/store to work at all here; that
# lives in home-manager/antigravity-cli.nix, not in here.
#
# To bump:
#   1. Read `version` and the trailing path segment (the build id) from the
#      manifest the official installer uses:
#        curl -fsSL https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
#   2. Recompute both hashes:
#        nix hash convert --hash-algo sha256 --to sri \
#          "$(curl -fsSL <url> | sha256sum | cut -d' ' -f1)"
#      for linux-x64/cli_linux_x64.tar.gz and linux-arm/cli_linux_arm64.tar.gz
#      under https://storage.googleapis.com/antigravity-public/antigravity-cli/<version>-<buildId>/
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:
let
  pname = "antigravity-cli";
  version = "1.5.17";
  buildId = "4823843970351104";

  wholeVersion = "${version}-${buildId}";
  baseUrl = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}";

  throwSystem = throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}";

  sourceData = {
    x86_64-linux = fetchurl {
      url = "${baseUrl}/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha256-YwS09ZKul+WSMc+xs2XuKcFVdQyaiB8MyO/l9SgQd88=";
    };
    aarch64-linux = fetchurl {
      url = "${baseUrl}/linux-arm/cli_linux_arm64.tar.gz";
      hash = "sha256-1tK4hJPm4ChU2keLIVzR3Zj9jPmFtr43gp2srepP/Ac=";
    };
  };

  meta = {
    description = "Terminal agent client for Google Antigravity";
    homepage = "https://antigravity.google/product/antigravity-cli";
    changelog = "https://antigravity.google/docs/changelog?tab=cli";
    license = lib.licenses.unfree;
    mainProgram = "agy";
    maintainers = with lib.maintainers; [ ];
    platforms = lib.attrNames sourceData;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit
    meta
    pname
    version
    ;

  __structuredAttrs = true;
  strictDeps = true;

  src = sourceData.${stdenvNoCC.hostPlatform.system} or throwSystem;
  sourceRoot = ".";

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The archive member is `antigravity`; the command is `agy`.
    install -Dm755 antigravity $out/bin/agy

    runHook postInstall
  '';

  # postFixup and not installPhase: autoPatchelfHook patches in fixupPhase, which
  # runs after installPhase, so wrapping any earlier puts the wrapper in front of
  # the binary the patcher still has to rewrite.
  postFixup = ''
    wrapProgram $out/bin/agy \
      --set AGY_CLI_DISABLE_AUTO_UPDATE true
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  passthru = {
    inherit wholeVersion;
  };
})
