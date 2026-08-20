#!/usr/bin/env bash
set -euo pipefail

model_root="${QWEN38_MODEL_ROOT:-$HOME/.local/share/models/huggingface}"

target_repo="unsloth/Qwen3.8-27B-GGUF"
target_rev="990216cf312573f2ac4060279848e0f4237600c7"
target_file="Qwen3.8-27B-UD-Q8_K_XL.gguf"
target_sha256="af36ecb6b5db1407953345b746c14ac93f0657dda413910b4348683a2d990377"
target_dir="$model_root/$target_repo/$target_rev"

draft_repo="incoai/Qwen3.8-27B-DFlash2-GGUF"
draft_rev="6cb5872e2cee6b4e780a8414922350be8e42d65c"
draft_file="Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
draft_sha256="18a380efc9b7ed8d88677fc895f5c11ae170653434ee378f7348f715c14d0594"
draft_dir="$model_root/$draft_repo/$draft_rev"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
aria_input="$work_dir/aria2.input"

add_file() {
  local repo="$1"
  local revision="$2"
  local file="$3"
  local sha256="$4"
  local target="$5"

  mkdir -p "$target"
  if [[ -f "$target/$file" && -f "$target/.verified" ]] \
    && [[ "$(<"$target/.verified")" == "$repo@$revision" ]]; then
    printf 'Already downloaded: %s\n' "$target/$file"
    return
  fi
  rm -f "$target/.verified"
  printf '%s@%s\n' "$repo" "$revision" > "$target/.source-revision"
  printf 'https://huggingface.co/%s/resolve/%s/%s?download=true\n  dir=%s\n  out=%s\n  checksum=sha-256=%s\n' \
    "$repo" "$revision" "$file" "$target" "$file" "$sha256" >> "$aria_input"
}

add_file "$target_repo" "$target_rev" "$target_file" "$target_sha256" "$target_dir"
add_file "$draft_repo" "$draft_rev" "$draft_file" "$draft_sha256" "$draft_dir"

if [[ -s "$aria_input" ]]; then
  aria2c \
    --input-file="$aria_input" \
    --continue=true \
    --max-concurrent-downloads=2 \
    --max-connection-per-server=16 \
    --split=16 \
    --min-split-size=16M \
    --file-allocation=none \
    --auto-file-renaming=false \
    --allow-overwrite=false \
    --retry-wait=5 \
    --max-tries=0
fi

printf '%s  %s\n' "$target_sha256" "$target_dir/$target_file" | sha256sum --check
printf '%s  %s\n' "$draft_sha256" "$draft_dir/$draft_file" | sha256sum --check
printf '%s@%s\n' "$target_repo" "$target_rev" > "$target_dir/.verified"
printf '%s@%s\n' "$draft_repo" "$draft_rev" > "$draft_dir/.verified"

printf 'Ready and verified:\n  %s\n  %s\n' \
  "$target_dir/$target_file" "$draft_dir/$draft_file"
