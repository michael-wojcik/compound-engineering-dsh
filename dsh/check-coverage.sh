#!/usr/bin/env bash
# Report whether every skill that dispatches agents carries the DeepSeek Harness
# binding, and which dispatch-bearing files still lack an in-file pointer.
#
# Two levels, because they fail differently:
#   - Skill level is a GATE. A skill that dispatches and carries no pointer
#     anywhere exits non-zero: a run through that skill never sees the binding.
#   - File level is EVIDENCE, not a gate. It lists dispatch-bearing files with no
#     in-file pointer. Some are genuine unbound launch sites; others only mention
#     a dispatch ("stop without dispatching reviewers"). A human reads the list.
#
# The dispatch pattern is deliberately broad. A false positive costs a review
# line; a false negative costs an unbound launch site, which is the failure this
# script exists to catch — an earlier narrow version reported "0 unbound" while
# ce-retune dispatched two waves with no pointer at all.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

# Dispatch verbs near an agent noun, plus CE's object-less phrasings.
DISPATCH_RE='(spawn|dispatch|launch|delegate)[a-z]*[^.]{0,60}(agent|reviewer|analyst|researcher|historian|leaf|leaves|peer|worker|scout|candidate|baker|validator)|separate dispatched agents|candidate and judge delegation'

# The negation filter below is deliberately NOT the same string as audit-bindings.sh's
# NEGATE_RE, and the difference is the apostrophe: this file matches a literal `don't`
# while that one matches `don.t`, which as an ERE also matches "dont" and "donXt".
# This pattern is the broader net for the broader DISPATCH_RE — two reviewers have now
# proposed unifying them, and unifying means adopting one file's detections. If you do
# it, move both gates' counts in the same commit.

is_prompt_asset() {
  case "$1" in
  */personas/* | */agents/*) return 0 ;;
  *) return 1 ;;
  esac
}

# A gate that reads nothing must not report success. An absent or moved skills/
# tree used to leave scanned/unbound at 0 and exit 0.
shopt -s nullglob
skill_dirs=("$SKILLS_DIR"/*/)
shopt -u nullglob
if (( ${#skill_dirs[@]} == 0 )); then
  echo "GATE FAIL: no skill directories under $SKILLS_DIR — the gate read nothing." >&2
  exit 2
fi

echo "SKILL LEVEL"
printf '  %-26s %-9s %-9s %s\n' "SKILL" "DISPATCH" "POINTERS" "STATUS"

unbound=0
scanned=0
for dir in "${skill_dirs[@]}"; do
  [[ -f "$dir/SKILL.md" ]] || continue
  name="$(basename "$dir")"
  scanned=$((scanned + 1))

  filtered=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_prompt_asset "$f" || filtered="$filtered$f"$'\n'
  done < <(grep -rliE "$DISPATCH_RE" "$dir" --include="*.md" 2>/dev/null || true)

  bound="$(grep -rl 'ce-dsh-host' "$dir" --include="*.md" 2>/dev/null || true)"

  if [[ -z "${filtered//$'\n'/}" ]]; then
    printf '  %-26s %-9s %-9s %s\n' "$name" "no" "-" "n/a"
    continue
  fi

  dcount="$(printf '%s' "$filtered" | grep -c . || true)"
  bcount="$(printf '%s' "$bound" | grep -c . || true)"
  if [[ "$bcount" -gt 0 ]]; then
    printf '  %-26s %-9s %-9s %s\n' "$name" "$dcount" "$bcount" "covered"
  else
    printf '  %-26s %-9s %-9s %s\n' "$name" "$dcount" "0" "MISSING"
    unbound=$((unbound + 1))
  fi
done

echo
echo "FILE LEVEL — dispatch-bearing files with no in-file pointer"
launch_unbound=0
mentions=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_prompt_asset "$f" && continue
  grep -q "ce-dsh-host" "$f" && continue
  # A line that forbids or avoids a dispatch is a mention, not a launch site.
  # The negation must sit next to the verb: matching it anywhere on the line hid
  # a real launch whose line happened to contain an unrelated "without".
  # The second alternative covers a prohibition on SUBSTITUTING a generic agent
  # ("Do not substitute a generic Task, Agent, or subagent"), which is a routing
  # rule rather than a launch. Measured before adding: it removes exactly one
  # candidate from this list and adds none.
  hits="$(grep -niE "$DISPATCH_RE" "$f" | grep -vEi "(do not|don't|never|without|rather than|instead of|temptation to|no subagents|skips)[a-z ]{0,12}(spawn|dispatch|launch|delegate)|(do not|never|rather than|instead of)[a-z ]{0,12}substitute[a-z ]{0,40}(task|agent|subagent|reviewer)" || true)"
  if [[ -z "$hits" ]]; then
    mentions=$((mentions + 1))
    continue
  fi
  printf '  LAUNCH   %s\n' "${f#"$REPO_ROOT"/}"
  # Print every candidate line, not just the first. An earlier version showed only
  # head -1, which let a file whose first match was descriptive be dismissed while a
  # real launch sat further down — that is how ce-retune/cut-passes.md and
  # ce-ideate/post-ideation-workflow.md passed review unbound.
  # A herestring, not a pipe into head: under `set -euo pipefail` a printf that
  # outruns head's buffer takes SIGPIPE, the pipeline returns 141, and the script
  # dies before the summary and its exit code — a crash standing in for a verdict.
  sed -n '1,3p' <<<"$hits" | cut -c1-140 | sed 's/^/           /'
  launch_unbound=$((launch_unbound + 1))
done < <(grep -rliE "$DISPATCH_RE" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort)
echo "  ($mentions further files mention a dispatch without launching one)"

echo
echo "BINDING VARIANTS IN USE"
while IFS= read -r v; do
  printf '  %-56s %s\n' "$v" "$(grep -rl "$v" "$SKILLS_DIR" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')"
done <<'VARIANTS'
every agent this file dispatches is spawned
every reviewer below is spawned
each analyzer is spawned
reach this peer through an Agent Teams teammate
a dispatch whose model does not actually differ
this dispatch is an Agent Teams teammate
VARIANTS

echo
# The guard at the top of this script tests that skill directories exist; this one
# tests that a skill was actually read. They are different failures: a tree whose
# directories all lack a SKILL.md used to scan zero skills and still exit 0, which
# is a gate reporting success over input it never parsed.
if (( scanned == 0 )); then
  echo "GATE FAIL: scanned 0 skills under $SKILLS_DIR — directories exist but none held a SKILL.md." >&2
  exit 2
fi
echo "skills scanned: $scanned, skill-level gaps: $unbound, unbound launch sites: $launch_unbound, mentions: $mentions"
exit "$unbound"
