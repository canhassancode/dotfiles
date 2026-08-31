import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("./gauntlet-run.js", import.meta.url), "utf8").replace(/^export const meta/m, "const meta");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const script = new AsyncFunction("agent", "log", "phase", "parallel", "pipeline", "workflow", "args", "budget", source);

const SECRET = "s3cret";
const HEAD = "abcdef0123456789";
const PR_URL = "https://github.com/oneforge/brushfeed/pull/9";
const PREFLIGHT = { ok: true, repoRoot: "/r", headSha: HEAD, secret: SECRET, branch: "gauntlet/63", ticket: "63", from: "specify" };

function fnv1a32(text) {
  let digest = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) digest = Math.imul(digest ^ byte, 0x01000193) >>> 0;
  return digest.toString(16).padStart(8, "0");
}

function next(scripted) {
  if (!Array.isArray(scripted)) return scripted ?? 0;
  return scripted.length > 1 ? scripted.shift() : scripted[0];
}

const RELAYED_FIELDS = ["nonce", "guard", "exitCode", "receipt", "head", "failed"];
const hostileRelay = (result) => Object.fromEntries(Object.entries(result).filter(([field]) => RELAYED_FIELDS.includes(field)));

const GATE_CHAINS = {
  specify: ["clean-tree", "spec:red"],
  code: ["clean-tree", "spec:green", "build", "coverage", "reachability", "crap", "depth"],
};
const GATE_STOPS_AT = ["clean-tree", "build", "coverage"];
const gateReceipt = (nonce, exitCode, failed, head) => fnv1a32(`${SECRET}:${nonce}:${exitCode}:${failed || "-"}:${head}`);

