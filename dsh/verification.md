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

**Two facts the live work established about the environment itself.** First, a non-Lead agent cannot create teammates — but the reason is annotation, not absence, and an earlier line here claimed absence until a later probe falsified it. `spawn_teammate`'s own description reads "Only the Lead may call this tool", and the tool **is** present in a dispatched agent's schema. The harness marks Lead-only explicitly where it means it — the same surface carries "Team Lead only" on `interrupt_agent` and a Lead-only `reassign` parameter on `team_task_update` — which is how the annotation is told apart from a genuinely unavailable tool. The adapter's precondition now says presence is not permission, for exactly this reason. Second, and materially: Agent Teams ships switched off, and its bundle's README states that enabling it disables ordinary `subagent` delegation while `workflow` can still create fresh children. A teammate's schema still lists `subagent` with no unavailability annotation, so that rung is recorded as unverified rather than assumed, and the ladder is given per profile.

**Stage 5b then ran, late, and earned its place.** A validator teammate was dispatched after this document had already recorded the batch as skipped — and checking the contract showed the skip was wrong: `finish-review.md` permits skipping a validator only when a finding has cross-model corroboration, and this run had no cross-model peer. Its verdicts were 1 confirmed and 4 rejected, and the four rejections are drift rather than acquittal: each cited finding had been fixed between the reviewed revision `351f2611` and validation at HEAD, which the validator states in every verdict. The one confirmation was live and is fixed above — `verification.md:77` quoted a file-level count of 19 where the script printed 23. Running this stage hours after the review is what made it mostly a drift detector; running it in sequence is what would have made it a filter.

**The nested case ran too, and it is the case the adapter only ever asserted.** Every live stage above was the Lead dispatching — the easy direction. A CE skill executing *inside* a dispatched agent is the hard one, so a teammate was given `ce-code-review` and asked to reach Stage 4's dispatch and follow the ladder without spawning. It reported back: the skill reached its dispatch step, the non-Lead rung was reachable, and it ran the reviewer work as a single `workflow` call with two concurrent agents, then verified the load-bearing claims inline — no dead end. That is the first execution rather than assertion of the fallback ladder, and it is what the adapter's `workflow`-then-inline row had been claiming on paper.

The same probe falsified two lines that had been recorded as fact. It reported `spawn_teammate` **present** in its schema, annotated "Only the Lead may call this tool" — so the earlier claim that the tool is absent from a dispatched agent's toolset does not hold for a teammate, and a precondition that tested presence was a false positive for exactly the agent it needed to catch. Both are corrected above and in the adapter. It also reported `subagent` present with no unavailability annotation, which contradicts the bundle README's statement that enabling Agent Teams disables ordinary `subagent` delegation; that rung is now recorded as unverified rather than absent. The likely reconciliation is that the earlier probe sampled a different child-creation route (a `workflow` child rather than a teammate), but that is a hypothesis, and confirming it needs a `workflow` child's own schema sampled — which has not been done.

**The `workflow` child was sampled too, and it closes the last open question about who can spawn.** A workflow child was asked to report its own tool list without invoking anything, and the answer is that it carries the **same Lead-shaped surface** as a teammate: `spawn_teammate`, `interrupt_agent`, `wait_agent`, `list_agents`, the full shared task board, plus `workflow`, `subagent`, and `todo_write` — nothing absent. Its `spawn_teammate` description is byte-identical to the teammate's, including "Only the Lead may call this tool."

That is a stronger result than it looks. Two independent non-Lead contexts — a teammate and a workflow child — now show that the tool surface is **not** a capability signal: every non-Lead agent still sees the Lead's tools, and the only thing stopping it from spawning is the role annotation. So the adapter's rule is not a heuristic that happens to work here; it is the only correct test, and the earlier claim that the tools are absent from a dispatched agent's schema was wrong for both contexts it could have been checked in.

**Not exercised:** nothing in the pipeline remains unrun — stages 4, 5b, 5, and 6 have each executed on Agent Teams, and both non-Lead contexts have now reported their own tool surface. Cross-model work is a separate case: *unavailable in this deployment* rather than untested, per section 7.

