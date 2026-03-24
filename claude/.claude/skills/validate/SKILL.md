---
name: validate
description: Run the full validation workflow — type-check, lint, and tests
disable-model-invocation: false
user-invocable: true
argument-hint: "[scope: all, types, lint, test]"
allowed-tools: Bash, Read, Grep, Glob
---

Run the project's validation workflow. Detect the package manager and available scripts automatically.

## Steps

1. **Detect setup**: Read `package.json` to find available scripts and the package manager (pnpm/npm)
2. **Run checks based on scope** (`$ARGUMENTS`, default: `all`):

   **types** — Run type checking:
   - `pnpm type-check` or `npx tsc --noEmit`

   **lint** — Run linting:
   - `pnpm lint` or `npm run lint`

   **test** — Run tests:
   - `pnpm test` or `npm test`
   - If Docker is needed for integration tests (check for `test:db:up` script), warn but don't start Docker automatically

   **all** — Run all three in order: types → lint → test

3. **Report results**:
   - For each step: pass/fail with error count
   - For failures: show the specific errors grouped by file
   - End with a clear summary

## Rules
- Stop on first failure in a step and report it — don't continue to the next step
- Never auto-fix lint errors unless explicitly asked
- If a script doesn't exist, skip it and note it was skipped
- For monorepos, run from the root unless a specific module is targeted
