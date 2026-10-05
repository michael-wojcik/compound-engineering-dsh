# DeepSeek Harness binding for Compound Engineering

This is a fork of [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) that adds a host binding for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH) on top of the upstream skills.

CE skills are written host-neutrally: they name a capability ("the host's subagent primitive", "the host's bounded in-turn wait") and leave the binding to the harness. That degrades gracefully on an unknown harness, but it leaves DSH agents guessing at primitives this harness actually exposes directly.

## What the binding adds

**`dsh/skills/ce-dsh-host/`** — a model-invocable skill carrying the DSH mapping:

| File | Carries |
|---|---|
| `SKILL.md` | Which DSH primitive to use for which dispatch shape, and the two constraints that change how a dispatch is written |
| `references/primitive-map.md` | Exact tool names, what counts as a collected result per primitive, model overrides, the cross-model reality, and the degradation ladder |
| `references/reviewer-fanout.md` | The reviewer-batch recipe: personas by path, the `workflow` schema projection rules, and how a failed agent is recorded |
| `references/background-watch.md` | The `ce-babysit-pr` watch loop on background jobs, and the durable escalation |

**Six pointer edits** in upstream skill files, each one or two sentences at the site that dispatches:

| File | Binding |
|---|---|
| `skills/ce-code-review/references/dispatch-reviewers.md` | Reviewer batch -> one blocking `workflow` call with `parallel()` and a projected per-agent schema |
| `skills/ce-doc-review/references/dispatch.md` | Added to the file's own host list of subagent primitives |
| `skills/ce-sweep/references/subagent-template.md` | Media analyzers -> one `workflow` batch, inputs passed by path |
| `skills/ce-pov/SKILL.md` | Oracle panel -> `workflow` agents with `provider`/`model` overrides |
| `skills/ce-work/references/execution-engines.md` | Which of the four execution engines probe as callable on DSH |
| `skills/ce-babysit-pr/references/watch-loop.md` | Added a DeepSeek Harness row to the file's own per-harness table |

The adapter skill deliberately lives outside `skills/`. It is a DSH-only artifact: keeping it out of the plugin's product surface leaves the upstream skill inventory, the marketplace metadata, and the release-version contract untouched, so `git pull upstream main` stays a small rebase.

## Install

```bash
./dsh/install.sh --global              # link into $DSH_HOME/skills
./dsh/install.sh --project [DIR]       # link into <DIR>/.dsh/skills
./dsh/install.sh --check               # report what a root currently resolves to
./dsh/install.sh --uninstall           # remove the links this script made
```

Only symlinks are created, so `git pull` updates the installed skills. A real directory sharing a skill's name is never overwritten; the script stops and names it. Start a new DSH session, or wait for the skill catalog to refresh.

## Updating from upstream

```bash
git fetch upstream
git rebase upstream/main dsh-adaptation
bun run release:validate && bun run test
```

The rebase conflicts are confined to the six pointer edits. To carry the binding to another checkout without the branch, `git format-patch upstream/main --stdout > dsh-adaptation.patch` exports the same change set.

## What this changes on DSH

Three of `ce-work`'s four execution engines probe as callable, where the upstream text assumes they need a workaround:

- **Inline/subagent** — `subagent`, with `run_in_background: false` to collect in-turn.
- **Goal-mode** — `create_goal` / `update_goal` are callable tools, so a skill starts it directly instead of printing a copyable `/goal` prompt.
- **Dynamic-workflow** — `workflow` is a callable orchestration primitive that returns structured results, so `ce-work`'s large-fan-out row is available rather than prompt-emission only.
- **Cross-model** — available only with a second provider configured in the DSH profile; otherwise the external-adapter path is what remains.

The reviewer fan-out is the largest behavioral change. Upstream needs a concurrent launch followed by "the host's bounded in-turn wait" and a per-reviewer artifact file. On DSH it becomes one blocking `workflow` call whose returned array is the collected batch, with the artifact files still written and still the fact the merge reads.

## Deliberate limits

- **`allowed-tools`, `argument-hint`, and `scripts/` in the upstream skills are untouched.** DSH ignores the first two; the bundled Python and shell scripts run under the ordinary `bash` tool.
- **Cross-model needs a second provider.** With one provider configured, a cross-model request takes CE's own fallback or returns a blocker. The binding states explicitly that re-running the session model and calling it an independent peer is not acceptable — CE's promotion and oracle logic treats peer agreement as independent evidence.
- **Teammates are bound but not pushed.** `spawn_teammate` is the right shape for work that outlives the turn; CE's reviewer leaves are short, independent, and needed this turn, so they stay on `workflow`. The primitive map says when each applies.
- **No upstream PR.** The upstream working agreement gates new skills behind maintainer approval, and this binding is fork-local by construction.

## Verification

- `bun run release:validate` and `bun run test` — run against this tree; results in the commit message.
- DSH skill discovery — all 37 skill bundles (36 upstream + `ce-dsh-host`) load through DSH's own `FileSystemSkillProvider` from both `$DSH_HOME/skills` and `<project>/.dsh/skills`, with no warnings and correct invocation policy.
- Reviewer fan-out — the `workflow` recipe was executed end to end against this repo's own persona files; see `dsh/verification.md`.
- **Skipped:** the repo's fresh-agent skill eval (`bun run test:skill-eval-pack`) needs `claude` / `codex` on PATH and bills those products. It was not run; the DSH-side dispatch was exercised directly instead, which is the behavior this fork changes.
