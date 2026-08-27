/**
 * Gauntlet orchestrator — the state machine above the stages.
 *
 * Invoked by the /gauntlet skill only, with preflight's JSON as `args`:
 *   {repoRoot, headSha, branch, secret, ticket, from}
 * The skill has already resolved the ticket to .gauntlet/ticket.json, left main, minted the
 * run secret and run clean-tree, install, setup, build and coverage in plain shell — no
 * model touches preflight. `from` names the stage to enter at (default specify), so an
 * escalated run re-enters where it stopped: /gauntlet <ticket> --from <stage>.
 *
 *   specify -> [clean-tree, spec red]
 *   coder   -> [clean-tree, spec green, build, coverage, reachability, crap, depth]
 *   cleaner -> [the same gates]           (unconditional — Bob's cleaner)
 *   qa      -> [qa]                       (wire evidence: the guard counts requests through
 *                                          its relay; zero is red)
 *   verdict -> writes the pre-PR artefact for HEAD (the machine's signature, not a review's)
 *   ship    -> PR                         (outcome "ship" only with a PR URL)
 *
 * Every stage is a fresh-context agent bound by agentType to .claude/agents/gauntlet-<stage>.md.
 * A red gate feeds its findings into the owning stage's next prompt under a per-stage attempt
 * cap; exhausting a cap escalates. Reachability red routes to the coder (the change is not
 * wired in); crap and depth red route to the cleaner (the change is wired in but badly shaped).
 * A stage that returns with HEAD unchanged has refused its feedback and escalates at once —
 * re-gating an unchanged tree can only reproduce the same result.
 *
 * Execution contract (Claude Code Dynamic Workflows, verified 2026-08-25/26):
 *   - Plain JS with NO filesystem, NO shell, NO module loading. Every deterministic act is
 *     performed BY a spawned conduit agent running a fixed `run.py <guard> <nonce>`; the
 *     runner prints a receipt hashed over a per-run secret the conduit never sees, so a
 *     relayed result that does not verify is a conduit error — retried, then escalated as
 *     a harness fault, never routed to a code stage. clean-tree's `head` is a branch field:
 *     the receipt covers it, so a conduit that drops it fails verification.
 *   - The ticket never crosses the conduit: every stage prompt opens by sending the stage to
 *     .gauntlet/ticket.json. No stage runs `gh issue view`.
 *   - Exit codes: 0 pass, 1 red in code (route to the owning stage), 2 operational
 *     (escalate). clean-tree after a stage is the one exception: dirty routes back to that
 *     stage with "commit your work".
 */

export const meta = {
  name: "gauntlet-run",
  description:
    "Run a preflighted ticket through the gated gauntlet — specify, coder, cleaner, QA — and open a PR only behind the pre-PR gate. Invoked by the /gauntlet skill.",
  phases: [
    { title: "Specify", detail: "one red acceptance test per criterion" },
    { title: "Code", detail: "coder then cleaner, gated" },
    { title: "QA", detail: "criteria against the served system, with wire evidence" },
    { title: "Ship", detail: "open the PR" },
  ],
};

const MAX_STAGE_ATTEMPTS = 3;
const CONDUIT_RETRIES = 2;
const CHEAP_MODEL = "haiku";
const RUNNER = '"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gauntlet/run.py"';
const STAGES = ["specify", "coder", "cleaner", "qa", "ship"];

const ROLE_CONDUIT =
  "You are a verbatim conduit, not a reviewer. Run exactly the command given — no edits, no extra flags, no chained steps, no fixing. Do not judge, summarise, decide pass/fail, or re-run for a different answer; the workflow branches on the raw exit code and any interpretation you add corrupts it. Return the JSON line the command prints byte-for-byte.";

const guardSchema = {
  type: "object",
  properties: {
    nonce: { type: "string" },
    guard: { type: "string" },
    exitCode: { type: "integer" },
    receipt: { type: "string" },
    head: { type: "string" },
    tail: { type: "string" },
    log: { type: "string" },
    offenders: { type: "array", items: { type: "object" } },
    problems: { type: "array", items: { type: "string" } },
    criteria: { type: "array", items: { type: "string" } },
    passed: { type: "array", items: { type: "string" } },
    failed: { type: "array", items: { type: "string" } },
    requests: { type: "integer" },
    skipped: { type: "boolean" },
  },
  required: ["nonce", "guard", "exitCode", "receipt"],
  additionalProperties: true,
};

