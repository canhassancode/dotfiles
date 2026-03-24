---
name: coding-conventions
description: Coding conventions and style rules for all code. Applies when writing, editing, or generating any code. Covers typing, naming, spelling, and structure preferences.
user-invocable: false
---

# Coding conventions

## TypeScript

- No `any` types — use existing types or create new ones in a centralised location
- Explicit return types on all functions
- Prefer explicit intermediate variables over clever composition
- Use `const` by default, `let` only when reassignment is necessary

## Spelling

- British English in all code, comments, copy, and commit messages
- Examples: `normalised`, `organised`, `colour`, `behaviour`, `centre`, `serialise`

## Comments

- Never add code comments — well-named variables and clear code are the documentation
- Do not add JSDoc, TSDoc, or docstrings unless explicitly asked

## Structure

- Do not over-engineer — only make changes that are directly requested
- Do not add error handling for scenarios that cannot happen
- Do not create abstractions for one-time operations
- Do not add feature flags or backwards-compatibility shims

## Objectivity

- Provide objective assessment regardless of expectations
- Present arguments both for and against changes when trade-offs exist
- If unsure, say so — do not default to approval
- Do not agree to avoid friction — challenge weak reasoning directly
