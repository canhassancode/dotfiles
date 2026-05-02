---
name: commit
description: Create a git commit with conventional commit message format. TRIGGER when the user asks to commit, stage changes, "get changes in", save work, or any request that involves creating a git commit without pushing or opening a PR.
argument-hint: [optional message override]
---

# Commit

Create a commit following the project's conventional commit format.

## Commit message format

```
<prefix>: <short summary>
```

## Prefixes

| Prefix     | Use case                                  |
| ---------- | ----------------------------------------- |
| `feat`     | New feature or capability                 |
| `fix`      | Bug fix                                   |
| `hotfix`   | Urgent production fix                     |
| `refactor` | Code restructure with no behaviour change |
| `chore`    | Dependencies, config, tooling, CI         |
| `docs`     | Documentation only                        |

## Rules

- Commit message is always a single line — no body, no multi-line, no Co-Authored-By
- Summary is a single short sentence, lowercase, no trailing full stop
- Summary describes the core change, not every file touched
- Use the most specific prefix that applies
- If the user provides a message via $ARGUMENTS, use it as the summary but still apply the correct prefix
- Stage only relevant files — never use `git add -A` or `git add .`
- Never skip hooks or bypass signing

## Process

1. Run `git status` and `git diff` to understand what changed
2. Run `git log --oneline -5` to check recent commit style
3. Determine the appropriate prefix based on the nature of the changes
4. Draft the commit message
5. Stage the relevant files by name
6. Create the commit
7. Run `git status` to verify success
