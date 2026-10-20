#!/bin/zsh
# Copies the undertone-backgrounds skill into ~/.claude/skills.
set -euo pipefail
source_dir="${0:A:h}/../skills/undertone-backgrounds"
target="$HOME/.claude/skills/undertone-backgrounds"
rm -rf "$target"
mkdir -p "$target"
cp -R "$source_dir/" "$target/"
echo "Installed $target"
