# pi

Configuration for the [pi coding agent](https://pi.dev) (`@earendil-works/pi-coding-agent`),
stowed into `~/.pi/agent/`. Currently ships one thing: **guardrails** that let pi run with
its usual autonomy on the host filesystem without being able to do destructive or
secret-leaking things unguarded.

```sh
cd ~/dotfiles && stow pi
```

Stow symlinks `extensions/` into `~/.pi/agent/` (which already exists as a real directory
holding `auth.json`, `settings.json`, `sessions/`, `skills/` — those stay machine-local and
are never touched). pi auto-discovers `~/.pi/agent/extensions/*.ts` on startup. After a pull,
`stow pi` again (idempotent) and `/reload` inside a running pi to pick up changes.

## What's deliberately *not* here

- **`settings.json`** — pi writes `lastChangelogVersion` back to it on update, so versioning
  it would churn the repo. It stays local; set `defaultModel` / `defaultThinkingLevel` there.
- **`auth.json`** — credentials. This repo is public; secrets never enter it.
- **The OS-level sandbox** — see [Going AFK](#going-afk-real-isolation) below.

## The guardrails

`extensions/guardrails.ts` is a single `tool_call` hook. Threat model: **interactive use on
the real filesystem**, where the human is the gate. It guards against two things slipping past
between glances — destructive ops, and secrets leaving the box.

The whole policy is four arrays at the top of the file. Edit those; the handler needs no
touching.

| Array | Tool | Effect |
|---|---|---|
| `denyBashPatterns` | `bash` | Blocked outright — no prompt, no override. The catastrophic-and-never-legitimate (`rm -rf /`, forkbomb, `mkfs`, `dd of=/dev/…`). |
| `confirmBashPatterns` | `bash` | Yes/No prompt before running. Blocked by default when there's **no UI** (print/headless), so an accidental unattended run can't wave them through. |
| `secretPrefixes` + `secretBasenamePatterns` | `read` | Blocks the read tool opening secret paths (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.pi/agent/auth.json`, `*.pem`, `*.key`, `.env*`) — keeps them out of the model context and session log. |
| (same secret set, plus `/.git/`) | `write`/`edit` | Blocks writes to those paths — clobber protection for your keys and git internals. |

What's flagged for **confirm**: recursive `rm`, `find -delete`, `xargs rm`, `git push --force`,
`git reset --hard`, `git clean -f`, `sudo`, recursive/`777` `chmod`/`chown`, upload-shaped network
calls (`curl -d/--data/-T/-F`, `wget --post`, `scp`, `nc`), and pipe-to-shell (`curl … | sh`).
Plain `GET` curls and ordinary commands pass untouched, so day-to-day friction is near zero.

### Scope boundary

pi's `bash` tool has **two entry points**: the agent's own tool calls (`tool_call`, what this
guards) and your `!`-prefixed commands (`user_bash`, untouched). Commands *you* type are yours —
they're never gated.

### Honest limit: this is a speed-bump, not isolation

Regex matching catches the accidental and the obvious. It does **not** stop a determined agent:
`cat ~/.ssh/id_rsa` via bash side-steps the read-tool block, and patterns are evadable with
base64, env indirection, or unusual flag spellings. That's an accepted trade-off for interactive
use where you're watching. For genuinely unattended runs, you need real isolation — see below.

### Editing the policy

Open `extensions/guardrails.ts`, adjust an array, save, and `/reload` (or restart pi). To
red-team a change, the regexes are plain — drop them into a throwaway Node script and assert the
classifications, e.g. `rm -rf /` → deny, `rm -rf node_modules` → confirm, `curl https://x` → pass.

## How pi extensions work (primer)

Enough to extend this yourself. Full docs ship with the package at
`$(npm root -g)/@earendil-works/pi-coding-agent/docs/extensions.md`.

- **An extension is a TypeScript module** exporting a default factory `(pi: ExtensionAPI) => void`.
  Loaded via [jiti](https://github.com/unjs/jiti) — no compile step, TS runs directly.
- **Locations** (auto-discovered): `~/.pi/agent/extensions/*.ts` (global, what this package uses)
  or `.pi/extensions/*.ts` (project-local). A subdirectory works too via `index.ts`. `pi -e ./x.ts`
  loads one ad-hoc for testing.
- **Events** — subscribe with `pi.on("event", handler)`. The lifecycle runs
  `session_start → before_agent_start → turn_start → [tool_execution_start → tool_call →
  tool_result] → turn_end → agent_end`. The guardrails use `tool_call`, which fires **before** a
  tool runs and can return `{ block: true, reason }` to stop it. `event.input` is also mutable in
  place if you want to *rewrite* args rather than block.
- **Typed narrowing** — `isToolCallEventType("bash", event)` narrows `event.input` to the right
  shape (`{ command }` for bash, `{ path }` for read/write/edit). No `any`, no casts.
- **`ctx`** — `ctx.hasUI` (false in print/headless mode — gate dangerous things on this),
  `ctx.cwd`, `ctx.ui.select/confirm/notify` (user interaction), `ctx.signal` (abort).
- **Beyond hooks** — `pi.registerTool()` adds a tool the model can call, `pi.registerCommand()`
  adds a `/command`, `pi.registerShortcut()` binds a key. Not needed for guardrails.

## Going AFK (real isolation)

If you ever run pi **unattended**, confirm-prompts are useless (no human to answer; the hook
hard-blocks them). You need OS- or container-level isolation. Two options:

1. **pi's bundled sandbox** — `examples/extensions/sandbox/` in the package uses
   `@anthropic-ai/sandbox-runtime` (`sandbox-exec` on macOS, bubblewrap on Linux) to enforce
   filesystem + network limits at the OS level. It needs its own `npm install` (a `node_modules`),
   which is why it's not vendored into this pure-config package. Configure via
   `~/.pi/agent/extensions/sandbox.json` — deny-read `~/.ssh ~/.aws ~/.gnupg`, deny-write
   `.env *.pem *.key`, and an allowlist of network domains.
2. **Docker `sbx`** — the same isolation layer the `ralph` package already uses for AFK Claude.
   One isolation model across every agent: run pi *inside* `sbx` rather than maintaining pi's
   separate sandbox extension. Set the network policy with `sbx policy allow/deny network <host>`.

When that day comes, prefer (2) for consistency with `ralph`, and copy the sandbox extension only
if you need pi-native, per-command wrapping.
