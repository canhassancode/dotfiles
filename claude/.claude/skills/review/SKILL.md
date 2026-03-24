---
name: review
description: Review code changes for quality, conventions, security, and test coverage. Use when asked to review code, check changes, audit a file, or before creating a PR.
argument-hint: [file-or-pattern]
---

# Code review

Review code for quality issues, convention violations, and security concerns.

## What to check

1. **Types** — no `any`, explicit return types, proper use of existing types
2. **Security** — no hardcoded secrets, input validation at boundaries, least-privilege
3. **Spelling** — British English in all code, comments, and copy
4. **Complexity** — no over-engineering, no unnecessary abstractions, no premature optimisation
5. **Tests** — changes should have corresponding tests, following the repo's testing strategy
6. **Comments** — should not exist unless explicitly requested

## Process

1. If no argument provided, run `git diff` to find recent changes
2. If a file or pattern is provided via $ARGUMENTS, review those files
3. Read each file to understand context before flagging issues
4. Report findings in `file:line` format
5. Categorise findings as: **must fix**, **should fix**, or **consider**

## Output format

```
## Must fix
- src/auth/login.ts:42 — `any` type on request parameter

## Should fix
- src/utils/format.ts:18 — `normalized` should be `normalised`

## Consider
- src/api/handler.ts:55 — validation could be stricter on external input
```
