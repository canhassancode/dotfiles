## Repo layout: GNU Stow

This is a GNU Stow-managed dotfiles repo. Each top-level directory (e.g. `zsh/`, `nvim/`, `git/`) is an independent stowable package. Stow creates symlinks from `$HOME` into `~/dotfiles`:

- `cd ~/dotfiles && stow zsh` → `~/.zshrc` symlinks to `~/dotfiles/zsh/.zshrc`
- `cd ~/dotfiles && stow nvim` → `~/.config/nvim/` symlinks into `~/dotfiles/nvim/`

**The directory tree inside each package mirrors the target tree under `$HOME`.** For example, `git/.gitconfig` stows to `~/.gitconfig`, `nvim/.config/nvim/init.lua` stows to `~/.config/nvim/init.lua`.

**When editing files here, you are editing the real file** — Stow's symlinks mean `~/.zshrc` *is* `~/dotfiles/zsh/.zshrc`. No copy step needed; changes take effect immediately. `stow` is idempotent and safe to re-run after pulling.

See `README.md` for the full package table and bootstrap instructions.

## Issue tracker

tracker: github

## Agent skills

### Issue tracker

GitHub Issues (`canhassancode/dotfiles`). External PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context (`CONTEXT.md` + `docs/adr/`). See `docs/agents/domain.md`.
