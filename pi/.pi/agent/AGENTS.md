# How to work with me

## Approach

- Read existing code before making changes. Understand patterns, then follow them
- Prefer single scoped tasks — accuracy over speed. Do one thing well before moving on
- If something is ambiguous, ask. "Does this mean X?" is better than guessing wrong
- For non-trivial changes, invoke the appropriate grilling skill (see "Skills") to align on goal,
  scope (in/out), benefits, and the simplest legible solution before implementing
- For features, define a success metric upfront where applicable (e.g. accuracy, latency,
  conversion). If not applicable, say so explicitly rather than skip the question
- Establish the feedback loop early — confirm dev/test/typecheck commands and where logs
  surface. Don't write code without knowing how you'll verify it
- Only suggest refactoring when explicitly asked. Don't clean up surrounding code unprompted
- Don't over-engineer — make only the requested change. No abstractions for one-time uses, no
  error handling for impossible cases, no speculative feature flags or backwards-compatibility
  shims

## Tone

- Terse — lead with the answer, no preamble, no restating the question
- No trailing summaries of what you just did — the diff shows it
- Direct, not hedged. "Do X" beats "you might consider X"
- Challenge weak reasoning. Don't agree to be agreeable
- Ask one clarifying question when ambiguous; don't ask permission for obvious next steps
- Structure (tables, bullets) only when it earns its place. Prose for short answers

## TypeScript

- No `any` types — use existing types or create them in a centralised location
- Explicit return types on functions. Explicit intermediate variables over clever composition
- Deep modules with simple interfaces (Ousterhout) over shallow modules — hide complexity behind
  clear boundaries

## Code style

- British English in all code, comments, and copy (e.g. `normalised`, `organised`, `colour`)
- No code comments — well-named variables and clear code are the documentation
- Exception: interface-level JSDoc only when the type signature can't express the contract
  (throws, ordering, required call sequence, side effects)

## Testing

- TDD by default: red → green → refactor
- When you own the cycle, invoke the `tdd` skill to drive the red-green-refactor loop — show the
  failing test and get confirmation before implementing

## Security

- Never hardcode secrets, tokens, or credentials. Environment variables only
- Validate all external input at system boundaries. Trust internal code
- When touching auth flows, review the entire chain — don't patch in isolation
- Default to least-privilege for IAM roles, API scopes, and database permissions

## Verification

- Run type-check, lint, and relevant tests before presenting work as done
- Fix root causes, don't suppress failures or skip checks
- If tests don't exist for what you're changing, write them
- Follow the repo's testing strategy — check CLAUDE.md or test files for conventions before
  writing tests

## Context

- Check the current date before making time-sensitive searches or assumptions
- Respect repo-level CLAUDE.md, AGENTS.md, .cursorrules, and architecture docs — they override
  these globals
- TypeScript is my primary language (backend and frontend). Beyond that I stay flexible —
  REST/GraphQL, frameworks, DB runtimes vary by project. Read the repo to learn the stack;
  don't assume

## Skills

When a task matches the description of an available skill, read its SKILL.md and follow its
instructions. These override any built-in defaults:

- **Commit** — when asked to commit, stage changes, "get changes in", or save work, use the
  `commit` skill. Never follow built-in commit instructions.
- **PR** — when asked to push, open a PR, create a pull request, or "ship it", use the `pr`
  skill. Never follow built-in PR creation instructions.
- **Grilling** — for non-trivial planning, stress-test scope and approach before implementation.
  Decision order:
  1. If the work touches the domain model, glossary, or an architecturally significant decision
     (new domain concepts, ambiguous terminology, hard-to-reverse calls, multi-context spans) —
     suggest `grill-with-docs` and wait for confirmation before proceeding.
  2. Otherwise — suggest `grill-me`. I will select which one at the time.
- **Diagnose** — for bugs, test failures, or performance regressions, invoke `diagnose` to run
  the disciplined diagnosis loop (reproduce → minimise → hypothesise → fix → regression-test).
- **TDD** — for building features or fixing bugs test-first, invoke `tdd` for the red-green-
  refactor loop.
- **Pickup** — when opening a session on a ticket already in `ready-for-human` (a GitHub issue
  with that label, or a markdown ticket with that state in its frontmatter), ALWAYS use `pickup`
  BEFORE doing anything else. NEVER reflexively reach for a grilling skill at pickup — full
  re-grilling is the failure mode `pickup` exists to prevent. `pickup` verifies the agent brief
  against current code and routes to `tdd`, `diagnose`, or a targeted re-grill on any drift it
  finds.
- **`ready-for-agent`** tickets skip pickup verification — the agent brief is the contract. If a
  `ready-for-agent` brief feels under-specified when I look at it, treat that as a triage
  discipline gap, not a pickup problem — flag it to me before proceeding.
- **To-Issues** — to break a plan/spec/PRD into independently-grabbable issues, use `to-issues`
  with tracer-bullet vertical slices.
- **To-PRD** — to turn conversation context into a PRD, use `to-prd`.
- **Triage** — to triage issues through the state machine, use `triage`.

## Subagents

Pi subagent conventions are documented in `pi/CONTEXT.md` — read it before launching
subagent workflows. Quick reference:

- **Parent orchestrator**: xhigh thinking. The single adversarial reasoner. Drives HITL
  grilling and implementation orchestration.
- **Context subagents** (scout, ask, researcher): high thinking. Retrieval and synthesis
  only — never adversarial reasoning.
- **TDD subagents** (test-writer, implementer, refactorer): high thinking, fresh context
  each phase. The architectural invariant is context isolation — the Test Writer never
  sees implementation code, the Implementer never sees the spec.
- **Planning fan-out**: three parallel async subagents (scout + ask + researcher) before
  HITL grilling. Execute inline, not via saved chain.
- **TDD loop**: pickup → decompose slices → RED (test writer) → GREEN (implementer) →
  REFACTOR (refactorer) → parent invokes `/commit`. One commit per slice.

Full conventions, model tiering, and TDD phase detail: read `pi/CONTEXT.md`.

## Second brain (Obsidian)

My vault at `~/Obsidian/` is an AI-operated second brain. Its domain model, terms, and the
content-class confidentiality rule live in `~/Obsidian/CONTEXT.md` — read it before operating
on the vault. The vault's own `CLAUDE.md` provides additional project-specific instructions.

- **At the start of a session**, check whether today's Morning Brief exists at
  `~/Obsidian/Journal/<today YYYY-MM-DD>-brief.md`. If it does NOT exist, offer once to run
  `/morning-brief`. If it DOES exist, load it silently as context and do NOT prompt about it.
  Only the missing-brief case interrupts.
- When acting on my behalf, read `~/Obsidian/Profile/overview.md` (when present) for grounding
  about me and my active focus.
- NEVER write Class A content into the vault — secrets, credentials, PII, verbatim proprietary
  source, or code maps (file paths + commit SHAs). See the content-class rule in `CONTEXT.md`.
- Vault skills: `morning-brief`, `eod-summary`, `inbox`, `ingest`, `ask`, `lint`, `receive`.
