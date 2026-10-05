# Verification record

What was run against this fork, and what it found. Evidence for the claims in `README.md`.

## 1. Installer behavior

Run against a throwaway root. All five cases pass:

| Case | Result |
|---|---|
| `--help` mentions an install path | Prints usage, exits 0, creates nothing |
| `--global` | Links 37 skill bundles (36 upstream + `ce-dsh-host`) into `$DSH_HOME/skills` |
| `--check` on a clean root | Reports 37 `ok`, exits 0 |
| `--uninstall` with a foreign symlink present | Removes the 36 links this checkout owns, keeps the foreign one, names it on stderr |
| `--project` from a subdirectory of a repo | Resolves the nearest `.git` ancestor, matching DSH's own project-root rule, and links there |

## 2. Repository gates

- `bun run release:validate` — passes: "compound-engineering currently has 0 agents, 36 skills, and 0 MCP servers." The plugin inventory is unchanged because the binding lives outside `skills/`.
- `bun run test` — **not green on this machine, and not green on a pristine checkout either.** A detached worktree of the base commit (`9af474a7`, no changes at all) fails 49 of 4437 tests here. This tree failed 79 of 4439 before the fix recorded below.
- The failures are dominated by `spawnSync timed out or lost child-exit` inside the python3-backed skill scripts, and by `git commit -m seed` errors in test fixtures. The repository's own `AGENTS.md` names the first as a bun defect (`oven-sh/bun#34069`) and `scripts/run-tests.ts` already carries a serial re-run for exactly that signature, which did not clear them here. They are timing-sensitive: the same suite produced 106 failures when a reviewer fan-out was running alongside it and 79 when it ran alone.
- The extra failures in this tree, beyond the baseline's, sit in test files this change does not touch — `ce-babysit-pr-snapshot`, the `ce-work` unit-workspace and fixed-write-route suites, `sweep-state`, `cline-install-skills`. They pass on their own (205 pass, 0 fail across the first batch), but the unit-workspace tests each take 9–26 seconds in this environment against a 20–30 second per-test timeout, so they sit on the boundary and flake in any full parallel run — in either tree.
- The change-specific gates do pass, and they are the ones that read the files this change edits: `tests/codex-skill-prompt-budget.test.ts`, `tests/pov-skill-contract.test.ts`, `tests/skill-conventions.test.ts`, `tests/frontmatter.test.ts`, `tests/release-metadata.test.ts` — **552 pass, 0 fail**.

## 3. DSH skill discovery

Run through DSH's own `FileSystemSkillProvider` (from the installed `@deepseek-ai/dsh-skill-filesystem`), not a reimplementation:

- `$DSH_HOME/skills`: **37/37 discovered**, `complete: true`, **0 warnings**.
- Invocation policy honored: 28 model-invocable, 9 `disable-model-invocation` skills hidden from the model and reachable by `/name` only.
- `ce-dsh-host` loads with its body and a resource base pointing at its own directory, so its `references/` resolve.
- Earlier run against the unmodified upstream tree: 36/36, 0 warnings, from both the project root and the user root.

## 4. Reviewer fan-out, end to end

The recipe in `ce-dsh-host/references/reviewer-fanout.md` was executed as written, against **this fork's own adaptation diff** (526 lines), using two of CE's real personas — `adversarial-reviewer` and `project-standards-reviewer` — from `skills/ce-code-review/references/personas/`.

| Check | Result |
|---|---|
| Agents launched concurrently | 2, via `parallel()` in one `workflow` call |
| Collected in the same turn | 2/2, both non-null |
| Schema-validated returns | Yes; every finding anchored at P1–P3 with quoted evidence |
| Findings returned | 15 (9 adversarial, 6 project-standards) |
| Artifacts written by the agents | `adversarial.json` (26 KB) and `project-standards.json` (24 KB), with `why_it_matters` and full evidence arrays |
| Personas read by path | Yes — the agents read them from disk, which is what the recipe depends on |

This is the important result: the binding's central claim is not just that the call shape works, but that it produces real review. It did — including findings against the binding itself, below.

