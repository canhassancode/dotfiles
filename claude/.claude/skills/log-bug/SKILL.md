# Log Bug

Capture a bug or issue to the Obsidian vault for tracking.

## Vault path

`/Users/hassan/Documents/Oneforge Vault/Claude/Bugs`

## Process

1. Gather details about the bug from conversation context or user description
2. Create a markdown file at the vault path named `YYYY-MM-DD-<short-slug>.md`
3. Write the file using the format below
4. Confirm the file was written and show the path

## File format

```markdown
---
date: YYYY-MM-DD
project: <project or repo name>
status: open
severity: <low | medium | high | critical>
tags:
  - bug
  - <relevant tags>
---

## Description

<clear description of the bug>

## Steps to reproduce

1. <step>
2. <step>

## Expected behaviour

<what should happen>

## Actual behaviour

<what actually happens>

## Context

- **File(s)**: <relevant file paths>
- **Branch**: <git branch if applicable>
- **Environment**: <local, staging, production>

## Notes

<any additional context, workarounds, or suspected root cause>
```

## Rules

- Be specific — include file paths, error messages, and stack traces where available
- British English spelling
- Default severity to `medium` unless the user specifies otherwise
- Omit sections that have no content
