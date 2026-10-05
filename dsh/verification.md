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

## 1b. Live acceptance run (the binding, executed)

The static audits cannot show that a CE skill actually reaches for the binding. This run does, in a live session.

**Setup.** `dsh/install.sh --project` linked all 37 bundles into `<workspace>/.dsh/skills`. The session's skill catalog hot-refreshed within one step and listed all 36 CE skills plus `ce-dsh-host`, each with its description intact.

**The chain, observed in order:**

| Step | What happened |
|---|---|
| `skill(ce-code-review)` | Loaded through the real skill tool from the installed tree, with `Base directory for this skill: …/.dsh/skills/ce-code-review` |
| Stage 4 | `references/dispatch-reviewers.md` line 3 carried the split binding, which orders the reader to load `ce-dsh-host` |
| `skill(ce-dsh-host)` | Loaded through the same tool, from the same installed tree — the routing works as written |
| Dispatch | Two shared tasks created; two teammates spawned (`ce-review-correctness-live1`, `ce-review-standards-live1`) with persona, scope-rule, diff, and artifact paths in the brief |
| Collection | Repeated bounded `wait_agent` calls. It woke on shared-board changes (a claim) and on mailbox messages, exactly as the protocol describes; the correctness reviewer's compact return arrived before its artifact, the standards reviewer's after |
| Collection | Both teammates claimed their task, wrote their artifact (`correctness.json` 10,260 bytes, `project-standards.json` 14,280 bytes), completed the task, and sent one compact-JSON message each |
| Terminal | Both tasks `completed`; every launch collected in the turn that made it |

**It found real defects — in the commit under review.** Six findings across the two reviewers, every `evidence[0]` verified verbatim, and the top finding was reached independently by both:

- **P2, corroborated twice** — the `ce-sweep` binding seeded analyzers with persona *content* while the adapter it points at said "pass paths, not file contents"; the two cannot both be satisfied. Fixed by scoping the adapter's rule to what the calling skill's own template does.
- **P3** — the README asserted a universal fallback clause and denied it in the same sentence; measured 44 of 62. Fixed.
- **P3** — `verification.md` both misdescribed which 18 bindings lack the clause and still quoted a stale 46. Fixed.
- **P3** — the README's "the only dispatch that leaves the teammate rung" survived the identical fix applied to `primitive-map.md`, and the same overstatement sat in the adapter's `SKILL.md` and `primitive-map.md`. All three fixed.

**Stages 5 and 6 then ran the same way.** A merge leaf was dispatched as a teammate, claimed its shared task, folded the two reviewer artifacts into `merged.json` — 6 raw findings into 5 distinct, with the ce-sweep P2 both reviewers reached independently recorded as one finding carrying both reviewer names — and reported. A report leaf then rendered `report.md` (18.9 KB) per its contract: ASCII tables, findings ordered by severity then confidence, the coverage limits the merge recorded, and an explicit note that no adversarial peer ran, so cross-reviewer agreement on the top finding is not cross-model corroboration. It also flagged that the tree had moved past the reviewed revision and re-checked the line-anchored findings before acting.

**Not exercised:** the validator leaf that sits between merge and report, and the non-Lead fallback path (a CE skill executing inside a dispatched agent). The second-provider model override cannot be exercised here at all — this profile configures one provider — and the external-CLI peer route is unavailable because the CLIs on this machine fail to authenticate.

## 1c. Mirror fidelity: the fork versus upstream

The objective has two halves, and this is the first: that the DSH skills still *are* the original plugin's skills. Measured against `upstream/main`, the entire divergence is:

| | |
|---|---|
| Files deleted or renamed | **0** |
| Upstream lines modified or removed | **0** |
| Lines added across `skills/` | **136**, across 62 files |
| Non-plugin divergence | the `dsh/` tree only — the adapter skill, the three scripts, `README.md`, `verification.md` |
| Untouched | every manifest, `src/`, `tests/`, the plugin `README.md`, the marketplace catalogs, and all 36 `SKILL.md` files except two that took a standalone paragraph |

Every upstream instruction is byte-identical: the fork adds binding paragraphs and changes no original sentence. The two files whose line counts moved are `ce-doc-review/references/dispatch.md` and `ce-explain/SKILL.md`, and in both the binding was first written *into* the upstream sentence and then moved out to its own paragraph, precisely so this table could read zero modified lines rather than two.

