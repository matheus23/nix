{
  inputs,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  gufoFlake = inputs.gufo;
  # Raise decoded-image budget to 256 MiB for agent screenshot turns
  gufo = gufoFlake.packages.${system}.default.overrideAttrs (
    _final: prev: { patches = (prev.patches or [ ]) ++ [ ./gufo-image-limit.patch ]; }
  );
  gufoServe = gufoFlake.lib.${system}.mkGufoServe {
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
    maxRequestBytes = 512 * 1024 * 1024; # base64 overhead for 256 MiB image budget
    extraArgs = [ "--log-progress" ];
  };

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
  environment.systemPackages = [
    gufo
    downloadModels
  ];

  # Started manually; shares the GPU with llama-server
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
