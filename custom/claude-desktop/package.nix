{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  libGL,
  libsecret,
  libseccomp,
  libcap_ng,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxtst,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  xdg-utils,
  zlib,
  stdenv,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  version = "5.11492.5";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${finalAttrs.version}_amd64.deb";
    hash = "sha256-uWIIsgfkULdA99vjBPYHf+2A5/PTfd1UWZHE6CAVZM8=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libsecret
    libseccomp
    libcap_ng
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxtst
    nspr
    nss
    pango
    pipewire
    systemd
    zlib
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar --no-same-permissions --no-same-owner -xf -
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin" "$out/share"
    cp -a usr/lib/claude-desktop "$out/lib/"
    cp -a usr/share/applications usr/share/icons "$out/share/"
    install -Dm644 usr/lib/claude-desktop/resources/linux-mime/com.anthropic.Claude.xml \
      "$out/share/mime/packages/com.anthropic.Claude.xml"

    # Use Chromium's user-namespace sandbox; a setuid helper cannot run from
    # the Nix store. This does not disable the renderer sandbox.
    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libGL
          libsecret
          libuuid
          libxtst
          pipewire
        ]
      } \
      --add-flags "--disable-setuid-sandbox"

    substituteInPlace "$out/share/applications/com.anthropic.Claude.desktop" \
      --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop" \
      --replace-fail "Icon=claude-desktop" \
        "Icon=$out/share/icons/hicolor/256x256/apps/claude-desktop.png"
    runHook postInstall
  '';

  meta = {
    description = "Official Claude Desktop Linux beta";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