const treeSchema = { ...guardSchema, required: [...guardSchema.required, "head"] };

const shipSchema = {
  type: "object",
  properties: { prUrl: { type: "string" }, blocked: { type: "string" } },
  additionalProperties: false,
};

function fnv1a32(text) {
  let digest = 0x811c9dc5;
  for (let index = 0; index < text.length; index++) {
    digest = Math.imul(digest ^ (text.charCodeAt(index) & 0xff), 0x01000193) >>> 0;
  }
  return digest.toString(16).padStart(8, "0");
}

const boot = args && typeof args === "object" && !Array.isArray(args) ? args : null;
if (!boot || !boot.ok || !boot.secret || !boot.headSha || !boot.branch || !boot.repoRoot || !boot.ticket) {
  throw new Error("gauntlet-run: invoke through /gauntlet <ticket> — args must be preflight's JSON");
}
if (/^(main|master)$/.test(boot.branch)) throw new Error("gauntlet-run: preflight left the run on main");
const ticketRef = String(boot.ticket);
const entryStage = boot.from || "specify";
if (!STAGES.includes(entryStage)) throw new Error(`gauntlet-run: from must be one of ${STAGES.join(", ")}`);

let nonceCounter = 0;
const mintNonce = (guard) => `${boot.headSha.slice(0, 8)}-${guard}-${++nonceCounter}`;

function verified(result, nonce) {
  if (!result || result.nonce !== nonce) return false;
  if (result.guard === "clean-tree" && !result.head) return false;
  const signed = `${boot.secret}:${nonce}:${result.exitCode}${result.head ? `:${result.head}` : ""}`;
  if (result.receipt !== fnv1a32(signed)) return false;
  return true;
}

async function runGuard(guard, { argument, label, nonce, schema } = {}) {
  for (let attempt = 0; attempt <= CONDUIT_RETRIES; attempt++) {
    const currentNonce = nonce || mintNonce(guard);
    const command = `python3 ${RUNNER} ${guard} ${currentNonce}${argument ? ` ${argument}` : ""}`;
    const result = await agent(`${ROLE_CONDUIT}\n\nCommand (run from ${boot.repoRoot}):\n${command}`, {
      label: label || guard,
      schema: schema || guardSchema,
      model: CHEAP_MODEL,
    });
    if (verified(result, currentNonce)) return result;
    log(`gauntlet: conduit error on ${guard} (attempt ${attempt + 1}/${CONDUIT_RETRIES + 1})`);
  }
  return null;
}

function findings(result) {
  if (!result) return "";
  if (result.offenders && result.offenders.length) {
    return `\n\nThe ${result.guard} guard reports these offenders (fix exactly these):\n${JSON.stringify(result.offenders, null, 2)}`;
  }
  if (result.problems && result.problems.length) {
    return `\n\nThe ${result.guard} guard reports:\n- ${result.problems.join("\n- ")}`;
  }
  if (result.failed && result.failed.length) {
    return `\n\nQA failed these criteria against the running system:\n- ${result.failed.join("\n- ")}\n\nQA log tail:\n${result.tail || ""}`;
  }
  return result.tail ? `\n\nThe previous gate failed; its output tail:\n${result.tail}` : "";
}

let state = entryStage;

function escalate(reason, result, extra) {
  const reenter = `/gauntlet ${ticketRef} --from ${state}`;
  const outcome = { outcome: "escalate", ticket: ticketRef, reason, stage: state, reenter, ...(extra || {}) };
  if (result) {
    outcome.exitCode = result.exitCode;
    if (result.log) outcome.log = result.log;
    if (result.tail) outcome.tail = result.tail.slice(-600);
  }
  log(`gauntlet: ESCALATE — ${reason}${outcome.log ? ` (see ${outcome.log})` : ""}`);
  log(`gauntlet: re-enter with ${reenter}`);
  return outcome;
}

const attempts = { specify: 0, coder: 0, cleaner: 0, qa: 0 };
const exhausted = (stageName) => ++attempts[stageName] > MAX_STAGE_ATTEMPTS;

