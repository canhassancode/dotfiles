# Gauntlet

The gated build machine under `claude/` — a ticket goes in, a pull request comes out, and every transition between them is decided by a deterministic check rather than a model. Exists because prose steering of agents fails silently; a machine can only take the transitions its guards permit.

## Language

**Stage**:
A fresh-context subagent that does fuzzy work — `specify`, `coder`, `cleaner`, `qa`, `ship`.
_Avoid_: step, phase, agent (all stages are agents; not all agents are stages)

**Guard**:
A deterministic check run by `run.py` that returns an exit code the workflow branches on; a model never decides its result.
_Avoid_: gate (the transition), check, test

**Conduit**:
The cheap subagent that runs one guard command and copies its JSON line back into the workflow, because the workflow script itself has no shell or filesystem.
_Avoid_: runner (that is `run.py`), relay agent

**Receipt**:
The hash `fnv1a32(secret:nonce:exitCode)` a guard prints, proving to the workflow that this guard ran under this nonce with this exit code; the conduit never sees the secret.

**Branch field**:
A relayed field the workflow's control flow reads — `nonce`, `guard`, `exitCode`, `receipt`. Always `required` in the conduit schema and always receipt-covered.

**Feedback field**:
A relayed field the workflow only forwards into the next stage's prompt — `tail`, `log`, `offenders`, `problems`, `failed`. Optional by contract; a drop degrades the retry prompt, never the branch.

**Ticket**:
The single input of a run: `.gauntlet/ticket.json` = `{issue, title, body}`, where `body` carries `- [ ] Given …, when …, then …` acceptance criteria. Whatever writes that file is the ticket's origin; the gauntlet does not know which.
_Avoid_: issue (a GitHub-specific origin), story

**Edge**:
A production file the runtime reaches on its own — a route, a page, middleware, a handler entry — declared as globs in `config.edges`. The outside seam an acceptance test drives, and the root every other file must be reachable from.
_Avoid_: entry point (framework-specific), seam (the test's side of the same boundary)

**Reachability**:
The guard that every new production file in the diff is an **Edge** or is imported, transitively, from an **Edge** or a pre-existing file. Red means the change ships a module nothing calls — a fixture wearing a feature's name.

**Preflight**:
Everything before the first **Stage** — resolving the **Ticket** by origin, minting the run secret, leaving main, and the baseline guards (clean-tree, install, setup, build, coverage) against the untouched tree. Deterministic shell run by the `/gauntlet` skill in the operator's session, never by a model; green invokes the workflow with the result as `args`, red stops with the failing guard's tail.

**Depth**:
The guard on every new production file: implementation lines divided by exported symbols, red below a ceiling. Ousterhout's definition operationalised — it fails pass-throughs and barrels, never a design. Red routes to the cleaner, like `crap`.

**Wire evidence**:
The counting relay `qa_guard` places in front of `serve.url`; the QA script receives the relay as `GAUNTLET_URL`, and zero requests through it is red. The only proof of "against the running system" that a **Stage** cannot author.

**Verdict**:
`.gauntlet/verdict-<HEAD>.json` — the clean-review artefact keyed to a commit that the pre-PR hook demands before `gh pr create`.

## Relationships

- A **Stage** never runs a **Guard**; a **Conduit** runs exactly one **Guard** per call
- Every **Guard** result carries a **Receipt**; the workflow discards any result whose receipt does not verify and retries the **Conduit**
- **Branch fields** decide transitions; **Feedback fields** ride into the next **Stage** prompt
- Every **Stage** reads the **Ticket** from disk; only the `ticket` **Guard** writes it
- `specify` maps the codebase first through a read-only exploration sub-agent (pointers, never quoted code; `CONTEXT.md` is its vocabulary when present) and returns, per test, the **Edge** and the existing module it drives — the claim **Reachability** later checks against the diff
- A run ends in `ship` only when a **Verdict** exists for HEAD
- The coder climbs the `/tdd` ladder (existing module > stdlib > platform > dependency > one-liner > new code); the cleaner may leave the diff for one pass — merging a new module into the existing one with the same responsibility
- **Reachability** and **Depth** run with the coder and cleaner gates; a **Stage** that returns with HEAD unchanged has refused its feedback and escalates without re-gating

## Example dialogue

> **Dev:** "The `ticket` guard passed but the run died — is the guard broken?"
> **Domain expert:** "Check `ticket.json` on disk first. If it is complete, the guard did its job and the **Conduit** lost something on the way back. A **Branch field** loss is a receipt failure and retries; anything else must be a **Feedback field**, which the workflow tolerates."
> **Dev:** "Then why did it die?"
> **Domain expert:** "Because the body was crossing the conduit as if it were a branch field. Large things do not cross the conduit; they stay on disk and the **Stage** reads them."

## Flagged ambiguities

- **"hash-verified ticket"** meant the relayed body's hash matched — resolved 2026-08-27: the body no longer crosses the **Conduit**; the ticket is verified by the `ticket` guard's **Receipt**, and its content lives only in `ticket.json`. `bodyHash` was removed with the relay it guarded.
- **"no stage runs `gh issue view`"** was implemented as "embed the body in every prompt" → resolved: the decision is *no agent-chosen fetch* (a stage once ran `gh issue view 63 | head -60` and acted on half a ticket); reading the file `run.py` wrote satisfies it without the relay.
- **Ticket origin** was GitHub-only (`fetch_ticket`) → resolved 2026-08-27: the `/gauntlet` skill resolves the reference by origin (issue number, Linear id, file path) and writes `ticket.json`; the workflow (`gauntlet-run`) only ever receives **Preflight**'s `args`. Free text is not an origin — a body without Given/When/Then criteria stops the run; criteria come from `/to-tickets`, never from the skill.
- **Preflight as seven model spawns** (bootstrap + six conduits, ~600k cached tokens on run #63) → resolved 2026-08-27: the workflow has no shell, so preflight moved out of it into the skill.
- **"red for the right reason"** was a rule in the specify prompt with no guard behind it → resolved 2026-08-27: not enforced on `spec red`, because under an in-process acceptance seam a genuinely new **Edge** cannot resolve before it exists. **Reachability** at the code gates catches the wrong-seam case instead (run #63 shipped `sessionClient.ts` with no importer).
- **QA passing without touching the served system** (run #63: six PASS lines, zero HTTP requests, SSO expired unnoticed) → resolved 2026-08-27: every other guard branches on machine-produced evidence; QA branched on text the stage wrote. **Wire evidence** closes it; a proxy on the script's text would not.
- **A parallel module is not a shallow module** — `sessionClient.ts` was deep (two exports over single-flight refresh) but a sibling of `client.ts`; **Reachability** catches the sibling, **Depth** catches the pass-through. Neither alone would have.
- **Re-entry** — an escalated run resumes with `/gauntlet <ticket> --from <stage>`; `resumeFromRunId` cannot, because identical calls replay their cached failure.
- **Teardown** is the repo's command only; the harness never clears `.gauntlet/`. The next run overwrites `ticket.json` and `run-secret`; verdicts are keyed by SHA and inert unless HEAD returns to that SHA.