## 5. Findings against this change, and their disposition

Every finding from that run, and what happened to it:

| Finding | Disposition |
|---|---|
| Reviewers obeying CE's compact-return contract fail the recipe's own projected schema and are recorded as failed | **Fixed.** The skeleton carried `additionalProperties: false` with a partial field list, so a correct CE return would validate as a failure and read as a failed reviewer. The schema now carries every merge-tier field, and the projection tells the reader to drop `additionalProperties` and why. |
| `--help` walks into a global install, mutating `$DSH_HOME/skills` | **Fixed.** The help branch now exits. |
| `--uninstall` deletes any same-named symlink, including links it never created | **Fixed.** Removal requires the link to resolve to this checkout's own source path. |
| `--check` reports `ok` for a symlink pointing anywhere or nowhere, and always exits 0 | **Fixed.** It now distinguishes ok / stale / foreign / dangling / conflict and exits non-zero on anything but ok. |
| `--project` links into `$PWD` while DSH scans the nearest `.git` ancestor, so skills land where DSH never looks | **Fixed.** The installer resolves the project root the way DSH does. |
| The reviewer prompt drops scope mode, remote head ref, and PR context, so the remote scope can never activate | **Fixed.** The recipe now requires the calling skill's full review context. |
| The fan-out omits CE's per-persona model tiering, and the binding frames model overrides as cross-model-only | **Fixed.** The recipe passes `model` per call for tiering, and the primitive map separates tiering from cross-model. |
| Reviewer-return schema drops the merge-tier fields CE's merge consumes | **Fixed** — same defect as the first row. |
| DSH reviewer dispatch omits the `<standards-paths>` criteria mapping | **Fixed.** The recipe instructs each agent to read the criteria files its persona names, under the calling skill's directory. |
| DSH dispatch reads personas and run directories without resolving the artifact root | **Fixed.** The run directory resolves through the calling skill's artifact-root rules, so a relocated `docs_root` moves with it. |
| The only claimed execution evidence is a file the change does not contain; the README points at a missing `verification.md` | **Fixed.** This file. |
| Six shipped skill files route to `ce-dsh-host` with no fallback when the load fails | **Fixed.** The four routing sites now state the fallback; the two remaining sites are per-harness table rows that route nothing. |
| The new skill points at another skill's files with skill-local path syntax | **Addressed.** The recipe resolves persona, scope, criteria, and schema paths from the calling skill's own directory and shows them as `skillDir + "/references/..."`, so nothing is written as a path into this skill's tree. |
| *(found by the repository suite, not by the review batch)* The one-line addition to `ce-pov/SKILL.md` took it from 7831 to 8189 bytes, past Codex's 8000-byte per-SKILL.md bound, failing `tests/codex-skill-prompt-budget.test.ts` | **Fixed.** The binding moved into `ce-pov/references/cross-model-panel.md`, which the SKILL.md already routes readers to for panel work. `SKILL.md` is byte-identical to upstream again and the test passes. |

One round was run. These fixes were not re-reviewed by a second batch, so treat the disposition column as the author's response, not as independent confirmation.

The prompt-budget regression is a lesson about the verification itself: a targeted run of seven skill-contract files, chosen by the names that looked relevant, missed a guard that measures `SKILL.md` size. The full suite caught it. Targeted subsets do not substitute for the whole gate.

## 6. Not run

- **The repo's fresh-agent skill eval** (`bun run test:skill-eval-pack`, and the `--arm ab` scenario packs) needs `claude` and `codex` on `PATH` and bills those products. Skip reason: no such CLI is available in this environment, and the behavior this fork changes is DSH dispatch, which those hosts cannot exercise. The DSH-side dispatch was run directly instead — section 4.
- **Cross-model execution.** This installation has one provider configured (`deepseek-account` / `deepseek-flash`), so the override path could not be exercised end to end. The binding states the fallback and forbids presenting a same-model re-run as an independent peer.
- **Durable teammate dispatch.** `spawn_teammate` is bound in the primitive map but no CE path was converted to it, so it carries no execution evidence here.
