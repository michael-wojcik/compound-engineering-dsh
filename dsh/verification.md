# Verification record

What was run against this fork, and what it found. Evidence for the claims in `README.md`.

## 1. Teammate dispatch, end to end

The protocol in `ce-dsh-host/references/dispatch-protocol.md` was executed before it was written down, not after. Every mechanic it prescribes was observed:

| Mechanic | Observed |
|---|---|
| `spawn_teammate` runs agents concurrently | Two persona reviewers spawned together, both running at once |
| A teammate reads its own persona and inputs from disk | Both read their persona file and the staged diff by path; the artifacts quote the diff lines verbatim |
| A teammate writes the artifact | `security.json` (3,975 bytes) and `testing.json` (2,749 bytes), each with `reviewer`, `findings`, `residual_risks`, `testing_gaps` |
| A teammate returns a compact report by message | Each sent exactly one JSON message to the lead, which arrived in the orchestrator's context |
| `wait_agent` collects the batch | One return per report; nothing was collected from a launch acknowledgement |
| The shared task board is real and teammate-visible | A teammate listed a task, claimed it (`ownerName` recorded), wrote its deliverable, and completed it — revision 3, status `completed` |
| `wait_agent` wakes on board changes | The claim/complete sequence produced wakes, not only messages |
| Terminal condition | Once nothing was running, `wait_agent` returned `noProgress` with reason `no-active-peer` immediately — the signal that any uncollected dispatch is failed |
| Name uniqueness | A second spawn of an existing teammate name was rejected outright, so names carry a per-run suffix |
| `write_scopes` are workspace-relative | A scope pointing outside the workspace was rejected; an out-of-workspace artifact path cannot be declared as a scope |

The review produced real findings, not placeholders: a P0 IDOR (`req.query.user_id` read with no ownership check, evidence quoting the added line), plus P1/P2 testing gaps for the untested new path.

## 2. Coverage of the binding

`dsh/check-coverage.sh` reports two levels: skill level is a gate, file level is evidence for review.

- **Skill level: 36 skills scanned, 0 gaps.** Every skill that stages a dispatch carries the binding somewhere.
- **41 binding sites**, in six variants matched to what the site does: 28 standard (a same-model dispatch), 2 for the reviewer and analyzer batches that name their own agents, 5 cross-model peer sites, 3 per-agent model-tier sites, and 3 short-form sites inside `SKILL.md` files where bytes are tight.
- **File level: 19 files still match dispatch language with no in-file pointer, and none is an unbound launch site.** Two are prompt templates a spawned agent receives; three are `SKILL.md` files that route to a bound reference; one is the `ce-babysit-pr` detector, which is a process rather than a subagent; the rest state a cap, a precondition, or analyze a past dispatch rather than issuing one. The script prints this list on every run so the judgement is re-checked rather than assumed.
- The check is a heuristic, and an earlier narrow version of it was wrong. It reported "0 unbound" while `ce-retune` required two waves to run as separate dispatched agents and `ce-simplify-code` dispatched three reviewers from its `SKILL.md` — neither carried a pointer. The pattern is now deliberately broad, and the script prints its own false positives instead of hiding them behind a single number.
- Four files were deliberately not edited, and each is correct: `ce-compound/references/lightweight.md` (the mode launches no subagents at all), `ce-doc-review/references/subagent-template.md` and `ce-optimize/references/experiment-prompt-template.md` (prompt payloads a spawned agent receives, not launch instructions), and `ce-brainstorm/references/model-tiers.md` (tier policy for dispatches staged elsewhere — closed instead by binding `ce-brainstorm/references/dialogue.md`, the file that dispatches).

On the `SKILL.md` byte budget: bindings went into `references/` wherever the repository's layout allowed. Three `SKILL.md` files took a short-form pointer and stay under Codex's 8000-byte bound — `ce-bakeoff` (7705), `ce-resolve-pr-feedback` (6859), `ce-simplify-code` (6989). `ce-explain` was already over that bound and inside the repository's own ratchet set before this change; its one dispatch site took a short-form clause and it stays in that set at 8785 bytes, which the guard tolerates because membership is a set rather than a size pin.

## 3. Repository gates

- `bun run release:validate` — passes: "0 agents, 36 skills, 0 MCP servers". The plugin inventory is untouched because the binding lives outside `skills/`.
- The change-specific guards — `codex-skill-prompt-budget`, `skill-conventions`, `review-skill-contract`, `frontmatter`, `pov-skill-contract`, `release-metadata`, `ce-babysit-pr-contract`, `skill-shell-safety`: **714 pass, 0 fail**.
- `bun run test` in full — **not green on this machine, and not green on a pristine checkout either.** A detached worktree of the base commit (`9af474a7`, no changes) fails 49 of 4437 tests here. The failures are dominated by `spawnSync timed out or lost child-exit` inside the python3-backed skill scripts and by fixture `git commit` errors; the repository's own `AGENTS.md` names the first as a bun defect (`oven-sh/bun#34069`), and its serial re-run for that signature did not clear them. The extra failures over baseline sit in files this change does not touch and pass on their own, though the `ce-work` unit-workspace tests take 9–26 seconds each against a 20–30 second timeout, so they sit on the boundary. Details: the same suite produced 106 failures while a reviewer fan-out ran alongside it and 79 when it ran alone.

