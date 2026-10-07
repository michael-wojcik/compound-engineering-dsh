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
# The path is normalised when it resolves: a link written relative to its own
# directory used to be compared unresolved, so `…/x/../skills/ce-plan` never
# matched `…/skills/ce-plan` and a correct link was reported stale — and then
# refused removal as "not owned by this checkout". When the path does not
# resolve, the unresolved form is returned so classification still works.
link_target_abs() {
  local link="$1" target raw
  target="$(readlink "$link")"
  case "$target" in
  /*) raw="$target" ;;
  *) raw="$(cd "$(dirname "$link")" && pwd)/$target" ;;
  esac
  printf '%s\n' "$(cd "$raw" 2>/dev/null && pwd || printf '%s' "$raw")"
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
  units=0
  while read -r name expected; do
    [[ -n "$name" ]] || continue
    units=$((units + 1))
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
  # Zero units read is not a pass. Both source roots can be absent or empty, and
  # the loop above would then report no problems because it saw no skills.
  if (( units == 0 )); then
    echo "GATE FAIL: no installable skills under ${SOURCE_ROOTS[*]} — the check read nothing." >&2
    exit 2
  fi
  exit "$bad"
fi

if [[ "$MODE" == "uninstall" ]]; then
  # Sweep by ownership over the target root, not over the current skill list: a
  # link whose skill upstream removed is still this checkout's link, and
  # enumerating only current skills left it dangling forever. A link into this
  # checkout from outside the skill roots is treated as the user's, not ours.
  removed=0
  skipped=0
  shopt -s nullglob
  for link in "$TARGET_ROOT"/*; do
    [[ -L "$link" ]] || continue
    name="$(basename "$link")"
    actual="$(link_target_abs "$link")"
    case "$actual" in
    "$REPO_ROOT"/skills/* | "$REPO_ROOT"/dsh/skills/*)
      rm "$link"
      removed=$((removed + 1))
      ;;
    *)
      echo "kept $name (points at $actual, not this checkout)" >&2
      skipped=$((skipped + 1))
      ;;
    esac
  done
  shopt -u nullglob
  echo "removed $removed symlink(s) from $TARGET_ROOT; kept $skipped not owned by this checkout"
  exit 0
fi

mkdir -p "$TARGET_ROOT"
linked=0
while read -r name expected; do
  [[ -n "$name" ]] || continue
  link="$TARGET_ROOT/$name"
  if [[ -L "$link" ]]; then
    # A foreign link is someone else's wiring. Refuse it, matching how --check
    # reports it and how --uninstall protects it, rather than silently replacing.
    actual="$(link_target_abs "$link")"
    if [[ "$actual" != "$expected" && "$actual" != "$REPO_ROOT"/* ]]; then
      echo "refusing to replace foreign symlink: $link -> $actual" >&2
      exit 1
    fi
  elif [[ -e "$link" ]]; then
    echo "refusing to replace non-symlink: $link" >&2
    exit 1
  fi
  ln -sfn "$expected" "$link"
  linked=$((linked + 1))
done < <(each_skill)

if (( linked == 0 )); then
  echo "GATE FAIL: no installable skills under ${SOURCE_ROOTS[*]} — nothing was linked." >&2
  exit 2
fi

echo "linked $linked skill(s) into $TARGET_ROOT"
echo "start a new DSH session, or wait for the skill catalog to refresh"
