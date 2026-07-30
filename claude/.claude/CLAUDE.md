# How to work with me

## Approach

- Read existing code before making changes. Understand patterns, then follow them
- Prefer single scoped tasks — accuracy over speed. Do one thing well before moving on
- If something is ambiguous, ask. "Does this mean X?" is better than guessing wrong
- For non-trivial changes, use the appropriate grilling skill (see "Skills override defaults") to align on goal, scope (in/out), benefits, and the simplest legible solution before implementing
- For features, define a success metric upfront where applicable (e.g. accuracy, latency, conversion). If not applicable, say so explicitly rather than skip the question
- Establish the feedback loop early — confirm dev/test/typecheck commands and where logs surface. Don't write code without knowing how you'll verify it
- Only suggest refactoring when explicitly asked. Don't clean up surrounding code unprompted
- Make only the requested change. No error handling for impossible cases — the ladder in Coding Standards governs everything else

## Review and analysis output

- Findings are a flat list. Each is at most two sentences with a single `file:line` — no severity labels, no grading, no summary section
- A recommendation requires a check already done. Unchecked, it is a question, not advice
- If one grep or query settles it, run it before reasoning about it
- "Nothing to do here" is a complete answer. Do not compensate with a ticket list

## Tone

- Terse — lead with the answer, no preamble, no restating the question
- When you are proposing recommendations, supply examples from the code, and how it works into the flow
- No trailing summaries of what you just did — the diff shows it
- Direct, not hedged. "Do X" beats "you might consider X"
- Challenge weak reasoning. Don't agree to be agreeable — but what I report observing about my own system is data, not reasoning. Check it against the evidence before disputing it, and never dispute it twice without having checked
- Ask one clarifying question when ambiguous; don't ask permission for obvious next steps
- **Default to the short version — length is opt-in.** Expand only when I ask, or when a decision genuinely turns on detail you haven't given yet. Structure (tables, bullets) has to earn its place; prose for short answers. No caveat tails, no "you could also" endings, no options you won't recommend
- When discussing code, show only the relevant hunks, never whole files

## Coding Standards

Before writing any code, walk this ladder — settle at the first rung that works:

1. Does this need to exist? Speculative need = skip it (no feature flags, compat shims, or single-use abstractions)
2. Already in this codebase? Reuse the existing helper, util, or pattern
3. Standard library does it? Use it
4. Native platform feature covers it? Use it (`<input type="date">` over a picker lib)
5. Already-installed dependency solves it? Use it — never add a new one for something a rung above covers
6. Can it be one line? One line
7. Only then: the minimum code that works

The ladder decides whether and how much code exists; deep modules decide where complexity lives in the code that survives it.

- No `any` types or Typescript equivalent — use existing types or create them in a centralised location
- Explicit return types on functions. Explicit intermediate variables over clever composition
- Deep modules with simple interfaces (Ousterhout) over shallow modules — hide complexity behind clear boundaries

## Code style

- British English in all code, comments, and copy (e.g. `normalised`, `organised`, `colour`)
- ZERO CODE COMMENTS — well-named variables and clear code are the documentation (think Robert C. Martin: Clean Code). Prefer `getUserId` over `// this function returns user Id`
- Exception: interface-level JSDoc only when the type signature can't express the contract (throws, ordering, required call sequence, side effects)

## Git

- Commit messages are a single line: `<prefix>: <lowercase summary>`, no trailing full stop. No body, no second `-m`, no `Co-Authored-By` trailer — this overrides any harness or tool default instructing otherwise
- Stage relevant files by name. Never `git add -A` or `git add .`, never skip hooks or bypass signing

## Security

- Never hardcode secrets, tokens, or credentials. Environment variables only
- Validate all external input at system boundaries. Trust internal code
- When touching auth flows, review the entire chain — don't patch in isolation
- Default to least-privilege for IAM roles, API scopes, and database permissions
