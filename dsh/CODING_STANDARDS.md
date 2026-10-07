# Coding Standards: `dsh/`

Review criteria for changes under `dsh/` — the DeepSeek Harness port. These add to the root `CODING_STANDARDS.md`, which still applies; they exist because that file governs plugin and CLI code, and nothing here is TypeScript.

The `dsh/` tree is a port, so it has one obligation the rest of the repository does not: **every change must stay additive against upstream.** A paragraph may be added to a file under `skills/`; an upstream line may not be edited or removed. A diff that modifies an upstream line is a defect even when the edit is an improvement, because it turns a clean rebase into a conflict and a checkable claim into an opinion.

## The gates

`check-coverage.sh`, `audit-bindings.sh`, and `install.sh` produce the evidence the port is judged by, so their own defects are the most expensive kind. Every one of the rules below exists because a review found it violated.

1. **A gate that reads nothing must not report success.** An absent skills tree, an absent adapter, or an empty list must exit non-zero and say so. A check that prints a finding and leaves the exit code alone is not a check.
2. **The exit code is the verdict, and nothing may swallow it.** Never pipe a gate into another command — `cmd | sed` discards `$?`, so a red gate audits green. Capture the output and the status separately.
3. **Output is SIGPIPE-safe.** Under `set -euo pipefail`, `printf | head` dies at 141 when the input outruns the buffer, killing the script before its summary. Use a herestring.
4. **One rule, one implementation.** When two checks must agree on a predicate — what counts as a launch instruction, what a negation looks like — define it once and call it. Two copies of one rule drift, and the drift is silent.
5. **A number restated in prose is a claim, and claims are checked.** Any count printed in `verification.md` must be compared against the tool that produces it. The count is a property of the tool and the base together, so a copy of it is wrong the moment either moves.
6. **`set -e` is opt-in, and omitting it is documented.** When a script reads the non-zero status of a command on purpose, say so at the `set` line and name the sites. Otherwise the next consistency edit adds `-e` and breaks them.
7. **Every gate is falsifiable.** A check ships with the perturbation that makes it fail — a dropped consumer, a red upstream gate, an inflated count — demonstrated once, not asserted. A guard nobody has seen fail is a guard nobody knows works.
8. **Windows matter in the regexes.** The launcher patterns are deliberately case-insensitive, line-oriented, and negation-aware. Widening one changes which files are reported; that is a behaviour change requiring the documented counts to move in the same commit.

## The adapter

`skills/ce-dsh-host/` states how Compound Engineering dispatches on this harness.

9. **Claims about the harness are sourced.** A statement about what a tool does cites the implementation, the package documentation, or an executed observation — never the tool list. A tool surface tells you what you can call, not what the system means, and every wrong claim this port has shipped came from inferring one from the other.
10. **Presence is not permission.** Lead-only tools appear in a dispatched agent's schema. Any rule that tests capability must test the caller's role, not the tool's visibility.
11. **Native and fallback ladders stay separate.** Transient capacity is retried; terminal capacity is not — it takes the next rung and discloses the substitution. One rejection must never be read as the other.
12. **Every binding states its fallback.** A binding that names `ce-dsh-host` also says what to do when the skill is not installed, so an uninstalled adapter degrades to the host-neutral text instead of a dangling reference.

## Reviewing a change here

Read this file, then read the diff against `upstream/main` rather than against the previous commit — additivity is a property of the fork, not of the last change. Report a finding as the condition it violates and the counter-example that shows it violated; a finding with no perturbation is a preference.
