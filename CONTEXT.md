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
The cheap subagent that runs one `run.py` command and copies its JSON line back into the workflow, because the workflow script itself has no shell or filesystem. Costs ~18K tokens per spawn whatever it runs, which is why a transition is one conduit, not one per guard.
_Avoid_: runner (that is `run.py`), relay agent

**Gate**:
The transition between two **Stages** — the guard chain `run.py gate <chain>` runs in one process and reports as one line: `failed` (the most upstream red guard, or null) and `findings` (every guard that ran). The chain stops only where the next guard would have no input (dirty tree, red build, coverage red after its retry, any exit 2); every other red keeps going so one retry prompt carries every finding. Two chains: `specify` (clean-tree, spec red) and `code` (clean-tree, spec green, build, coverage, reachability, crap, depth).
_Avoid_: guard (one check inside a gate), gates (plural — one transition is one gate)

**Receipt**:
The hash `fnv1a32(secret:nonce:exitCode)` a guard prints — for a **Gate**, `fnv1a32(secret:nonce:exitCode:failed-or-dash:head)` — proving to the workflow that this guard ran under this nonce with this result; the conduit never sees the secret.

**Branch field**:
A relayed field the workflow's control flow reads — `nonce`, `guard`, `exitCode`, `receipt`, and on a **Gate** `failed` and `head`. Always `required` in the conduit schema and always receipt-covered.

**Feedback field**:
A relayed field the workflow only forwards into the next stage's prompt — `tail`, `log`, `findings`, `offenders`, `problems`, QA's `failed` list. Optional by contract; a drop degrades the retry prompt, never the branch.

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

**Surface**:
One served address a monorepo exposes — the web app, the API, a BFF — declared under `serve.surfaces` keyed by name, each with its own `url`, `ready` probes, and `paths` glob. The **Surface** a ticket crosses is derived deterministically from where its matched acceptance tests sit (the observation seam), not from the diff — a vertical slice touching many modules but asserting through one page selects one surface. The `spec` guard writes the selected set to `.gauntlet/surfaces.json`; `qa_guard` fronts a relay per surface. A single-surface repo declares no `surfaces` and keeps a flat `serve.url`.

**Wire evidence**:
The counting relay `qa_guard` places in front of each selected **Surface** (`serve.url` when a repo declares none); the QA script receives each as `GAUNTLET_URL_<SURFACE>` (or `GAUNTLET_URL` when one is selected), and zero requests through any selected surface's relay is red. The only proof of "against the running system" that a **Stage** cannot author.

**Verdict**:
`.gauntlet/verdict-<HEAD>.json` — the clean-review artefact keyed to a commit that the pre-PR hook demands before `gh pr create`.

## Relationships

- A **Stage** never runs a **Guard**; a **Conduit** runs exactly one `run.py` command per call — a whole **Gate**, or a single **Guard** (qa, verdict, teardown)
- Every **Guard** result carries a **Receipt**; the workflow discards any result whose receipt does not verify and retries the **Conduit**
- **Branch fields** decide transitions; **Feedback fields** ride into the next **Stage** prompt
- Every **Stage** reads the **Ticket** from disk; only the `ticket` **Guard** writes it
- `specify` maps the codebase first through a read-only exploration sub-agent (pointers, never quoted code; `CONTEXT.md` is its vocabulary when present) and returns, per test, the **Edge** and the existing module it drives — the claim **Reachability** later checks against the diff
- A run ends in `ship` only when a **Verdict** exists for HEAD
- The coder climbs the `/tdd` ladder (existing module > stdlib > platform > dependency > one-liner > new code); the cleaner may leave the diff for one pass — merging a new module into the existing one with the same responsibility
- **Reachability** and **Depth** run inside the `code` **Gate**; a **Stage** that returns with HEAD unchanged has refused its feedback and escalates without re-gating
- A **Gate** routes on `failed` alone: clean-tree → commit and retry; spec/build → the same stage; coverage → escalate; reachability → coder; crap/depth → cleaner. The findings of every red guard ride into that prompt together

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
- **One conduit per guard** (19 spawns, 349K of run #109's 536K tokens, for 19 shell commands) → resolved 2026-08-28: the chain moved into `run.py gate`; the JS branches on the same fields, once. Short-circuit was dropped with it — a retry round costs an Opus stage, a guard costs seconds, so any red that leaves the next guard's input intact collects it.
- **Teardown** is the repo's command only; the harness never clears `.gauntlet/`. The next run overwrites `ticket.json` and `run-secret`; verdicts are keyed by SHA and inert unless HEAD returns to that SHA.
- **Single-surface `serve`** forced a per-ticket config flip on monorepos (dotfiles#57: brushfeed serves web `:4321` + core-api `:3000` from one `dev:headless`) → resolved 2026-08-28: `serve.surfaces` keyed by name, the crossed **Surface** derived from where a ticket's matched acceptance tests sit. Selecting from the *diff* was rejected — a vertical slice's diff spans web+api even when it asserts through the page alone, so it would demand traffic to an API relay the script never hits and false-red; the acceptance test's own location is the observation seam and never over-selects. No new artefact carries it: the test's `file` is already in the `spec` guard's jest report.
