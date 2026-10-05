#!/usr/bin/env bash
# Report, per skill, whether it stages a subagent dispatch and whether it carries
# the DeepSeek Harness binding pointer.
#
# The dispatch test is a heuristic over the imperative phrasings CE uses when a
# skill launches an agent. Prompt assets (references/personas, references/agents)
# are excluded: they are the text a spawned agent receives, not a dispatch site.
# A skill whose only matches are incidental ("spawn a background process") shows
# up here as a dispatch site and needs a human read, so this is evidence for
# review, not a gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

DISPATCH_RE='(spawn|dispatch|launch)[a-z]* (the |a |each |one |its |every |all |two )?(generic )?(sub-?agents?|reviewers?|analyzers?|leaves?|leaf|personas?|workers?|researchers?|historians?)'

printf '%-28s %-8s %-8s %s\n' "SKILL" "DISPATCH" "BOUND" "STATUS"
printf '%-28s %-8s %-8s %s\n' "----------------------------" "--------" "--------" "------"

missing=0
total=0
for dir in "$SKILLS_DIR"/*/; do
  [[ -f "$dir/SKILL.md" ]] || continue
  name="$(basename "$dir")"
  total=$((total + 1))

  dispatch_files="$(grep -rlE "$DISPATCH_RE" "$dir" --include="*.md" 2>/dev/null |
    grep -v '/personas/' | grep -v '/agents/' || true)"
  bound_files="$(grep -rl 'ce-dsh-host' "$dir" --include="*.md" 2>/dev/null || true)"

  if [[ -z "$dispatch_files" ]]; then
    printf '%-28s %-8s %-8s %s\n' "$name" "no" "-" "n/a (no dispatch site)"
    continue
  fi

  dcount="$(printf '%s\n' "$dispatch_files" | grep -c . || true)"
  bcount="$(printf '%s\n' "$bound_files" | grep -c . || true)"
  if [[ "$bcount" -gt 0 ]]; then
    printf '%-28s %-8s %-8s %s\n' "$name" "$dcount" "$bcount" "covered"
  else
    printf '%-28s %-8s %-8s %s\n' "$name" "$dcount" "0" "MISSING"
    missing=$((missing + 1))
  fi
done

echo
echo "skills scanned: $total, dispatching without the binding: $missing"
exit "$missing"
