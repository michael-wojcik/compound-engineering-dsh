// Runs the dsh gate falsifiability harness inside `bun run test`.
//
// The harness itself is `dsh/selftest.sh`: every case is a shell perturbation
// against a throwaway copy, which is not expressible as a bun test without
// reimplementing the scripts. This wrapper exists so the gates are exercised by
// the same command CI runs, rather than only when someone remembers to run them.
//
// It is deliberately not in the `test:skill-guards` fast subset, which selects by
// name; it costs about 17 seconds because it copies `skills/` once per fixture.
//
// A failure here means a gate stopped failing when it should, or started failing
// when it should not — both worth a red suite.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const here = import.meta.dir;
const repoRoot = join(here, "..");

describe("dsh gate falsifiability", () => {
  test("every gate still fails when it should", () => {
    const r = spawnSync("bash", [join(here, "selftest.sh")], {
      cwd: repoRoot,
      encoding: "utf8",
      timeout: 300_000,
    });

    // Assert on the harness's own output, so a failure names the case that broke
    // rather than only reporting an exit status.
    const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
    expect(r.status, out).toBe(0);
    expect(out).toContain("0 failed");
  }, 300_000);
});
