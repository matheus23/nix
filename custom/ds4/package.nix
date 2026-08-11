{
  lib,
  stdenv,
  fetchFromGitHub,
  rocmPackages,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ds4";
  version = "unstable-2026-07-28";

  src = fetchFromGitHub {
    owner = "antirez";
    repo = "ds4";
    rev = "54b36ed9ba42da31b24f2d1a5feb075c2475dbb1";
    hash = "sha256-HVw/5BOqZUA79UWbyWSaNGJVhcYjwKNhhN7qefwdaFQ=";
  };

  # ROCm build for Strix Halo (gfx1151 — AMD Ryzen AI MAX / Framework Desktop).
  # The Makefile's strix-halo target compiles ROCm objects with hipcc and
  # links with hipblas + hipblaslt. autoPatchelfHook fixes the RPATH so the
  # runtime libraries are found outside Nix's build sandbox.
  nativeBuildInputs = [
    rocmPackages.hipcc
    autoPatchelfHook
  ];
  rocmInputs = [
    rocmPackages.hipblas
    rocmPackages.hipblas-common
    rocmPackages.hipblaslt
    rocmPackages.clr
    rocmPackages.rocm-device-libs
    rocmPackages.rocwmma
    rocmPackages.hipcub
    rocmPackages.rocprim
  ];

  buildInputs = finalAttrs.rocmInputs;

  # ROCM_CFLAGS must be set as an env var, not a makeFlag — nixpkgs splits
  # makeFlag values on spaces, breaking the multi-flag ROCM_CFLAGS string.
  # hipcc doesn't use nixpkgs' CC wrapper, so include paths, device library
  # path, and link library paths must be passed explicitly.
  makeFlags = [ "NATIVE_CPU_FLAG=" ];

  preBuild = let
    rocmIncludePath = lib.makeSearchPath "include" finalAttrs.rocmInputs;
    rocmLibPath = lib.makeLibraryPath finalAttrs.rocmInputs;
    deviceLibPath = "${rocmPackages.rocm-device-libs}/amdgcn/bitcode";
  in ''
    export CPLUS_INCLUDE_PATH="${rocmIncludePath}:$CPLUS_INCLUDE_PATH"
    export C_INCLUDE_PATH="${rocmIncludePath}:$C_INCLUDE_PATH"
    export LIBRARY_PATH="${rocmLibPath}:$LIBRARY_PATH"
    export ROCM_CFLAGS="-O3 -ffast-math -g -fno-finite-math-only -pthread -D__HIP_PLATFORM_AMD__ -Wno-unused-command-line-argument --offload-arch=gfx1151 --rocm-device-lib-path=${deviceLibPath}"
  '';
  buildFlags = [ "strix-halo" ];

  installPhase = ''
    runHook preInstall
    install -D -m 0555 ds4 ds4-server ds4-bench ds4-eval ds4-agent -t $out/bin
    runHook postInstall
  '';

  meta = {
    description = "DwarfStar — native inference engine for DeepSeek V4 Flash/PRO and GLM 5.2";
    homepage = "https://github.com/antirez/ds4";
    license = lib.licenses.mit;
    mainProgram = "ds4";
    platforms = lib.platforms.linux;
  };
})
