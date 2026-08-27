#!/usr/bin/env bash
set -euo pipefail

model_root="${QWEN38_MODEL_ROOT:-$HOME/.local/share/models/huggingface}"

repo="unsloth/Qwen3.8-Flash-Next-GGUF"
revision="824f539b2710e5a9e47af4952cf6578cf5ee8932"
target_dir="$model_root/$repo/$revision"

files=(
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf"
  "mmproj-F16.gguf"
)
sha256s=(
  "4448186216b3af4cc558bbce2c3213f01608f8f8b2e5267a9767971dd3ec8082"
  "3f342f1c1580473f1ee94ddd5b28206e8c07a70fa1a366f59d1d6c922919a6c9"
  "56758f40269cad5cd9b0d3d6fbae0f40f6d5be6de49e4ab392dbe83157d9cbd3"
  "753bda48b98ba4f1636134a90a967de1b2d3908a236c026e464777342e53510a"
  "1f7b7f0b984cf065c604360c29c8098362ed61b290db0ff12c6f360bb1a8a980"
)

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
aria_input="$work_dir/aria2.input"

if [[ -f "$target_dir/.verified" ]] \
  && [[ "$(<"$target_dir/.verified")" == "$repo@$revision" ]]; then
  missing=false
  for file in "${files[@]}"; do
    if [[ ! -f "$target_dir/$file" ]]; then
      missing=true
      break
    fi
  done
  if [[ "$missing" == false ]]; then
    printf 'Already downloaded and verified: %s\n' "$target_dir"
    exit 0
  fi
fi

mkdir -p "$target_dir"
rm -f "$target_dir/.verified"
printf '%s@%s\n' "$repo" "$revision" > "$target_dir/.source-revision"

for i in "${!files[@]}"; do
  file="${files[$i]}"
  sha256="${sha256s[$i]}"
  output_dir="$target_dir/$(dirname "$file")"
  output_file="$(basename "$file")"
  mkdir -p "$output_dir"
  if [[ -f "$output_dir/$output_file" ]] \
    && printf '%s  %s\n' "$sha256" "$output_dir/$output_file" | sha256sum --check --status; then
    printf 'Already downloaded: %s\n' "$output_dir/$output_file"
    continue
  fi
  if [[ -f "$output_dir/$output_file" && ! -f "$output_dir/$output_file.aria2" ]]; then
    printf 'Checksum mismatch for completed file: %s\n' "$output_dir/$output_file" >&2
    printf 'Remove or move it before retrying.\n' >&2
    exit 1
  fi
  printf 'https://huggingface.co/%s/resolve/%s/%s?download=true\n  dir=%s\n  out=%s\n  checksum=sha-256=%s\n' \
    "$repo" "$revision" "$file" "$output_dir" "$output_file" "$sha256" >> "$aria_input"
done

if [[ -s "$aria_input" ]]; then
  aria2c \
    --input-file="$aria_input" \
    --continue=true \
    --max-concurrent-downloads=3 \
    --max-connection-per-server=16 \
    --split=16 \
    --min-split-size=16M \
    --file-allocation=none \
    --auto-file-renaming=false \
    --allow-overwrite=false \
    --retry-wait=5 \
    --max-tries=0
fi

for i in "${!files[@]}"; do
  printf '%s  %s\n' "${sha256s[$i]}" "$target_dir/${files[$i]}"
done | sha256sum --check

printf '%s@%s\n' "$repo" "$revision" > "$target_dir/.verified"
printf 'Ready and verified: %s\n' "$target_dir"
