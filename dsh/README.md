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

**A binding pointer at every dispatch site** in the upstream skills — 41 of them, in six variants matched to what the site does. Each naming the `ce-dsh-host` skill and falling back to the file as written when it is not installed. A same-model dispatch gets the teammate protocol; a cross-model peer gets the split rule, because a teammate cannot carry a model override; a per-agent tier site gets the same split; a `SKILL.md` with no byte headroom gets a short form. `dsh/check-coverage.sh` gates at skill level, reports unbound launch sites separately from mere mentions, and exits non-zero when a skill dispatches without a pointer.

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

The rebase conflicts are confined to the binding pointers. To carry the binding to another checkout without the branch, `git format-patch upstream/main --stdout > dsh-adaptation.patch` exports the same change set.

## What this changes on DSH

Every CE subagent dispatch becomes an Agent Teams dispatch: one shared task per dispatch, one teammate per agent, collected inside the turn that launched it by repeated bounded `wait_agent` calls, with the artifact on disk still the fact the merge reads. This does not bend CE's collection rule — CE's own dispatch text prescribes exactly this pattern and states that repeated blocking collection waits are not the detached-delegate poll loop it bans.

Four of `ce-work`'s execution engines now probe as callable, where the upstream text assumes they need a workaround:

- **Inline/subagent** — Agent Teams teammates, per the dispatch protocol.
- **Goal-mode** — `create_goal` / `update_goal` are callable tools, so a skill starts it directly instead of printing a copyable `/goal` prompt.
- **Dynamic-workflow** — `workflow` is a callable orchestration primitive that returns structured results, so `ce-work`'s large-fan-out row is available rather than prompt-emission only.
- **Cross-model** — a peer that runs through an external CLI is hosted by a teammate; only a peer that must run in-harness on a second configured provider needs the `workflow` override route.

## Deliberate limits

- **`allowed-tools`, `argument-hint`, and `scripts/` in the upstream skills are untouched.** DSH ignores the first two; the bundled Python and shell scripts run under the ordinary `bash` tool.
- **One dispatch cannot be a teammate.** `spawn_teammate` takes no model override, so an in-harness peer on a second provider is the only dispatch that leaves the teammate rung. The binding still states that re-running the session model and calling it an independent peer is unacceptable — CE's promotion and oracle logic treats peer agreement as independent evidence.
- **Teammates are Lead-only and permanent.** A CE skill executing inside a teammate or subagent falls back to `workflow` or a single `subagent`; every teammate persists for the session and its name cannot be reused, so names carry a per-run suffix.
- **No upstream PR.** The upstream working agreement gates new skills behind maintainer approval, and this binding is fork-local by construction.

## Verification

- `bun run release:validate` and the change-specific guards — full record in `dsh/verification.md`, including the pre-existing suite failure mode on this machine.
- `dsh/check-coverage.sh` — skill-level gate plus the file-level list of dispatch-bearing files that still lack an in-file pointer, so the residuals are re-judged rather than assumed.
- `dsh/audit-bindings.sh` — deeper checks: every file that mentions DeepSeek Harness routes to the adapter, every binding precedes its file's first launch instruction, exception texts sit on exception sites, and the adapter's own references resolve. Prints candidates for judgement rather than a bare pass.
- DSH skill discovery — all 37 skill bundles (36 upstream + `ce-dsh-host`) load through DSH's own `FileSystemSkillProvider` from both `$DSH_HOME/skills` and `<project>/.dsh/skills`, with no warnings and correct invocation policy.
- Teammate dispatch — spawned, collected, and released end to end with CE's own personas; evidence in `dsh/verification.md`.
- **Skipped:** the repo's fresh-agent skill eval (`bun run test:skill-eval-pack`) needs `claude` / `codex` on PATH and bills those products. It was not run; the DSH-side dispatch was exercised directly instead, which is the behavior this fork changes.
