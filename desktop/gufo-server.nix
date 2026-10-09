{ pkgs, ... }:

let
  # Pin the Gufo source independently of this repository's nixpkgs. Gufo's
  # flake carries the ROCm toolchain it qualifies for Strix Halo.
  gufoFlake = builtins.getFlake "github:gufo-org/gufo/e03bb9115abc6be469927fed76fddaf1ef0682b3";
  # Local patch: Gufo hard-codes 16 images per chat request. Agent clients
  # re-send retained screenshots every turn, so a low cap fails every later
  # request while the context still has room and compaction never runs. The
  # patch raises the count and image-byte budget to 128 images; the
  # maxRequestBytes below is the HTTP-body side of the same change.
  gufo = gufoFlake.packages.${pkgs.system}.default.overrideAttrs (
    _final: prev: { patches = (prev.patches or [ ]) ++ [ ./gufo-image-limit.patch ]; }
  );
  gufoServe = gufoFlake.lib.${pkgs.system}.mkGufoServe {
    inherit gufo;
    host = "127.0.0.1";
    port = 8422;
    sessions = 2;
    model = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/824f539b2710e5a9e47af4952cf6578cf5ee8932/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
    servedModelName = "qwen3.8-flash-next-q4";
    context = 262144;
    speculative = "mtp";
    mtpModel = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/824f539b2710e5a9e47af4952cf6578cf5ee8932/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
    draftTokens = 7;
    minDraftTokens = 1;
    think = "on";
    reasoningEffort = "high";
    preserveThinking = "on";
    cacheDisk = "/var/lib/gufo/cache";
    cacheDiskBytes = 8589934592;
    cacheDiskStagingBytes = 8589934592;
    # Base64 payloads for the patched 128-image request budget (256 MiB
    # decoded) do not fit the 8 MiB default HTTP body limit.
    maxRequestBytes = 512 * 1024 * 1024;
    extraArgs = [ "--log-progress" ];
  };
in
{
  # The service is deliberately not enabled by default: the existing
  # llama-server uses the same GPU. Start gufo-server manually for comparison.
  environment.systemPackages = [ gufo ];

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
