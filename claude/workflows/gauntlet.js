/**
 * Gauntlet orchestrator — the state machine above the stages.
 *
 * Bootstrap (never on main) -> ticket (hash-verified) -> pre-flight (clean-tree, install,
 * setup, build, coverage, each gated once against the untouched tree) then
 *
 *   specify -> [clean-tree, spec red]
 *   coder   -> [clean-tree, spec green, build, coverage, crap]
 *   cleaner -> [the same gates]           (unconditional — Bob's cleaner)
 *   qa      -> [qa]                       (drives the served system from the criteria only)
 *   verdict -> writes the pre-PR artefact for HEAD (the machine's signature, not a review's)
 *   ship    -> PR                         (outcome "ship" only with a PR URL)
 *
 * Every stage is a fresh-context agent bound by agentType to .claude/agents/gauntlet-<stage>.md,
 * whose tool set is the deterministic layer. A red gate feeds its findings into the owning
 * stage's next prompt under a per-stage attempt cap; exhausting a cap escalates.
 *
 * Execution contract (Claude Code Dynamic Workflows, verified 2026-08-25/26):
 *   - Plain JS with NO filesystem, NO shell, NO module loading. Every deterministic act is
 *     performed BY a spawned conduit agent running a fixed `run.py <guard> <nonce>`; the
 *     runner prints a receipt hashed over a per-run secret the conduit never sees, so a
 *     relayed result that does not verify is a conduit error — retried, then escalated as
 *     a harness fault, never routed to a code stage.
 *   - The ticket never crosses the conduit: run.py fetches it and persists .gauntlet/ticket.json
 *     ({issue, title, body}); the workflow receives only the receipt, and every stage prompt
 *     opens by sending the stage to that file. No stage runs `gh issue view`.
 *   - Exit codes: 0 pass, 1 red in code (route to the owning stage), 2 operational
 *     (escalate). clean-tree after a stage is the one exception: dirty routes back to that
 *     stage with "commit your work".
 */

export const meta = {
  name: "gauntlet",
  description:
    "Run a ticket through the gated gauntlet — specify, coder, cleaner, QA — and open a PR only behind the pre-PR gate.",
  phases: [
    { title: "Pre-flight", detail: "ticket, environment, baseline" },
    { title: "Specify", detail: "one red acceptance test per criterion" },
    { title: "Code", detail: "coder then cleaner, gated" },
    { title: "QA", detail: "criteria against the served system" },
    { title: "Ship", detail: "open the PR" },
  ],
};

const MAX_STAGE_ATTEMPTS = 3;
const CONDUIT_RETRIES = 2;
const CHEAP_MODEL = "haiku";
const RUNNER = '"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gauntlet/run.py"';

const ROLE_CONDUIT =
  "You are a verbatim conduit, not a reviewer. Run exactly the command given — no edits, no extra flags, no chained steps, no fixing. Do not judge, summarise, decide pass/fail, or re-run for a different answer; the workflow branches on the raw exit code and any interpretation you add corrupts it. Return the JSON line the command prints byte-for-byte.";

const guardSchema = {
  type: "object",
  properties: {
    nonce: { type: "string" },
    guard: { type: "string" },
    exitCode: { type: "integer" },
    receipt: { type: "string" },
    tail: { type: "string" },
    log: { type: "string" },
    offenders: { type: "array", items: { type: "object" } },
    problems: { type: "array", items: { type: "string" } },
    criteria: { type: "array", items: { type: "string" } },
    passed: { type: "array", items: { type: "string" } },
    failed: { type: "array", items: { type: "string" } },
    skipped: { type: "boolean" },
  },
  required: ["nonce", "guard", "exitCode", "receipt"],
  additionalProperties: true,
};

const bootstrapSchema = {
  type: "object",
  properties: {
    repoRoot: { type: "string" },
    headSha: { type: "string" },
    secret: { type: "string" },
    branch: { type: "string" },
  },
  required: ["repoRoot", "headSha", "secret", "branch"],
  additionalProperties: false,
};

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

const ticketRef = (typeof args === "string" ? args : Array.isArray(args) ? args.join(" ") : "").trim();
if (!ticketRef) throw new Error("gauntlet: invoke as /gauntlet <issue-number>");

phase("Pre-flight");

const boot = await agent(
  `Bootstrap a gauntlet run for ticket ${ticketRef}. From the repo root (git rev-parse --show-toplevel): if the current branch is main or master, create and switch to gauntlet/${ticketRef}; otherwise stay on the current branch. Create .gauntlet/ if missing and write a fresh random token to .gauntlet/run-secret using \`python3 -c "import secrets; print(secrets.token_hex(8))" > .gauntlet/run-secret\`. Return repoRoot, headSha (git rev-parse HEAD), branch (git branch --show-current) and secret (the exact contents of .gauntlet/run-secret, trimmed).`,
  { label: "bootstrap", schema: bootstrapSchema, model: CHEAP_MODEL }
);
if (!boot || !boot.secret || !boot.branch || /^(main|master)$/.test(boot.branch)) {
  throw new Error("gauntlet: bootstrap failed to leave main or mint a run secret");
}

