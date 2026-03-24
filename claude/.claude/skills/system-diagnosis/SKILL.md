---
name: system-diagnosis
description: Systematic debugging through phased root cause analysis. Use when encountering any bug, test failure, or unexpected behaviour. Forces evidence gathering before proposing fixes. Do NOT skip to solutions.
---

# System Diagnosis

## Iron law

No fixes without root cause investigation first. If you haven't completed Phase 1, you cannot propose fixes.

## When to use

Any technical issue: test failures, bugs, unexpected behaviour, performance problems, build failures, integration issues.

Use this especially when under time pressure, when "just one quick fix" seems obvious, or when previous fixes haven't worked.

## Phase 1: Root cause investigation

Before attempting any fix:

1. **Read error messages carefully** — don't skip past errors. Read stack traces completely. Note line numbers, file paths, error codes.

2. **Reproduce consistently** — can you trigger it reliably? What are the exact steps? If not reproducible, gather more data — don't guess.

3. **Check recent changes** — git diff, recent commits, new dependencies, config changes, environmental differences.

4. **Gather evidence in multi-component systems** — before proposing fixes, add diagnostic instrumentation at each component boundary. Log what enters and exits each layer. Run once to gather evidence showing WHERE it breaks. Then investigate that specific component.

5. **Trace data flow** — where does the bad value originate? What called this with the bad value? Keep tracing up until you find the source. Fix at source, not at symptom.

## Phase 2: Pattern analysis

1. **Find working examples** — locate similar working code in the same codebase
2. **Compare against references** — if implementing a pattern, read the reference implementation completely
3. **Identify differences** — list every difference between working and broken, however small
4. **Understand dependencies** — what other components, settings, config, or environment does this need?

## Phase 3: Hypothesis and testing

1. **Form a single hypothesis** — state clearly: "I think X is the root cause because Y"
2. **Test minimally** — make the smallest possible change. One variable at a time.
3. **Verify before continuing** — did it work? If not, form a new hypothesis. Do not add more fixes on top.

## Phase 4: Implementation

1. **Create a failing test case** — simplest possible reproduction. Must exist before fixing.
2. **Implement a single fix** — address the root cause. One change at a time. No "while I'm here" improvements.
3. **Verify the fix** — test passes? No other tests broken? Issue actually resolved?
4. **If 3+ fixes have failed** — stop. This is likely an architectural problem, not a bug. Question the pattern fundamentally. Discuss before attempting more fixes.

## Red flags — stop and return to Phase 1

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- Proposing solutions before tracing data flow
- Each fix reveals a new problem in a different place

## Common rationalisations

| Excuse | Reality |
|---|---|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is faster than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
