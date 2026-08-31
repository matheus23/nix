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

  modelPreset = pkgs.writeText "llama-server-models.ini" ''
    version = 1

    [*]
    n-gpu-layers = 999999
    threads = 12
    batch-size = 512
    ubatch-size = 256
    flash-attn = on
    cache-type-k = f16
    cache-type-v = f16
    load-mode = mmap
    jinja = on

    [qwen3.8-flash-next-q4]
    model = ${target}
    mmproj = ${mmproj}
    ctx-size = 524288
    parallel = 2
    fit = off
    override-tensor = per_layer_token_embd=CPU
    reasoning-preserve = on
    reasoning-effort = low
    temp = 1.0
    top-p = 0.95
    top-k = 20
    min-p = 0.0
    load-on-startup = true

    [llama-3.2-1b-instruct-q4]
    model = ${llama32Target}
    ctx-size = 131072
    parallel = 1
    fit = off
    temp = 0.7
    top-p = 0.9
    load-on-startup = false
  '';

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

  enterPerformanceProfile = pkgs.writeShellScript "llama-server-enter-performance" ''
    previous="$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)"
    printf '%s\n' "$previous" > /run/llama-server/previous-power-profile
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
  '';

  restorePowerProfile = pkgs.writeShellScript "llama-server-restore-power" ''
    profile_file=/run/llama-server/previous-power-profile
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
  # head is not supported by llama.cpp yet, so its preset deliberately uses
  # target-only decoding until that path has a correctness-tested implementation.
  systemd.services.llama-server = {
    description = "llama.cpp model router";
    conflicts = [
      "ds4-server.service"
    ];
    wantedBy = [ ];
    unitConfig.ConditionPathExists = [
      "${modelDir}/.verified"
      llama32Target
    ];
    serviceConfig = {
      Type = "simple";
      User = "philipp";
      Group = "users";
      SupplementaryGroups = [
        "render"
        "video"
      ];
      RuntimeDirectory = "llama-server";
      Environment = [
        "HOME=/home/philipp"
        "GGML_VK_VISIBLE_DEVICES=0"
      ];
      ExecStartPre = "+${enterPerformanceProfile}";
      ExecStart = lib.escapeShellArgs [
        "${llamaCppQwen4Exp}/bin/llama-server"
        "--host"
        "127.0.0.1"
        "--port"
        "8422"
        "--webui"
        "--path"
        llamaUi
        "--models-preset"
        modelPreset
        "--models-max"
        "2"
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
}
