import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("./gauntlet.js", import.meta.url), "utf8").replace(/^export const meta/m, "const meta");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const script = new AsyncFunction("agent", "log", "phase", "parallel", "pipeline", "workflow", "args", "budget", source);

const SECRET = "s3cret";
const HEAD = "abcdef0123456789";
const BODY = [
  "## Acceptance criteria",
  "- [ ] Given an expired access token, when the client calls any route, then the response is 200",
  "- [ ] Given ten parallel 401s, when they resolve, then exactly one refresh call was made",
].join("\n");
const PR_URL = "https://github.com/oneforge/brushfeed/pull/9";

function fnv1a32(text) {
  let digest = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) digest = Math.imul(digest ^ byte, 0x01000193) >>> 0;
  return digest.toString(16).padStart(8, "0");
}

function next(scripted) {
  if (!Array.isArray(scripted)) return scripted ?? 0;
  return scripted.length > 1 ? scripted.shift() : scripted[0];
}

const RELAYED_FIELDS = ["nonce", "guard", "exitCode", "receipt"];
const hostileRelay = (result) => Object.fromEntries(Object.entries(result).filter(([field]) => RELAYED_FIELDS.includes(field)));

async function dryRun({ guards = {}, stages = {}, ticket = "63", hostile = false } = {}) {
  const scriptedGuards = structuredClone(guards);
  const calls = [];
  const logs = [];
  async function agent(prompt, options = {}) {
    const call = { prompt, ...options };
    calls.push(call);
    const label = options.label || "";
    if (label === "bootstrap") return { repoRoot: "/r", headSha: HEAD, secret: SECRET, branch: "gauntlet/63" };
    const invocation = prompt.match(/run\.py"?\s+(\S+)\s+(\S+)(?:\s+(\S+))?/);
    if (invocation) {
      const [, guard, nonce, argument] = invocation;
      const key = guard === "spec" ? `spec:${argument}` : guard;
      let scripted = next(scriptedGuards[key]);
      if (typeof scripted === "number") scripted = { exitCode: scripted };
      if (scripted.conduit === "fabricated") return { nonce, guard, exitCode: 0, receipt: "deadbeef" };
      if (scripted.conduit === "wrong-nonce") return { nonce: "other", guard, exitCode: 0, receipt: fnv1a32(`${SECRET}:other:0`) };
      const { conduit, ...fields } = scripted;
      const result = { nonce, guard, ...fields };
      if (guard === "ticket" && result.exitCode === 0) {
        result.title = "Session token does not auto-refresh";
        result.body = fields.body ?? BODY;
      }
      result.receipt = fnv1a32(`${SECRET}:${nonce}:${result.exitCode}`);
      return hostile ? hostileRelay(result) : result;
    }
    if (label === "ship") return stages.ship === undefined ? { prUrl: PR_URL } : stages.ship;
    const stage = stages[label];
    return typeof stage === "function" ? stage(prompt, options) : (stage ?? "done");
  }
  const outcome = await script(agent, (line) => logs.push(line), () => {}, null, null, null, ticket, { total: null, spent: () => 0, remaining: () => Infinity });
  return { outcome, calls, logs, labels: calls.map((call) => call.label) };
}

const STAGE_LABELS = new Set(["specify", "coder", "cleaner", "qa", "ship"]);
const stagesOf = (labels) => labels.filter((label) => STAGE_LABELS.has(label));

test("all green: specify → coder → cleaner → qa → ship, and ship only with a PR URL", async () => {
  const { outcome, labels, calls } = await dryRun();
  assert.deepEqual(stagesOf(labels), ["specify", "coder", "cleaner", "qa", "ship"]);
  assert.deepEqual(labels.slice(0, 7), ["bootstrap", "ticket", "preflight:clean-tree", "preflight:install", "preflight:setup", "preflight:build", "preflight:coverage"]);
  assert.deepEqual(
    labels.slice(labels.indexOf("specify")),
    ["specify", "clean-tree", "spec:red", "coder", "clean-tree", "spec:green", "build", "coverage", "crap", "cleaner", "clean-tree", "spec:green", "build", "coverage", "crap", "qa", "qa-guard", "verdict", "ship", "teardown"]
  );
  assert.equal(outcome.outcome, "ship");
  assert.equal(outcome.prUrl, PR_URL);
  for (const stage of STAGE_LABELS) assert.equal(calls.find((call) => call.label === stage).agentType, `gauntlet-${stage}`);
});

const promptOf = (calls, label, nth = 0) => calls.filter((call) => call.label === label)[nth].prompt;

test("every stage prompt opens by sending the stage to the ticket file and never asks for gh", async () => {
  const { calls } = await dryRun();
  for (const stage of STAGE_LABELS) {
    const prompt = promptOf(calls, stage);
    if (stage !== "ship") assert.match(prompt, /^Read \.gauntlet\/ticket\.json first/);
    assert.doesNotMatch(prompt, /gh issue view/);
  }
});

test("a ticket body with non-ASCII characters reaches the stages", async () => {
  const body = "## Acceptance criteria\n- [ ] Given an expired token — when the client calls any route, then the response is 200";
  const { outcome } = await dryRun({ guards: { ticket: { exitCode: 0, body } } });
  assert.equal(outcome.outcome, "ship");
});

test("a hostile conduit that relays only the receipt-verified fields still ships, and no stage sees a hole where the ticket was", async () => {
  const { outcome, calls } = await dryRun({ hostile: true });
  assert.equal(outcome.outcome, "ship");
  for (const stage of STAGE_LABELS) assert.doesNotMatch(promptOf(calls, stage), /undefined/);
});

test("every field the workflow verifies a guard result by is one the conduit schema requires", () => {
  const verifiedFields = [...source.match(/function verified[\s\S]*?\n\}/)[0].matchAll(/result\.(\w+)/g)].map((match) => match[1]);
  const required = JSON.parse(source.match(/const guardSchema = \{[\s\S]*?required: (\[[^\]]*\])/)[1]);
  assert.ok(verifiedFields.length >= 3);
  for (const field of verifiedFields) assert.ok(required.includes(field), `verified() reads ${field} but the conduit schema does not require it`);
});

