#!/usr/bin/env bash
set -euo pipefail

args=()
mode=plan
case "${1:-}" in
  "") printf 'Dry-run only: no files will be deleted.\n\n' ;;
  --apply)
    args=(--apply)
    mode=apply
    printf 'Removing only the old Qwen revision from snapshots and the migration copy.\n'
    printf 'Each pass asks for confirmation. Snapshot contents cannot be restored afterward.\n\n'
    ;;
  *) printf 'Usage: %s [--apply]\n' "$0" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  printf 'Usage: %s [--apply]\n' "$0" >&2
  exit 2
fi

scrub="$(command -v btrfs-snap-scrub)"
old="huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/824f539b2710e5a9e47af4952cf6578cf5ee8932"
new="$HOME/.local/share/models/huggingface/unsloth/Qwen3.8-Flash-Next-GGUF/f5d175de2cf7f720d45d6064019a81fcf056e986"
test -f "$new/.verified"

df -h /home
sudo "$scrub" "${args[@]}" \
  "/home/.snapshots/1083/snapshot/philipp/.local/share/models/$old" \
  | tee "/tmp/qwen-old-snapshots-$mode.txt"

printf '\nChecking the retained migration copy…\n\n'
sudo "$scrub" "${args[@]}" \
  "$HOME/.local/share/models.pre-subvolume/$old" \
  | tee "/tmp/qwen-old-backup-$mode.txt"

printf '\nLogs saved to /tmp/qwen-old-{snapshots,backup}-%s.txt\n' "$mode"
df -h /home
