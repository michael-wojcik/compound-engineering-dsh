---
name: ce-dsh-host
description: "Binds Compound Engineering's host-neutral dispatch language to DeepSeek Harness primitives, so a multi-agent step runs as one in-turn, schema-validated dispatch. Use when a CE skill dispatches reviewers, panel peers, or media analyzers in this harness; when a CE step must collect launched agents in the same turn; or when a CE watch loop needs the harness's non-blocking wait."
---

# CE on DeepSeek Harness

**Outcome.** A Compound Engineering step that dispatches agents runs on the DeepSeek Harness primitive that carries CE's guarantees: every launch collected inside the turn that made it, nothing detached and polled, and a recorded failure rather than a silent skip. Consumers are the CE orchestrators that dispatch — `ce-code-review`, `ce-doc-review`, `ce-sweep`, `ce-pov`, `ce-work`, `ce-babysit-pr`, `lfg`.

**Done.** The dispatch used the mapped primitive, every launched agent was collected in the same turn, and any launch that failed is recorded as a failed reviewer or a blocked step.

## Pick the primitive

| The work is | Use | Why it satisfies CE |
|---|---|---|
| N independent leaf agents whose results are needed this turn — reviewer batch, media analyzers, panel peers | `workflow` with `parallel()` and a per-agent `schema` | One blocking tool call. Returns when every agent settled, and validates each return against the schema. In-turn, so it is not the polled background review CE forbids. |
| One agent whose result is needed this turn | `subagent` with `run_in_background: false` | Blocks until the child settles and returns its result. |
| One agent whose result may land later | `subagent` (background, the default) | Returns an id; the settle notification carries the result. |
| Work that must outlive the turn and be steered — a long `lfg` run, an author loop, units implemented in parallel | `spawn_teammate` with `team_task_*` and `wait_agent` | Durable and addressable, with a shared task board that survives the turn. |
| A background shell process — the `ce-babysit-pr` detector | `bash` with `run_in_background`, then `job_output` with `wait: true` | The harness's native non-blocking wait. |

Sizing is a condition, not a number: size a batch to the cap the call accepts. A batch the `workflow` call rejects as too large is backpressure — halve it and relaunch; never drop a reviewer for capacity.

## Read next

- `references/primitive-map.md` — exact tool names, collection and failure semantics, model overrides, and the degradation ladder. Read when a dispatch needs a primitive you have not used yet in this session, or when a launch fails.
- `references/reviewer-fanout.md` — the reviewer-batch recipe: personas by path, the schema projection rules, and how a failed agent is recorded. Read before dispatching any CE reviewer batch.
- `references/background-watch.md` — the `ce-babysit-pr` watch loop on background jobs and the durable escalation. Read before starting a babysit session.

## Two constraints that change how you write a dispatch

`workflow` accepts a narrow schema keyword set — `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `oneOf`. CE's `findings-schema.json` uses keywords outside it, so project it rather than passing it through; `references/reviewer-fanout.md` carries the projection.

A `workflow` script has no filesystem access, so it cannot read persona or scope files. Pass each agent the path and let the agent read it.
