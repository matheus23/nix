{ pkgs, unstable, letta-code }:

let
  profile = pkgs.writeText "letta-nono-profile.json" (builtins.toJSON {
    meta = {
      name = "letta";
      description = "Letta Code CLI agent sandbox profile";
    };
    extends = "default";
    groups = {
      include = [
        "deny_credentials"
        "deny_keychains_linux"
        "deny_browser_data_linux"
        "deny_shell_history"
        "deny_shell_configs"
        "system_read_linux_core"
        "system_write_linux"
        "user_tools"
        "dangerous_commands"
        "dangerous_commands_linux"
        "node_runtime"
        "rust_runtime"
        "nix_runtime"
        "git_config"
        "unlink_protection"
        "user_caches_linux"
        "linux_sysfs_read"
      ];
    };
    workdir = { access = "readwrite"; };
    filesystem = {
      allow = [
        "$HOME/.letta"
        "$HOME/.cargo"
        "$HOME/.cache/kache"
        "$HOME/.config/nono/profile-drafts"
        "/tmp"
      ];
      read = [
        "$HOME/.config/nono/packages"
        "$HOME/.config/nono/profiles"
        "$HOME/.agents/skills"
      ];
    };
    rollback = {
      exclude_patterns = [ "node_modules" ".next" "__pycache__" "target" ".letta" ];
    };
  });
in
pkgs.writeShellApplication {
  name = "le-nono";
  runtimeInputs = [ unstable.nono ];
  text = ''
    NONO_EXTRA_FLAGS=()

    GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || true
    if [[ -n "$GIT_DIR" ]] && echo "$GIT_DIR" | grep -q '/worktrees/'; then
      WORKTREE_NAME="$(basename "$GIT_DIR")"
      MAIN_GIT="$(dirname "$(dirname "$GIT_DIR")")"

      NONO_EXTRA_FLAGS=(--read "$MAIN_GIT" --allow "$MAIN_GIT/worktrees/$WORKTREE_NAME")
    fi

    # Split args: everything before -- goes to nono, after -- goes to letta.
    NONO_USER_ARGS=()
    LETTA_ARGS=()
    SPLIT=false
    for arg in "$@"; do
      if [[ "$arg" == "--" ]]; then
        SPLIT=true
      elif ! $SPLIT && [[ "$arg" == "--access-laptop" ]]; then
        NONO_EXTRA_FLAGS+=(--allow "$HOME/.config/letta/ssh")
      elif $SPLIT; then
        LETTA_ARGS+=("$arg")
      else
        NONO_USER_ARGS+=("$arg")
      fi
    done

    # This directory contains the dedicated key and tunnel config for the
    # isolated laptop agent, not the user's normal SSH credentials.
    exec nono run -v --read /nix --read ~/.nix-profile --read ~/.config/gh/ --allow-cwd \
      "''${NONO_EXTRA_FLAGS[@]}" \
      "''${NONO_USER_ARGS[@]}" \
      --profile ${profile} ${letta-code}/bin/letta "''${LETTA_ARGS[@]}"
  '';
}
