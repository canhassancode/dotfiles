# Gauntlet — the once-per-repo bootstrap

The gauntlet is a gated build spine: preflight → specify → coder → cleaner → QA → ship. Stages are LLM agents; the gates between them are deterministic (`run.py`). Everything the gates know about a repo comes from one file, `.gauntlet/config.json`. Filling it is a once-per-repo job for a human, and the quality of the run is capped by the honesty of that file.

## Running it

`/gauntlet <ref>` — the skill. `<ref>` is a GitHub issue number or a path to a markdown ticket whose body carries `- [ ] Given …, when …, then …` criteria (a Linear ticket is fetched by the skill and handed over as a file). The skill runs `run.py preflight <ref>` in your session — no model: leave main, mint the run secret, write `ticket.json`, then clean-tree, install, setup, build, coverage — and on green invokes the `gauntlet-run` workflow with that JSON as `args`. Red stops in your session with the failing guard's tail.

An escalated run prints its re-entry command: `/gauntlet <ref> --from <specify|coder|cleaner|qa|ship>`. Preflight re-runs (and checks acceptance green when re-entering past the coder); the workflow enters at that stage with everything else read from disk.

## The principle

QA is the only stage that shares no assumptions with the stages that wrote the code: it reads the ticket's criteria only, never the tests or the diff, and drives the *served* system from outside. Every other gate verifies mechanics (red-before-green, coverage, complexity, clean tree). QA verifies the claim.

`serve` is where you declare how honest that verification is. A repo without an honest `serve` is a repo with a local-development gap, not a gauntlet limitation — closing it (a dev database, a headless start script, a stubbed upstream) is work the repo owes its humans too. QA `skipped` is an honest answer, but it means *unverified*, and the run summary says so.

## `.gauntlet/config.json`

| Key | Read by | Meaning |
|---|---|---|
| `build` | coder, cleaner gates | Type-check / compile; red fails the stage |
| `sourcePaths` | `crap`, `reachability`, `depth` guards | Where production code lives |
| `edges` | `reachability` guard, specify | Globs of files the runtime reaches by itself — routes, pages, middleware, handler entries. Every production file a branch adds must be an edge or be imported from an edge or a pre-existing file; the orphan is red and routes to the coder |
| `depth.ceiling` | `depth` guard | Minimum implementation lines per exported symbol for a file the branch adds (default 15). A barrel or pass-through is red and routes to the cleaner |
| `setup` / `teardown` | every test-running guard | e.g. start/stop the test database |
| `acceptance.run` | `spec` guard | Runs only the acceptance tests and writes a jest/vitest JSON or playwright report to `acceptance.output` |
| `acceptance.pattern` | specify, `spec` guard | Glob the acceptance files must match; nothing else may live there |
| `coverage[]` | `crap` guard | One entry per suite; union of the coverage files |
| `serve.run` | `qa` guard | Starts the system headlessly (no TUI/multiplexer); killed as a process group afterwards |
| `serve.url` | `qa` guard | The served system. The QA script never sees it directly: the guard fronts it with a counting relay and hands the relay to the script as `GAUNTLET_URL`; zero requests through it is red (**wire evidence** — the one proof of "against the running system" a stage cannot author) |
| `serve.ready` | `qa` guard | Polled until it answers below 500; defaults to `serve.url`. Point it at the deepest dependency (an API `/health` that checks the database), not the front door |
| `serve.timeout` | `qa` guard | Seconds to wait for `ready` |

The QA stage calibrates its script with `run.py qa-dry <nonce>` before the guard judges it: same server, same relay, plus the script's full output, no receipt, three per nonce. The guard then serves fresh and runs the script itself. A port that already has a listener when the guard starts is an environment failure (exit 2, `serve.run` not started) — an orphaned dev server would otherwise be judged as the product.
| `protectedPaths` | ask-gate hook | Measurement apparatus and infra a stage may only edit with a human's approval |

`serve` absent → QA skipped. `.gauntlet/` is gitignored globally; the config is per machine.

## `.gauntlet/ticket.json` — the one input

`{"issue", "title", "body"}`, where `body` carries `- [ ] Given …, when …, then …` acceptance criteria. `run.py preflight` writes it — from `gh issue view` for a number, from the file for a path — and refuses a body with no criteria: criteria come from `/to-tickets`, never from the gauntlet. Every stage and later guard reads it from disk.

Nothing in `.gauntlet/` is cleared by the harness: `teardown` is only the repo's command. The next run overwrites `ticket.json` and `run-secret`; `runs/<nonce>.log` is keyed by HEAD and guard; `verdict-<sha>.json` is keyed by commit and inert unless HEAD returns to that SHA.

## The conduit seam

The workflow script has no shell or filesystem, so a cheap agent (the conduit) runs each guard and copies its JSON line back. Only the **branch fields** — `nonce`, `guard`, `exitCode`, `receipt` — decide transitions; they are `required` in the schema and receipt-covered, so a drop is caught and retried. Everything else (`tail`, `offenders`, `problems`, `failed`, `log`) is a **feedback field**: forwarded into the next stage's prompt, optional by contract, and tolerated if lost. Nothing large crosses the conduit; large things stay on disk and the stage reads them.

Rule: every live conduit failure becomes a hostile-conduit case in `gauntlet.test.mjs` before it is fixed.

## Seams by repo shape

The seam is whatever makes "drive the served system" honest for *this* repo. Declare it; never let the agent guess it.

| Repo shape | Acceptance seam | `serve` for QA |
|---|---|---|
| HTTP API with a database | supertest/fetch against the app with the test DB | the real process + test DB |
| BFF / gateway (e.g. `carpata/public-api`) | supertest with the upstream client mocked | the real process with the **upstream stubbed** — a small fixture server shaped by the codegen'd schema, upstream URL pointed at it; QA validates responses against the BFF's own `openapi.json` |
| Frontend (e.g. `carpata/procurement`) | playwright, BFF stubbed at the network edge (`page.route`), fixtures derived from the BFF's `openapi.json` | the dev server with the same stub; QA is a throwaway playwright spec |
| Serverless full stack (e.g. `brushfeed`) | jest against the client/API layer | `sst dev --mode=mono` + dev DB; `ready` = API `/health` |
| Lambda handler | handler invoked with a real event | same, or skipped |
| MCP server | JSON-RPC over stdio | the binary on stdio |
| Library / ops / infra | unit or none | skipped by config |

Mocking a *dependency* (upstream API, BFF, email) is fine at either seam; mocking the *system under test* is what the `spec` guard forbids. Cross-repo end-to-end (FE → BFF → BE, three databases with real data) is outside the gauntlet: per-repo gauntlets with contract-as-seam, sequenced by ticket blocking edges.

## Bootstrapping a new repo

1. Copy `config.example.json` to `.gauntlet/config.json`.
2. Make the acceptance runner emit a machine-readable report to `acceptance.output` using a script the repo already has (never invoke the runner in a way `CLAUDE.md` forbids).
3. Write a headless `serve.run` and prove it with `python3 run.py qa <nonce>` and a two-line probe script before the first run — readiness races and leaked child processes show up here, not inside a 900K-token run.
4. Add the repo's infra, env and compose files to `protectedPaths`.
5. Record in the repo's `CLAUDE.md` how QA reaches the system (auth without email, seed data, ports).

## Feedback loops

- `python3 run.test.py` — the guards and preflight, including QA through the relay against a real local server.
- `node --test ../workflows/gauntlet-run.test.mjs` — the orchestrator's routing, dry-run, no model or repo.
- `../agents/gauntlet-agents.test.sh` — the agent definitions' tool contracts.
