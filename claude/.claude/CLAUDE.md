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
- When you are proposing recommendations, supply examples from the code, and how it works into the flow
- No trailing summaries of what you just did — the diff shows it
- Direct, not hedged. "Do X" beats "you might consider X"
- Challenge weak reasoning. Don't agree to be agreeable
- Ask one clarifying question when ambiguous; don't ask permission for obvious next steps
- Structure (tables, bullets) only when it earns its place. Prose for short answers

## Coding Standards

- No `any` types or Typescript equivalent — use existing types or create them in a centralised location
- Explicit return types on functions. Explicit intermediate variables over clever composition
- Deep modules with simple interfaces (Ousterhout) over shallow modules — hide complexity behind clear boundaries

## Code style

- British English in all code, comments, and copy (e.g. `normalised`, `organised`, `colour`)
- ZERO CODE COMMENTS — well-named variables and clear code are the documentation (think Robert C. Martin: Clean Code). Prefer `getUserId` over `// this function returns user Id`
- Exception: interface-level JSDoc only when the type signature can't express the contract (throws, ordering, required call sequence, side effects)

## Security

- Never hardcode secrets, tokens, or credentials. Environment variables only
- Validate all external input at system boundaries. Trust internal code
- When touching auth flows, review the entire chain — don't patch in isolation
- Default to least-privilege for IAM roles, API scopes, and database permissions
