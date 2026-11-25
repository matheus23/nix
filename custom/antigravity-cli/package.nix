# Prebuilt Antigravity CLI (`agy`) with auto-update disabled.
# Bump: read `version` + buildId from
#   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
# then recompute both tarball SRI hashes.
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

  # Wrap after autoPatchelfHook runs in fixupPhase
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
