#!/usr/bin/env bash
# Link this checkout's CE skills plus the DeepSeek Harness host binding into a
# DSH skill root, so DSH discovers them as `<root>/<name>/SKILL.md` bundles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"

usage() {
  cat <<'EOF'
Usage: install.sh [--global | --project [DIR]] [--check] [--uninstall]

  --global            Link into $DSH_HOME/skills (default).
  --project [DIR]     Link into the DSH project skill root at or above DIR
                      (default: $PWD). DSH resolves that root as the nearest
                      ancestor holding .git, falling back to the directory
                      itself, and this script resolves it the same way.
  --check             Report each skill link's state and exit non-zero when any
                      link is missing, stale, foreign, dangling, or a conflict.
  --uninstall         Remove the symlinks this checkout owns.

Set DSH_SKILLS_DIR to override the destination root entirely.

Only symlinks are created. A real directory with a skill's name is never
overwritten; the script stops and names it instead.
EOF
}

# DSH project-root rule: nearest ancestor with a .git entry, else the directory.
resolve_project_root() {
  local dir="$1" parent
  while :; do
    if [[ -e "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done
  printf '%s\n' "$1"
}

# Absolute path a symlink points at, whether its target is absolute or relative.
link_target_abs() {
  local link="$1" target
  target="$(readlink "$link")"
  case "$target" in
  /*) printf '%s\n' "$target" ;;
  *) printf '%s\n' "$(cd "$(dirname "$link")" && pwd)/$target" ;;
  esac
}

MODE="install"
SCOPE="--global"
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --global)
    SCOPE="--global"
    shift
    ;;
  --project)
    SCOPE="--project"
    shift
    if [[ $# -gt 0 && "$1" != --* ]]; then
      PROJECT_DIR="$1"
      shift
    fi
    ;;
  --check)
    MODE="check"
    shift
    ;;
  --uninstall)
    MODE="uninstall"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

if [[ -n "${DSH_SKILLS_DIR:-}" ]]; then
  TARGET_ROOT="$DSH_SKILLS_DIR"
elif [[ "$SCOPE" == "--global" ]]; then
  TARGET_ROOT="$DSH_HOME_DIR/skills"
else
  PROJECT_DIR="${PROJECT_DIR:-$PWD}"
  [[ -d "$PROJECT_DIR" ]] || {
    echo "not a directory: $PROJECT_DIR" >&2
    exit 1
  }
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  TARGET_ROOT="$(resolve_project_root "$PROJECT_DIR")/.dsh/skills"
fi

# Source skill roots, in link order: the plugin's own skills, then this fork's
# DeepSeek Harness binding.
SOURCE_ROOTS=("$REPO_ROOT/skills" "$REPO_ROOT/dsh/skills")

# Emits "<name> <expected-source-dir>" for every installable skill.
each_skill() {
  local root dir name
  for root in "${SOURCE_ROOTS[@]}"; do
    for dir in "$root"/*/; do
      [[ -f "$dir/SKILL.md" ]] || continue
      name="$(basename "$dir")"
      printf '%s %s\n' "$name" "${dir%/}"
    done
  done
}

if [[ "$MODE" == "check" ]]; then
  echo "skill root: $TARGET_ROOT"
  bad=0
  while read -r name expected; do
    link="$TARGET_ROOT/$name"
    if [[ -L "$link" ]]; then
      actual="$(link_target_abs "$link")"
      if [[ "$actual" == "$expected" ]]; then
        echo "  ok       $name"
      elif [[ -e "$actual" ]]; then
        echo "  stale    $name -> $actual"
        bad=1
      elif [[ "$actual" == "$REPO_ROOT"/* ]]; then
        echo "  dangling $name -> $actual"
        bad=1
      else
        echo "  foreign  $name -> $actual"
        bad=1
      fi
    elif [[ -e "$link" ]]; then
      echo "  conflict $name (not a symlink)"
      bad=1
    else
      echo "  missing  $name"
      bad=1
    fi
  done < <(each_skill)
  exit "$bad"
fi

if [[ "$MODE" == "uninstall" ]]; then
  removed=0
  skipped=0
  while read -r name expected; do
    link="$TARGET_ROOT/$name"
    [[ -L "$link" ]] || continue
    actual="$(link_target_abs "$link")"
    if [[ "$actual" == "$expected" ]]; then
      rm "$link"
      removed=$((removed + 1))
    else
      echo "kept $name (points at $actual, not this checkout)" >&2
      skipped=$((skipped + 1))
    fi
  done < <(each_skill)
  echo "removed $removed symlink(s) from $TARGET_ROOT; kept $skipped not owned by this checkout"
  exit 0
fi

mkdir -p "$TARGET_ROOT"
linked=0
while read -r name expected; do
  link="$TARGET_ROOT/$name"
  if [[ -e "$link" && ! -L "$link" ]]; then
    echo "refusing to replace non-symlink: $link" >&2
    exit 1
  fi
  ln -sfn "$expected" "$link"
  linked=$((linked + 1))
done < <(each_skill)

echo "linked $linked skill(s) into $TARGET_ROOT"
echo "start a new DSH session, or wait for the skill catalog to refresh"
