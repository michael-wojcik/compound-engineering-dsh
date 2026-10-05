# DeepSeek Harness primitive map

Read this when a CE dispatch needs a primitive you have not used yet in this session, or when a launch fails.

## Tool names

CE prose names capabilities, not tools. In this harness they are:

| CE says | DeepSeek Harness tool |
|---|---|
| the platform's file-read / write / edit tool | `read`, `write`, `edit` |
| run a command | `bash` |
| search file contents / find files | `grep`, `glob` |
| the harness's subagent primitive | `subagent`, or `workflow` for a batch |
| the host's bounded in-turn wait | `subagent` with `run_in_background: false`, or the default blocking `workflow` call |
| a durable scheduler | `schedule_create` |
| ask the user | `ask_user_question` |
| web fetch / search | `web_fetch`, `web_search` |

## Collection

A launch is collected when its terminal outcome is in hand. Per primitive:

- **`workflow`** — the call returns only after every agent settles, so the returned array *is* the collected batch. An agent that failed resolves to `null` in that array; a `null` is a failed reviewer, recorded as one, not a missing one.
- **`subagent` with `run_in_background: false`** — the call's return is the outcome.
- **`subagent` (background)** — the settle notification carries the outcome; a launch acknowledgement is not a result.
- **`bash` + `run_in_background`** — `job_output` with `wait: true` blocks until the job finishes or the timeout expires. A timeout is not a result; wait again or take the failure direction.

Misusing a `workflow` hook — a bad option, an unsupported schema keyword, a tripped cap — ends the whole script instead of returning `null`. That is a dispatch failure: record it as one, correct the script, and relaunch; do not treat the empty result as "no findings".

## Model overrides, and what "cross-model" can mean here

`workflow`'s `agent(prompt, opts)` takes independent `provider` and `model` overrides. That is the native way to run CE's cross-model author, reviewer, or oracle panel, and it needs no external CLI.

It requires a second provider to be configured in the DSH profile. This installation has one, so a cross-model request currently has two honest outcomes:

- A second provider is configured: pass `{ provider, model }` and run the peer there.
- No second provider: take CE's own fallback — the external-CLI peer path the skill already documents (`peer-job-runner.py`, `cross-model-*.sh`) — or return a blocker.

Never satisfy a cross-model request by re-running the same model and reporting it as an independent peer. CE's promotion and oracle logic treats peer agreement as independent evidence, and a same-model peer is not independent.

## Durable work versus leaf work

`spawn_teammate` creates a durable, addressable peer with a shared task board; `wait_agent` observes its status and mailbox changes. Reach for it when the work must outlive the turn and someone will steer it — a long `lfg` run, an implementation unit owned across turns, an author loop the user will redirect.

Do not use it for CE's reviewer leaves. Those are short, independent, and needed this turn; `workflow` is the right shape, and a teammate adds lifecycle the reviewer never needs.

## Degradation ladder

Take the first rung that works and record which one you took:

1. `workflow` batch with schemas.
2. `subagent` with `run_in_background: false`, one reviewer at a time.
3. Review inline in the orchestrator's own context.

CE already governs rung 3: an inline pass is not independent, so it contributes attributed evidence but never counts as an independent reviewer, and the lost coverage is named in the result.
