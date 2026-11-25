{
  lib,
  pkgs,
  ...
}:

let
  llamaCppInkling = pkgs.callPackage ./llama-cpp-inkling.nix { };

  modelDir = "/home/philipp/.local/share/models/huggingface/ggml-org/Inkling-2-Mini-GGUF/e8a2cecf0e78914f07cc27b9be711a9b2c7561d9";
  slotSavePath = "/home/philipp/.cache/ava/slots";

  models = [
    {
      name = "inkling-2-mini-iq4-nl";
      model = "${modelDir}/Inkling-2-Mini-IQ4_NL.gguf";
      mmproj = "${modelDir}/mmproj-Inkling-2-Mini-Q8_0.gguf";
      # Model card sampling defaults (sharper values degrade reasoning).
      # 128K ctx leaves room for gufo's weights on the same GPU.
      settings = {
        ctx-size = 131072;
        parallel = 1;
        fit = "off";
        temp = 1.0;
        top-p = 1.0;
        top-k = 0;
        min-p = 0.0;
        load-on-startup = true;
      };
    }
  ];

  formatValue = v: if builtins.isBool v then (if v then "true" else "false") else builtins.toString v;

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

  modelPaths = lib.concatMap (m: [ m.model ] ++ lib.optional (m ? mmproj) m.mmproj) models;

  # Prebuilt Llama Chat UI (upstream dropped tools/ui in b12651)
  llamaUi = pkgs.fetchzip {
    name = "llama-ui";
    url = "https://huggingface.co/buckets/ggml-org/llama-ui/resolve/latest/dist.tar.gz?download=true";
    hash = "sha256-7xNWI6FJH/nuSRCWapn1QptnhTVNlVf9i2hfEg4zzvw=";
    stripRoot = false;
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
  environment.systemPackages = [ llamaCppInkling ];

  systemd.services.llama-server = {
    description = "llama.cpp model router (Inkling 2 Mini)";
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
        "${llamaCppInkling}/bin/llama-server"
        "--host"
        "127.0.0.1"
        "--port"
        "8423" # gufo-server uses 8422
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