The fork is rebased on `upstream/main` (`030188b4`, 0 commits behind). Its base changed once during this work: the earlier base predated upstream's test-loop repair, which is why the `TimeoutError` failures recorded in section 3 appeared at all.

## 2. Coverage of the binding

`dsh/check-coverage.sh` reports two levels: skill level is a gate, file level is evidence for review.

- **Skill level: 36 skills scanned, 0 gaps.** Every skill that stages a dispatch carries the binding somewhere.
- **62 files carry a binding**, in the variants `dsh/check-coverage.sh` reports; the adapter's consumer list names the 21 skills they belong to, and `dsh/audit-bindings.sh` fails when that list and the tree disagree. Earlier rounds of this document quoted 26, then 41, then 46 — each was an under-count produced by a tool defect recorded in §2b and §2d, which is why the counts now live in the scripts rather than here.
- **File level: 19 files still match dispatch language with no in-file pointer, and none is an unbound launch site.** Two are prompt templates a spawned agent receives; three are `SKILL.md` files that route to a bound reference; one is the `ce-babysit-pr` detector, which is a process rather than a subagent; the rest state a cap, a precondition, or analyze a past dispatch rather than issuing one. The script prints this list on every run so the judgement is re-checked rather than assumed.
- The check is a heuristic, and an earlier narrow version of it was wrong. It reported "0 unbound" while `ce-retune` required two waves to run as separate dispatched agents and `ce-simplify-code` dispatched three reviewers from its `SKILL.md` — neither carried a pointer. The pattern is now deliberately broad, and the script prints its own false positives instead of hiding them behind a single number.
- Four files were deliberately not edited, and each is correct: `ce-compound/references/lightweight.md` (the mode launches no subagents at all), `ce-doc-review/references/subagent-template.md` and `ce-optimize/references/experiment-prompt-template.md` (prompt payloads a spawned agent receives, not launch instructions), and `ce-brainstorm/references/model-tiers.md` (tier policy for dispatches staged elsewhere — closed instead by binding `ce-brainstorm/references/dialogue.md`, the file that dispatches).

On the `SKILL.md` byte budget: bindings went into `references/` wherever the repository's layout allowed. Three `SKILL.md` files took a short-form pointer and stay under Codex's 8000-byte bound — `ce-bakeoff` (7705), `ce-resolve-pr-feedback` (6859), `ce-simplify-code` (6989). `ce-explain` was already over that bound and inside the repository's own ratchet set before this change; its one dispatch site took a short-form clause and it stays in that set at 8785 bytes, which the guard tolerates because membership is a set rather than a size pin.

## 2b. Deep audit of the bindings

`dsh/audit-bindings.sh` asks four questions that `check-coverage.sh` cannot, each chosen because it could falsify the integration rather than restate it:

| Check | Result |
|---|---|
| Does every file that discusses DeepSeek Harness route to the adapter? | 62 files mention DSH; all 62 name `ce-dsh-host` (46 at the time this check first ran). This found one real gap: `ce-babysit-pr/references/watch-loop.md` gained a DSH table row but never routed, so the watch's own reference was unreachable from it. |
| Does each binding precede its file's first launch instruction? | 14 files carry both. Four candidates were raised and all four are descriptive lines, not launches: "The elevated steps: …" (×2), the definition of "dispatch context", and a "before dispatching subagents" precondition. |
| Do the exception texts sit on exception sites? | 5 peer bindings and 3 tier bindings, each on a file that discusses models. One further flag is a false positive: `dispatch-reviewers.md` has a *subsection* on the cross-model pass while its own dispatch is the local batch, and the peer's files carry the exception binding. |
| Does the adapter's own material resolve? | No citation of the removed `reviewer-fanout` reference; every `references/` file named by the adapter exists. |

The audit also found a defect in the earlier shape of `execution-engines.md`: the DeepSeek Harness paragraph sat *after* the engine table that describes the subagent primitive, so the mechanism was read before the binding. It now precedes the table.

Every check in this repository is heuristic, and two of them were wrong before this round — `check-coverage.sh` under-reported, and the first version of `audit-bindings.sh` aborted silently on a `pipefail` interaction and printed nothing after its second heading. Both now print their candidates for judgement rather than a single number.

## 2c. Independent adversarial verification

