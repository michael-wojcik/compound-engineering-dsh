# DeepSeek Harness primitive map

Read this when a dispatch needs a primitive you have not used yet in this session, or when a launch fails. The dispatch procedure itself is `references/dispatch-protocol.md`.

## Tool names

CE prose names capabilities, not tools. In this harness they are:

| CE says | DeepSeek Harness tool |
|---|---|
| the platform's file-read / write / edit tool | `read`, `write`, `edit` |
| run a command | `bash` |
| search file contents / find files | `grep`, `glob` |
| the host's subagent primitive | `spawn_teammate` by default; `workflow` and `subagent` on the fallback ladder |
| the host's bounded in-turn wait | `wait_agent`, repeated back to back |
| a durable scheduler | `schedule_create` |
| ask the user | `ask_user_question` |
| web fetch / search | `web_fetch`, `web_search` |

## Teammate mechanics that shape a dispatch

- **Lead-only.** Only the Lead can spawn. A CE skill executing inside a teammate or subagent cannot dispatch teammates.
- **Names are permanent for the session.** A spawn with a used name is rejected outright; there is no delete. Always suffix with the run.
- **The shared task board is durable and visible.** A teammate can list, claim, and complete tasks, and `wait_agent` wakes on board changes as well as messages. This makes the board the launch inventory that survives compaction, and `blocked_by` the place to express ordering the calling skill already defines.
- **`write_scopes` are workspace-relative.** An artifact outside the workspace cannot be declared as a scope.
- **No model override.** A teammate runs the session model, so a dispatch that must genuinely run on a different model leaves the teammate rung. The other reason to leave it is that the dispatcher is not the Lead; `references/dispatch-protocol.md` carries both.

## The task surface is two things, not one

CE skills say "use the platform's task-tracking capability when available" and, on Claude Code, name `TaskCreate` / `TaskUpdate` / `TaskList`. Those tools do not exist here. This harness has two distinct task mechanisms and they are not interchangeable:

- **`todo_write`** is the session's task list, visible to the user. It is where a pipeline or stage-level view belongs — `lfg`'s stage view, `ce-plan`'s route-level outcomes, `ce-work`'s unit list, and a skill's own progress display.
- **`team_task_create` / `team_task_update` / `team_task_list`** are the Agent Teams shared board. It carries the work items of the *teammates* a dispatch creates, and it is what `wait_agent` wakes on. A teammate listing or claiming its task uses this board.

Publishing the pipeline view on the board would mix a stage view with teammate work items, and publishing teammate work items on `todo_write` would lose the board's dependency and wake behaviour. Keep them apart.

## Collection

A launch is collected when its terminal outcome is in hand. Per primitive:

- **`spawn_teammate`** — collected when the teammate's compact report message arrives or its artifact exists on disk, whichever is first, consumed once. A launch acknowledgement, a status change, or a progress update is not a result.
- **`workflow`** — the call returns only after every agent settles, so the returned array *is* the collected batch. An agent that failed resolves to `null` in that array; a `null` is a failed reviewer, recorded as one, not a missing one.
- **`subagent` with `run_in_background: false`** — the call's return is the outcome.
- **`subagent` (background)** — the settle notification carries the outcome.
- **`bash` + `run_in_background`** — `job_output` with `wait: true` blocks until the job finishes or the timeout expires. A timeout is not a result; wait again or take the failure direction.

`wait_agent` returns `noProgress` with reason `no-active-peer` once nothing is running. That is the terminal check: re-list, then anything with neither report nor artifact is a failed dispatch.

Misusing a `workflow` hook — a bad option, an unsupported schema keyword, a tripped cap — ends the whole script instead of returning `null`. That is a dispatch failure: record it as one, correct the script, and relaunch; do not treat the empty result as "no findings".

## Model overrides, and what "cross-model" can mean here

`spawn_teammate` has no `provider`/`model` parameter, so a teammate cannot be a different model. `workflow`'s `agent(prompt, opts)` can, and CE's external-CLI route does not need one at all because the peer's model comes from the CLI it runs.

So a cross-model request resolves in one of three ways, and never by re-running the session model and calling it an independent peer — CE treats peer agreement as independent evidence, and a same-model peer is not independent:

- **External CLI peer** (CE's own cross-model route): host it *in* a teammate. The teammate runs the CLI and reports; the diversity is the CLI's.
- **In-harness second provider**: `workflow` with `provider`/`model`. This dispatch cannot be a teammate; the only other dispatch that leaves the rung is one issued by an agent that is not the Lead.
- **No second route available**: take the skill's documented fallback or return a blocker.

## Durable ownership

Because every dispatch is a teammate, durable ownership is available wherever the calling skill needs it: a unit implemented across turns, a long `lfg` run, an author loop the user will redirect. Use the board for the parts that must survive the turn — `team_task_create` with `write_scopes` and `blocked_by`, and `send_message` to steer a member that is still running.

`wait_agent` observes changes; it never wakes an inactive member. To resume one, `send_message` it, then wait again.