## 1c. Mirror fidelity: the fork versus upstream

The objective has two halves, and this is the first: that the DSH skills still *are* the original plugin's skills. Measured against `upstream/main`, the entire divergence is:

| | |
|---|---|
| Files deleted or renamed | **0** |
| Upstream lines modified or removed | **0** |
| Lines added across `skills/` | **140**, across 63 files |
| Non-plugin divergence | the `dsh/` tree only — the adapter skill, the three scripts, `README.md`, `verification.md` |
| Untouched | every manifest, `src/`, `tests/`, the plugin `README.md`, the marketplace catalogs, and all 36 `SKILL.md` files except two that took a standalone paragraph |

Every upstream instruction is byte-identical: the fork adds binding paragraphs and changes no original sentence. The two files whose line counts moved are `ce-doc-review/references/dispatch.md` and `ce-explain/SKILL.md`, and in both the binding was first written *into* the upstream sentence and then moved out to its own paragraph, precisely so this table could read zero modified lines rather than two.

The fork is rebased on `upstream/main` (`cef001f7`, 0 commits behind). Its base has moved three times, and the second move is the useful evidence: the first rebase (`9af474a7` → `030188b4`) picked up upstream's test-loop repair, which is why the `TimeoutError` failures recorded in section 3 appeared at all; the second (`030188b4` → `efcb657d`) was a genuine merge rather than a fast-forward, and cost five conflict resolutions across four `ce-work` files.

One binding did not survive it, and that is the right outcome. Upstream's `#1837` deleted `ce-work`'s engine-probe section outright, taking the table the `execution-engines.md` binding described with it — goal-mode and dynamic-workflow no longer exist as `ce-work` engines. The binding was retired rather than re-homed, which is why the counts above read 61 files, not 62. A binding whose referent upstream removed is worse than no binding: it would fail the vacuous-binding check in `dsh/audit-bindings.sh` and tell a reader to route dispatch through a section that is no longer there.

## 2. Coverage of the binding

`dsh/check-coverage.sh` reports two levels: skill level is a gate, file level is evidence for review.

- **Skill level: 36 skills scanned, 0 gaps.** Every skill that stages a dispatch carries the binding somewhere.
- **63 files carry a binding**, in the variants `dsh/check-coverage.sh` reports; the adapter's consumer list names the 21 skills they belong to, and `dsh/audit-bindings.sh` fails when that list and the tree disagree. Earlier rounds of this document quoted 26, then 41, then 46 — each was an under-count produced by a tool defect recorded in §2b and §2d, which is why the counts now live in the scripts rather than here.
- **File level: the coverage script lists the files that still match dispatch language with no in-file pointer — 23 at this revision — and none is an unbound launch site.** Two are prompt templates a spawned agent receives; three are `SKILL.md` files that route to a bound reference; one is the `ce-babysit-pr` detector, which is a process rather than a subagent; one is upstream's `skills/CODING_STANDARDS.md`, added in `#1840`, which *describes* what a dispatch prompt must carry ("A dispatched subagent's prompt carries every input its steps name") without ever instructing one; the rest state a cap, a precondition, or analyze a past dispatch rather than issuing one. The count has moved six times, and the reasons are worth keeping because each one was a different failure of the tool rather than of the tree — 19 to 23 when the launcher pattern was made case-insensitive (section 2d), 23 to 22 when a rebase retired a binding whose section upstream had deleted, 22 to 25 when dogfooding found that only the *skill-level* scan had been made case-insensitive, so four files with sentence-initial launch instructions could never appear at all — two of those were genuinely unbound and now carry bindings (`ce-compound/references/assembly.md`, `ce-brainstorm/references/handoff.md`), which is where 25 became 23 — 23 to 24 when a later upstream commit added a standards file that discusses dispatch, and back to 23 when the negation vocabulary was widened to recognise a prohibition on *substituting* a generic agent, which took `ce-plan/references/plan-handoff.md` off the list after it had been carried as a reviewed false positive. That last change was measured before it was made: it removes exactly one candidate and adds none. That is why `dsh/audit-bindings.sh` check 7 compares this number against the script's own output and fails on disagreement: the number is a property of the tool and the base together, so a prose copy of it is wrong the moment either moves — and it caught this change's drift on its own, before the count above was corrected.
- The check is a heuristic, and an earlier narrow version of it was wrong. It reported "0 unbound" while `ce-retune` required two waves to run as separate dispatched agents and `ce-simplify-code` dispatched three reviewers from its `SKILL.md` — neither carried a pointer. The pattern is now deliberately broad, and the script prints its own false positives instead of hiding them behind a single number.
- Four files were deliberately not edited, and each is correct: `ce-compound/references/lightweight.md` (the mode launches no subagents at all), `ce-doc-review/references/subagent-template.md` and `ce-optimize/references/experiment-prompt-template.md` (prompt payloads a spawned agent receives, not launch instructions), and `ce-brainstorm/references/model-tiers.md` (tier policy for dispatches staged elsewhere — closed instead by binding `ce-brainstorm/references/dialogue.md`, the file that dispatches).

