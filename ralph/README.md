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
- The repo must have triage labels (`/to-prd`, `/to-issues`, `/triage` create them on first use)

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
