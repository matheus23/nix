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
        version = "0-unstable-2026-09-21-qwen4exp-direct-rows";
        src = pkgs.fetchzip {
          url = "https://github.com/ggml-org/llama.cpp/archive/6f41ac59e0a49a00483a316a22ada6b04edd2950.tar.gz";
          hash = "sha256-d9dRcpOeyxC477iSWzxCEG3XyBploQGsjiVCaHHNjZk=";
        };
        # Use upstream PR #29030 for explicit, parallel reads of lazy PLE rows.
        # Keep the local mmap policy workaround as a separate rebased patch.
        patches = (old.patches or [ ]) ++ [
          ./llama-qwen38-direct-rows.patch
          ./llama-qwen38-random-ple.patch
        ];
        buildInputs = old.buildInputs ++ [ pkgs.spirv-headers ];
        preConfigure = ''
          printf '%s\n' 6f41ac59e0a49a00483a316a22ada6b04edd2950 > COMMIT
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
  qwen3Target = "/home/philipp/.local/share/models/huggingface/unsloth/Qwen3-0.6B-GGUF/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-UD-Q6_K_XL.gguf";
  slotSavePath = "/home/philipp/.cache/ava/slots";

  # Models exposed by the llama-server router. Comment out an entry to disable
  # that model; --models-max and ConditionPathExists follow this list.
  models = [
    {
      name = "qwen3.8-flash-next-q4";
      model = target;
      mmproj = mmproj;
      # Qwen3.8-Flash-Next is the experimental Qwen4 architecture. Its native
      # MTP head is not supported by llama.cpp yet, so this preset deliberately
      # uses target-only decoding until that path has a correctness-tested
      # implementation.
      settings = {
        ctx-size = 262144;
        parallel = 2;
        fit = "off";
        lazy-mode = "on-direct";
        override-tensor = "per_layer_token_embd=CPU";
        reasoning-preserve = "on";
        reasoning-effort = "low";
        temp = 1.0;
        top-p = 0.95;
        top-k = 20;
        min-p = 0.0;
        load-on-startup = true;
      };
    }
    # {
    #   name = "llama-3.2-1b-instruct-q4";
    #   model = llama32Target;
    #   settings = {
    #     ctx-size = 20000;
    #     parallel = 1;
    #     fit = "off";
    #     temp = 0.7;
    #     top-p = 0.9;
    #     load-on-startup = false;
    #   };
    # }
    # {
    #   name = "qwen3-0.6b-q6";
    #   model = qwen3Target;
    #   settings = {
    #     ctx-size = 40000;
    #     parallel = 2;
    #     fit = "off";
    #     temp = 0.6;
    #     top-p = 0.95;
    #     top-k = 20;
    #     min-p = 0.0;
    #     load-on-startup = false;
    #   };
    # }
  ];

  formatValue =
    v: if builtins.isBool v then (if v then "true" else "false") else builtins.toString v;

  formatSettings =
    settings: lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = ${formatValue v}") settings);

  modelPreset = pkgs.writeText "llama-server-models.ini" (
    ''
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
      cont-batching = off
    ''
    + lib.concatMapStrings (
      m:
      "\n[${m.name}]\nmodel = ${m.model}\n"
      + lib.optionalString (m ? mmproj) "mmproj = ${m.mmproj}\n"
      + formatSettings m.settings
      + "\n"
    ) models
  );

  modelPaths = map (m: m.model) models;

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

  systemd.services.llama-server = {
    description = "llama.cpp model router";
    conflicts = [
      "ds4-server.service"
    ];
    wantedBy = [ ];
    unitConfig.ConditionPathExists = [ "${modelDir}/.verified" ] ++ modelPaths;
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
        (toString (builtins.length models))
        "--slot-save-path"
        slotSavePath
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