let nonceCounter = 0;
const mintNonce = (guard) => `${boot.headSha.slice(0, 8)}-${guard}-${++nonceCounter}`;

function verified(result, nonce) {
  if (!result || result.nonce !== nonce) return false;
  if (result.receipt !== fnv1a32(`${boot.secret}:${nonce}:${result.exitCode}`)) return false;
  return true;
}

async function runGuard(guard, { argument, label, nonce } = {}) {
  for (let attempt = 0; attempt <= CONDUIT_RETRIES; attempt++) {
    const currentNonce = nonce || mintNonce(guard);
    const command = `python3 ${RUNNER} ${guard} ${currentNonce}${argument ? ` ${argument}` : ""}`;
    const result = await agent(`${ROLE_CONDUIT}\n\nCommand (run from ${boot.repoRoot}):\n${command}`, {
      label: label || guard,
      schema: guardSchema,
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
    return `\n\nThe CRAP guard reports these offenders (fix exactly these):\n${JSON.stringify(result.offenders, null, 2)}`;
  }
  if (result.problems && result.problems.length) {
    return `\n\nThe acceptance guard (${result.guard}) reports:\n- ${result.problems.join("\n- ")}`;
  }
  if (result.failed && result.failed.length) {
    return `\n\nQA failed these criteria against the running system:\n- ${result.failed.join("\n- ")}\n\nQA log tail:\n${result.tail || ""}`;
  }
  return result.tail ? `\n\nThe previous gate failed; its output tail:\n${result.tail}` : "";
}

function escalate(reason, result, extra) {
  const outcome = { outcome: "escalate", ticket: ticketRef, reason, ...(extra || {}) };
  if (result) {
    outcome.exitCode = result.exitCode;
    if (result.log) outcome.log = result.log;
    if (result.tail) outcome.tail = result.tail.slice(-600);
  }
  log(`gauntlet: ESCALATE — ${reason}${outcome.log ? ` (see ${outcome.log})` : ""}`);
  return outcome;
}

const attempts = { specify: 0, coder: 0, cleaner: 0, qa: 0 };
const exhausted = (stageName) => ++attempts[stageName] > MAX_STAGE_ATTEMPTS;

const ticket = await runGuard("ticket", { argument: ticketRef });
if (!ticket) throw new Error("gauntlet: harness: ticket — could not deliver a hash-verified ticket");
if (ticket.exitCode !== 0) throw new Error(`gauntlet: harness: ticket — ${ticket.tail || "gh issue view failed"}`);

const TICKET = `Read .gauntlet/ticket.json first — it is ticket #${ticketRef} as {issue, title, body}, and its body carries the acceptance criteria. Never fetch the ticket any other way.`;

async function stage(name, task, feedback) {
  return await agent(`${TICKET}\n\n${task}${feedback || ""}`, { label: name, agentType: `gauntlet-${name}` });
}

async function preflight() {
  for (const guard of ["clean-tree", "install", "setup", "build", "coverage"]) {
    const result = await runGuard(guard, { label: `preflight:${guard}` });
    if (!result) return escalate(`harness: conduit failed on ${guard}`);
    if (result.exitCode !== 0) return escalate(`harness: ${guard} failed in preflight`, result);
  }
  return null;
}

const GATE = { ok: "ok", retry: "retry", cleaner: "cleaner", escalate: "escalate" };

async function committedTree(stageName) {
  const tree = await runGuard("clean-tree");
  if (!tree) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on clean-tree") };
  if (tree.exitCode !== 0) {
    return { verdict: GATE.retry, feedback: `\n\nYour previous attempt left uncommitted work — commit everything you changed (the ${stageName} stage owns its own commits), then return:\n${tree.tail || ""}` };
  }
  return { verdict: GATE.ok };
}

async function codeGates(stageName) {
  const tree = await committedTree(stageName);
  if (tree.verdict !== GATE.ok) return tree;

  const acceptance = await runGuard("spec", { argument: "green", label: "spec:green" });
  if (!acceptance) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on spec") };
  if (acceptance.exitCode === 2) return { verdict: GATE.escalate, outcome: escalate("harness: spec guard operational failure", acceptance) };
  if (acceptance.exitCode !== 0) return { verdict: GATE.retry, feedback: findings(acceptance) };

  const build = await runGuard("build");
  if (!build) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on build") };
  if (build.exitCode === 2) return { verdict: GATE.escalate, outcome: escalate("harness: build guard operational failure", build) };
  if (build.exitCode !== 0) return { verdict: GATE.retry, feedback: findings(build) };

  let coverage = await runGuard("coverage");
  if (!coverage) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on coverage") };
  if (coverage.exitCode === 2) return { verdict: GATE.escalate, outcome: escalate("harness: coverage guard operational failure", coverage) };
  if (coverage.exitCode === 1) {
    log("gauntlet: coverage red — retrying once as a flake guard before escalating");
    coverage = await runGuard("coverage", { label: "coverage:retry" });
    if (!coverage) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on coverage") };
    if (coverage.exitCode === 2) return { verdict: GATE.escalate, outcome: escalate("harness: coverage guard operational failure", coverage) };
    if (coverage.exitCode !== 0) {
      return { verdict: GATE.escalate, outcome: escalate("coverage: tests red after retry — triage (ticket-caused vs pre-existing flake) before re-run", coverage) };
    }
  }

  const crap = await runGuard("crap");
  if (!crap) return { verdict: GATE.escalate, outcome: escalate("harness: conduit failed on crap") };
  if (crap.exitCode === 2) return { verdict: GATE.escalate, outcome: escalate("harness: crap guard operational failure", crap) };
  if (crap.exitCode !== 0) return { verdict: GATE.cleaner, feedback: findings(crap) };

  return { verdict: GATE.ok };
}

let outcome = null;
let setupRan = false;

try {
  outcome = await preflight();
  setupRan = true;

  let state = "specify";
  let feedback = "";
  let qaRedOnce = false;

  while (!outcome) {
    if (state === "specify") {
      phase("Specify");
      if (exhausted("specify")) { outcome = escalate("specify: exhausted", null, { feedback }); break; }
      await stage("specify", "Write one red acceptance test per acceptance criterion of this ticket, named verbatim after the criterion, in the repo's declared acceptance seam. Do not implement anything. Commit the tests.", feedback);
      const tree = await committedTree("specify");
      if (tree.verdict === GATE.escalate) { outcome = tree.outcome; break; }
      if (tree.verdict === GATE.retry) { feedback = tree.feedback; continue; }
      const red = await runGuard("spec", { argument: "red", label: "spec:red" });
      if (!red) { outcome = escalate("harness: conduit failed on spec"); break; }
      if (red.exitCode === 2) { outcome = escalate("harness: spec guard operational failure", red); break; }
      if (red.exitCode !== 0) { feedback = findings(red); continue; }
      feedback = "";
      state = "coder";
      continue;
    }

    if (state === "coder") {
      phase("Code");
      if (exhausted("coder")) { outcome = escalate("coder: exhausted", null, { feedback }); break; }
      await stage("coder", "Make the acceptance tests for this ticket pass with the minimum correct change, keeping build and typecheck green. Commit your work.", feedback);
      const gate = await codeGates("coder");
      if (gate.verdict === GATE.escalate) { outcome = gate.outcome; break; }
      if (gate.verdict === GATE.retry) { feedback = gate.feedback; continue; }
      feedback = gate.verdict === GATE.cleaner ? gate.feedback : "";
      state = "cleaner";
      continue;
    }

    if (state === "cleaner") {
      if (exhausted("cleaner")) { outcome = escalate("cleaner: exhausted", null, { feedback }); break; }
      await stage("cleaner", "Clean up the change for this ticket without changing behaviour: fix any CRAP offenders listed below, then apply the Standards, Structure and Design baselines to the diff since the merge-base. Commit your work.", feedback);
      const gate = await codeGates("cleaner");
      if (gate.verdict === GATE.escalate) { outcome = gate.outcome; break; }
      if (gate.verdict === GATE.ok) { feedback = ""; state = "qa"; continue; }
      feedback = gate.feedback;
      continue;
    }

    if (state === "qa") {
      phase("QA");
      if (exhausted("qa")) { outcome = escalate("qa: exhausted", null, { feedback }); break; }
      const nonce = mintNonce("qa");
      await stage("qa", `Prove each acceptance criterion of this ticket against the running system from the outside. Write a bash script to .gauntlet/qa/${nonce}.sh that uses $GAUNTLET_URL, drives the served system, and prints exactly one line per criterion: "PASS <criterion verbatim>" or "FAIL <criterion verbatim>". Do not read or run the repo's tests. Do not run the script yourself.`, feedback);
      const qa = await runGuard("qa", { nonce, label: "qa-guard" });
      if (!qa) { outcome = escalate("harness: conduit failed on qa"); break; }
      if (qa.exitCode === 2) { outcome = escalate("harness: qa guard operational failure", qa); break; }
      if (qa.exitCode !== 0) {
        if (qaRedOnce) { outcome = escalate("spec: acceptance disagrees with QA — the acceptance tests pass but QA fails the same criteria; the acceptance tests are too weak", qa, { failed: qa.failed }); break; }
        qaRedOnce = true;
        feedback = findings(qa);
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
  if (setupRan) await runGuard("teardown");
}

return { ...outcome, attempts };