async function dryRun({ guards = {}, stages = {}, args = PREFLIGHT, hostile = false } = {}) {
  const scriptedGuards = structuredClone(guards);
  const calls = [];
  const logs = [];
  const ran = [];
  let commits = 0;
  const scriptedFor = (key) => {
    ran.push(key);
    const scripted = next(scriptedGuards[key]);
    return typeof scripted === "number" ? { exitCode: scripted } : scripted;
  };
  function hostileConduit(scripted, nonce, guard) {
    if (scripted.conduit === "fabricated") return { nonce, guard, exitCode: 0, failed: null, head: "x", receipt: "deadbeef" };
    if (scripted.conduit === "wrong-nonce") return { nonce: "other", guard, exitCode: 0, failed: null, head: "x", receipt: gateReceipt("other", 0, null, "x") };
    if (scripted.conduit === "dropped-head") return { nonce, guard, exitCode: 0, failed: null, receipt: gateReceipt(nonce, 0, null, "") };
    if (scripted.conduit === "renamed-failed") return { nonce, guard, exitCode: 1, failed: "build", head: "x", receipt: gateReceipt(nonce, 1, "crap", "x") };
    return null;
  }
  function runGate(nonce, chain) {
    const findings = {};
    let failed = null;
    let exitCode = 0;
    let head = "";
    for (const key of GATE_CHAINS[chain]) {
      const guard = key.split(":")[0];
      let scripted = scriptedFor(key);
      const hostile = hostileConduit(scripted, nonce, "gate");
      if (hostile) return hostile;
      if (guard === "coverage" && scripted.exitCode === 1) scripted = scriptedFor(key);
      const { conduit, ...fields } = scripted;
      if (guard === "clean-tree") {
        head = "head" in fields ? fields.head : fields.exitCode === 0 ? `commit-${++commits}` : "dirty";
        fields.exitCode = Math.min(fields.exitCode, 1);
      }
      findings[guard] = fields;
      if (fields.exitCode === 0) continue;
      if (failed === null) { failed = guard; exitCode = fields.exitCode; }
      if (exitCode === 2 || GATE_STOPS_AT.includes(guard)) break;
    }
    const tail = Object.entries(findings).filter(([, f]) => f.exitCode !== 0).map(([g, f]) => `[${g}]\n${f.tail || ""}`).join("\n\n");
    return { nonce, guard: "gate", exitCode, failed, head, findings, tail, receipt: gateReceipt(nonce, exitCode, failed, head) };
  }
  async function agent(prompt, options = {}) {
    const call = { prompt, ...options };
    calls.push(call);
    const label = options.label || "";
    const invocation = prompt.match(/run\.py"?\s+(\S+)\s+(\S+)(?:\s+(\S+))?/);
    if (invocation) {
      const [, guard, nonce, argument] = invocation;
      if (guard === "gate") {
        const result = runGate(nonce, argument);
        return hostile ? hostileRelay(result) : result;
      }
      const scripted = scriptedFor(guard);
      const bad = hostileConduit(scripted, nonce, guard);
      if (bad) return bad;
      const { conduit, ...fields } = scripted;
      const result = { nonce, guard, ...fields };
      result.receipt = fnv1a32(`${SECRET}:${nonce}:${result.exitCode}`);
      return hostile ? hostileRelay(result) : result;
    }
    if (label === "ship") return stages.ship === undefined ? { prUrl: PR_URL } : stages.ship;
    const stage = stages[label];
    return typeof stage === "function" ? stage(prompt, options) : (stage ?? "done");
  }
  const outcome = await script(agent, (line) => logs.push(line), () => {}, null, null, null, args, { total: null, spent: () => 0, remaining: () => Infinity });
  return { outcome, calls, logs, ran, labels: calls.map((call) => call.label) };
}

const STAGE_LABELS = new Set(["specify", "coder", "cleaner", "qa", "ship"]);
const stagesOf = (labels) => labels.filter((label) => STAGE_LABELS.has(label));
const conduitsOf = (labels) => labels.filter((label) => !STAGE_LABELS.has(label));

test("all green: specify → coder → cleaner → qa → ship, no model before specify, and ship only with a PR URL", async () => {
  const { outcome, labels, calls } = await dryRun();
  assert.deepEqual(stagesOf(labels), ["specify", "coder", "cleaner", "qa", "ship"]);
  assert.equal(labels[0], "specify");
  assert.deepEqual(labels, ["specify", "gate:specify", "coder", "gate:code", "cleaner", "gate:code", "qa", "qa-guard", "verdict", "ship", "teardown"]);
  assert.equal(conduitsOf(labels).length, 6);
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

test("the run refuses to start without preflight's args or from main", async () => {
  await assert.rejects(dryRun({ args: "63" }), /invoke through \/gauntlet/);
  await assert.rejects(dryRun({ args: { ...PREFLIGHT, ok: false } }), /invoke through \/gauntlet/);
  await assert.rejects(dryRun({ args: { ...PREFLIGHT, branch: "main" } }), /left the run on main/);
  await assert.rejects(dryRun({ args: { ...PREFLIGHT, from: "review" } }), /from must be one of/);
});

test("--from re-enters at the named stage with the gates that follow it", async () => {
  const qa = await dryRun({ args: { ...PREFLIGHT, from: "qa" } });
  assert.deepEqual(qa.labels, ["qa", "qa-guard", "verdict", "ship", "teardown"]);
  assert.equal(qa.outcome.outcome, "ship");
  const coder = await dryRun({ args: { ...PREFLIGHT, from: "coder" } });
  assert.deepEqual(stagesOf(coder.labels), ["coder", "cleaner", "qa", "ship"]);
  const ship = await dryRun({ args: { ...PREFLIGHT, from: "ship" } });
  assert.deepEqual(ship.labels, ["verdict", "ship", "teardown"]);
});

test("a hostile conduit that relays only the receipt-verified fields still ships", async () => {
  const { outcome, calls } = await dryRun({ hostile: true });
  assert.equal(outcome.outcome, "ship");
  for (const stage of STAGE_LABELS) assert.doesNotMatch(promptOf(calls, stage), /undefined/);
});

test("every field the workflow verifies a guard result by is one a conduit schema requires", () => {
  const verifiedFields = [...source.match(/function verified[\s\S]*?\n\}/)[0].matchAll(/result\.(\w+)/g)].map((match) => match[1]);
  const required = JSON.parse(source.match(/const guardSchema = \{[\s\S]*?required: (\[[^\]]*\])/)[1]);
  const gateRequired = [...source.match(/const gateSchema = \{[\s\S]*?required: \[([^\]]*)\]/)[1].matchAll(/"(\w+)"/g)].map((match) => match[1]);
  assert.ok(verifiedFields.length >= 4);
  for (const field of verifiedFields) assert.ok([...required, ...gateRequired].includes(field), `verified() reads ${field} but no conduit schema requires it`);
});

test("a gate's head is receipt-covered: a conduit that drops it is retried, then escalated as harness", async () => {
  const { outcome, labels } = await dryRun({ guards: { "clean-tree": { conduit: "dropped-head" } } });
  assert.equal(outcome.outcome, "escalate");
  assert.equal(outcome.reason, "harness: conduit failed on gate specify");
  assert.equal(labels.filter((label) => label === "gate:specify").length, 3);
});

test("a gate's failed guard is receipt-covered: a conduit that renames it is retried, then escalated as harness, never routed to a code stage", async () => {
  const { outcome, labels } = await dryRun({ guards: { crap: { conduit: "renamed-failed" } } });
  assert.equal(outcome.outcome, "escalate");
  assert.equal(outcome.reason, "harness: conduit failed on gate code");
  assert.equal(labels.filter((label) => label === "gate:code").length, 3);
  assert.deepEqual(stagesOf(labels), ["specify", "coder"]);
});

test("a stage that returns with HEAD unchanged escalates at once, naming it and the re-entry command", async () => {
  const { outcome, labels } = await dryRun({ guards: { "clean-tree": { exitCode: 0, head: HEAD } } });
  assert.equal(outcome.outcome, "escalate");
  assert.match(outcome.reason, /specify: returned with HEAD unchanged/);
  assert.equal(outcome.reenter, "/gauntlet 63 --from specify");
  assert.deepEqual(labels, ["specify", "gate:specify", "teardown"]);
});

test("a retry that refuses its feedback escalates instead of re-gating", async () => {
  const { outcome, labels, ran } = await dryRun({ guards: { "clean-tree": [{ exitCode: 0, head: "c1" }, { exitCode: 0, head: "c1" }], "spec:red": { exitCode: 1, problems: ["mocks src/config"] } } });
  assert.deepEqual(stagesOf(labels), ["specify", "specify"]);
  assert.equal(ran.filter((guard) => guard === "spec:red").length, 2);
  assert.match(outcome.reason, /specify: returned with HEAD unchanged/);
});

test("spec red failing routes back to specify with the problems in the retry prompt", async () => {
  const { calls, labels } = await dryRun({ guards: { "spec:red": [{ exitCode: 1, problems: ["0 tests named after criterion: Given ten parallel 401s, when they resolve, then exactly one refresh call was made"] }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 3), ["specify", "specify", "coder"]);
  assert.match(promptOf(calls, "specify", 1), /0 tests named after criterion: Given ten parallel 401s/);
});

test("a dirty tree after a stage re-prompts the same stage to commit", async () => {
  const { calls, labels } = await dryRun({ guards: { "clean-tree": [0, { exitCode: 2, tail: "M src/a.ts" }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 3), ["specify", "coder", "coder"]);
  assert.match(promptOf(calls, "coder", 1), /commit everything you changed/);
  assert.match(promptOf(calls, "coder", 1), /M src\/a\.ts/);
});

test("spec green red after the coder routes back to the coder with the failing names", async () => {
  const { calls, labels } = await dryRun({ guards: { "spec:green": [{ exitCode: 1, problems: ["expected passed in green mode but was failed: Given an expired access token, when the client calls any route, then the response is 200"] }, 0] } });
  assert.deepEqual(stagesOf(labels).slice(0, 4), ["specify", "coder", "coder", "cleaner"]);
  assert.match(promptOf(calls, "coder", 1), /expected passed in green mode but was failed: Given an expired access token/);
});

test("build red routes back to the owning stage; build exit 2 escalates", async () => {
  const red = await dryRun({ guards: { build: [{ exitCode: 1, tail: "TS2322: type error" }, 0] } });
  assert.deepEqual(stagesOf(red.labels).slice(0, 4), ["specify", "coder", "coder", "cleaner"]);
  assert.match(promptOf(red.calls, "coder", 1), /TS2322/);
  const broken = await dryRun({ guards: { build: 2 } });
  assert.equal(broken.outcome.outcome, "escalate");
  assert.match(broken.outcome.reason, /harness: build guard operational failure/);
});

test("reachability red routes to the coder naming the orphan, whether after coder or after cleaner", async () => {
  const orphan = "src/lib/sessionClient.ts is reached by nothing: not an edge and imported from no edge or pre-existing file";
  const afterCoder = await dryRun({ guards: { reachability: [{ exitCode: 1, problems: [orphan] }, 0] } });
  assert.deepEqual(stagesOf(afterCoder.labels), ["specify", "coder", "coder", "cleaner", "qa", "ship"]);
  assert.match(promptOf(afterCoder.calls, "coder", 1), /reachability guard reports:[\s\S]*sessionClient\.ts is reached by nothing/);
  const afterCleaner = await dryRun({ guards: { reachability: [0, { exitCode: 1, problems: [orphan] }, 0] } });
  assert.deepEqual(stagesOf(afterCleaner.labels), ["specify", "coder", "cleaner", "coder", "cleaner", "qa", "ship"]);
  assert.match(promptOf(afterCleaner.calls, "coder", 1), /sessionClient\.ts is reached by nothing/);
});

test("crap and depth both red route to the cleaner once, with both guards' offenders in the same prompt", async () => {
  const { calls, labels } = await dryRun({ guards: { crap: [{ exitCode: 1, offenders: [{ function: "handleRequest", crap: 756 }] }, 0], depth: [{ exitCode: 1, offenders: [{ file: "src/lib/index.ts", exports: 3, lines: 3, depth: 1 }] }, 0] } });
  assert.deepEqual(stagesOf(labels), ["specify", "coder", "cleaner", "qa", "ship"]);
  assert.equal(labels.filter((label) => label === "gate:code").length, 2);
  assert.match(promptOf(calls, "cleaner", 0), /crap guard reports these offenders[\s\S]*"crap": 756/);
  assert.match(promptOf(calls, "cleaner", 0), /depth guard reports these offenders[\s\S]*"file": "src\/lib\/index\.ts"/);
});

test("a red build stops the chain: coverage, reachability, crap and depth do not run, and the coder retry carries the build output", async () => {
  const { calls, ran } = await dryRun({ guards: { build: [{ exitCode: 1, tail: "TS2322: type error" }, 0] } });
  const firstCodeGate = ran.slice(ran.indexOf("build"));
  assert.deepEqual(firstCodeGate.slice(0, 2), ["build", "clean-tree"]);
  assert.match(promptOf(calls, "coder", 1), /TS2322/);
});

test("the cleaner runs even when every gate after the coder is green", async () => {
  const { labels } = await dryRun();
  assert.ok(stagesOf(labels).includes("cleaner"));
});

test("coverage red retries once as a flake guard, then escalates — never routes to a code stage", async () => {
  const flake = await dryRun({ guards: { coverage: [1, 0] } });
  assert.equal(flake.ran.filter((guard) => guard === "coverage").length, 3);
  assert.equal(flake.labels.filter((label) => label === "gate:code").length, 2);
  assert.equal(flake.outcome.outcome, "ship");
  const persistent = await dryRun({ guards: { coverage: 1 } });
  assert.equal(persistent.outcome.outcome, "escalate");
  assert.match(persistent.outcome.reason, /coverage: tests red after retry/);
  assert.equal(persistent.outcome.reenter, "/gauntlet 63 --from coder");
  assert.deepEqual(stagesOf(persistent.labels), ["specify", "coder"]);
});

test("qa red once routes to the coder with the failed criteria; qa red again escalates as acceptance disagreeing with QA", async () => {
  const once = await dryRun({ guards: { qa: [{ exitCode: 1, requests: 4, failed: ["Given ten parallel 401s, when they resolve, then exactly one refresh call was made"], tail: "refresh called 3 times" }, 0] } });
  assert.deepEqual(stagesOf(once.labels), ["specify", "coder", "cleaner", "qa", "coder", "cleaner", "qa", "ship"]);
  assert.match(promptOf(once.calls, "coder", 1), /QA failed these criteria[\s\S]*Given ten parallel 401s/);
  assert.match(promptOf(once.calls, "coder", 1), /refresh called 3 times/);
  const twice = await dryRun({ guards: { qa: { exitCode: 1, requests: 4, failed: ["Given ten parallel 401s, when they resolve, then exactly one refresh call was made"] } } });
  assert.equal(twice.outcome.outcome, "escalate");
  assert.match(twice.outcome.reason, /spec: acceptance disagrees with QA/);
  assert.equal(twice.outcome.reenter, "/gauntlet 63 --from qa");
});

test("qa that never touched the served system re-prompts qa, not the coder, and exhausts", async () => {
  const noWire = { exitCode: 1, requests: 0, passed: ["Given a, when b, then c"], failed: [], tail: "QA made 0 requests to the served system through GAUNTLET_URL" };
  const { outcome, labels, calls } = await dryRun({ guards: { qa: noWire } });
  assert.deepEqual(stagesOf(labels), ["specify", "coder", "cleaner", "qa", "qa", "qa"]);
  assert.match(promptOf(calls, "qa", 1), /0 requests to the served system/);
  assert.equal(outcome.reason, "qa: exhausted");
  assert.match(promptOf(calls, "qa", 0), /Every request must go through \$GAUNTLET_URL/);
});

test("qa skipped by config still ships; qa exit 2 escalates as harness", async () => {
  const skipped = await dryRun({ guards: { qa: { exitCode: 0, skipped: true } } });
  assert.equal(skipped.outcome.outcome, "ship");
  const down = await dryRun({ guards: { qa: { exitCode: 2, tail: "did not answer" } } });
  assert.match(down.outcome.reason, /harness: qa guard operational failure/);
  assert.equal(down.outcome.reenter, "/gauntlet 63 --from qa");
});

test("a fabricated or mis-nonced receipt is a conduit error: retried, then escalated as harness, never routed to a code stage", async () => {
  const fabricated = await dryRun({ guards: { build: { conduit: "fabricated" } } });
  assert.equal(fabricated.outcome.outcome, "escalate");
  assert.equal(fabricated.outcome.reason, "harness: conduit failed on gate code");
  assert.equal(fabricated.labels.filter((label) => label === "gate:code").length, 3);
  assert.deepEqual(stagesOf(fabricated.labels), ["specify", "coder"]);
  const misnonced = await dryRun({ guards: { verdict: { conduit: "wrong-nonce" } } });
  assert.equal(misnonced.outcome.reason, "harness: conduit failed on verdict");
});

test("per-stage caps escalate with the stage name and the last findings", async () => {
  const { outcome, labels } = await dryRun({ guards: { "spec:red": { exitCode: 1, problems: ["0 tests named after criterion: X"] } } });
  assert.equal(outcome.reason, "specify: exhausted");
  assert.equal(stagesOf(labels).filter((label) => label === "specify").length, 3);
  assert.match(outcome.feedback, /0 tests named after criterion: X/);
  assert.equal(outcome.attempts.specify, 4);
});

test("ship is recorded only when a PR URL comes back; a blocked ship escalates with re-entry at ship", async () => {
  const blocked = await dryRun({ stages: { ship: { blocked: "pre-PR gate: no clean verdict for HEAD" } } });
  assert.equal(blocked.outcome.outcome, "escalate");
  assert.match(blocked.outcome.reason, /ship: no PR opened — pre-PR gate/);
  assert.equal(blocked.outcome.reenter, "/gauntlet 63 --from ship");
  const silent = await dryRun({ stages: { ship: null } });
  assert.equal(silent.outcome.outcome, "escalate");
});

test("a verdict that cannot be written escalates before ship is attempted, and teardown always runs", async () => {
  const { outcome, labels } = await dryRun({ guards: { verdict: 2 } });
  assert.match(outcome.reason, /harness: verdict guard operational failure/);
  assert.ok(!labels.includes("ship"));
  assert.equal(labels.at(-1), "teardown");
});

test("stage prompts carry the seam, ladder and merge instructions", async () => {
  const { calls } = await dryRun();
  assert.match(promptOf(calls, "specify"), /names, per test, the edge it drives and the existing module/);
  assert.match(promptOf(calls, "coder"), /climbs the ladder/);
  assert.match(promptOf(calls, "cleaner"), /merge any new module into the existing module/);
});
