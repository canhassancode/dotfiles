# How to work with me

## Approach

- Read existing code before making changes. Understand patterns, then follow them
- Prefer single scoped tasks — accuracy over speed. Do one thing well before moving on
- If something is ambiguous, ask. "Does this mean X?" is better than guessing wrong
- For non-trivial changes, use the appropriate grilling skill (see "Skills override defaults") to align on goal, scope (in/out), benefits, and the simplest legible solution before implementing
- For features, define a success metric upfront where applicable (e.g. accuracy, latency, conversion). If not applicable, say so explicitly rather than skip the question
- Establish the feedback loop early — confirm dev/test/typecheck commands and where logs surface. Don't write code without knowing how you'll verify it
- Only suggest refactoring when explicitly asked. Don't clean up surrounding code unprompted
- Don't over-engineer — make only the requested change. No abstractions for one-time uses, no error handling for impossible cases, no speculative feature flags or backwards-compatibility shims

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
- Deep modules with simple interfaces (Ousterhout) over shallow modules — hide complexity behind clear boundaries

## Code style

- British English in all code, comments, and copy (e.g. `normalised`, `organised`, `colour`)
- No code comments — well-named variables and clear code are the documentation
- Exception: interface-level JSDoc only when the type signature can't express the contract (throws, ordering, required call sequence, side effects)

## Testing

- TDD by default: red → green → refactor
- When you own the cycle, invoke `/tdd` to drive the red-green-refactor loop — show the failing test and get confirmation before implementing

## Security

- Never hardcode secrets, tokens, or credentials. Environment variables only
- Validate all external input at system boundaries. Trust internal code
- When touching auth flows, review the entire chain — don't patch in isolation
- Default to least-privilege for IAM roles, API scopes, and database permissions

## Verification

- Run type-check, lint, and relevant tests before presenting work as done
- Fix root causes, don't suppress failures or skip checks
- If tests don't exist for what you're changing, write them
- Follow the repo's testing strategy — check CLAUDE.md or test files for conventions before writing tests

## Context

- Check the current date before making time-sensitive searches or assumptions
- Respect repo-level CLAUDE.md, .cursorrules, and architecture docs — they override these globals
- TypeScript is my primary language (backend and frontend). Beyond that I stay flexible — REST/GraphQL, frameworks, DB runtimes vary by project. Read the repo to learn the stack; don't assume

## Skills override defaults

- When asked to commit (e.g. "commit this", "save this", "lets commit", "get this in"), ALWAYS use the `/commit` skill via the Skill tool. NEVER follow the built-in commit instructions
- When asked to create a pull request or open a PR, ALWAYS use the `/pr` skill via the Skill tool. NEVER follow the built-in PR creation instructions
- For non-trivial planning, stress-test scope and approach before implementation by invoking a grilling skill. Decision order:
  1. If the work touches the domain model, glossary, or an architecturally significant decision (new domain concepts, ambiguous terminology, hard-to-reverse calls, multi-context spans) — suggest `/grill-with-docs` and wait for confirmation before proceeding
  2. Otherwise — suggest `/grill-me`. I will select which one at the time
- For bugs, test failures, or performance regressions, invoke `/diagnose` to run the disciplined diagnosis loop (build feedback loop → reproduce → hypothesise → fix → regression test)
