# Tracy 0.13.1 requires wayland >= 1.24 (for wl_display_dispatch_timeout),
# which is not yet in nixos-25.11 stable.  Pass unstable pkgs to get it.
{
  pkgs ? import <nixpkgs> { },
  unstable ? import <nixos-unstable> { },
}:

with pkgs;

let
  withGtkFileSelector = false;
  withWayland = false;

  # CPM dependencies that have no system pkg-config fallback must be
  # pre-fetched and injected via SOURCE_DIR so the sandbox build succeeds.

  # Tracy 0.13.1 requires capstone 6.x (CS_ARCH_AARCH64 API), but nixpkgs
  # 25.11 only has capstone 5.x.  Let tracy build its own bundled capstone 6.
  cpmCapstone = fetchFromGitHub {
    owner = "capstone-engine";
    repo = "capstone";
    rev = "6.0.0-Alpha5";
    hash = "sha256-18PTj4hvBw8RTgzaFGeaDbBfkxmotxSoGtprIjcEuVg=";
  };
  cpmZstd = fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "v1.5.7";
    hash = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
  cpmImgui = fetchFromGitHub {
    owner = "ocornut";
    repo = "imgui";
    rev = "v1.92.5-docking";
    hash = "sha256-/jVT7+874LCeSF/pdNVTFoSOfRisSqxCJnt5/SGCXPQ=";
  };
  cpmNfd = fetchFromGitHub {
    owner = "btzy";
    repo = "nativefiledialog-extended";
    rev = "v1.2.1";
    hash = "sha256-GwT42lMZAAKSJpUJE6MYOpSLKUD5o9nSe9lcsoeXgJY=";
  };
  cpmPPQSort = fetchFromGitHub {
    owner = "GabTux";
    repo = "PPQSort";
    rev = "v1.0.6";
    hash = "sha256-HgM+p2QGd9C8A8l/VaEB+cLFDrY2HU6mmXyTNh7xd0A=";
  };
  cpmJson = fetchFromGitHub {
    owner = "nlohmann";
    repo = "json";
    rev = "v3.12.0";
    hash = "sha256-cECvDOLxgX7Q9R3IE86Hj9JJUxraDQvhoyPDF03B2CY=";
  };
  cpmMd4c = fetchFromGitHub {
    owner = "mity";
    repo = "md4c";
    rev = "release-0.5.2";
    hash = "sha256-2/wi7nJugR8X2J9FjXJF1UDnbsozGoO7iR295/KSJng=";
  };
  cpmBase64 = fetchFromGitHub {
    owner = "aklomp";
    repo = "base64";
    rev = "v0.5.2";
    hash = "sha256-dIaNfQ/znpAdg0/vhVNTfoaG7c8eFrdDTI0QDHcghXU=";
  };
  cpmTidy = fetchFromGitHub {
    owner = "htacg";
    repo = "tidy-html5";
    rev = "5.8.0";
    hash = "sha256-vzVWQodwzi3GvC9IcSQniYBsbkJV20iZanF33A0Gpe0=";
  };
  # usearch requires fp16 and simsimd git submodules
  cpmUsearch = fetchgit {
    url = "https://github.com/unum-cloud/usearch";
    rev = "v2.21.3";
    fetchSubmodules = true;
    hash = "sha256-7IylunAkVNceKSXzCkcpp/kAsI3XoqniHe10u3teUVA=";
  };
  # Transitive dep pulled in by PPQSort's own CMakeLists.txt
  cpmPackageProject = fetchFromGitHub {
    owner = "TheLartians";
    repo = "PackageProject.cmake";
    rev = "v1.11.1";
    hash = "sha256-E7WZSYDlss5bidbiWL1uX41Oh6JxBRtfhYsFU19kzIw=";
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = if withWayland then "tracy-wayland" else "tracy-glfw";
  version = "0.13.1";

  src = fetchFromGitHub {
    owner = "wolfpld";
    repo = "tracy";
    rev = "v${finalAttrs.version}";
    hash = "sha256-D4aQ5kSfWH9qEUaithR0W/E5pN5on0n9YoBHeMggMSE=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wayland-scanner ]
  ++ lib.optionals stdenv.cc.isClang [ stdenv.cc.cc.libllvm ];

  buildInputs = [
    freetype
    tbb
    curl
    pugixml
  ]
  ++ lib.optionals (stdenv.hostPlatform.isLinux && withGtkFileSelector) [ gtk3 ]
  ++ lib.optionals (stdenv.hostPlatform.isLinux && !withGtkFileSelector) [ dbus ]
  ++ lib.optionals (stdenv.hostPlatform.isLinux && withWayland) [
    libglvnd
    libxkbcommon
    unstable.wayland # 1.24+ required for wl_display_dispatch_timeout
    wayland-protocols
    extra-cmake-modules
  ]
  ++ lib.optionals (stdenv.hostPlatform.isDarwin || (stdenv.hostPlatform.isLinux && !withWayland)) [
    glfw
    xorg.libX11
    xorg.libXrandr
    xorg.libXcursor
    xorg.libXi
    libGL
  ];

  cmakeFlags = [
    "-DDOWNLOAD_FREETYPE=off"
    "-DDOWNLOAD_LIBCURL=off"
    "-DDOWNLOAD_PUGIXML=off"
    "-DTRACY_STATIC=off"
  ]
  ++ lib.optional (stdenv.hostPlatform.isLinux && withGtkFileSelector) "-DGTK_FILESELECTOR=ON"
  ++ lib.optional (stdenv.hostPlatform.isLinux && !withWayland) "-DLEGACY=on";

  env.NIX_CFLAGS_COMPILE = toString (
    [ ]
    ++ lib.optional stdenv.hostPlatform.isLinux "-ltbb"
    ++ lib.optional (stdenv.cc.isClang && stdenv.hostPlatform.isDarwin) "-fno-lto"
  );

  env.LD_LIBRARY_PATH = lib.optionalString (stdenv.hostPlatform.isLinux && !withWayland)
    (lib.makeLibraryPath [ libGL xorg.libX11 ]);

  dontUseCmakeBuildDir = true;

  postPatch = ''
        # imgui, PPQSort, and tidy are patched by the tracy build system, so they
        # need writable copies — the Nix store paths are read-only.
        cp -r --no-preserve=mode ${cpmImgui}   imgui-src
        cp -r --no-preserve=mode ${cpmPPQSort} ppqsort-src
        cp -r --no-preserve=mode ${cpmTidy}    tidy-src
        # Replace PPQSort's bundled CPM.cmake with tracy's to avoid its self-download
        cp cmake/CPM.cmake ppqsort-src/cmake/CPM.cmake
        # Apply imgui, PPQSort and tidy patches ourselves now so all 5 sub-builds
        # share one pre-patched copy; PATCHES blocks are stripped from vendor.cmake below.
        patch -d imgui-src   -p1 < cmake/imgui-emscripten.patch
        patch -d imgui-src   -p1 < cmake/imgui-loader.patch
        patch -d ppqsort-src -p1 < cmake/ppqsort-nodebug.patch
        patch -d tidy-src    -p1 < cmake/tidy-cmake.patch
        imgui_abs="$(pwd)/imgui-src"
        ppqsort_abs="$(pwd)/ppqsort-src"
        tidy_abs="$(pwd)/tidy-src"
        wp_protocols_dir="${wayland-protocols}/share/wayland-protocols"

        # Redirect all CPM GITHUB_REPOSITORY fetches to pre-fetched Nix store paths,
        # and strip PATCHES blocks for packages we've already patched above.
        python3 - "$imgui_abs" "$ppqsort_abs" "$tidy_abs" "$wp_protocols_dir" <<'EOF'
    import re, pathlib, sys

    imgui_abs, ppqsort_abs, tidy_abs, wp_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    # Patch tracy's vendor.cmake
    f = pathlib.Path("cmake/vendor.cmake")
    s = f.read_text()

    replacements = [
        (r'GITHUB_REPOSITORY capstone-engine/capstone\s*\n\s*GIT_TAG 6\.0\.0-Alpha5',
         'SOURCE_DIR ${cpmCapstone}'),
        (r'GITHUB_REPOSITORY facebook/zstd\s*\n\s*GIT_TAG v1\.5\.7',
         'SOURCE_DIR ${cpmZstd}'),
        (r'GITHUB_REPOSITORY ocornut/imgui\s*\n\s*GIT_TAG v1\.92\.5-docking',
         f'SOURCE_DIR {imgui_abs}'),
        (r'GITHUB_REPOSITORY btzy/nativefiledialog-extended\s*\n\s*GIT_TAG v1\.2\.1',
         'SOURCE_DIR ${cpmNfd}'),
        (r'GITHUB_REPOSITORY GabTux/PPQSort\s*\n\s*VERSION 1\.0\.6',
         f'SOURCE_DIR {ppqsort_abs}'),
        (r'GITHUB_REPOSITORY nlohmann/json\s*\n\s*GIT_TAG v3\.12\.0',
         'SOURCE_DIR ${cpmJson}'),
        (r'GITHUB_REPOSITORY mity/md4c\s*\n\s*GIT_TAG release-0\.5\.2',
         'SOURCE_DIR ${cpmMd4c}'),
        (r'GITHUB_REPOSITORY aklomp/base64\s*\n\s*GIT_TAG v0\.5\.2',
         'SOURCE_DIR ${cpmBase64}'),
        (r'GITHUB_REPOSITORY htacg/tidy-html5\s*\n\s*GIT_TAG 5\.8\.0',
         f'SOURCE_DIR {tidy_abs}'),
        (r'GITHUB_REPOSITORY unum-cloud/usearch\s*\n\s*GIT_TAG v2\.21\.3',
         'SOURCE_DIR ${cpmUsearch}'),
    ]

    for pattern, repl in replacements:
        s, n = re.subn(pattern, repl, s)
        if n == 0:
            raise RuntimeError(f"Pattern not found: {pattern}")

    f.write_text(s)
    print("vendor.cmake patched successfully")

    # Strip PATCHES blocks for packages we pre-patched above so CPM doesn't
    # try to re-apply them to the already-modified writable copies.
    s2 = f.read_text()
    patches_blocks = [
        r'\s*PATCHES\s*\n\s*"\$\{CMAKE_CURRENT_LIST_DIR\}/imgui-emscripten\.patch"\s*\n\s*"\$\{CMAKE_CURRENT_LIST_DIR\}/imgui-loader\.patch"',
        r'\s*PATCHES\s*\n\s*"\$\{CMAKE_CURRENT_LIST_DIR\}/ppqsort-nodebug\.patch"',
        r'\s*PATCHES\s*\n\s*"\$\{CMAKE_CURRENT_LIST_DIR\}/tidy-cmake\.patch"',
    ]
    for pb in patches_blocks:
        s2, n = re.subn(pb, "", s2)
        if n == 0:
            raise RuntimeError(f"PATCHES block not found: {pb}")
    f.write_text(s2)
    print("vendor.cmake PATCHES blocks stripped")

    # Patch PPQSort's own CMakeLists.txt to redirect its transitive PackageProject dep.
    # NAME is required when using SOURCE_DIR without a URL/GIT_REPOSITORY.
    pp = pathlib.Path(ppqsort_abs) / "CMakeLists.txt"
    ps = pp.read_text()
    ps, n = re.subn(
        r'CPMAddPackage\("gh:TheLartians/PackageProject\.cmake@1\.11\.1"\)',
        'CPMAddPackage(NAME PackageProject.cmake SOURCE_DIR ${cpmPackageProject})',
        ps
    )
    if n == 0:
        raise RuntimeError("PPQSort PackageProject.cmake pattern not found")
    pp.write_text(ps)
    print("PPQSort CMakeLists.txt patched successfully")

    # Patch profiler/CMakeLists.txt: replace CPM wayland-protocols fetch with
    # a set() pointing to the nixpkgs wayland-protocols store path.
    pf = pathlib.Path("profiler/CMakeLists.txt")
    ps2 = pf.read_text()
    ps2, n = re.subn(
        r'CPMAddPackage\(\s*\n\s*NAME wayland-protocols\s*\n\s*GIT_REPOSITORY [^\n]+\s*\n\s*GIT_TAG [^\n]+\s*\n\s*DOWNLOAD_ONLY YES\s*\n\s*\)',
        f'set(wayland-protocols_SOURCE_DIR "{wp_dir}")',
        ps2
    )
    if n == 0:
        raise RuntimeError("profiler wayland-protocols CPMAddPackage pattern not found")
    pf.write_text(ps2)
    print("profiler/CMakeLists.txt wayland-protocols patched successfully")
    EOF
  '';

  postConfigure = ''
    cmake -B capture/build  -S capture  $cmakeFlags
    cmake -B csvexport/build -S csvexport $cmakeFlags
    cmake -B import/build   -S import   $cmakeFlags
    cmake -B profiler/build  -S profiler  $cmakeFlags
    cmake -B update/build   -S update   $cmakeFlags
  '';

  postBuild = ''
    ninja -C capture/build
    ninja -C csvexport/build
    ninja -C import/build
    ninja -C profiler/build
    ninja -C update/build
  '';

  postInstall = ''
    install -D -m 0555 capture/build/tracy-capture -t $out/bin
    install -D -m 0555 csvexport/build/tracy-csvexport $out/bin
    install -D -m 0555 import/build/{tracy-import-chrome,tracy-import-fuchsia} -t $out/bin
    install -D -m 0555 profiler/build/tracy-profiler $out/bin/tracy
    install -D -m 0555 update/build/tracy-update -t $out/bin
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace extra/desktop/tracy.desktop \
      --replace-fail Exec=/usr/bin/tracy Exec=tracy

    install -D -m 0444 extra/desktop/application-tracy.xml $out/share/mime/packages/application-tracy.xml
    install -D -m 0444 extra/desktop/tracy.desktop $out/share/applications/tracy.desktop
    install -D -m 0444 icon/application-tracy.svg $out/share/icons/hicolor/scalable/apps/application-tracy.svg
    install -D -m 0444 icon/icon.png $out/share/icons/hicolor/256x256/apps/tracy.png
    install -D -m 0444 icon/icon.svg $out/share/icons/hicolor/scalable/apps/tracy.svg
  '';

  meta = with lib; {
    description = "Real time, nanosecond resolution, remote telemetry frame profiler for games and other applications";
    homepage = "https://github.com/wolfpld/tracy";
    license = licenses.bsd3;
    mainProgram = "tracy";
    maintainers = with maintainers; [
      mpickering
      nagisa
    ];
    platforms = platforms.linux ++ optionals (!withWayland) platforms.darwin;
  };
})
