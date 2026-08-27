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

**Verdict**:
`.gauntlet/verdict-<HEAD>.json` — the clean-review artefact keyed to a commit that the pre-PR hook demands before `gh pr create`.

## Relationships

- A **Stage** never runs a **Guard**; a **Conduit** runs exactly one **Guard** per call
- Every **Guard** result carries a **Receipt**; the workflow discards any result whose receipt does not verify and retries the **Conduit**
- **Branch fields** decide transitions; **Feedback fields** ride into the next **Stage** prompt
- Every **Stage** reads the **Ticket** from disk; only the `ticket` **Guard** writes it
- A run ends in `ship` only when a **Verdict** exists for HEAD

## Example dialogue

> **Dev:** "The `ticket` guard passed but the run died — is the guard broken?"
> **Domain expert:** "Check `ticket.json` on disk first. If it is complete, the guard did its job and the **Conduit** lost something on the way back. A **Branch field** loss is a receipt failure and retries; anything else must be a **Feedback field**, which the workflow tolerates."
> **Dev:** "Then why did it die?"
> **Domain expert:** "Because the body was crossing the conduit as if it were a branch field. Large things do not cross the conduit; they stay on disk and the **Stage** reads them."

## Flagged ambiguities

- **"hash-verified ticket"** meant the relayed body's hash matched — resolved 2026-08-27: the body no longer crosses the **Conduit**; the ticket is verified by the `ticket` guard's **Receipt**, and its content lives only in `ticket.json`. `bodyHash` was removed with the relay it guarded.
- **"no stage runs `gh issue view`"** was implemented as "embed the body in every prompt" → resolved: the decision is *no agent-chosen fetch* (a stage once ran `gh issue view 63 | head -60` and acted on half a ticket); reading the file `run.py` wrote satisfies it without the relay.
- **Ticket origin** is currently GitHub-only (`fetch_ticket`) → flagged, not resolved: Linear, a vault `.md`, or a `/diagnose` output are all valid writers of `ticket.json`. Own grilling.
- **Teardown** is the repo's command only; the harness never clears `.gauntlet/`. The next run overwrites `ticket.json` and `run-secret`; verdicts are keyed by SHA and inert unless HEAD returns to that SHA.
