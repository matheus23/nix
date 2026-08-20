{
  lib,
  pkgs,
  ...
}:

let
  llamaCppDFlash2 =
    (pkgs.llama-cpp.override {
      vulkanSupport = true;
      rocmSupport = false;
      blasSupport = false;
    }).overrideAttrs
      (old: {
        version = "0-unstable-2026-08-18";
        src = pkgs.fetchzip {
          url = "https://github.com/z-lab/llama.cpp-fork/archive/5ecbe1ac17ec0484c5b44af0bd580cdc9c428ed4.tar.gz";
          hash = "sha256-KUNt0vXCCVBxoljNTrFZ2pL8opheI1ySPoRmBrChGfg=";
        };
        buildInputs = old.buildInputs ++ [ pkgs.spirv-headers ];
        preConfigure = ''
          printf '%s\n' 5ecbe1ac17ec0484c5b44af0bd580cdc9c428ed4 > COMMIT
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

  targetDir = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3.8-27B-GGUF/990216cf312573f2ac4060279848e0f4237600c7";
  target = "${targetDir}/Qwen3.8-27B-UD-Q8_K_XL.gguf";
  draftDir = "/home/philipp/.local/share/models/huggingface/incoai/Qwen3.8-27B-DFlash2-GGUF/6cb5872e2cee6b4e780a8414922350be8e42d65c";
  draft = "${draftDir}/Qwen3.8-27B-DFlash2-Q4_K_M.gguf";

  downloadModels = pkgs.writeShellApplication {
    name = "download-qwen38-llama-models";
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
    llamaCppDFlash2
  ];

  # The Q4 draft only proposes candidates. Q8 target verification and residual
  # sampling preserve the target distribution; draft quantization affects
  # acceptance and speed rather than the intended output quality.
  systemd.services.llama-qwen38 = {
    description = "Qwen3.8 27B Q8-XL with DFlash2 speculative decoding";
    conflicts = [
      "ds4-server.service"
      "vllm-qwen38.service"
      "vllm-qwen38-vision.service"
    ];
    wantedBy = [ ];
    unitConfig.ConditionPathExists = [
      "${targetDir}/.verified"
      "${draftDir}/.verified"
    ];
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
        "${llamaCppDFlash2}/bin/llama-server"
        "--model"
        target
        "--alias"
        "qwen3.8-27b-q8"
        "--host"
        "127.0.0.1"
        "--port"
        "8422"
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
        "512"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "f16"
        "--cache-type-v"
        "f16"
        "--kv-unified"
        "--load-mode"
        "none"
        "--jinja"
        "--reasoning-preserve"
        "--temp"
        "0"
        "--metrics"
        "--spec-type"
        "draft-dflash"
        "--spec-draft-model"
        draft
        "--spec-draft-ngl"
        "999999"
        "--spec-draft-type-k"
        "f16"
        "--spec-draft-type-v"
        "f16"
        "--spec-draft-n-max"
        "7"
      ];
      ExecStopPost = "+${restorePowerProfile}";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 600;
      TimeoutStopSec = 120;
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 1048576;
    };
  };
}
