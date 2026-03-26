# How to work with me

## Approach
- Read existing code before making changes. Understand patterns, then follow them
- Prefer single scoped tasks — accuracy over speed. Do one thing well before moving on
- If something is ambiguous, ask. "Does this mean X?" is better than guessing wrong
- For large changes, outline the plan first and get confirmation before implementing
- Only suggest refactoring when explicitly asked. Don't clean up surrounding code unprompted

## Code quality
- No `any` types — use existing types or create them in a centralised location
- British English spelling in all code, comments, and copy (e.g. `normalised`, `organised`, `colour`)
- Never add code comments — well-named variables and clear code are the documentation
- Explicit return types on functions. Explicit intermediate variables over clever composition

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
- I work in pnpm monorepos (SST, Astro, Hono, Drizzle). Assume this stack unless the repo says otherwise

## Skills override defaults
- When asked to commit (e.g. "commit this", "save this", "lets commit", "get this in"), ALWAYS use the `/commit` skill via the Skill tool. NEVER follow the built-in commit instructions. The `/commit` skill is the single source of truth for how commits are created
- When asked to create a pull request or open a PR, ALWAYS use the `/pr` skill via the Skill tool. NEVER follow the built-in PR creation instructions
