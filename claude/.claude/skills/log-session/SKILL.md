# Log Session

Write a session summary to the Obsidian vault.

## Vault path

`/Users/hassan/Documents/Oneforge Vault/Claude/Sessions`

## Process

1. Review the conversation so far — what was discussed, what was built, what was changed
2. Identify the project name from the working directory or conversation context
3. Create a markdown file at the vault path named `YYYY-MM-DD-<short-slug>.md` (e.g. `2026-03-24-kitty-config.md`)
4. If multiple sessions on the same day and project, append a number: `2026-03-24-kitty-config-2.md`
5. Write the file using the format below
6. Confirm the file was written and show the path

## File format

```markdown
---
date: YYYY-MM-DD
project: <project or repo name>
tags:
  - claude-session
  - <relevant tags>
---

## Summary

<2-3 sentences on what was accomplished>

## Changes

- <bullet list of concrete changes made — files edited, features added, bugs fixed>

## Bugs found

- <any bugs discovered during the session, or "None">

## Decisions

- <any notable decisions or trade-offs made, or "None">

## Next steps

- <what remains to be done, or "None">
```

## Rules

- Keep the summary concise — this is a log, not documentation
- Use wikilinks (`[[Page Name]]`) when referencing other vault notes if relevant
- Tags should be lowercase, hyphenated
- Only include sections that have content — omit empty sections rather than writing "None"
- Use the current date, not a guess
