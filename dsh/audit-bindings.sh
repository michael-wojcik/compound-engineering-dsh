#!/usr/bin/env bash
# Deeper binding audit: checks that could falsify "every dispatch reaches the
# Agent Teams binding". Complements check-coverage.sh, which only asks whether a
# skill carries a pointer somewhere.
#
# 1. Completeness  — every file that discusses DeepSeek Harness routes to the adapter.
# 2. Placement     — the binding precedes the file's first launch instruction.
# 3. Variant fit   — exception texts sit on genuinely cross-model or tier sites.
# 4. Internal      — the adapter's references resolve and nothing cites a removed file.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
ADAPTER="$REPO_ROOT/dsh/skills/ce-dsh-host"
fails=0

STANDARD='every agent this file dispatches is spawned'
REVIEWER='every reviewer below is spawned'
ANALYZER='each analyzer is spawned'
SHORT='this dispatch is an Agent Teams teammate'
PEER='reach this peer through an Agent Teams teammate'
TIER='a dispatch whose model does not actually differ'
LAUNCH_RE='(spawn|dispatch|launch|delegate)[a-z]* ((a|an|the|each|one|its|every|two|both) )?([a-z][a-z-]* ){0,3}(sub-?agent|agent|reviewer|analyst|researcher|historian|leaf|leaves|peer|worker|scout|candidate|baker|validator)'
# The negation must sit next to the verb. Matching it anywhere on the line hid a
# real launch ("spawn a lightweight sub-agent ... without a full review").
NEGATE_RE='(do not|don.t|never|without|rather than|instead of|temptation to|no subagents|skips)[a-z ]{0,12}(spawn|dispatch|launch|delegate)'

echo "1. COMPLETENESS — every file discussing DeepSeek Harness routes to the adapter"
count=0
completeness_fails=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  count=$((count + 1))
  if ! grep -q "ce-dsh-host" "$f"; then
    echo "   FAIL: ${f#"$REPO_ROOT"/} discusses DSH without naming the binding"
    completeness_fails=$((completeness_fails + 1))
  fi
done < <(grep -rl "DeepSeek Harness" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort)
fails=$((fails + completeness_fails))
[[ "$completeness_fails" -eq 0 ]] && echo "   ok: all $count files that mention DSH name the binding"

echo
echo "2. PLACEMENT — binding precedes the file's first launch instruction (candidates for review)"
misplaced=0
checked=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  pline="$(grep -n "ce-dsh-host" "$f" 2>/dev/null | head -1 | cut -d: -f1)"
  lline="$(grep -nE "$LAUNCH_RE" "$f" 2>/dev/null | grep -vEi "$NEGATE_RE" | head -1 | cut -d: -f1)"
  [[ -n "$pline" && -n "$lline" ]] || continue
  checked=$((checked + 1))
  if [[ "$pline" -gt "$lline" ]]; then
    echo "   REVIEW: ${f#"$REPO_ROOT"/} — binding at line $pline, earlier candidate at line $lline"
    sed -n "${lline}p" "$f" | cut -c1-110 | sed 's/^/           /'
    misplaced=$((misplaced + 1))
  fi
done < <(grep -rl "ce-dsh-host" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort)
echo "   $checked files carry both; $misplaced candidate(s) to judge (a descriptive mention is not a launch)"

echo
echo "3. VARIANT FIT — exception texts sit on exception sites"
peer_files="$(grep -rl "$PEER" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)"
tier_files="$(grep -rl "$TIER" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)"
misfit=0
for f in $peer_files $tier_files; do
  if ! grep -qiE "cross-model|provider|model (tier|override|selection)|elevat" "$f"; then
    echo "   FAIL: ${f#"$REPO_ROOT"/} carries an exception binding but never discusses models"
    misfit=$((misfit + 1))
  fi
done
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  grep -q "$PEER\|$TIER" "$f" && continue
  # Only a file whose own heading is about cross-model should not carry the plain binding;
  # a reviewer file that merely mentions the peer is fine, since the peer has its own bound site.
  if grep -qiE "^#+ .*cross-model" "$f" && grep -qE "$STANDARD|$SHORT|$REVIEWER|$ANALYZER" "$f"; then
    echo "   REVIEW: ${f#"$REPO_ROOT"/} is titled cross-model but carries the plain teammate binding"
  fi
done < <(grep -rl "ce-dsh-host" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort)
fails=$((fails + misfit))
[[ "$misfit" -eq 0 ]] && echo "   ok: peer bindings $(printf '%s\n' $peer_files | grep -c .), tier bindings $(printf '%s\n' $tier_files | grep -c .), each on a model-discussing file"

echo
echo "4. INTERNAL CONSISTENCY"
stale="$(grep -rn "reviewer-fanout" "$SKILLS_DIR" "$ADAPTER" 2>/dev/null || true)"
if [[ -z "$stale" ]]; then
  echo "   ok: nothing cites the removed reviewer-fanout reference"
else
  echo "   FAIL: stale reference:"; printf '%s\n' "$stale" | sed 's/^/     /'; fails=$((fails + 1))
fi
missing=0
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ -f "$ADAPTER/$ref" ]] || { echo "   FAIL: adapter cites missing $ref"; missing=$((missing + 1)); }
done < <(grep -oE 'references/[a-z-]+\.md' "$ADAPTER/SKILL.md" 2>/dev/null | sort -u)
fails=$((fails + missing))
[[ "$missing" -eq 0 ]] && echo "   ok: every reference the adapter names resolves"

echo
echo "5. CONSUMER LIST — the adapter names exactly the skills that carry a binding"
claimed="$(sed -n '/Consumers are the CE skills that carry a binding/,/audit-bindings.sh/p' "$ADAPTER/SKILL.md" | grep -oE '`(ce-[a-z-]+|lfg)`' | tr -d '`' | sort -u)"
actual="$(for d in "$SKILLS_DIR"/*/; do n="$(basename "$d")"; grep -rq 'ce-dsh-host' "$d" 2>/dev/null && echo "$n"; done | sort -u)"
if [[ "$claimed" == "$actual" ]]; then
  echo "   ok: $(printf '%s\n' "$actual" | grep -c .) skills claimed and bound, and no others"
else
  echo "   FAIL: the adapter's consumer list disagrees with the tree (claimed vs bound):"
  diff <(printf '%s\n' "$claimed") <(printf '%s\n' "$actual") | sed 's/^/     /'
  fails=$((fails + 1))
fi

echo
echo "files carrying a binding: $(grep -rl 'ce-dsh-host' "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
echo "audit failures: $fails"
exit "$fails"
