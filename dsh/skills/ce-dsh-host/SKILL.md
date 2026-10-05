---
name: ce-dsh-host
description: "Binds Compound Engineering's host-neutral dispatch language to DeepSeek Harness primitives, so every CE subagent becomes an Agent Teams teammate collected inside the turn that launched it. Use when a CE skill dispatches reviewers, panel peers, media analyzers, or implementation units in this harness; when a CE step must collect launched agents in the same turn; or when a CE watch loop needs the harness's non-blocking wait."
---

# CE on DeepSeek Harness

**Outcome.** Every subagent a CE skill needs runs as an Agent Teams teammate: one shared task per dispatch, the launch collected inside the turn that made it by repeated bounded `wait_agent` calls, and the artifact on disk still the fact the merge reads. Consumers are the CE skills that carry a binding — `ce-babysit-pr`, `ce-bakeoff`, `ce-brainstorm`, `ce-code-review`, `ce-compound`, `ce-compound-refresh`, `ce-debug`, `ce-doc-review`, `ce-explain`, `ce-ideate`, `ce-optimize`, `ce-plan`, `ce-pov`, `ce-prototype`, `ce-resolve-pr-feedback`, `ce-retune`, `ce-simplify-code`, `ce-sweep`, `ce-work`. `dsh/audit-bindings.sh` fails when that list and the files that actually carry a binding disagree.

**Done.** Every dispatch became a teammate, every teammate was collected in-turn or recorded as failed, and the merge read artifacts rather than this context.

## Pick the primitive

| The work is | Use | Why |
|---|---|---|
| Any CE subagent dispatch — one agent or a batch, leaf or worker | `spawn_teammate`, one shared task per dispatch | This is the harness default for CE work. The member is durable and addressable, and the task board records the dispatch. |
| Collecting those launches | repeated `wait_agent` with a bound | CE's own text prescribes exactly this: a blocking collection wait repeated back to back until every launch is terminal or its artifact lands, which it states is *not* the forbidden detached-delegate poll loop. |
| A dispatch that must run on a **different model** — panel peer, cross-model author or reviewer, per-persona tier | `workflow` with `provider`/`model` overrides, or CE's external-adapter path | A teammate runs the session model; `spawn_teammate` takes no model override. See the exception below. |
| A dispatch issued by an agent that is not the Team Lead | `workflow` batch, then a single `subagent` | `spawn_teammate` is Lead-only. |
| A background shell process — the `ce-babysit-pr` detector | `bash` with `run_in_background`, then `job_output` with `wait: true` | Not a subagent dispatch; a process wait. |

**The one dispatch that cannot be a teammate.** `spawn_teammate` takes no model override and a teammate runs the session model, so a peer that must run **in-harness on a second configured provider** has no teammate form; `workflow`'s `agent(prompt, { provider, model })` is the only primitive that expresses it. Two things that look like exceptions are not. A peer that runs through an external CLI — CE's own cross-model route — is hosted *by* a teammate that runs the CLI and reports, because the model diversity comes from the CLI rather than from the teammate. And per-persona model tiering still runs as teammates whenever the tiers would not actually differ.

## Read next

- `references/dispatch-protocol.md` — the validated spawn, collect, and release protocol: naming, the shared task, the brief a teammate needs, the terminal condition, and every failure direction. Read before any CE dispatch.
- `references/primitive-map.md` — exact tool names, what counts as collected, the Lead-only and uniqueness constraints, and the fallback ladder. Read when a launch fails or a primitive is unfamiliar in this session.
- `references/background-watch.md` — the `ce-babysit-pr` watch loop on background jobs. Read before starting a babysit session.

## Two facts that change how a dispatch is written

A `workflow` script has no filesystem access, so it passes paths and the agents read them. A teammate has full tool access, so it reads its own persona file directly — pass paths, not file contents.

A teammate cannot be deleted and its name cannot be reused. Name every teammate with a per-run suffix or a second run in the same session fails to spawn.
