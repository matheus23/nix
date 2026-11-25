# Antigravity CLI (`agy`).
# Merges Nix store read grants into settings.json so agy's pivot_root sandbox
# can resolve autoPatchelfHook'd binaries (google-antigravity/antigravity-cli#1753).
{
  lib,
  pkgs,
  ...
}:

let
  antigravity-cli = pkgs.callPackage ../custom/antigravity-cli/package.nix { };

  nixStoreGrants = [
    "read_file(/nix/store)"
    "read_file(/run/current-system/sw)"
    "read_file(/etc/profiles)"
  ];

  settingsFile = ".gemini/antigravity-cli/settings.json";

  # Also on PATH so grants can be re-applied if `agy /config` drops them
  seedGrants = pkgs.writeShellApplication {
    name = "agy-nix-sandbox-grants";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      settings="$HOME/${settingsFile}"
      grants='${builtins.toJSON nixStoreGrants}'

      mkdir -p "$(dirname "$settings")"
      [ -e "$settings" ] || printf '{}\n' > "$settings"

      if ! jq -e . "$settings" > /dev/null 2>&1; then
        echo "antigravity-cli: $settings is not valid JSON, leaving it alone" >&2
        exit 0
      fi

      jq --argjson grants "$grants" '
        (.permissions.allow // []) as $allow
        | ($grants - $allow) as $missing
        | if ($missing | length) == 0 then .
          else .permissions.allow = $allow + $missing
          end
      ' "$settings" > "$settings.tmp"

      if cmp -s "$settings" "$settings.tmp"; then
        rm -f "$settings.tmp"
      else
        mv "$settings.tmp" "$settings"
        echo "antigravity-cli: granted agy's sandbox read access to the Nix store in $settings"
      fi
    '';
  };
in
{
  home.packages = [
    antigravity-cli
    seedGrants
  ];

  home.activation.antigravityCliSandboxGrants = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${seedGrants}/bin/agy-nix-sandbox-grants
  '';
}
