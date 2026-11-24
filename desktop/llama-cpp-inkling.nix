{
  lib,
  llama-cpp,
  fetchzip,
}:

# llama.cpp pinned to an upstream release that understands the `inkling2_loop`
# architecture, including the NVFP4 scale fix that landed with it. Unlike
# nixpkgs' `llama-cpp` this build carries no local patches: the Qwen3.8
# patches it used to carry stream `per_layer_token_embd`, a tensor Inkling 2
# Mini does not have.
#
# Bump by taking the newest `b*` tag from
# https://github.com/ggml-org/llama.cpp/releases , then:
#   nix-prefetch-url --unpack https://github.com/ggml-org/llama.cpp/archive/refs/tags/<tag>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
# and updating `version` and `hash` below (the source URL is derived from `version`).
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

      # Upstream removed tools/ui, so nixpkgs' npm setup and the `npm run build`
      # that feeds it no longer have a home. Leaving them in place makes the
      # fetchNpmDeps derivation (a build input even though nothing consumes it)
      # fail on `pushd tools/ui`. The server serves a prebuilt UI from --path
      # instead; see llama-server.nix.
      npmDeps = null;
      nativeBuildInputs = builtins.filter (
        p: !(lib.isDerivation p && p.pname or "" == "npm-config-hook")
      ) prev.nativeBuildInputs;

      # nixpkgs' preConfigure builds the UI off COMMIT; keep only the commit id,
      # which `-DLLAMA_BUILD_COMMIT` (added by the same phase) reads.
      preConfigure = ''
        printf '%s\n' ${lib.escapeShellArg "b${finalAttrs.version}"} > COMMIT
      '';

      cmakeFlags = prev.cmakeFlags ++ [
        "-DLLAMA_BUILD_UI=OFF"
        # Would otherwise fetch the UI tarball from the HF bucket at runtime.
        "-DLLAMA_USE_PREBUILT_UI=OFF"
      ];
    }
  )
