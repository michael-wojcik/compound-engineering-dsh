#!/usr/bin/env bash
# Deeper binding audit: checks that could falsify "every dispatch reaches the
# Agent Teams binding". Complements check-coverage.sh, which only asks whether a
# skill carries a pointer somewhere.
#
# 1. Completeness  — every file that discusses DeepSeek Harness routes to the adapter.
# 2. Placement     — the binding precedes the file's first launch instruction.
# 3. Variant fit   — exception texts sit on genuinely cross-model or tier sites.
# 4. Internal      — the adapter's references resolve and nothing cites a removed file.
# 5. Consumer list — the adapter names exactly the skills that carry bindings.
# 6. Vacuous       — no positive dispatch binding in a file that launches nothing.
# 7. Documented    — the counts verification.md quotes match this tree. A number
#                    restated in prose went stale twice (the launcher pattern and
#                    a rebase each moved it), so it is checked rather than trusted.
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
  lline="$(grep -niE "$LAUNCH_RE" "$f" 2>/dev/null | grep -vEi "$NEGATE_RE" | head -1 | cut -d: -f1)"
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
# Read the file list line-wise and deduplicated: an unquoted $peer_files $tier_files
# word-split on spaces and visited a file carrying both variants twice, so one misfit
# could count as two. Counts are computed from the tree, not from the string.
misfit=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if ! grep -qiE "cross-model|provider|model (tier|override|selection)|elevat" "$f"; then
    echo "   FAIL: ${f#"$REPO_ROOT"/} carries an exception binding but never discusses models"
    misfit=$((misfit + 1))
  fi
done < <(grep -rlE "$PEER|$TIER" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort -u)
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
[[ "$misfit" -eq 0 ]] && echo "   ok: peer bindings $(grep -rl "$PEER" "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' '), tier bindings $(grep -rl "$TIER" "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' '), each on a model-discussing file"

echo
echo "4. INTERNAL CONSISTENCY"
# An absent adapter would make every check below pass by having nothing to read, so
# say so instead of reporting green over a directory that is not there.
if [[ ! -r "$ADAPTER/SKILL.md" ]]; then
  echo "   FAIL: adapter SKILL.md is not readable at $ADAPTER — sections 4 and 5 read nothing"
  fails=$((fails + 1))
fi
stale="$(grep -rn "reviewer-fanout" "$SKILLS_DIR" "$ADAPTER" 2>/dev/null || true)"
if [[ -z "$stale" ]]; then
  echo "   ok: nothing cites the removed reviewer-fanout reference"
else
  echo "   FAIL: stale reference:"; printf '%s\n' "$stale" | sed 's/^/     /'; fails=$((fails + 1))
fi
missing=0
# Allow digits and nested paths: 'references/[a-z-]+\.md' never checked a citation
# like references/step-2.md or references/agents/x.md, so those resolved by default.
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ -f "$ADAPTER/$ref" ]] || { echo "   FAIL: adapter cites missing $ref"; missing=$((missing + 1)); }
done < <(grep -oE 'references/[A-Za-z0-9_/-]+\.md' "$ADAPTER/SKILL.md" 2>/dev/null | sort -u)
fails=$((fails + missing))
[[ "$missing" -eq 0 ]] && echo "   ok: every reference the adapter names resolves"

echo
echo "5. CONSUMER LIST — the adapter names exactly the skills that carry a binding"
claimed="$(grep -F 'Consumers are the CE skills that carry a binding' "$ADAPTER/SKILL.md" \
  | sed 's/.*Consumers are the CE skills that carry a binding//; s/\. [A-Z].*//' \
  | grep -oE '`(ce-[a-z-]+|lfg)`' | tr -d '`' | sort -u)"
# The list is a sentence on one long line. A sed range whose end anchor also matched
# that line ran to EOF and absorbed skill names from unrelated prose, so deleting a
# consumer from the list still produced a passing comparison.
actual="$(for d in "$SKILLS_DIR"/*/; do n="$(basename "$d")"; grep -rq 'ce-dsh-host' "$d" 2>/dev/null && echo "$n"; done | sort -u)"
if [[ "$claimed" == "$actual" ]]; then
  echo "   ok: $(printf '%s\n' "$actual" | grep -c .) skills claimed and bound, and no others"
else
  echo "   FAIL: the adapter's consumer list disagrees with the tree (claimed vs bound):"
  diff <(printf '%s\n' "$claimed") <(printf '%s\n' "$actual") | sed 's/^/     /'
  fails=$((fails + 1))
fi

echo
echo "6. VACUOUS BINDINGS — a positive dispatch binding in a file with no launch instruction"
vacuous=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  grep -qE "$STANDARD|$REVIEWER|$ANALYZER|$SHORT" "$f" || continue
  # Same negation filter check 2 applies: a file whose only dispatch text is a
  # prohibition ("never spawn a subagent") launches nothing and is still vacuous.
  if ! grep -niE "$LAUNCH_RE" "$f" | grep -qvEi "$NEGATE_RE"; then
    echo "   FAIL: ${f#"$REPO_ROOT"/} says \"every agent this file dispatches\" but launches nothing"
    vacuous=$((vacuous + 1))
  fi
done < <(grep -rl "ce-dsh-host" "$SKILLS_DIR" --include="*.md" 2>/dev/null | sort)
fails=$((fails + vacuous))
[[ "$vacuous" -eq 0 ]] && echo "   ok: every positive dispatch binding sits in a file that launches an agent"

echo
echo "7. DOCUMENTED COUNTS — the numbers verification.md quotes match this tree"
stale=0
# Capture the gate's output and its status. Piping straight into sed discarded the
# exit code, so a red skill-level gate still audited green here.
coverage_out="$(bash "$REPO_ROOT/dsh/check-coverage.sh" 2>&1)"
coverage_rc=$?
if [[ "$coverage_rc" -ne 0 ]]; then
  echo "   FAIL: check-coverage.sh exited $coverage_rc — the skill-level gate is red, so its counts are not a pass"
  stale=$((stale + 1))
fi
actual_launch="$(printf '%s\n' "$coverage_out" | sed -n 's/.*unbound launch sites: \([0-9][0-9]*\).*/\1/p' | tail -1)"
actual_files="$(grep -rl 'ce-dsh-host' "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
doc_launch="$(sed -n 's/.*no in-file pointer[^0-9]*\([0-9][0-9]*\) at this revision.*/\1/p' "$REPO_ROOT/dsh/verification.md" | head -1)"
doc_files="$(sed -n 's/.*\*\*\([0-9][0-9]*\) files carry a binding\*\*.*/\1/p' "$REPO_ROOT/dsh/verification.md" | head -1)"
if [[ -z "$doc_launch" || -z "$doc_files" ]]; then
  echo "   REVIEW: verification.md no longer quotes both counts, so this check cannot compare them"
  stale=$((stale + 1))
else
  [[ "$doc_launch" == "$actual_launch" ]] || {
    echo "   MISMATCH: verification.md says $doc_launch unbound launch sites, check-coverage.sh says $actual_launch"
    stale=$((stale + 1))
  }
  [[ "$doc_files" == "$actual_files" ]] || {
    echo "   MISMATCH: verification.md says $doc_files files carry a binding, the tree has $actual_files"
    stale=$((stale + 1))
  }
fi
[[ "$stale" -eq 0 ]] && echo "   ok: the record quotes $actual_launch unbound launch sites and $actual_files binding files"

fails=$((fails + stale))

echo
echo "files carrying a binding: $(grep -rl 'ce-dsh-host' "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
echo "audit failures: $fails"
exit "$fails"
