{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kache";
  version = "0.14.2";

  src = fetchurl {
    url = "https://github.com/kunobi-ninja/kache/releases/download/v${finalAttrs.version}/kache-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-jMSj6xYhJocywDCzx0u/MGb66QXk7Q8n4yrsqDaz6Vo=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 kache "$out/bin/kache"

    runHook postInstall
  '';

  meta = {
    description = "Zero-copy, content-addressed build cache";
    homepage = "https://kunobi.ninja/docs/kache";
    license = lib.licenses.asl20;
    mainProgram = "kache";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
