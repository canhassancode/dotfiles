# claude

Global Claude Code configuration. Stows `claude/.claude/` → `~/.claude/`, which Claude Code reads on every session regardless of cwd.

## Install

```sh
cd ~/dotfiles && stow claude
```

## Layout

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions — how I want Claude to work with me (tone, TS conventions, testing, security) |
| `skills/` | Slash-command skills available in any session |
| `agents/` | Sub-agent definitions |
| `hooks/` | Lifecycle hooks |
| `settings.json` | Permissions, model defaults, env vars |
| `statusline-command.sh` | Status line script |

## Skills

| Skill | Purpose |
|---|---|
| `/grill-me` | Socratic interview to stress-test a plan before implementing |
| `/grill-with-docs` | Same as `/grill-me`, plus captures decisions in repo docs/ADRs |
| `/challenge` | Engineering-judgement coaching on architecture decisions |
| `/to-prd` | Synthesize current conversation into a PRD on the issue tracker |
| `/to-issues` | Break a plan or PRD into independently-grabbable vertical-slice issues |
| `/triage` | Move issues through the triage state machine (`needs-triage` → `ready-for-agent`/`ready-for-human`/`wontfix`) |
| `/tdd` | Red-green-refactor loop with the agent |
| `/diagnose` | Disciplined diagnosis loop for hard bugs and perf regressions |
| `/improve-codebase-architecture` | Find deepening opportunities informed by domain language and ADRs |
| `/review` | Review code changes for quality, conventions, security, test coverage |
| `/commit` | Conventional commit, single-line message, no co-authoring |
| `/pr` | Open a pull request with a structured summary |
| `/validate` | Run typecheck, lint, and tests in one go |
| `/write-skill` | Scaffold a new skill with progressive disclosure |
| `/obsidian-vault` | Search, create, manage notes in the Obsidian vault |

## Pipeline

The skills compose into a deliberate workflow:

```
ideation → /grill-me or /grill-with-docs
        → /to-prd        (parent issue, needs-triage)
        → /to-issues     (vertical slices, needs-triage)
        → /triage        (ready-for-agent | ready-for-human)
        → ralph          (AFK execution — see ../ralph/)
```

See [ralph](../ralph/) for the AFK execution layer.
