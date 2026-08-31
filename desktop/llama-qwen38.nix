{
  lib,
  pkgs,
  ...
}:

let
  llamaCppQwen4Exp =
    (pkgs.llama-cpp.override {
      vulkanSupport = true;
      rocmSupport = false;
      blasSupport = false;
    }).overrideAttrs
      (old: {
        version = "0-unstable-2026-08-27-qwen4exp";
        src = pkgs.fetchzip {
          url = "https://github.com/unslothai/llama.cpp/archive/6c5afc86ae84448ae4d744e357017e2c490ad9c3.tar.gz";
          hash = "sha256-6qMeFRuSn/5CEU/AN6sArXJzQfC4rhSlPXuHGHmMGwU=";
        };
        # Avoid prefaulting the full model alongside its Vulkan copy, and mark
        # the host-side PLE range as random-access. Remove this when upstream
        # issue #27766 gains equivalent per-tensor mmap policy.
        patches = (old.patches or [ ]) ++ [ ./llama-qwen38-random-ple.patch ];
        buildInputs = old.buildInputs ++ [ pkgs.spirv-headers ];
        preConfigure = ''
          printf '%s\n' 6c5afc86ae84448ae4d744e357017e2c490ad9c3 > COMMIT
        ''
        + old.preConfigure;
        cmakeFlags =
          builtins.filter (flag: !(lib.hasPrefix "-DLLAMA_BUILD_NUMBER" flag)) old.cmakeFlags
          ++ [
            "-DLLAMA_BUILD_NUMBER=0"
            "-DLLAMA_BUILD_UI=OFF"
            "-DLLAMA_USE_PREBUILT_UI=OFF"
          ];
      });

  modelDir = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/824f539b2710e5a9e47af4952cf6578cf5ee8932";
  target = "${modelDir}/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
  mmproj = "${modelDir}/mmproj-F16.gguf";
  llama32Target = "/home/philipp/.lmstudio/models/unsloth/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf";

  # Keep the UI separate from the llama-server binary so the server build does
  # not need npm. The fixed-output hash pins the prebuilt assets from the
  # llama.cpp UI bucket.
  llamaUi = pkgs.fetchzip {
    name = "llama-ui";
    url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/dist.tar.gz?download=true";
    hash = "sha256-7xNWI6FJH/nuSRCWapn1QptnhTVNlVf9i2hfEg4zzvw=";
    stripRoot = false;
  };

  downloadModels = pkgs.writeShellApplication {
    name = "download-qwen38-flash-next-model";
    runtimeInputs = with pkgs; [
      aria2
      coreutils
    ];
    text = builtins.readFile ../scripts/download-qwen38-llama-models.sh;
  };

  enterPerformanceProfile = pkgs.writeShellScript "llama-qwen38-enter-performance" ''
    previous="$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)"
    printf '%s\n' "$previous" > /run/llama-qwen38/previous-power-profile
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
  '';

  restorePowerProfile = pkgs.writeShellScript "llama-qwen38-restore-power" ''
    profile_file=/run/llama-qwen38/previous-power-profile
    if [[ -s "$profile_file" ]]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$(<"$profile_file")"
    fi
  '';
in
{
  environment.systemPackages = [
    downloadModels
    llamaCppQwen4Exp
  ];

  # Qwen3.8-Flash-Next is the experimental Qwen4 architecture. Its native MTP
  # head is not supported by llama.cpp yet, so this service deliberately uses
  # target-only decoding until that path has a correctness-tested implementation.
  systemd.services.llama-qwen38 = {
    description = "Qwen3.8 Flash Next Q4-XL (experimental Qwen4 architecture)";
    conflicts = [
      "ds4-server.service"
    ];
    wantedBy = [ ];
    unitConfig.ConditionPathExists = [ "${modelDir}/.verified" ];
    serviceConfig = {
      Type = "simple";
      User = "philipp";
      Group = "users";
      SupplementaryGroups = [
        "render"
        "video"
      ];
      RuntimeDirectory = "llama-qwen38";
      Environment = [
        "HOME=/home/philipp"
        "GGML_VK_VISIBLE_DEVICES=0"
      ];
      ExecStartPre = "+${enterPerformanceProfile}";
      ExecStart = lib.escapeShellArgs [
        "${llamaCppQwen4Exp}/bin/llama-server"
        "--model"
        target
        "--mmproj"
        mmproj
        "--alias"
        "qwen3.8-flash-next-q4"
        "--host"
        "127.0.0.1"
        "--port"
        "8422"
        "--webui"
        "--path"
        llamaUi
        "--ctx-size"
        "524288"
        "--fit"
        "off"
        "--n-gpu-layers"
        "999999"
        "--parallel"
        "2"
        "--threads"
        "12"
        "--batch-size"
        "512"
        "--ubatch-size"
        "256"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "f16"
        "--cache-type-v"
        "f16"
        # The 51B n-gram embedding is a sparse lookup table. Keep it host-side
        # and mmap-backed instead of spending most of unified memory on it.
        "--override-tensor"
        "per_layer_token_embd=CPU"
        "--load-mode"
        "mmap"
        "--jinja"
        "--reasoning-preserve"
        "--reasoning-effort"
        "low"
        "--temp"
        "1.0"
        "--top-p"
        "0.95"
        "--top-k"
        "20"
        "--min-p"
        "0.0"
        "--metrics"
      ];
      ExecStopPost = "+${restorePowerProfile}";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 1800;
      TimeoutStopSec = 120;
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 1048576;
    };
  };

  systemd.services.llama-3-2 = {
    description = "Llama 3.2 1B Instruct Q4_K_M";
    wantedBy = [ ];
    unitConfig.ConditionPathExists = [ llama32Target ];
    serviceConfig = {
      Type = "simple";
      User = "philipp";
      Group = "users";
      SupplementaryGroups = [
        "render"
        "video"
      ];
      Environment = [
        "HOME=/home/philipp"
        "GGML_VK_VISIBLE_DEVICES=0"
      ];
      ExecStart = lib.escapeShellArgs [
        "${llamaCppQwen4Exp}/bin/llama-server"
        "--model"
        llama32Target
        "--alias"
        "llama-3.2-1b-instruct-q4"
        "--host"
        "127.0.0.1"
        "--port"
        "8423"
        "--ctx-size"
        "131072"
        "--fit"
        "off"
        "--n-gpu-layers"
        "999999"
        "--parallel"
        "1"
        "--threads"
        "12"
        "--batch-size"
        "512"
        "--ubatch-size"
        "256"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "f16"
        "--cache-type-v"
        "f16"
        "--load-mode"
        "mmap"
        "--jinja"
        "--temp"
        "0.7"
        "--top-p"
        "0.9"
        "--metrics"
      ];
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 300;
      TimeoutStopSec = 120;
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 1048576;
    };
  };
}
