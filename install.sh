#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_src="$repo_dir/skills/game-bgm-video-maker"
skill_dest="$HOME/.codex/skills/game-bgm-video-maker"

if [[ ! -d "$skill_src" ]]; then
  echo "Missing skill folder: $skill_src" >&2
  exit 1
fi

mkdir -p "$HOME/.codex/skills"
rm -rf "$skill_dest"
cp -R "$skill_src" "$skill_dest"

echo "Installed game-bgm-video-maker to $skill_dest"
