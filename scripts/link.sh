#!/usr/bin/env bash
# Usage: .ai-base/scripts/link.sh [--check]
# Run from the project root (the directory that contains .ai-base/).
#
# Creates (default) or verifies (--check) the symlinks from the project's
# .claude/ and .github/ directories and SPEC.md into the ai-base submodule.
# Regular files at a link path are project overrides and are never touched.

set -euo pipefail

mode="link"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  -h|--help)
    echo "Usage: .ai-base/scripts/link.sh [--check]"
    echo "Run from the project root (the directory that contains .ai-base/)."
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: .ai-base/scripts/link.sh [--check]" >&2
    exit 2
    ;;
esac

if [ ! -f .ai-base/handbook.md ]; then
  echo ".ai-base is not initialized — run: git submodule update --init" >&2
  exit 2
fi

shopt -s nullglob

problems=0

# Prints "<link path> <target>" lines for every desired link.
desired_links() {
  local file name skill
  for file in .ai-base/agents/*.md; do
    name="$(basename "$file" .md)"
    echo ".claude/agents/$name.md ../../.ai-base/agents/$name.md"
    echo ".github/agents/$name.agent.md ../../.ai-base/agents/$name.md"
  done
  for file in .ai-base/skills/*/SKILL.md; do
    skill="$(basename "$(dirname "$file")")"
    echo ".claude/skills/$skill/SKILL.md ../../../.ai-base/skills/$skill/SKILL.md"
    echo ".github/skills/$skill/SKILL.md ../../../.ai-base/skills/$skill/SKILL.md"
  done
  echo "SPEC.md .ai-base/SPEC.md"
}

# Prints every symlink below the managed directories that points into
# .ai-base/ but no longer resolves.
stale_links() {
  local dir link
  for dir in .claude/agents .claude/skills .github/agents .github/skills; do
    [ -d "$dir" ] || continue
    find "$dir" -type l | while IFS= read -r link; do
      case "$(readlink "$link")" in
        *.ai-base/*)
          [ -e "$link" ] || echo "$link"
          ;;
      esac
    done
  done
}

while read -r path target; do
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    echo "override: $path"
    continue
  fi
  if [ "$mode" = "link" ]; then
    mkdir -p "$(dirname "$path")"
    ln -sfn "$target" "$path"
    echo "linked: $path"
  else
    if [ ! -L "$path" ]; then
      echo "MISSING: $path"
      problems=1
    elif [ "$(readlink "$path")" != "$target" ]; then
      echo "WRONG: $path"
      problems=1
    elif [ ! -e "$path" ]; then
      echo "BROKEN: $path"
      problems=1
    fi
  fi
done < <(desired_links)

while IFS= read -r link; do
  [ -n "$link" ] || continue
  if [ "$mode" = "link" ]; then
    rm "$link"
    echo "removed stale: $link"
    parent="$(dirname "$link")"
    case "$parent" in
      .claude/skills/*|.github/skills/*)
        rmdir "$parent" 2>/dev/null || true
        ;;
    esac
  else
    echo "STALE: $link"
    problems=1
  fi
done < <(stale_links)

if [ "$mode" = "check" ]; then
  exit "$problems"
fi