## 4. Installer behavior

Run against a throwaway root. All five cases pass:

| Case | Result |
|---|---|
| `--help` mentions an install path | Prints usage, exits 0, creates nothing |
| `--global` | Links 37 bundles (36 upstream + `ce-dsh-host`) |
| `--check` on a clean root | 37 `ok`, exit 0 |
| `--uninstall` with a foreign symlink present | Removes only the links this checkout owns, keeps and names the foreign one |
| `--project` from a repo subdirectory | Resolves the nearest `.git` ancestor, matching DSH's own project-root rule |

## 5. DSH skill discovery

Through DSH's own `FileSystemSkillProvider`, not a reimplementation: **37/37 discovered**, `complete: true`, **0 warnings**; 28 model-invocable and 9 `disable-model-invocation`; `ce-dsh-host` loads with its body and a resource base pointing at its own directory.

## 6. Findings against this change, and their disposition

Every finding from the review runs, and what happened to it.

| Finding | Disposition |
|---|---|
| Reviewers obeying CE's compact-return contract fail the recipe's projected schema and are recorded as failed | **Fixed.** The skeleton carried `additionalProperties: false` with a partial field list, so a correct CE return validated as a failure and read as a failed reviewer. The fallback rung now carries every merge-tier field and tells the reader to drop `additionalProperties` and why. |
| `--help` walks into a global install | **Fixed.** The help branch exits. |
| `--uninstall` deletes any same-named symlink | **Fixed.** Removal requires the link to resolve to this checkout's own source path. |
| `--check` reports `ok` for a symlink pointing anywhere or nowhere, and always exits 0 | **Fixed.** Distinguishes ok / stale / foreign / dangling / conflict, and exits non-zero otherwise. |
| `--project` links into `$PWD` while DSH scans the nearest `.git` ancestor | **Fixed.** The installer resolves the project root the way DSH does. |
| The dispatch brief drops scope mode, remote head ref, and PR context | **Fixed.** The protocol requires the calling skill's full review context. |
| The dispatch omits per-persona model tiering | **Fixed, then superseded.** Teammates take no model override, so the protocol states that tiers which must actually differ take the `workflow` rung; the pre-change recipe's `model` per call is still recorded there. |
| DSH dispatch omits the criteria mapping for personas that need one | **Fixed.** The brief instructs each agent to read the criteria files its persona names. |
| Dispatch reads personas and run directories without resolving the artifact root | **Fixed.** The run directory resolves through the calling skill's artifact-root rules. |
| The claimed execution evidence pointed at a file the change did not contain | **Fixed.** This file. |
| Shipped skill files route to `ce-dsh-host` with no fallback when the load fails | **Fixed.** Every pointer states the fallback. |
| The new skill points at another skill's files with skill-local path syntax | **Addressed.** The protocol resolves persona, scope, criteria, and schema paths from the calling skill's own directory. |
| The one-line addition to `ce-pov/SKILL.md` took it past Codex's 8000-byte bound | **Fixed.** The block moved into `ce-pov/references/cross-model-panel.md`; `SKILL.md` is byte-identical to upstream. |

One review round was run per recipe generation. The disposition column is the author's response, not independent confirmation. The prompt-budget regression is also a lesson about the verification itself: a targeted run of seven skill-contract files, chosen by names that looked relevant, missed a guard that measures `SKILL.md` size. Targeted subsets do not substitute for the whole gate.

## 7. Not run, or unverified

- **A teammate hosting an external CLI peer.** The binding claims this shape for cross-model work, and it is sound by construction — a teammate runs a command and reports — but it was **not exercised here**. Neither peer answered: `claude -p` produced no output within 90 seconds, and `codex exec` failed with `401 Unauthorized: Could not validate your refresh token`. Both CLIs are on PATH, so this is an authentication state, not a missing dependency. Treat the claim as designed, not demonstrated.
- **An in-harness peer on a second provider.** This installation configures one provider (`deepseek-account` / `deepseek-flash`), so the `workflow` override rung could not be exercised. This is the one dispatch the binding keeps off the teammate rung.
- **The repository's fresh-agent skill eval** (`bun run test:skill-eval-pack`) needs `claude` and `codex` working and bills those products. Skip reason: same authentication failure as above, and the behavior this fork changes is DSH dispatch, which those hosts do not exercise. The DSH-side dispatch was run directly instead — section 1.
- **A full-suite green run.** See section 3; the suite is not green on the untouched base commit in this environment.
