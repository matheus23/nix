{ pkgs, ... }:

let
  # Pin the Gufo source independently of this repository's nixpkgs. Gufo's
  # flake carries the ROCm toolchain it qualifies for Strix Halo.
  gufoFlake = builtins.getFlake "github:gufo-org/gufo/2845939b2a7d61243d407c8816c6d42652512e50"; # v0.34.0
  # Agent clients re-send retained screenshots on every turn. Keep a 256 MiB
  # decoded-image budget; maxRequestBytes below covers the base64 HTTP body.
  # Remove the patch when upstream allows configuring this budget.
  gufo = gufoFlake.packages.${pkgs.system}.default.overrideAttrs (
    _final: prev: { patches = (prev.patches or [ ]) ++ [ ./gufo-image-limit.patch ]; }
  );
  gufoServe = gufoFlake.lib.${pkgs.system}.mkGufoServe {
    inherit gufo;
    host = "127.0.0.1";
    port = 8422;
    sessions = 2;
    model = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/f5d175de2cf7f720d45d6064019a81fcf056e986/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
    servedModelName = "qwen3.8-flash-next-q4";
    context = 262144;
    speculative = "mtp";
    mtpModel = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/f5d175de2cf7f720d45d6064019a81fcf056e986/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
    think = "on";
    reasoningEffort = "high";
    preserveThinking = "on";
    cacheDisk = "/var/lib/gufo/cache";
    cacheDiskBytes = 8589934592;
    cacheDiskStagingBytes = 8589934592;
    # Base64 payloads for the patched 256 MiB decoded-image budget do not fit
    # the default HTTP body limit.
    maxRequestBytes = 512 * 1024 * 1024;
    extraArgs = [ "--log-progress" ];
  };

  # llama-server no longer serves Qwen3.8-Flash-Next, so the fetcher for its
  # GGUF shards lives here with the engine that actually loads them.
  downloadModels = pkgs.writeShellApplication {
    name = "download-qwen38-flash-next-model";
    runtimeInputs = with pkgs; [
      aria2
      coreutils
    ];
    text = builtins.readFile ../scripts/download-qwen38-llama-models.sh;
  };
in
{
  # The service is deliberately not enabled by default: llama-server uses the
  # same GPU. Start gufo-server manually for comparison.
  environment.systemPackages = [
    gufo
    downloadModels
  ];

  systemd.services.gufo-server = {
    description = "Gufo Strix Halo inference server";
    after = [ "network.target" ];
    conflicts = [ "llama-server.service" ];
    serviceConfig = {
      Type = "simple";
      User = "philipp";
      Group = "users";
      SupplementaryGroups = [ "render" "video" ];
      StateDirectory = "gufo";
      UMask = "0077";
      Environment = [
        "HOME=/home/philipp"
        "GPU_MAX_HW_QUEUES=2"
      ];
      ExecStart = gufoServe;
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 1800;
      TimeoutStopSec = 120;
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 1048576;
    };
  };
}
