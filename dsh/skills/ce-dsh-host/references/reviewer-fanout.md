# Reviewer fan-out on DeepSeek Harness

Read this before dispatching any CE reviewer batch (`ce-code-review`, `ce-doc-review`, `ce-sweep` media analyzers). It replaces the "launch, then find the host's bounded wait" dance with one blocking call, and it preserves everything CE's merge stage depends on.

The invariants it keeps: every launch is collected in the same turn; the artifact file on disk stays the fact the merge reads; a failed reviewer is recorded as failed rather than dropped; a batch the harness rejects for capacity is retried, not shrunk.

## 1. Prepare absolute paths

The script cannot read files, so it passes paths and the agents read them. Resolve these before writing it: the run directory, each selected `references/personas/<reviewer>.md`, the scope-rules file, and — for a staged review — the diff file rather than the diff text. Create the run directory first with `bash`.

The run directory comes from the calling skill's artifact-root rules, so a relocated artifact root moves with it. The persona, scope, criteria, and schema files come from the calling skill's own directory, which its SKILL.md already resolves.

Pass the calling skill's full review context, not just the diff: scope mode (`local-aligned`, `branch-remote`, `pr-remote`), the head ref when the scope is remote, PR metadata when there is a PR, the changed-file list, the intent summary, and the run ID. `references/diff-scope.md` selects tiers from that context, so a prompt carrying only a diff silently reviews against the wrong tier.

## 2. Project the findings schema

`workflow` accepts only `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `oneOf`. CE's `findings-schema.json` additionally uses `$schema`, `title`, `description`, `maxLength`, `minItems`, and `minimum`, so pass a projection of it, not the file. The artifact files keep the full schema; only the returned value is projected.

Keep every enum. `severity` stays `["P0","P1","P2","P3"]`, `confidence` stays `[0,25,50,75,100]`, and `autofix_class` and `owner` keep theirs. The enums, not the prose, are what the projection is for.

**Do not set `additionalProperties: false` on the projected finding.** An agent that returns a field outside the projection fails validation, resolves to `null`, and is recorded as a failed reviewer — a false failure is worse than an extra key, and CE's merge ignores fields it does not consume. Project what merge consumes and let the rest pass.

The returned value is CE's **compact return**, not the full artifact: `reviewer`, `findings[]` carrying `title`, `severity`, `file`, `line`, `confidence`, `autofix_class`, `owner`, `requires_verification`, `pre_existing`, `suggested_fix`, and `first_evidence`, plus `residual_risks[]` and `testing_gaps[]`. Require only what merge cannot proceed without. Leave `first_evidence` optional in the schema and enforce the quote-the-line gate in the orchestrator, because a 50-anchor finding legitimately omits it. The full artifact, with `why_it_matters` and the whole `evidence` array, still goes to disk.

## 3. Write the script

One agent per reviewer, launched together. This is the shape — fill it from the calling skill's persona set, its scope context, and the run's own artifact root:

```js
const runDir = "<abs run dir resolved from the artifact root>";
const skillDir = "<abs directory of the calling skill>";
const scopePath = skillDir + "/references/diff-scope.md";
const diffPath = "<abs staged diff, or inline a small diff>";
const context = [
  "Scope mode: <local-aligned | branch-remote | pr-remote>",
  "Head ref: <ref, when the scope is remote>",
  "PR: <url, title, body -- omit when there is no PR>",
  "Changed files: " + fileListPath,
  "Intent: <2-3 line summary>",
  "Run ID: " + runId,
].join("\n");
const reviewers = [
  { name: "correctness", persona: skillDir + "/references/personas/correctness-reviewer.md" },
  { name: "security", persona: skillDir + "/references/personas/security-reviewer.md" },
];

const finding = {
  type: "object",
  required: ["title", "severity", "file", "line", "confidence", "evidence"],
  properties: {
    title: { type: "string" },
    severity: { type: "string", enum: ["P0", "P1", "P2", "P3"] },
    file: { type: "string" },
    line: { type: "number" },
    confidence: { type: "number", enum: [0, 25, 50, 75, 100] },
    autofix_class: { type: "string", enum: ["gated_auto", "manual", "advisory"] },
    owner: { type: "string", enum: ["downstream-resolver", "human", "release"] },
    requires_verification: { type: "boolean" },
    pre_existing: { type: "boolean" },
    suggested_fix: { type: "string" },
    first_evidence: { type: "string" },
    evidence: { type: "array", items: { type: "string" } },
  },
};
const schema = {
  type: "object",
  required: ["reviewer", "findings", "residual_risks", "testing_gaps"],
  properties: {
    reviewer: { type: "string" },
    findings: { type: "array", items: finding },
    residual_risks: { type: "array", items: { type: "string" } },
    testing_gaps: { type: "array", items: { type: "string" } },
  },
};

const prompt = (r) => [
  `You are reviewer "${r.name}" inside a running ce-code-review batch.`,
  `Read your persona at ${r.persona} and follow it exactly.`,
  `Read the scope rules at ${scopePath}.`,
  `Read the diff at ${diffPath}.`,
  `Read any criteria files your persona names, under ${skillDir}.`,
  context,
  `Write your full artifact to ${runDir}/${r.name}.json with the write tool. That is your only permitted write.`,
  "Return compact JSON only, matching the schema. Put the quoted motivating line first in evidence.",
  "Suppress any finding you cannot anchor at 50 or higher.",
].join("\n");

const results = await parallel(
  reviewers.map((r) => () => agent(prompt(r), { label: r.name, schema, phase: "reviewers" })),
);
return results.map((res, i) => ({ name: reviewers[i].name, ok: res !== null, result: res }));
```

Keep the diff out of the script when it is large or arbitrary: pass `diffPath` and let each agent read it. If a small diff must be inlined, build the string with `JSON.stringify(diff)` so backticks and `${` in the diff cannot break the template.

When the calling skill tiers reviewers by model, pass the tier on the same call: `agent(prompt(r), { label: r.name, schema, model })`. That is the harness's model override, and it is the only place a per-reviewer tier can be applied here.

## 4. Read the result

The returned array is the collected batch, in the order the reviewers were listed.

- `ok: true` — the compact return is in hand; merge from it and from the artifacts.
- `ok: false` — that reviewer is a **failed reviewer**. Record it as one, name the lost coverage, and do not shrink the roster to hide it.
- The script itself erroring means the batch did not run at all. Correct the script and relaunch; an empty result is never "no findings".

## 5. When the batch is rejected for capacity

A `workflow` call that rejects the batch as too large is backpressure. Halve the batch, keep every reviewer, and relaunch. If no batch size is accepted, fall to the ladder in `references/primitive-map.md`: collect with `subagent` and `run_in_background: false`, one reviewer at a time.