Every check above is one I wrote, so a third round ran the claim past readers with no stake in it: three verifiers were given the skills and the instruction to falsify "every launch reaches the binding", reporting only what they could cite at `file:line`. Two returned; one returned nothing and its run settled without delivering, so the independent leg is two-thirds complete, and the one that mattered most covered the six highest-risk skills synchronously.

**The claim was falsified.** What the verifiers found, and what my own gates had missed:

| Finding | Why the gates missed it | Disposition |
|---|---|---|
| `ce-code-review/references/scope.md:39` spawns a lightweight sub-agent at Stage 1, before any bound file on that path — and prescribes a model override | The launch pattern required the agent noun adjacent to the verb, so "spawn a lightweight sub-agent" never matched; the line-level negation filter also discarded it | Bound with the split rule |
| `ce-plan/references/universal-planning.md:41` dispatches on the non-software route, which skips every software-phase binding in that skill | Coverage is judged per skill, and this skill has three bindings elsewhere — all on the route that gets skipped | Bound at the head of the file |
| Five files mandate a per-agent model override on the very dispatch they bind (`dispatch-reviewers.md`, `orchestration.md`, `corpus-audit.md`, `judging.md`, `ce-bakeoff/SKILL.md`) | The variant check asked whether a file discusses models, not whether it *requires* an override for the same dispatch | Plain binding replaced by the split |
| The cross-model peer sites define the peer as a detached CLI job with a job id, reaping, and a `peer.outcome` contract | I had reasoned that a teammate can host a CLI peer; the verifiers showed the job-id contract has no referent if a teammate is the carrier | Binding rewritten: the peer is not a subagent dispatch, and the teammate protocol governs only subagent work on that path |
| `ce-brainstorm/references/dialogue.md` requires in-turn collection, but its scout deliberately runs across the user's think-time | The contradiction is between two files I wrote | Tailored binding plus a named exception in the protocol |
| `ce-optimize/references/loop.md` binds a file that also stages a `codex exec` shell pipeline | Same reasoning error as the peer sites | Binding now separates the subagent dispatch from the pipeline |

Two defects in the auditing tools themselves, both of which would have hidden the above indefinitely, are fixed: a launch pattern that required the agent noun adjacent to the verb, and a negation filter that discarded an entire line when it contained any negation anywhere.

## 2d. Third audit round: the task surface, and a case-sensitivity bug

The question "is `/lfg` using Agent Teams?" produced the most useful result of any round, and it was not about dispatch at all.

`/lfg` launches no agent: its eleven files contain zero launch instructions. It resolves and invokes other CE skills, and each of those carries its own binding — so a live run does use teammates, through its callees. The adapter had claimed `lfg` as a consumer, which was the inverse error; that is fixed and guarded.