test("spec red failing routes back to specify with the problems in the retry prompt", async () => {
  const { calls, labels } = await dryRun({ guards: { "spec:red": [{ exitCode: 1, problems: ["0 tests named after criterion: Given ten parallel 401s, when they resolve, then exactly one refresh call was made"] }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 3), ["specify", "specify", "coder"]);
  assert.match(promptOf(calls, "specify", 1), /0 tests named after criterion: Given ten parallel 401s/);
});

test("a dirty tree after a stage re-prompts the same stage to commit", async () => {
  const { calls, labels } = await dryRun({ guards: { "clean-tree": [0, { exitCode: 2, tail: "M src/a.ts" }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 3), ["specify", "specify", "coder"]);
  assert.match(promptOf(calls, "specify", 1), /commit everything you changed/);
  assert.match(promptOf(calls, "specify", 1), /M src\/a\.ts/);
});

test("spec green red after the coder routes back to the coder with the failing names", async () => {
  const { calls, labels } = await dryRun({ guards: { "spec:green": [{ exitCode: 1, problems: ["expected passed in green mode but was failed: Given an expired access token, when the client calls any route, then the response is 200"] }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 4), ["specify", "coder", "coder", "cleaner"]);
  assert.match(promptOf(calls, "coder", 1), /expected passed in green mode but was failed: Given an expired access token/);
});

test("build red routes back to the owning stage; build exit 2 escalates", async () => {
  const red = await dryRun({ guards: { build: [0, { exitCode: 1, tail: "TS2322: type error" }, 0] } });
  assert.deepEqual(stagesOf(red.labels).slice(0, 4), ["specify", "coder", "coder", "cleaner"]);
  assert.match(promptOf(red.calls, "coder", 1), /TS2322/);
  const broken = await dryRun({ guards: { build: [0, 2] } });
  assert.equal(broken.outcome.outcome, "escalate");
  assert.match(broken.outcome.reason, /harness: build guard operational failure/);
});

test("crap red routes to the cleaner with the offenders, whether after coder or after cleaner", async () => {
  const { calls, labels } = await dryRun({ guards: { crap: [{ exitCode: 1, offenders: [{ function: "handleRequest", crap: 756 }] }, { exitCode: 1, offenders: [{ function: "handleRequest", crap: 40 }] }, 0] } });
  assert.deepEqual(stagesOf(labels), ["specify", "coder", "cleaner", "cleaner", "qa", "ship"]);
  assert.match(promptOf(calls, "cleaner", 0), /"crap": 756/);
  assert.match(promptOf(calls, "cleaner", 1), /"crap": 40/);
});

test("the cleaner runs even when every gate after the coder is green", async () => {
  const { labels } = await dryRun();
  assert.ok(stagesOf(labels).includes("cleaner"));
});

test("coverage red retries once as a flake guard, then escalates — never routes to a code stage", async () => {
  const flake = await dryRun({ guards: { coverage: [0, 1, 0] } });
  assert.ok(flake.labels.includes("coverage:retry"));
  assert.equal(flake.outcome.outcome, "ship");
  const persistent = await dryRun({ guards: { coverage: [0, 1, 1] } });
  assert.equal(persistent.outcome.outcome, "escalate");
  assert.match(persistent.outcome.reason, /coverage: tests red after retry/);
  assert.deepEqual(stagesOf(persistent.labels), ["specify", "coder"]);
});

test("qa red once routes to the coder with the failed criteria; qa red again escalates as acceptance disagreeing with QA", async () => {
  const once = await dryRun({ guards: { qa: [{ exitCode: 1, failed: ["Given ten parallel 401s, when they resolve, then exactly one refresh call was made"], tail: "refresh called 3 times" }, 0] } });
  assert.deepEqual(stagesOf(once.labels), ["specify", "coder", "cleaner", "qa", "coder", "cleaner", "qa", "ship"]);
  assert.match(promptOf(once.calls, "coder", 1), /QA failed these criteria[\s\S]*Given ten parallel 401s/);
  assert.match(promptOf(once.calls, "coder", 1), /refresh called 3 times/);
  const twice = await dryRun({ guards: { qa: { exitCode: 1, failed: ["Given ten parallel 401s, when they resolve, then exactly one refresh call was made"] } } });
  assert.equal(twice.outcome.outcome, "escalate");
  assert.match(twice.outcome.reason, /spec: acceptance disagrees with QA/);
  assert.deepEqual(twice.outcome.failed, ["Given ten parallel 401s, when they resolve, then exactly one refresh call was made"]);
});

test("qa skipped by config still ships; qa exit 2 escalates as harness", async () => {
  const skipped = await dryRun({ guards: { qa: { exitCode: 0, skipped: true } } });
  assert.equal(skipped.outcome.outcome, "ship");
  const down = await dryRun({ guards: { qa: { exitCode: 2, tail: "did not answer" } } });
  assert.match(down.outcome.reason, /harness: qa guard operational failure/);
});

test("a fabricated or mis-nonced receipt is a conduit error: retried, then escalated as harness, never routed to a code stage", async () => {
  const fabricated = await dryRun({ guards: { build: [0, { conduit: "fabricated" }] } });
  assert.equal(fabricated.outcome.outcome, "escalate");
  assert.equal(fabricated.outcome.reason, "harness: conduit failed on build");
  assert.equal(fabricated.labels.filter((label) => label === "build").length, 3);
  assert.deepEqual(stagesOf(fabricated.labels), ["specify", "coder"]);
  const misnonced = await dryRun({ guards: { crap: { conduit: "wrong-nonce" } } });
  assert.equal(misnonced.outcome.reason, "harness: conduit failed on crap");
});

test("per-stage caps escalate with the stage name and the last findings", async () => {
  const { outcome, labels } = await dryRun({ guards: { "spec:red": { exitCode: 1, problems: ["0 tests named after criterion: X"] } } });
  assert.equal(outcome.reason, "specify: exhausted");
  assert.equal(stagesOf(labels).filter((label) => label === "specify").length, 3);
  assert.match(outcome.feedback, /0 tests named after criterion: X/);
  assert.equal(outcome.attempts.specify, 4);
});

test("ship is recorded only when a PR URL comes back; a blocked ship escalates", async () => {
  const blocked = await dryRun({ stages: { ship: { blocked: "pre-PR gate: no clean verdict for HEAD" } } });
  assert.equal(blocked.outcome.outcome, "escalate");
  assert.match(blocked.outcome.reason, /ship: no PR opened — pre-PR gate/);
  const silent = await dryRun({ stages: { ship: null } });
  assert.equal(silent.outcome.outcome, "escalate");
});

test("preflight red escalates before any stage runs and teardown still runs", async () => {
  const { outcome, labels } = await dryRun({ guards: { setup: 2 } });
  assert.match(outcome.reason, /harness: setup failed in preflight/);
  assert.deepEqual(stagesOf(labels), []);
  assert.ok(labels.includes("teardown"));
});

test("a verdict that cannot be written escalates before ship is attempted", async () => {
  const { outcome, labels } = await dryRun({ guards: { verdict: 2 } });
  assert.match(outcome.reason, /harness: verdict guard operational failure/);
  assert.ok(!labels.includes("ship"));
});

test("bootstrap that stays on main aborts the run", async () => {
  const source = readFileSync(new URL("./gauntlet.js", import.meta.url), "utf8");
  assert.match(source, /\/\^\(main\|master\)\$\/\.test\(boot\.branch\)/);
});
