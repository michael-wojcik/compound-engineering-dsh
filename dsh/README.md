# DeepSeek Harness binding for Compound Engineering

This is a fork of [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) that adds a host binding for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH) on top of the upstream skills.

CE skills are written host-neutrally: they name a capability ("the host's subagent primitive", "the host's bounded in-turn wait") and leave the binding to the harness. That degrades gracefully on an unknown harness, but it leaves DSH agents guessing at primitives this harness actually exposes directly.

## What the binding adds

**`dsh/skills/ce-dsh-host/`** — a model-invocable skill carrying the DSH mapping:

| File | Carries |
|---|---|
| `SKILL.md` | The rule that every CE subagent dispatch is an Agent Teams dispatch, the single exception, and the two facts that change how a dispatch is written |
| `references/dispatch-protocol.md` | The validated spawn, collect, and release protocol: naming, the shared task, the teammate brief, the terminal condition, every failure direction |
| `references/primitive-map.md` | Exact tool names, what counts as collected per primitive, the Lead-only and name-uniqueness constraints, model overrides, the fallback ladder |
| `references/background-watch.md` | The `ce-babysit-pr` watch loop on background jobs, and the durable escalation |

**A binding in 61 upstream skill files**, in six reusable variants matched to what the site does plus tailored forms for the watch, the engine table, the peer panel, and the task surface. Every binding names the `ce-dsh-host` skill and states a fallback for when it is not installed, in one of three wordings: dispatch bindings say to follow the file as written, task-surface bindings say the `todo_write` mapping still applies, and self-contained route bindings say the file's own route stands unchanged. A same-model dispatch gets the teammate protocol; a dispatch that must run on a different model gets the split rule, because a teammate cannot carry an override; a site that may execute inside a dispatched agent states that spawning is unavailable there; a `SKILL.md` with no byte headroom gets a short form. `dsh/check-coverage.sh` gates at skill level and reports unbound launch sites separately from mere mentions; `dsh/audit-bindings.sh` checks placement, variant fit, DSH-mention completeness, the adapter's consumer list, and vacuous bindings.

The adapter skill deliberately lives outside `skills/`. It is a DSH-only artifact: keeping it out of the plugin's product surface leaves the upstream skill inventory, the marketplace metadata, and the release-version contract untouched, so `git pull upstream main` stays a small rebase.

## Install

```bash
./dsh/install.sh --global              # link into $DSH_HOME/skills
./dsh/install.sh --project [DIR]       # link into <DIR>/.dsh/skills
./dsh/install.sh --check               # report what a root currently resolves to
./dsh/install.sh --uninstall           # remove the links this script made
```

Only symlinks are created, so `git pull` updates the installed skills. A real directory sharing a skill's name is never overwritten; the script stops and names it. Start a new DSH session, or wait for the skill catalog to refresh.

**Requires the Agent Teams bundle.** `@deepseek-ai/dsh-experimental-agent-team-profile` ships switched off; enable it from the DSH Plugins page or add it to the profile. Without it there is no `spawn_teammate`, no shared task board, and no `wait_agent`, and every binding falls back to the ladder in the adapter's `dispatch-protocol.md`. That bundle also disables ordinary `subagent` delegation, so the fallback differs by profile: teammates → `workflow` → inline when it is on, `subagent` → `workflow` → inline when it is off.

## Updating from upstream

A clone of this fork has `origin` pointing here, so add the upstream remote once:

```bash
git remote add upstream https://github.com/EveryInc/compound-engineering-plugin.git
git fetch upstream
git rebase upstream/main dsh-adaptation
bun install && bun run release:validate && bun run test:skill-guards
```

The working branch is `dsh-adaptation`; `main` is the untouched upstream branch. Every change is additive — verified at `upstream/main` `efcb657d`, where the fork diverges by 136 added lines, zero removed, and zero files deleted. The rebase is not always clean: upstream's `#1837` deleted `ce-work`'s engine-probe section, which took the `execution-engines.md` binding with it, and resolving that plus four neighbouring conflicts was the maintenance cost of staying current. When upstream retires a section, follow upstream and drop the binding whose referent it removed rather than re-homing it. To carry the binding to another checkout without the branch, `git format-patch upstream/main --stdout > dsh-adaptation.patch` exports the same change set.

## What this changes on DSH

Every CE subagent dispatch becomes an Agent Teams dispatch: one shared task per dispatch, one teammate per agent, collected inside the turn that launched it by repeated bounded `wait_agent` calls, with the artifact on disk still the fact the merge reads. This does not bend CE's collection rule — CE's own dispatch text prescribes exactly this pattern and states that repeated blocking collection waits are not the detached-delegate poll loop it bans.

Four of `ce-work`'s execution engines now probe as callable, where the upstream text assumes they need a workaround:

- **Inline/subagent** — Agent Teams teammates, per the dispatch protocol.
- **Goal-mode** — `create_goal` / `update_goal` are callable tools, so a skill starts it directly instead of printing a copyable `/goal` prompt.
- **Dynamic-workflow** — `workflow` is a callable orchestration primitive that returns structured results, so `ce-work`'s large-fan-out row is available rather than prompt-emission only.
- **Cross-model** — a peer that runs through an external CLI is hosted by a teammate; only a peer that must run in-harness on a second configured provider needs the `workflow` override route. **Neither route is available in this deployment**: no Codex subscription for the CLI peers, and one configured provider, so CE's cross-model paths take their own documented fallbacks. A second model from the same provider would run but is not an independent peer — CE verifies independence only across model families.

## Deliberate limits

- **`allowed-tools`, `argument-hint`, and `scripts/` in the upstream skills are untouched.** DSH ignores the first two; the bundled Python and shell scripts run under the ordinary `bash` tool.
- **A dispatch that cannot be a teammate.** `spawn_teammate` takes no model override, so an in-harness peer on a second provider leaves the teammate rung; the other case is a dispatch issued by an agent that is not the Lead. The binding still states that re-running the session model and calling it an independent peer is unacceptable — CE's promotion and oracle logic treats peer agreement as independent evidence.
- **Teammates are Lead-only and permanent.** A CE skill executing inside a teammate or subagent falls back to `workflow` or a single `subagent`; every teammate persists for the session and its name cannot be reused, so names carry a per-run suffix.
- **No upstream PR.** The upstream working agreement gates new skills behind maintainer approval, and this binding is fork-local by construction.

## Verification

- `bun run release:validate` and the change-specific guards — full record in `dsh/verification.md`, including the pre-existing suite failure mode on this machine.
- `dsh/check-coverage.sh` — skill-level gate plus the file-level list of dispatch-bearing files that still lack an in-file pointer, so the residuals are re-judged rather than assumed.
- `dsh/audit-bindings.sh` — deeper checks: every file that mentions DeepSeek Harness routes to the adapter, every binding precedes its file's first launch instruction, exception texts sit on exception sites, and the adapter's own references resolve. Prints candidates for judgement rather than a bare pass.
- DSH skill discovery — all 37 skill bundles (36 upstream + `ce-dsh-host`) load through DSH's own `FileSystemSkillProvider` from both `$DSH_HOME/skills` and `<project>/.dsh/skills`, with no warnings and correct invocation policy.
- Teammate dispatch — spawned, collected, and released end to end with CE's own personas; evidence in `dsh/verification.md`.
- **Skipped:** the repo's fresh-agent skill eval (`bun run test:skill-eval-pack`) needs `claude` / `codex` on PATH and bills those products. It was not run; the DSH-side dispatch was exercised directly instead, which is the behavior this fork changes.
