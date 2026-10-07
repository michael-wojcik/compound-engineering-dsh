#!/usr/bin/env bash
# Falsifiability harness for the dsh gates.
#
# `dsh/CODING_STANDARDS.md` rule 7 says every gate ships with the perturbation that
# makes it fail, demonstrated rather than asserted. Until this file existed, those
# demonstrations were manual notes in `verification.md`, which means a later edit
# could re-break a guard with every gate still green.
#
# Every case runs against a throwaway copy under $TMPDIR — never this checkout —
# because each perturbation writes to the tree it inspects.
#
# Run: bash dsh/selftest.sh   (exit 0 = every guard still fails when it should)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then
    printf '  ok    %-52s rc=%s\n' "$1" "$3"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-52s expected rc=%s, got %s\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

# Some perturbations trip more than one check, so the code is not the assertion —
# only that the gate refused to report success.
check_nonzero() { # <name> <actual-rc>
  if [[ "$2" != "0" ]]; then
    printf '  ok    %-52s rc=%s\n' "$1" "$2"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-52s expected a non-zero exit, got 0\n' "$1"
    fail=$((fail + 1))
  fi
}

# A throwaway repo carrying the real `skills/` and `dsh/` trees, so a case can
# perturb either without touching this checkout.
fixture() {
  local d="$1"
  mkdir -p "$d"
  cp -R "$REPO_ROOT/skills" "$d/skills"
  cp -R "$REPO_ROOT/dsh" "$d/dsh"
}

rc_of() { "$@" >/dev/null 2>&1; echo $?; }

echo "check-coverage.sh"
F="$TMP/cc"; fixture "$F"
check "unperturbed tree reports clean" 0 "$(rc_of bash "$F/dsh/check-coverage.sh")"
mv "$F/skills" "$F/skills-away"
check "absent skills tree fails loudly" 2 "$(rc_of bash "$F/dsh/check-coverage.sh")"
mv "$F/skills-away" "$F/skills"
# A new skill that stages a dispatch and carries no pointer anywhere: this is the
# skill-level gap the gate exists to catch. (Moving an existing skill's SKILL.md
# aside does NOT create one — its references still carry the binding.)
mkdir -p "$F/skills/unbound-skill"
printf '# Unbound\n\nDispatch a reviewer subagent for every unit.\n' > "$F/skills/unbound-skill/SKILL.md"
check "a dispatch site with no binding fails" 1 "$(rc_of bash "$F/dsh/check-coverage.sh")"
# The scanned-zero guard needs its own tree: adding an empty directory to a real
# tree still scans 36 skills and must stay green.
E="$TMP/empty"; mkdir -p "$E/skills/empty-skill" "$E/dsh"
cp "$REPO_ROOT/dsh/check-coverage.sh" "$E/dsh/"
check "directories without a SKILL.md fail" 2 "$(rc_of bash "$E/dsh/check-coverage.sh")"

echo
echo "audit-bindings.sh"
A="$TMP/ab"; fixture "$A"
check "unperturbed tree reports clean" 0 "$(rc_of bash "$A/dsh/audit-bindings.sh")"
sed -i '' 's/no in-file pointer — [0-9]* at this revision/no in-file pointer — 99 at this revision/' "$A/dsh/verification.md"
check "a drifted documented count fails check 7" 1 "$(rc_of bash "$A/dsh/audit-bindings.sh")"
A="$TMP/ab2"; fixture "$A"
sed -i '' 's/`ce-sweep`, //' "$A/dsh/skills/ce-dsh-host/SKILL.md"
check "a dropped consumer fails check 5" 1 "$(rc_of bash "$A/dsh/audit-bindings.sh")"
A="$TMP/ab3"; fixture "$A"
rm -rf "$A/dsh/skills/ce-dsh-host"
check_nonzero "an absent adapter fails instead of passing" "$(rc_of bash "$A/dsh/audit-bindings.sh")"

echo
echo "install.sh"
T="$TMP/target"; mkdir -p "$T"
export DSH_SKILLS_DIR="$T"
check "install links every skill" 0 "$(rc_of bash "$REPO_ROOT/dsh/install.sh")"
check "check reports the freshly linked root clean" 0 "$(rc_of bash "$REPO_ROOT/dsh/install.sh" --check)"
rm -f "$T/ce-plan"; ln -s "$REPO_ROOT/skills/../skills/ce-plan" "$T/ce-plan"
check "a correct link written with .. is not stale" 0 "$(rc_of bash "$REPO_ROOT/dsh/install.sh" --check)"
rm -f "$T/ce-plan"; ln -s /tmp/not-ours "$T/ce-plan"
check "a foreign link is refused, not replaced" 1 "$(rc_of bash "$REPO_ROOT/dsh/install.sh")"
rm -f "$T/ce-plan"
N="$TMP/notrees"; mkdir -p "$N/dsh"; cp "$REPO_ROOT/dsh/install.sh" "$N/dsh/"
DSH_SKILLS_DIR="$TMP/target2" bash "$N/dsh/install.sh" --check >/dev/null 2>&1
check "check over no skill roots fails loudly" 2 "$?"
DSH_SKILLS_DIR="$TMP/target2" bash "$N/dsh/install.sh" >/dev/null 2>&1
check "install over no skill roots fails loudly" 2 "$?"
ln -sfn "$REPO_ROOT/skills/gone-skill" "$T/gone-skill"
check "check reports a link whose skill is gone" 1 "$(rc_of bash "$REPO_ROOT/dsh/install.sh" --check)"
DSH_SKILLS_DIR="$T" bash "$REPO_ROOT/dsh/install.sh" --uninstall >/dev/null 2>&1
[[ -L "$T/gone-skill" ]] && gone=1 || gone=0
check "uninstall sweeps a link whose skill is gone" 0 "$gone"

echo
echo "selftest: $pass passed, $fail failed"
exit "$fail"
