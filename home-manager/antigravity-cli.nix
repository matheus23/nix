# Antigravity CLI (`agy`), Google's terminal agent client.
#
# Two things here are NixOS-specific and both would bite silently:
#
# 1. The self-updater. Upstream's installer drops the binary in ~/.local/bin and
#    rewrites it in place on a timer; in the store that can only fail, so the
#    package wraps `agy` with AGY_CLI_DISABLE_AUTO_UPDATE. Bumping the version is
#    a rebuild — see custom/antigravity-cli/package.nix.
#
# 2. The terminal sandbox. `agy` runs agent shell commands in a fresh mount
#    namespace rooted on a tmpfs that holds only the FHS directories plus whatever
#    its `read_file` grants add. autoPatchelfHook repointed the binary's PT_INTERP
#    at a glibc inside the store, so after pivot_root the kernel cannot resolve
#    the interpreter and the sandbox helper dies with
#    `sbox: exec /proc/self/exe: no such file or directory`. Every command then
#    fails with `connecting to sandbox server: ... connection reset by peer`, and
#    because `auto` mode turns the sandbox on by default that means the agent
#    cannot run anything. Granting read access to the store makes sbox start.
#    Tracked upstream as google-antigravity/antigravity-cli#1753; once that is
#    fixed the grants below can go away.
#
# `agy` owns settings.json and rewrites it from /config, so this merges the grants
# in additively instead of managing the file, and rewrites it only when one of the
# grants is actually missing.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  antigravity-cli = pkgs.callPackage ../custom/antigravity-cli/package.nix { };

  # /nix/store holds agy's ELF interpreter and every binary a sandboxed command
  # might exec. /run/current-system/sw and /etc/profiles are the system and
  # home-manager profiles: symlink trees into the store, but they have to be
  # mounted as themselves for PATH lookups to resolve.
  nixStoreGrants = [
    "read_file(/nix/store)"
    "read_file(/run/current-system/sw)"
    "read_file(/etc/profiles)"
  ];

  settingsFile = ".gemini/antigravity-cli/settings.json";

  # Also installed, so `agy-nix-sandbox-grants` can repair the grants by hand
  # after `agy /config` rewrites settings.json in a fresh checkout.
  seedGrants = pkgs.writeShellApplication {
    name = "agy-nix-sandbox-grants";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      settings="$HOME/${settingsFile}"
      grants='${builtins.toJSON nixStoreGrants}'

      mkdir -p "$(dirname "$settings")"
      [ -e "$settings" ] || printf '{}\n' > "$settings"

      # agy may hold a half-written file, and a broken settings.json is worse
      # than missing grants.
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
