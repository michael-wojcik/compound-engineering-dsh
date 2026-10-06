# Dispatch protocol on DeepSeek Harness

Every CE subagent dispatch is an Agent Teams dispatch: one shared task, one teammate, one artifact, collected inside the turn that launched it. This protocol was validated end to end before it was written down — two persona reviewers spawned concurrently, each read its persona and diff from disk, wrote its artifact, claimed and completed its shared task, and reported compact JSON the orchestrator collected with bounded waits.

**This protocol governs every dispatch the reader performs under any CE skill for the rest of the session, not only dispatches from the file whose binding sent you here.** Individual bindings name the file that carries them; a CE run reads several files per stage, so treat the binding as skill-wide and this protocol as session-wide.

The invariants it keeps: every launch is collected in the turn that made it; the artifact on disk stays the fact the merge reads; a failed dispatch is recorded as failed rather than dropped; a batch the harness rejects for capacity is retried, not shrunk.

## Preconditions

- **The orchestrator must be the Team Lead.** `spawn_teammate` is Lead-only. A CE skill running inside a teammate or subagent cannot dispatch teammates and takes the fallback ladder at the end of this file. Do not decide this by looking for the tool: a dispatched agent's schema still lists `spawn_teammate`, annotated in its own description with "Only the Lead may call this tool". The test is who you are, not what you can see.
- **Names are unique for the session and cannot be reused.** Name every teammate `<skill>-<persona>-<run4>`, where `run4` is the last four characters of the run ID, lowercased. Without the suffix, a second run in the same session fails to spawn. A spawn rejected because the name is taken is a naming collision: change the suffix and relaunch. A spawn rejected for capacity is a different failure — treat it as backpressure, keep the roster intact, and retry when a slot frees, exactly as the calling skill's own capacity rules require. Never read one rejection as the other.
- **Teammates are never deleted.** They persist, inactive, for the session, which is a second reason the run suffix matters.

## 1. Resolve the brief

Resolve absolute paths before spawning: the run directory, each selected persona or prompt asset, the scope-rules file, the criteria files a persona names, and the diff (a path for a staged review, never the text). Take the run directory from the calling skill's artifact-root rules so a relocated artifact root moves with it.

Carry the calling skill's full review context, not just the diff: scope mode, the head ref when the scope is remote, PR metadata when there is a PR, the changed-file list, the intent summary, and the run ID.

## 2. Create one shared task per dispatch

`team_task_create(subject, description, write_scopes?, blocked_by?)` — the board is the durable inventory of the launch, and `wait_agent` wakes on board changes as well as on messages.

- Make the subject name the work and the persona, so a later reader can tell two runs apart.
- Put the deliverable and the done condition in the description: the artifact path, and that the artifact is the fact.
- `write_scopes` are **workspace-relative** prefixes and a path outside the workspace cannot be expressed at all. A run directory under the OS temp root therefore carries no scope; declare scopes for what the dispatch may touch *inside* the workspace, and treat the artifact path as the deliverable rather than as a scope.
- Use `blocked_by` only where the calling skill already orders the work, such as a validator that must follow the reviewers.

## 3. Spawn the teammate

`spawn_teammate(name, description, prompt)` — the `prompt` is the complete initial task, and a teammate has full tool access, so it reads its own persona file rather than receiving its contents. The exception is a calling skill whose own template inlines the persona as part of that skill's contract, as `ce-sweep`'s does; follow that template.

The brief carries, in this order: the persona or prompt-asset path and the instruction to follow it; the scope-rules and criteria paths; the diff path; the review context; the artifact path with the note that this is the only permitted write; the shared task id with the instruction to claim it before working and complete it after the artifact is written; the compact-return shape; and the instruction to send the lead exactly one message containing only that compact JSON.

One teammate per dispatch. A batch is N teammates and N tasks.

## 4. Collect

Collect with the host's blocking wait, repeated back to back, which is the pattern CE's own dispatch text prescribes and exempts from the ban on detached polling.

```
loop:
  wait_agent(timeout_ms)          # returns on any teammate status, mailbox, or board change
  re-check which reviewers have reported and which artifacts exist on disk
  stop when every dispatch has a report or an artifact, or the bound passes
```

- A dispatch is **collected** when its compact report has arrived or its artifact is on disk — whichever lands first, consumed once. A launch acknowledgement, a status change, or a progress update is not a collection.
- `wait_agent` returns `noProgress` with reason `no-active-peer` as soon as nothing is running. That is the terminal check, not a failure: re-list with `list_agents` and `team_task_list`, then any dispatch with neither report nor artifact is a failed dispatch.
- The bound is the aggregate wall-clock limit the calling skill states — for CE reviewers, the 20 minutes per launch that `subagent-template.md` sets. A single short wait reaches that bound by repeating, not by treating one return as the deadline.

## 5. Release and record

- A teammate still running when the bound passes is stopped with `interrupt_agent` and recorded as a failed dispatch under the calling skill's own degraded-coverage rules. It cannot be deleted, so it stays listed; that is expected.
- A teammate that reports but whose artifact is missing is collected with the missing artifact noted, because the merge reads artifacts and degrades to the compact return.
- Never end the turn to await a dispatch. The waits are in-turn; a turn that ends on "still waiting" is the failure CE names explicitly. The one licensed exception is a dispatch the calling skill deliberately runs across the user's think-time — `ce-brainstorm`'s opening scout. There the turn ends on a question to the user, not on waiting, and the collection happens when the answer returns.

## Precondition, then the fallback ladder

Everything above assumes the Agent Teams bundle (`dsh-experimental-agent-team-profile`) is enabled in the DSH profile. **It ships switched off.** With it off there is no `spawn_teammate`, no shared board, and no `wait_agent`, so nothing in this file applies and the calling skill's own host-neutral text is the whole instruction.

With it on, the bundle also changes the rest of the toolset: ordinary `subagent` delegation and the overlapping global child controls are disabled, while `workflow` can still create fresh children. So the available rungs differ by profile, and the two profiles do not share one ladder:

| Profile | Ladder, first rung that works |
|---|---|
| **Agent Teams on** | teammates, then a `workflow` batch, then inline |
| **Agent Teams off** | `subagent` with `run_in_background: false`, then a `workflow` batch, then inline |

Record which rung you took. Inline is last in both because CE governs it: an inline pass is not independent, contributes attributed evidence only, and the lost coverage is named in the result.

A `workflow` schema accepts only `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `oneOf`, so project CE's `findings-schema.json` rather than passing it through, and do not set `additionalProperties: false` on a finding — a validation failure resolves that agent to `null`, which reads as a failed reviewer.