What the question exposed is that the **task surface** had never been audited. CE skills say "use the platform's task-tracking capability" and, on Claude Code, name `TaskCreate` / `TaskUpdate` / `TaskList` — tools that do not exist here. Eleven sites across ten skills prescribed it with no binding. The adapter now separates the two mechanisms (`todo_write` for the session's user-visible list, `team_task_*` for teammates' work items, and why mixing them loses either the board's wake behaviour or the user-visible view), and all eleven sites carry the mapping.

The independent verifier that did report found two further unbound launch sites — `ce-retune/references/cut-passes.md` (the Phase 4 per-unit dispatch, reached from `SKILL.md:40`) and `ce-ideate/references/post-ideation-workflow.md` plus `universal-ideation.md` (the basis verifier) — and one over-bound file, a persona prompt payload carrying a task binding it had no business carrying.

**Why they were missed is a tool defect, and the most important finding of the round.** The launch pattern was case-sensitive, so sentence-initial imperatives — "Dispatch one agent per unit", "Spawn a single subagent" — never matched anything. Both audits had been blind to the most common way CE writes a launch instruction. With `-i` added, the four files the new vacuous-binding guard flagged turn out to be genuine launch sites, and the check passes cleanly.

Two guards were added: a consumer-list check that fails when the adapter's claimed skills and the files carrying a binding disagree, and a vacuous-binding check that fails when a file claims "every agent this file dispatches" but contains no launch instruction. The coverage tool now prints every candidate line per file rather than the first, because triage by first match is what let `cut-passes.md` pass review unbound.

## 3. Repository gates

Measured on the rebased tree, against a detached worktree of `upstream/main` (`030188b4`) on the same machine.

| Gate | Result |
|---|---|
| `bun run release:validate` | passes: "0 agents, 36 skills, 0 MCP servers" — the plugin inventory is untouched |
| `bun run typecheck` | clean |
| `bun run test:skill-guards` (fast subset, 22 files) | **797 pass, 0 fail** |
| `check-coverage.sh` / `audit-bindings.sh` | exit 0, 0 skill-level gaps, 0 audit failures |
| `bun run test` (full) | fork 29 fail, pristine upstream **19 fail** — same base, same machine |

**Attribution of the ten-test difference — closed.** One was real: the `ce-optimize` em-dash guard, described below. The other nine are load flakes: `skill-eval-cell catalog`, `pi-writer`, and `session-history-scripts` pass in isolation (151 tests, 0 fail), and `ce-babysit-pr-snapshot` with `sweep-state` — the two families that appeared only in the fork's run — pass in isolation too (202 tests, 0 fail). The remaining families flake in both runs: `ce-work serial cross-model transaction` fails 20 times pristine and 22 in the fork, `ce-work unit workspace controller` 4 pristine and 8 in the fork, all with the `spawnSync`/child-exit signature the repository's `AGENTS.md` attributes to `oven-sh/bun#34069`. With the em-dash fix in, no test failure is attributable to this fork.

**A real regression this round caught.** Rebasing and running the *entire* suite found that `tests/skills/ce-optimize-decide.test.ts` rejects em dashes anywhere under the `ce-optimize` skill, and the binding paragraphs added to `loop.md` and `measurement.md` contained one. It passed on the pristine base and failed here. Both files now carry an em-dash-free binding, and that file is 81/81. The fast `test:skill-guards` subset does not include it, which is why every earlier targeted run missed it — a reminder that the subset is not the gate.

The same suite previously produced 106 failures while a reviewer fan-out ran alongside it, 79 when it ran alone on the older base, and 49 on the older base pristine. Load and base both move these numbers; only the paired comparison above is meaningful.

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
| Shipped skill files route to `ce-dsh-host` with no fallback when the load fails | **Partly fixed, and two successive claims were overstated.** 44 of the 62 bindings state the fallback. Of the 18 that do not, most are task-surface mappings and short forms, where a missing skill leaves the sentence inert; the rest are the detached-CLI peer, panel, watch, and engine-table bindings, and one (`ce-doc-review/references/dispatch.md`) states an equivalent fallback in other words. |
| The new skill points at another skill's files with skill-local path syntax | **Addressed.** The protocol resolves persona, scope, criteria, and schema paths from the calling skill's own directory. |
| The one-line addition to `ce-pov/SKILL.md` took it past Codex's 8000-byte bound | **Fixed.** The block moved into `ce-pov/references/cross-model-panel.md`; `SKILL.md` is byte-identical to upstream. |

One review round was run per recipe generation. The disposition column is the author's response, not independent confirmation. The prompt-budget regression is also a lesson about the verification itself: a targeted run of seven skill-contract files, chosen by names that looked relevant, missed a guard that measures `SKILL.md` size. Targeted subsets do not substitute for the whole gate.

## 7. Not run, or unverified

- **A teammate hosting an external CLI peer.** The binding claims this shape for cross-model work, and it is sound by construction — a teammate runs a command and reports — but it was **not exercised here**. Neither peer answered: `claude -p` produced no output within 90 seconds, and `codex exec` failed with `401 Unauthorized: Could not validate your refresh token`. Both CLIs are on PATH, so this is an authentication state, not a missing dependency. Treat the claim as designed, not demonstrated.
- **An in-harness peer on a second provider.** This installation configures one provider (`deepseek-account` / `deepseek-flash`), so the `workflow` override rung could not be exercised. This is the one dispatch the binding keeps off the teammate rung.
- **The repository's fresh-agent skill eval** (`bun run test:skill-eval-pack`) needs `claude` and `codex` working and bills those products. Skip reason: same authentication failure as above, and the behavior this fork changes is DSH dispatch, which those hosts do not exercise. The DSH-side dispatch was run directly instead — section 1.
- **A full-suite green run.** See section 3; the suite is not green on the untouched base commit in this environment.