On the `SKILL.md` byte budget: bindings went into `references/` wherever the repository's layout allowed. Three `SKILL.md` files took a short-form pointer and stay under Codex's 8000-byte bound — `ce-bakeoff` (7705), `ce-resolve-pr-feedback` (6859), `ce-simplify-code` (6989). `ce-explain` was already over that bound and inside the repository's own ratchet set before this change; its one dispatch site took a short-form clause and it stays in that set at 8785 bytes, which the guard tolerates because membership is a set rather than a size pin.

## 2b. Deep audit of the bindings

`dsh/audit-bindings.sh` asks four questions that `check-coverage.sh` cannot, each chosen because it could falsify the integration rather than restate it:

| Check | Result |
|---|---|
| Does every file that discusses DeepSeek Harness route to the adapter? | 63 files mention DSH; all 63 name `ce-dsh-host` (46 at the time this check first ran). This found one real gap: `ce-babysit-pr/references/watch-loop.md` gained a DSH table row but never routed, so the watch's own reference was unreachable from it. |
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

## 2e. Dogfooding: the plugin run on its own work

The objective asks for the current iteration to be dogfooded, so the adapted skills were used on real work rather than inspected. `ce-dogfood` itself is diff-scoped browser QA and this branch has no user-visible surface to drive, so dogfooding here meant running a CE workflow on the fork's own code.

**`ce-simplify-code`, followed as written.** Scope resolved from the branch diff with the preflight applied, which drops the sixty-odd markdown files and leaves the three shell scripts as the code. This is where the dogfood earned its keep: the natural dispatch is three reviewers as teammates, and the team's member budget is **terminal** — the roster is immutable, with no release or delete primitive anywhere in the surface. My own adapter had been calling that case backpressure and telling the reader to retry when a slot frees, which would have retried forever. The skill's own bounded-dispatch rule covers it ("when a dispatch cannot recover through active work, supported release, or a corrected invocation, run that pass inline"), and the ladder's next rung is a `workflow` batch, so the three personas were dispatched as one workflow call with 3/3 returning 15 findings. **The capacity guidance in `dispatch-protocol.md` was wrong on this point and is now corrected**: it told the reader to treat a capacity rejection as backpressure and retry when a slot frees, which for an immutable roster means retrying forever. It now separates transient capacity (retry) from terminal capacity (take the next rung, disclose the substitution).

