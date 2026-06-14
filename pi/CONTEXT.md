# Pi Subagent Workflow Conventions

The tiered model and subagent orchestration patterns for pi coding sessions.
Designed 2026-06-14; grilling source: `Library/concepts/` (ingest pending).

## Model tiering

| Role | Model | Thinking | Rationale |
|---|---|---|---|
| **Parent orchestrator** | deepseek-v4-pro | xhigh | Adversarial reasoning, cross-referencing, trade-off navigation. Grilling and HITL decisions |
| **Context subagents** (scout, ask, researcher) | deepseek-v4-pro | high | Retrieval and synthesis — not adversarial reasoning |
| **TDD subagents** (test-writer, implementer, refactorer) | V4-Flash (default) / V4-Pro (complex) | high | See TDD section below |
| **Review / validation** | deepseek-v4-pro | high | Diff inspection, structural critique |

The parent at xhigh is the single adversarial reasoner. All other agents run high.
V4-Flash is ~20× cheaper than V4-Pro at output ($0.28/M vs $3.48/M list) and
sufficient for mechanical work (test generation, straightforward implementation).

## Planning fan-out

For non-trivial planning sessions (grill-with-docs / grill-me):

1. Parent fires three parallel async subagents:
   - **scout** — code trace (follow every request path, enumerate branches), consumer
     hunt (grep reads of every changed contract), feature-flag sweep
   - **ask** — vault sweep: query the Library for prior grillings, ingested articles,
     Profile focus bearing on the topic
   - **researcher** — external docs, ecosystem behaviour, recent changes, primary sources
2. Parent reads CONTEXT.md / ADRs directly while subagents run
3. Subagent results synthesised; HITL grilling proceeds
4. Output routed per the fan-out menu: PRD → `/to-prd` → `/to-issues`;
   proposal → `/to-proposal`; ADR → write in-repo; Library → capture via `/ingest`;
   nothing → done

Execute inline — no saved chain file (HITL is inherently interactive).

## TDD implementation loop

Triggered after `/pickup` verifies a ticket brief against current code.

### Phase 0: Pickup gate

- Pickup verifies brief surfaces and consumers against current code
- Aligned → proceed to Phase 1
- Misaligned → HITL micro-grilling session (parent, xhigh) to realign

### Phase 1: Slice decomposition (parent)

- Break the feature into ordered vertical slices (one testable behaviour each)
- Slice order: domain → domain-service → application → infrastructure (inside-out)
- User approves decomposition

### Phase 2: RED — Test Writer subagent

- Agent: `tdd-test-writer` (V4-Flash, high, fresh context)
- Sees: slice spec, public API signatures, framework conventions
- Does NOT see: any implementation code
- Returns: failing test file + failure output
- **RED gate** (HITL-flexible): parent reviews test against slice spec. Flexible —
  some sessions parent-automated, others show user for approval

### Phase 3: GREEN — Implementer subagent

- Agent: `tdd-implementer` (V4-Flash high default; escalate to V4-Pro for
  multi-file invariants, fresh context)
- Sees: failing test code + test failure output only
- Does NOT see: the spec, the slice description
- Returns: minimal implementation, passing test output
- Retry up to 5 attempts on failure
- **GREEN gate**: parent confirms test passes, sanity-checks diff size

### Phase 4: REFACTOR — Refactorer subagent

- Agent: `tdd-refactorer` (V4-Pro, high, fresh context)
- Sees: all implementation + all tests + green results
- Returns: improvements applied + tests still green, or "no refactoring needed"
- **Post-REFACTOR**: parent optionally fires a fresh-context `reviewer` subagent
  for structural quality

### Commit

- Parent invokes `/commit` after each completed slice (RED→GREEN→REFACTOR)
- Conventional commits, one per slice

### V4-Flash vs V4-Pro routing for TDD

- **Test Writer**: V4-Flash. Mechanical — writes assertions from spec. Bounded scope.
- **Implementer**: V4-Flash default. Most implementation is straightforward from a
  clean failing test. Escalate to V4-Pro when the feature spans multiple files with
  cross-module invariants (parent decides).
- **Refactorer**: V4-Pro. Structural reasoning (extract module? simplify contract?)
  rewards deeper thinking.

## Agent configuration

Agent overrides live in `pi/.pi/agent/settings.json` → `subagents.agentOverrides`.

Custom TDD agents live in `pi/.pi/agent/agents/` (symlinked to `~/.pi/agent/agents/`):

| Agent | Model | Thinking |
|---|---|---|
| `tdd-test-writer` | deepseek-v4-flash | high |
| `tdd-implementer` | deepseek-v4-flash | high |
| `tdd-refactorer` | deepseek-v4-pro | high |

## Context isolation (the architectural invariant)

The point of subagents in TDD is context isolation. Each phase must run in a
fresh context that sees only what it needs:

| Agent | Sees | Must not see |
|---|---|---|
| Test Writer | Slice spec, API signatures, framework conventions | Implementation code |
| Implementer | Failing test + error output, file tree, existing source | The spec |
| Refactorer | All code + all green tests | The spec |

Without this separation, the LLM "cheats" — implementation intent leaks into test
design, and the test no longer validates behaviour independently.

## Guardrails

`extensions/guardrails.ts` blocks destructive bash patterns and secret reads.
See `pi/README.md` for the full policy. Commands typed via `!` prefix are never gated.
