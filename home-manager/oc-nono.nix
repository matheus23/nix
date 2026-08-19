{ pkgs, unstable }:

let
  profile = pkgs.writeText "opencode-nono-profile.json" (
    builtins.toJSON {
      meta = {
        name = "opencode";
        description = "OpenCode agent sandbox profile";
      };
      extends = "always-further/opencode";
      filesystem = {
        allow = [ "$HOME/.cache/kache" ];
      };
    }
  );
in
pkgs.writeShellApplication {
  name = "oc-nono";
  runtimeInputs = [ unstable.nono ];
  text = ''
    NONO_EXTRA_FLAGS=""

    GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || true
    if [[ -n "$GIT_DIR" ]] && echo "$GIT_DIR" | grep -q '/worktrees/'; then
      WORKTREE_NAME="$(basename "$GIT_DIR")"
      MAIN_GIT="$(dirname "$(dirname "$GIT_DIR")")"

      NONO_EXTRA_FLAGS="--read $MAIN_GIT --allow $MAIN_GIT/worktrees/$WORKTREE_NAME"
    fi

    # Split args: everything before -- goes to nono, after -- goes to opencode
    NONO_USER_ARGS=()
    OC_ARGS=()
    SPLIT=false
    for arg in "$@"; do
      if [[ "$arg" == "--" ]]; then
        SPLIT=true
      elif $SPLIT; then
        OC_ARGS+=("$arg")
      else
        NONO_USER_ARGS+=("$arg")
      fi
    done

    # shellcheck disable=SC2086,SC2068
    exec nono run -v --read /nix --read ~/.nix-profile --read ~/.config/gh/ --allow-cwd \
      $NONO_EXTRA_FLAGS \
      ''${NONO_USER_ARGS[@]} \
      --profile ${profile} opencode ''${OC_ARGS[@]}
  '';
}