**The claim above was inferred first and sourced second, which is worth recording.** The inference came from the tool surface — no removal tool in the Lead's schema, and the cap error named no remedy. It was later confirmed against the implementation in the application bundle: `@deepseek-ai/dsh-experimental-agent-team` documents its own limitation as a "**flat immutable roster** — only the Lead creates direct teammates; there is no nested Team, rename, deletion, or name reuse", and `interrupt_agent` "stop[s] a teammate's current turn without deleting its queued messages". Two details the inference got wrong and the source fixed: the budget is `maxMembers`, **a cumulative count of teammates the team may ever create including failed creations**, not a number of live members — 16 by default, overridden to 8 by `dsh-experimental-agent-team-profile/cordis.patch.yml` — and `disposalTimeoutMs` exists but governs shutdown cleanup, not on-demand removal. The lesson is the same one this document keeps relearning: a tool surface tells you what you can call, not what the system means.

**The budget was then raised and the raise verified, which settles the "terminal capacity" reading.** A `agent-team` entry was added to the desktop profile's patch layer with `maxMembers: 64`. Three independent checks agree it took effect. *Empirically*: the team had already created 8 teammates against a budget of 8, the roster **survived the app restart** — all eight members were still listed, which contradicts the assumption that a team is scoped to one app run — and the next creation succeeded, so the effective budget exceeded 8. *Machine-produced*: the app's own composer, reached by copying the profile under an isolated `DSH_HOME` and renaming it, since `--dump-config` refuses an app-managed profile by name, emits `agent-team.config` with `maxMembers: 64` and all four sibling keys intact. *Source-level*: replaying `applyEntryPatches` from `@deepseek-ai/dsh-app-boot` over the seven real layers yields 64 with zero skipped-patch warnings.

**One trap is worth carrying forward.** An id-targeted patch **replaces the targeted row's whole `config`** rather than merging into it — `dsh-base`'s own patch header says so, and the implementation does a shallow `target[key] = value` per override key. A lone `maxMembers: 64` would therefore have silently discarded the other four keys and let the schema defaults refill them. That happens to be harmless here, because the bundle's values for those four are the package defaults; it would not be harmless wherever a bundle sets a non-default value.

**What the reviewers found that mattered** came through the out-of-scope channel, and it falsified a claim in §2d above: the earlier case-sensitivity repair was applied to the *skill-level* scan only. Four files that match dispatch language case-insensitively could never reach the file-level evidence list, so the list was narrower than the record said. Two of them are genuine unbound launch sites and now carry bindings — `ce-compound/references/assembly.md` ("Dispatch one read-only generic subagent") and `ce-brainstorm/references/handoff.md` ("Dispatch reviewer agents with `ce-doc-review`"). The other two are correct as they stand: `ce-plan/references/plan-handoff.md`'s line is a prohibition ("Do not substitute a generic Task, Agent, or subagent") that `NEGATE_RE` does not cover, and `ce-optimize/references/judge-prompt-template.md` is a prompt asset a spawned agent receives, which is the documented carve-out. The gate prints its candidate list on every run, and its length is quoted in exactly one place — the checked count in section 2 above — so the files named here are the ones a reader can check instead of trusting a number. A second restatement of that count stood here and a reviewer found it stale within a day, which is why it is gone rather than corrected.

**Structural fixes taken from the review.** Checks 2 and 6 now share one `launch_hits()` definition — they had already drifted apart once, which is exactly the failure a second copy invites. And `audit-bindings.sh` now records why `-e` is deliberately absent from its `set` line: sections 2 and 7 both read the exit status of commands allowed to fail, so a future "consistency" edit adding `-e` would abort before section 7 could report a red gate.

**Skipped, with reasons.** The reviewers proposed roughly twenty further changes and rejected about as many themselves; the rejections are the more useful half. Merging `DISPATCH_RE` with `LAUNCH_RE` was rejected because the two are deliberately different in breadth and unifying them moves both gates' exit codes. Sharing the variant strings through a sourced file was rejected because it gives two standalone gates a new failure mode. Replacing `install.sh`'s `link_target_abs` with `readlink -f` was rejected because the current function must return a path for a dangling link. Two efficiency findings were applied in spirit but not in letter: the binding-file list is still recomputed per section rather than captured once, because capturing it couples read-only gates to a quiescent tree for about 0.35s.



## 3. Repository gates

