{
  lib,
  llama-cpp,
  fetchzip,
}:

# Upstream llama.cpp release with `inkling2_loop` support.
# Bump: pick a `b*` tag from github.com/ggml-org/llama.cpp/releases and update `version` + `hash`:
#   nix-prefetch-url --unpack https://github.com/ggml-org/llama.cpp/archive/refs/tags/<tag>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
(llama-cpp.override {
  vulkanSupport = true;
  rocmSupport = false;
  blasSupport = false;
}).overrideAttrs
  (
    finalAttrs: prev: {
      version = "12651";

      src = fetchzip {
        url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/b${finalAttrs.version}.tar.gz";
        hash = "sha256-GNdA6CFxrkFNSocjHhZT2ML53WkdvTSQBMieitPR1ts=";
      };

      # Upstream removed tools/ui, so drop nixpkgs' npm UI build
      npmDeps = null;
      nativeBuildInputs = builtins.filter (
        p: !(lib.isDerivation p && p.pname or "" == "npm-config-hook")
      ) prev.nativeBuildInputs;

      preConfigure = ''
        printf '%s\n' ${lib.escapeShellArg "b${finalAttrs.version}"} > COMMIT
      '';

      cmakeFlags = prev.cmakeFlags ++ [
        "-DLLAMA_BUILD_UI=OFF"
        "-DLLAMA_USE_PREBUILT_UI=OFF"
      ];
    }
  )
