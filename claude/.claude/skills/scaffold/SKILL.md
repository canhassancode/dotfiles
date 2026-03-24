---
name: scaffold
description: Scaffold a new module, component, or API route following project conventions
disable-model-invocation: false
user-invocable: true
argument-hint: "<type> <name> (e.g. module auth, component UserCard, route /v1/posts)"
---

Scaffold a new `$ARGUMENTS` following the conventions of this project.

## Before scaffolding
1. Read the project's CLAUDE.md, .cursorrules, and architecture docs to understand conventions
2. Look at existing examples of the same type to match patterns exactly
3. Identify the correct location based on project structure

## What to scaffold based on type

**module** (monorepo workspace module)
- `package.json` with correct workspace name and dependencies
- `tsconfig.json` extending root config
- `src/` directory with appropriate structure (routes/, services/, types/, etc.)
- Add to `pnpm-workspace.yaml` if needed
- Add to SST config if it's a Lambda function

**component** (React/Astro component)
- Component file with proper TypeScript types
- Tailwind styling only
- Props type defined inline or in local types file
- Follow existing component patterns in the project

**route** (API route — Hono)
- Route handler in correct routes/ directory
- Request/response types
- Validation with Zod schemas
- Integration test file with BDD structure (Given/when/then)

**service** (business logic)
- Service functions (functional, not class-based unless project uses classes)
- Types for inputs/outputs
- Integration test file

## Rules
- Match existing patterns exactly — don't introduce new conventions
- British English in all naming and copy
- No `any` types, no code comments
- Explicit return types on all functions
- Only create what's needed — don't over-scaffold