Measured against a detached worktree of `upstream/main` (`cef001f7`, the current base) on the same machine, back to back.

| Gate | Result |
|---|---|
| `bun run release:validate` | passes: "0 agents, 36 skills, 0 MCP servers" — the plugin inventory is untouched |
| `bun run typecheck` | clean |
| `bun run test:skill-guards` (fast subset, 22 files) | **797 pass, 0 fail** |
| `check-coverage.sh` / `audit-bindings.sh` | exit 0, 0 skill-level gaps, 0 audit failures |
| `bun run test` (full) | fork **4358 pass, 81 fail**; pristine upstream **4332 pass, 105 fail** — same base, same machine, run back to back |

**The whole failure family was misdiagnosed as flakiness, and the real cause is this machine's git configuration.** Later runs failed *fast* rather than timing out, which does not fit the load signature this document had been attributing them to. Chasing one failure gave up its cause in three steps: the test's seed commit fails, a plain temp-repo commit succeeds, and reproducing the test's exact sequence shows `git add .` staging nothing. The machine's global excludes file is `~/.gitignore_global`, and its line 192 is `docs/` — so every test that seeds a temp repository containing `docs/plans/` commits an empty tree and dies. The tests are not flaky and never were; they cannot pass with this global ignore in effect.

That is decisive attribution, and it is stronger than the isolation runs it replaces. Running one family with the global config neutralised (`GIT_CONFIG_GLOBAL=/dev/null`) gives **13 pass, 0 fail** where the normal environment gives **3 pass, 10 fail**; `ce-code-review-mechanics.test.ts` goes from 2 fail to 0 the same way. In the latest full run, 18 tests failed on the fork and 14 of them are this one cause — the entire `ce-work serial cross-model transaction` family plus two `ce-code-review deterministic mechanics` cases. The rest is a `ce-packs-resolver` case that manipulates `PATH` to remove git, which fails with the global config neutralised too and is a separate environmental limit.

None of it is attributable to the fork, and the reason is structural rather than statistical: the fork changes no file those tests read. Every prose and anchor contract test passes on the fork, including the eight upstream tests that read `skills/**` — `pipeline-review-contract`, `review-skill-contract`, `user-facing-skill-invocation-rendering`, `unified-plan-artifact-contract`, `ce-work-outcome-spine`, `ce-plan-handoff-routing`, and the `ce-optimize-decide` em-dash guard. Those are the tests a binding could actually break, and none of them did.

**For anyone re-running this suite on this machine:** `GIT_CONFIG_GLOBAL=/dev/null bun run test` is the honest configuration, and it is what the numbers above should be read against. The earlier paired comparisons in this section were run with the global ignore active on *both* trees, so the comparison held — but the label "load flake" was wrong, and a deterministic environmental failure is a different thing from a flaky one.

**A real regression this round caught.** Rebasing and running the *entire* suite found that `tests/skills/ce-optimize-decide.test.ts` rejects em dashes anywhere under the `ce-optimize` skill, and the binding paragraphs added to `loop.md` and `measurement.md` contained one. It passed on the pristine base and failed here. Both files now carry an em-dash-free binding, and that file is 81/81. The fast `test:skill-guards` subset does not include it, which is why every earlier targeted run missed it — a reminder that the subset is not the gate.

The same suite previously produced 106 failures while a reviewer fan-out ran alongside it, 79 when it ran alone on the older base, and 49 on the older base pristine. Load and base both move these numbers; only the paired comparison above is meaningful.

**The gates themselves were defective, which qualifies every number above.** An adversarial probe reviewed `dsh/check-coverage.sh` and `dsh/audit-bindings.sh` — the two scripts that produce the coverage evidence this document rests on — and returned 12 findings, 7 of them P1/P2. The ones that mattered:

