#!/usr/bin/env bash

set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
target_dir="$config_root/codex-status"
formatter_target="$target_dir/formatters"

while (($# > 0)); do
  case "$1" in
    --config-root)
      if (($# < 2)); then
        printf 'install.sh: --config-root requires a directory\n' >&2
        exit 2
      fi
      config_root="$2"
      target_dir="$config_root/codex-status"
      formatter_target="$target_dir/formatters"
      shift 2
      ;;
    -h | --help)
      printf '%s\n' \
        'Usage: ./install.sh [--config-root DIRECTORY]' \
        '' \
        "Installs into $target_dir." \
        'An existing formatter theme.json is preserved.'
      exit 0
      ;;
    *)
      printf 'install.sh: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$formatter_target"
chmod 700 "$target_dir"
chmod 700 "$formatter_target"

install -m 700 "$script_dir/codex-status.sh" "$target_dir/codex-status.sh"

for source_path in "$script_dir"/formatters/*.sh; do
  install -m 600 "$source_path" "$formatter_target/$(basename "$source_path")"
done

install -m 600 "$script_dir/formatters/theme.json" "$formatter_target/theme.default.json"

if [[ ! -e "$formatter_target/theme.json" ]]; then
  install -m 600 "$script_dir/formatters/theme.json" "$formatter_target/theme.json"
  theme_result="installed"
else
  theme_result="preserved"
fi

printf 'Installed codex-status in %s\n' "$target_dir"
printf 'Theme %s at %s\n' "$theme_result" "$formatter_target/theme.json"
printf 'Current default theme at %s\n' "$formatter_target/theme.default.json"