const TICKET = `Read .gauntlet/ticket.json first — it is ticket #${ticketRef} as {issue, title, body}, and its body carries the acceptance criteria. Never fetch the ticket any other way.`;

async function stage(name, task, feedback) {
  return await agent(`${TICKET}\n\n${task}${feedback || ""}`, { label: name, agentType: `gauntlet-${name}` });
}

const GATE = { ok: "ok", retry: "retry", coder: "coder", cleaner: "cleaner", escalate: "escalate" };

let head = boot.headSha;

async function committedTree(stageName) {
  const tree = await runGuard("clean-tree", { schema: treeSchema });
  if (!tree) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on clean-tree") };
  if (tree.exitCode !== 0) {
    return { verdict: GATE.retry, feedback: `\n\nYour previous attempt left uncommitted work — commit everything you changed (the ${stageName} stage owns its own commits), then return:\n${tree.tail || ""}` };
  }
  if (tree.head === head) {
    return { verdict: GATE.escalate, outcome: escalate(`${stageName}: returned with HEAD unchanged — the stage refused its feedback`, null) };
  }
  head = tree.head;
  return { verdict: GATE.ok };
}

async function operational(guard, options = {}) {
  const result = await runGuard(guard, options);
  if (!result) return { result: null, gate: { verdict: GATE.escalate, outcome: escalate(`harness: conduit failed on ${guard}`) } };
  if (result.exitCode === 2) return { result, gate: { verdict: GATE.escalate, outcome: escalate(`harness: ${guard} guard operational failure`, result) } };
  return { result, gate: null };
}

async function codeGates(stageName) {
  const tree = await committedTree(stageName);
  if (tree.verdict !== GATE.ok) return tree;

  const acceptance = await operational("spec", { argument: "green", label: "spec:green" });
  if (acceptance.gate) return acceptance.gate;
  if (acceptance.result.exitCode !== 0) return { verdict: GATE.retry, feedback: findings(acceptance.result) };

  const build = await operational("build");
  if (build.gate) return build.gate;
  if (build.result.exitCode !== 0) return { verdict: GATE.retry, feedback: findings(build.result) };

  let coverage = await operational("coverage");
  if (coverage.gate) return coverage.gate;
  if (coverage.result.exitCode === 1) {
    log("gauntlet: coverage red — retrying once as a flake guard before escalating");
    coverage = await operational("coverage", { label: "coverage:retry" });
    if (coverage.gate) return coverage.gate;
    if (coverage.result.exitCode !== 0) {
      return { verdict: GATE.escalate, outcome: escalate("coverage: tests red after retry — triage (ticket-caused vs pre-existing flake) before re-run", coverage.result) };
    }
  }

  const reachability = await operational("reachability");
  if (reachability.gate) return reachability.gate;
  if (reachability.result.exitCode !== 0) return { verdict: GATE.coder, feedback: findings(reachability.result) };

  const crap = await operational("crap");
  if (crap.gate) return crap.gate;
  if (crap.result.exitCode !== 0) return { verdict: GATE.cleaner, feedback: findings(crap.result) };

  const depth = await operational("depth");
  if (depth.gate) return depth.gate;
  if (depth.result.exitCode !== 0) return { verdict: GATE.cleaner, feedback: findings(depth.result) };

  return { verdict: GATE.ok };
}

let outcome = null;

