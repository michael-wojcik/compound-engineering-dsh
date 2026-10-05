# Background watch on DeepSeek Harness

Read this before starting a `ce-babysit-pr` session. It binds CE's three scheduling shapes to this harness and keeps the one rule that matters: the watch never busy-spins and never uses a foreground `sleep`.

`ce-babysit-pr` runs a deterministic detector, `pr-snapshot watch`, which uses no agent tokens and prints one `BABYSIT_WAKE {reason,url,...}` line only when there is work to inspect.

## Sustained watch (default)

1. Launch the detector as a background job: `bash` with `run_in_background: true`. You get a job id back and the call returns immediately.
2. Wait for the detector natively: `job_output` with `wait: true` and a bounded `timeout_ms`. The call returns when the detector prints, or when the timeout expires.
3. On a `BABYSIT_WAKE` line, run one tick, then re-arm by launching the detector again.
4. On a timeout with no wake, wait again. A timeout is not a stop condition and not a reason to run a tick — the detector has not reported work.

This wait is the harness's non-blocking wait. A foreground `sleep`, a detached process the session does not own, or a busy loop is never the answer. When the detector exits, read its output before re-arming so a crash is not mistaken for quiet.

## Pipeline mode (`mode:pipeline`)

An orchestrator such as `lfg` drives ticks in line and the loop must terminate. Run the same launch-and-wait cycle, but keep each wait short enough that control returns to the orchestrator between ticks, and stop on the first terminal stop condition. Never end the orchestrator's turn to wait for a wake.

## Checkpoint mode

Use it when the user asks for it or when the session cannot stay active while waiting. Run one tick, persist state to disk, report, and print the resume invocation. Say that monitoring is paused.

## Durability

The in-session watch dies with the session. State lives in the state file, so re-invoking the skill resumes from disk, and a fresh run has no memory of this conversation: consequential decisions belong on disk, not in context. Environment variables do not persist between tool calls either, so re-set `SKILL_DIR` and `STATE_DIR` inline in every command.

For an unattended watch, escalate past the session:

- `schedule_create` re-prompts this session on a cron or fixed interval — the right shape when the *session* is what should resume the loop and the app stays up. A recurring reminder delivers only its latest missed occurrence after downtime, so it does not reconstruct a missed schedule.
- OS cron invoking the CLI is the answer when the loop must survive the session and the app entirely. Each run starts fresh, so it must be able to resume from the state file alone.
