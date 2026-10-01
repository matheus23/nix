{ pkgs, ... }:

let
  # Pin the Gufo source independently of this repository's nixpkgs. Gufo's
  # flake carries the ROCm toolchain it qualifies for Strix Halo.
  gufoFlake = builtins.getFlake "github:gufo-org/gufo/f783fedb9bea2ec7de941f6da4e02f4a4596b29e";
  gufo = gufoFlake.packages.${pkgs.system}.default;
  gufoServe = gufoFlake.lib.${pkgs.system}.mkGufoServe {
    inherit gufo;
    host = "127.0.0.1";
    port = 8422;
    sessions = 1;
    model = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/824f539b2710e5a9e47af4952cf6578cf5ee8932/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
    servedModelName = "qwen3.8-flash-next-q4";
    context = 262144;
    think = "on";
    reasoningEffort = "low";
    preserveThinking = "on";
    cacheDisk = "/var/lib/gufo/cache";
    cacheDiskBytes = 8589934592;
    cacheDiskStagingBytes = 8589934592;
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