| Defect | Consequence | Fix |
|---|---|---|
| `check-coverage.sh` piped `printf` into `head -3` under `set -euo pipefail` | A file with more matching lines than the pipe buffer took SIGPIPE; the script died at 141 before printing its summary or its exit code, so a crash stood in for a verdict | Herestring instead of the pipe; regression-tested against a 1500-match file, which now prints its summary and exits 1 for the real gap |
| Check 6 counted `vacuous` and never added it to `fails` | The check printed `REVIEW:` and the audit exited 0 anyway | Counter now gates the exit code; the message reads `FAIL:` |
| Check 5's `sed` range had both anchors on one long line | The range ran to EOF; deleting `ce-sweep` from the adapter's consumer list still compared equal, so a dropped consumer passed the check that exists to catch it | Extracts the list from its own sentence; verified by deleting `ce-sweep`, which now fails with `rc=1` |
| Check 7 piped the coverage gate into `sed`, discarding its status | A red skill-level gate still audited green | Captures and checks the exit code |
| Missing `skills/` tree, and missing adapter | Both scripts reported green over a tree they never read | Both fail loudly instead |

**The line-oriented regex limit was measured rather than left as a caveat, and the measurement says not to fix it.** Both launcher patterns match within a line, so a dispatch instruction whose verb and object are separated by a line wrap would be invisible. That was recorded as an unacknowledged false-negative axis; it is now a number. A wrap-tolerant scan — paragraph-bounded, so a sentence cannot manufacture a match by meeting an unrelated later paragraph, and negation-aware — would add exactly **one** file to the candidate list across all 358 markdown files under `skills/`: `ce-doc-review/references/rendering-floor.md`, on the sentence "Rendering happens after a long dispatch has filled the context with reviewer returns." That is descriptive prose, not a launch instruction, so the tolerant scan would add a false positive and catch nothing real. The gates keep the line-oriented pattern, and the axis is now a measured non-issue rather than an open worry. A first, cruder measurement had said six files; it ignored the negation filter and joined across paragraph boundaries, which is exactly the error the paragraph-bounded version avoids.

The remaining five are P3: an unquoted file list that word-split and double-counted, a reference regex that skipped digits and nested paths, a header documenting 4 checks while running 7, check 6 missing check 2's negation filter, and two latent line-oriented regex limits. The first four are fixed. The line-oriented ones are recorded as limits: `DISPATCH_RE` cannot see a verb and its object split across a line wrap, so a launch site written that way would be invisible to the gate — an unacknowledged false-negative axis, stated here rather than left implicit.

This is worth stating plainly: the coverage numbers in this document were produced by scripts that had a broken consumer-list check and a crash path. The numbers are still what the scripts printed, and the fixes did not change any of them — but a reader should know the gates were audited adversarially rather than assumed sound.

## 4. Installer behavior

Run against a throwaway root. All five cases pass:

| Case | Result |
|---|---|
| `--help` mentions an install path | Prints usage, exits 0, creates nothing |
| `--global` | Links 37 bundles (36 upstream + `ce-dsh-host`) |
| `--check` on a clean root | 37 `ok`, exit 0 |
| `--uninstall` with a foreign symlink present | Removes only the links this checkout owns, keeps and names the foreign one |
| `--project` from a repo subdirectory | Resolves the nearest `.git` ancestor, matching DSH's own project-root rule |

**A review then found the installer was the least-guarded of the three scripts, and the fixes are now asserted by `dsh/selftest.sh`.** Two reviewers independently reached the same first finding: `--check` over a tree with no skill roots read nothing and exited 0, and install mode printed `linked 0 skill(s)` and exited 0 — the same vacuous-green failure already fixed in `check-coverage.sh`, still live in its sibling. Four more defects came with it, each demonstrated by perturbation before it was fixed:

