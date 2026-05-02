---
name: pr
description: Create a GitHub pull request with a structured summary. TRIGGER when the user asks to commit and push, push changes, open a PR, create a pull request, "ship it", or any request involving pushing code or creating a pull request.
argument-hint: [optional title override]
---

# Create pull request

Create a GitHub PR with a structured summary of all changes.

## Process

1. Run `git status` to check for uncommitted changes — commit first if needed
2. Run `git log` and `git diff` against the base branch to understand all changes
3. Determine the base branch (usually `main` or `master`)
4. Push the current branch to remote with `-u` flag if needed
5. Create the PR using `gh pr create`

## PR format

- Title: short (under 70 characters), use the same prefix convention as commits (feat, fix, etc.)
- If the user provides a title via $ARGUMENTS, use it

Body template:

```markdown
## Summary

- Bullet points describing the key changes

## Test plan

- [ ] How to verify the changes work
```

## Rules

- Analyse ALL commits on the branch, not just the latest one
- Never force push
- Do not push to main/master directly