try {
  let feedback = "";
  let qaRedOnce = false;

  while (!outcome && state !== "ship") {
    if (state === "specify") {
      phase("Specify");
      if (exhausted("specify")) { outcome = escalate("specify: exhausted", null, { feedback }); break; }
      await stage("specify", "Map the codebase first, then write one red acceptance test per acceptance criterion of this ticket, named verbatim after the criterion, in the repo's declared acceptance seam, driving the edge that already exists. Do not implement anything. Commit the tests. Your return names, per test, the edge it drives and the existing module that owns the behaviour.", feedback);
      const tree = await committedTree("specify");
      if (tree.verdict === GATE.escalate) { outcome = tree.outcome; break; }
      if (tree.verdict === GATE.retry) { feedback = tree.feedback; continue; }
      const red = await operational("spec", { argument: "red", label: "spec:red" });
      if (red.gate) { outcome = red.gate.outcome; break; }
      if (red.result.exitCode !== 0) { feedback = findings(red.result); continue; }
      feedback = "";
      state = "coder";
      continue;
    }

    if (state === "coder") {
      phase("Code");
      if (exhausted("coder")) { outcome = escalate("coder: exhausted", null, { feedback }); break; }
      await stage("coder", "Make the acceptance tests for this ticket pass with the minimum correct change that climbs the ladder — deepen the existing module the tests reach before creating a new one — keeping build and typecheck green. Commit your work.", feedback);
      const gate = await codeGates("coder");
      if (gate.verdict === GATE.escalate) { outcome = gate.outcome; break; }
      if (gate.verdict === GATE.retry || gate.verdict === GATE.coder) { feedback = gate.feedback; continue; }
      feedback = gate.verdict === GATE.cleaner ? gate.feedback : "";
      state = "cleaner";
      continue;
    }

    if (state === "cleaner") {
      if (exhausted("cleaner")) { outcome = escalate("cleaner: exhausted", null, { feedback }); break; }
      await stage("cleaner", "Clean up the change for this ticket without changing behaviour: fix any offenders listed below, merge any new module into the existing module that already owns its responsibility, then apply the Standards, Structure and Design baselines to the diff since the merge-base. Commit your work.", feedback);
      const gate = await codeGates("cleaner");
      if (gate.verdict === GATE.escalate) { outcome = gate.outcome; break; }
      if (gate.verdict === GATE.ok) { feedback = ""; state = "qa"; continue; }
      if (gate.verdict === GATE.coder) { feedback = gate.feedback; state = "coder"; continue; }
      feedback = gate.feedback;
      continue;
    }

    if (state === "qa") {
      phase("QA");
      if (exhausted("qa")) { outcome = escalate("qa: exhausted", null, { feedback }); break; }
      const nonce = mintNonce("qa");
      await stage("qa", `Prove each acceptance criterion of this ticket against the running system from the outside. Write a bash script to .gauntlet/qa/${nonce}.sh that uses $GAUNTLET_URL, drives the served system, and prints exactly one line per criterion: "PASS <criterion verbatim>" or "FAIL <criterion verbatim>". Every request must go through $GAUNTLET_URL — the guard counts them, and a script that makes none is red. Do not read or run the repo's tests. Calibrate the script with python3 ${RUNNER} qa-dry ${nonce} (free, at most three) until every criterion prints a verdict you can explain, then return.`, feedback);
      const qa = await operational("qa", { nonce, label: "qa-guard" });
      if (qa.gate) { outcome = qa.gate.outcome; break; }
      if (qa.result.exitCode !== 0) {
        if (qa.result.requests === 0) { feedback = findings(qa.result); continue; }
        if (qaRedOnce) { outcome = escalate("spec: acceptance disagrees with QA — the acceptance tests pass but QA fails the same criteria; the acceptance tests are too weak", qa.result, { failed: qa.result.failed }); break; }
        qaRedOnce = true;
        feedback = findings(qa.result);
        state = "coder";
        continue;
      }
      feedback = "";
      state = "ship";
      break;
    }
  }

  if (!outcome) {
    phase("Ship");
    const verdict = await runGuard("verdict");
    if (!verdict) outcome = escalate("harness: conduit failed on verdict");
    else if (verdict.exitCode !== 0) outcome = escalate("harness: verdict guard operational failure", verdict);
  }

  if (!outcome) {
    const ship = await agent(
      `Every gauntlet gate is green for ticket #${ticketRef} on branch ${boot.branch}. Push the branch and open the pull request with 'gh pr create', body summarising the acceptance criteria now proven. The pre-PR hook may block; if it does, stop and return {blocked: <its message>} rather than retrying. On success return {prUrl}.`,
      { label: "ship", agentType: "gauntlet-ship", schema: shipSchema }
    );
    if (ship && /^https?:\/\//.test(ship.prUrl || "")) {
      outcome = { outcome: "ship", ticket: ticketRef, prUrl: ship.prUrl };
      log(`gauntlet: SHIP — ${ship.prUrl}`);
    } else {
      outcome = escalate(`ship: no PR opened${ship && ship.blocked ? ` — ${ship.blocked}` : ""}`);
    }
  }
} finally {
  await runGuard("teardown");
}

return { ...outcome, attempts };