| Defect | Consequence | Fix |
|---|---|---|
| `--check` and install mode over zero skill roots | A gate reported success over input it never read | Both exit 2 with `GATE FAIL`, mirroring `check-coverage.sh` |
| `link_target_abs` returned relative targets with `..` unresolved | A correct link compared unequal to its expectation, so `--check` called it `stale` and `--uninstall` then refused it as "not owned by this checkout" | The target is normalised when it resolves and returned unresolved when it does not, so classification still works |
| Link mode let `ln -sfn` replace a foreign symlink | The one path that silently took someone else's wiring, while `--check` called it a defect and `--uninstall` protected it | Refuses with exit 1, naming the link it would have replaced |
| `--check` and `--uninstall` iterated the current skill list | A link whose skill upstream removed was invisible to one mode and unswept by the other — a dangling owned link, permanently, the same class upstream keeps two cleanup registries for | Both walk the target root by ownership: links into this checkout's skill roots are reported or removed, links elsewhere are kept and named |
| `check-coverage.sh` guarded on directories, not on skills read | A tree whose directories all lacked a `SKILL.md` scanned zero skills and still exited 0 | A second guard fails when `scanned` is 0 |

`dsh/selftest.sh` runs every one of those perturbations against a throwaway copy and asserts the exit code — 16 cases, all passing. It exists because both reviewers noted that nothing automated invoked any of the three scripts, which left the demonstrations as prose in this document and a later edit free to re-break a guard with every gate still green. Writing it immediately caught three bad assertions of its own, which is the argument for having it: a guard nobody has seen fail is a guard nobody knows works. `dsh/CODING_STANDARDS.md`, added in the same round, states the twelve rules these gates are now held to, so a reviewer of `dsh/**` has criteria that name the failure modes actually found rather than re-deriving them.

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
| Shipped skill files route to `ce-dsh-host` with no fallback when the load fails | **Closed.** Two successive claims were overstated, then the gap itself was closed: all 62 bindings now state a fallback, in one of three wordings matched to what the binding does — dispatch bindings say to follow the file as written, task-surface bindings say the `todo_write` mapping still applies, and self-contained route bindings say the file's own route stands unchanged. |
| The new skill points at another skill's files with skill-local path syntax | **Addressed.** The protocol resolves persona, scope, criteria, and schema paths from the calling skill's own directory. |
| The one-line addition to `ce-pov/SKILL.md` took it past Codex's 8000-byte bound | **Fixed.** The block moved into `ce-pov/references/cross-model-panel.md`; `SKILL.md` is byte-identical to upstream. |

One review round was run per recipe generation. The disposition column is the author's response, not independent confirmation. The prompt-budget regression is also a lesson about the verification itself: a targeted run of seven skill-contract files, chosen by names that looked relevant, missed a guard that measures `SKILL.md` size. Targeted subsets do not substitute for the whole gate.

## 7. Not run, or unverified

- **Cross-model work is unavailable in this deployment, not merely unexercised.** CE reaches a cross-model peer by one of two routes, and neither is open here. The CLI route needs a subscription: `codex exec` fails with `401 Unauthorized: Could not validate your refresh token` because this machine has no Codex subscription, and `claude -p` produced no output within 90 seconds. The in-harness route needs a second configured provider, and this profile has one (`deepseek-account` / `deepseek-flash`), so the `workflow` override rung has nothing to override to. CE's own fallbacks and blockers therefore govern these paths, which is the behaviour the binding preserves: the peer stays the detached CLI job each file defines, and the teammate protocol governs only subagent work.
- **The teammate-hosting-a-CLI-peer shape is designed, not demonstrated.** It is sound by construction — a teammate runs a command and reports — but it has never run here, because no CLI peer authenticates. Adding a second *model* from the same provider would not close the gap either: CE verifies independence only when the peer's model **family** differs, so a same-family peer would be recorded as `independence_verified: false` and must not be presented as corroboration. A genuinely independent peer means a different vendor's model, reached by a subscription-backed CLI or by a second provider in the profile.
- **The repository's fresh-agent skill eval** (`bun run test:skill-eval-pack`) needs `claude` and `codex` working and bills those products. Skip reason: no Codex subscription and no working Claude CLI on this machine, and the behavior this fork changes is DSH dispatch, which those hosts do not exercise. The DSH-side dispatch was run directly instead — section 1.
- **A full-suite green run.** See section 3; the suite is not green on the untouched base commit in this environment.
