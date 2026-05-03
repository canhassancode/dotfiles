# ralph

AFK Claude loop. Runs Claude inside a Docker sandbox against the current repo's `ready-for-agent` GitHub issue pool, opens a PR per issue, and exits when the pool is drained or the iteration cap is hit.

Named after [Ralph Wiggum](https://ghuntley.com/ralph/), the autonomous-coding pattern popularised by [Matt Pocock](https://www.aihero.dev/getting-started-with-ralph).

## Install

```sh
cd ~/dotfiles && stow ralph
```

| Path                      | Stows to                                                            |
| ------------------------- | ------------------------------------------------------------------- |
| `.local/bin/ralph`        | `~/.local/bin/ralph` (must be on `$PATH`)                           |
| `.config/ralph/prompt.md` | `~/.config/ralph/prompt.md` (or `$XDG_CONFIG_HOME/ralph/prompt.md`) |

## Prerequisites

- `sbx` — Docker sandbox CLI (`brew install sbx`)
- `gh` — authenticated for the current repo
- `claude` — available inside the sandbox
- Dotfiles repo cloned at `$HOME/dotfiles` (ralph mounts it read-only into the sandbox)
- The repo must have triage labels (`/to-prd`, `/to-issues`, `/triage` create them on first use)

## Sandbox bootstrap

The first time ralph runs in a repo, it creates a sandbox named `<repo>-ralph` with two read-only mounts:

| Host path        | Why                                                                    |
| ---------------- | ---------------------------------------------------------------------- |
| `$HOME/.claude`  | Resolves stow-managed symlinks like `~/.claude/CLAUDE.md` on the host. |
| `$HOME/dotfiles` | Provides the actual stow source the above symlinks resolve into.       |

It then symlinks the canonical config into the agent's `$HOME` inside the sandbox:

```
$HOME/.claude/CLAUDE.md → $HOME/dotfiles/claude/.claude/CLAUDE.md
$HOME/.claude/skills    → $HOME/dotfiles/claude/.claude/skills
```

This is the smallest change that lets Claude inside the sandbox load your global `CLAUDE.md` and personal skills (`/commit`, `/pr`, `/tdd`, etc.) without giving the agent write access to your host config. Settings, sessions, and credentials stay in the agent's own writable `~/.claude/` — they aren't touched.

Skill edits on the host are visible to the next iteration immediately; nothing is baked into a container image.

### Smoke test

After ralph creates the sandbox, verify the integration:

```sh
sbx exec <repo>-ralph -- ls $HOME/.claude/skills
```

You should see your personal skills (`commit`, `pr`, `tdd`, `triage`, …). If the listing is empty or errors, the symlink target isn't reachable — check the mount with `sbx exec <repo>-ralph -- mount | grep claude`.

### Recreating the sandbox

Mounts are fixed at create time. To change them, remove and let ralph recreate:

```sh
sbx rm <repo>-ralph
ralph
```

## Usage

```sh
ralph                       # drain the ready-for-agent pool (cap: 30 iterations)
ralph --issue 42            # work a single issue (cap: 10 iterations)
ralph --max-iterations 50   # override the cap
```

The sandbox name is derived from the cwd: `~/code/brushfeed` → `brushfeed-ralph`.

## Per-iteration contract

Each iteration is a one-shot Claude session inside the sandbox executing [prompt.md](.config/ralph/prompt.md):

1. **Pick** — query `gh issue list --label ready-for-agent`, oldest first. Empty pool → emit `<promise>COMPLETE</promise>` and stop.
2. **Claim** — `gh issue edit <N> --remove-label ready-for-agent` (concurrency-safe).
3. **Read brief** — `gh issue view <N>`; the `## Agent Brief` section is the contract.
4. **Branch** — `ralph/issue-<N>` off the default branch.
5. **Implement** — vertical slice, small commits.
6. **Feedback loops** — typecheck, lint, test (commands sourced from the repo's `CLAUDE.md`). Up to 3 attempts per step.
7. **Success** — open a real PR with `Closes #<N>`. Exit iteration.
8. **Failure** — push WIP branch, comment findings on the issue, flip to `ready-for-human`. Exit iteration.

PR existence is the binary signal: PR open = Ralph thinks it's done. No PR = Ralph couldn't finish; the issue comment has forensics.

## Customising

- **Prompt**: edit `.config/ralph/prompt.md` and `stow ralph` again (or just edit through the symlink). The script `cat`s it on every invocation, so changes are picked up immediately.
- **Iteration caps**: pass `--max-iterations`, or change the defaults at the top of the script.

## Related

- [`claude`](../claude/) — the skills (`/to-prd`, `/to-issues`, `/triage`) that feed the `ready-for-agent` pool Ralph drains.
