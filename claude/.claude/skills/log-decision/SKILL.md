# Log Decision

Record an architectural or technical decision to the Obsidian vault.

## Vault path

`/Users/hassan/Documents/Oneforge Vault/Claude/Decisions`

## Process

1. Identify the decision from conversation context or user description
2. Create a markdown file at the vault path named `YYYY-MM-DD-<short-slug>.md`
3. Write the file using the format below
4. Confirm the file was written and show the path

## File format

```markdown
---
date: YYYY-MM-DD
project: <project or repo name>
tags:
  - decision
  - <relevant tags>
---

## Decision

<one-line summary of what was decided>

## Context

<why this decision was needed — the problem or trade-off>

## Options considered

- **<Option A>**: <pros/cons>
- **<Option B>**: <pros/cons>

## Outcome

<what was chosen and why>

## Consequences

- <what this means going forward — what it enables or constrains>
```

## Rules

- Focus on the "why" — the code shows the "what"
- Keep it brief but complete enough to understand months later
- Use wikilinks to reference related vault notes if relevant
- Omit sections that have no content
