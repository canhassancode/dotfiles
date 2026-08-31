# Porting the gauntlet to the pi harness

## The question

On Claude Code, the gauntlet is a state machine that spawns fresh-context subagents as **conduits** — a subagent exists only to relay the output of a deterministic Python script (`run.py`) back to an orchestrator, because Claude Code has no way to run a script as a first-class step. Determinism is enforced *outside* the model via receipt-hashed script exit codes.

**Can the same gauntlet be built on the pi harness so that the harness itself has real layers/stages that run scripts deterministically — a step that runs `python3 run.py <guard>` and branches on its exit code with NO LLM in the loop — instead of using conduit subagents to fake it?**

## Which "pi" this is

**pi.dev** — "There are many agent harnesses but this one is yours" — a minimal terminal coding-agent harness by Mario Zechner. Source: `earendil-works/pi`, package `@earendil-works/pi-coding-agent` (aka `@mariozechner/pi-coding-agent`).

- Home + tagline: https://pi.dev/ (links to docs at `/docs/latest`)
- Docs root: https://pi.dev/docs/latest
- Source repo: https://github.com/earendil-works/pi/tree/main/packages/coding-agent
- Extensions doc: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md
- SDK doc: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md
- RPC doc: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md

Design premise (stated on the home page and repo): the **core is deliberately minimal** — it ships four tools (Read, Write, Edit, Bash) and *no* plan mode, sub-agents, MCP, or permission popups. Everything beyond the agent loop is built as **extensions, skills, or packages** (https://pi.dev/, https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md). So "does pi have workflows/stages" is really "does an extension provide them", and the answer is yes.

The relevant extension is **`tintinweb/pi-subagents`** — "Claude Code like Sub-Agents & Workflow Orchestration for Pi ... claude compatible dynamic workflows" (https://github.com/tintinweb/pi-subagents). Its workflow tool is a **verbatim port of Claude Code's `Workflow` tool down to its state model — "a script written for Claude Code runs here unchanged"** (https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md, "Coming from Claude Code"). This is almost certainly the exact package the current gauntlet's Dynamic Workflows would land on.

## Capability table

| Feature | Supported on pi? | Source |
|---|---|---|
| Native pipeline/stages/phases in core | No — core is a minimal agent loop | https://pi.dev/ |
| Workflow orchestrator (Dynamic Workflows, Claude-compatible) | Yes, via `pi-subagents` extension (`SubagentWorkflow` tool) | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md |
| Orchestrator control flow is deterministic, not an LLM | Yes — workflow is imperative JS in a `node:vm` sandbox; `agent()` is the only thing that calls a model | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md |
| Deterministic script/shell **gate** that branches on exit code | Yes — `gate: "npm test"` on an `agent()` call; non-zero exit fails the agent, output becomes the error | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md ("Reference → agent") |
| Standalone script step with **no agent attached** (a pure `run.py` node in the workflow DAG) | No — workflow scripts have no filesystem/network/module access; shell only runs via `gate`, which is bound to an `agent()` call | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md ("What workflows can't do") |
| Hooks / lifecycle events | Yes — rich event bus: `project_trust`, `session_start`, `before_agent_start`, `context`, `before_provider_request`, `tool_execution_start`, `tool_call`, `tool_execution_end`, `agent_settled`, `session_before_compact`, ... | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md ("Events → Lifecycle Overview") |
| A hook can run arbitrary code (child_process → `python3 run.py`) deterministically | Yes — "Extensions run with your full system permissions and can execute arbitrary code" | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md ("Extension Locations", security note) |
| A hook can **block/gate** a tool call on that script's result | Yes — `tool_call` handler returns `{ block: true, reason?, terminate? }`; can also mutate `event.input` in place | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md ("Tool Events → tool_call") |
| Subagents | Yes, via `pi-subagents` (`Agent` tool + workflow `agent()`); fresh context, own tools/model per child | https://github.com/tintinweb/pi-subagents |
| MCP support | Not in core; add via extension (reads `.pi/mcp.json`, Claude-Code format) | https://pi.dev/ ; https://github.com/earendil-works/pi/issues/563 |
| Structured output / schema enforcement | Partial — `schema` on `agent()` returns a validated object, but it is **pressure, not force** (`StructuredOutput` tool + `constrainedSampling: "prefer"` + retry), where Claude Code can force the tool call | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md ("schema is pressure, not a guarantee"; "Coming from Claude Code") |
| Drive pi as a subprocess from an external deterministic orchestrator | Yes — SDK (`createAgentSession()`), RPC mode (`pi --mode rpc`, LF-delimited JSONL), print/JSON mode (`pi -p`) | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md ; https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md |
| Determinism guardrails inside workflows | Yes — `node:vm` sandbox where `Date.now()`, `new Date()`, `Math.random()`, `eval`, `Function()` all throw; runs are journalled for prefix-replay resume | https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md ("Troubleshooting"; "What workflows can't do") |

## Verdict on the crux: **partial — and the conduit pattern becomes unnecessary either way**

pi.dev has **no native pipeline layer in the core** and **no first-class "run this script, branch on exit code" node that stands alone in a workflow graph**. But it removes the *reason* the conduit pattern exists, in three complementary ways:

1. **The workflow orchestrator is itself deterministic, non-LLM code.** In `pi-subagents`, a workflow is imperative JavaScript (`agent()`, `pipeline()`, `parallel()`, `phase()`, `if`/`switch`) running in a `node:vm` on a worker thread. Only `agent()` calls invoke a model; all branching is real code. So you never need a subagent to *relay* a script's output to an orchestrator — the orchestrator is a program and can branch on results directly. (https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md)

2. **`gate` runs your script and branches on its exit code with no model involved** — `gate: "python3 run.py <guard>"` runs the command after the agent; a non-zero exit fails that agent and feeds its output back as the error, driving a retry/`resume` loop. This is the "verify by running, not by asking" primitive and is a strict signal, exactly like the receipt-hashed exit code in the current gauntlet. The one caveat: `gate` is *attached to an `agent()` call*, and workflow scripts have no direct filesystem/child_process of their own — so a script step in the workflow always hangs off an agent as its verifier, rather than being a standalone graph node. (https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md)

3. **For a truly agent-free deterministic script step, pi has a native harness layer that the workflow does not: extension lifecycle hooks.** An extension is TypeScript running with full system permissions (Node `child_process`), so a `tool_call` (or `before_agent_start` / `context`) handler can run `python3 run.py <guard>`, read its exit code, and return `{ block: true, reason }` — or mutate the tool input — entirely outside the model. That is a deterministic gate enforced *by the harness*, no LLM and no conduit subagent. It is event-triggered rather than a numbered pipeline stage, but it is a genuine "the harness runs the script and decides" layer. (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)

So: **no native standalone script *stage*, yes to deterministic script *gates* (via `gate`) and deterministic script *hooks* (via extensions), and yes to a deterministic *orchestrator* that never needs a conduit.** Overall: partial on "pipeline of script stages", but a strict improvement over the Claude Code conduit hack — determinism lives in code and hooks, not in a subagent pretending to be a wire.

## How you'd build the gauntlet on pi

Three viable shapes, strongest first for matching "determinism enforced outside the model":

**A. External orchestrator drives pi (closest match to the current gauntlet).** Keep `run.py` as the state machine. Between stages, call pi headlessly as a subprocess — `pi -p "<stage prompt>"` for one-shot turns, or the RPC/SDK surface (`pi --mode rpc`, or `createAgentSession()`) for a persistent session you feed turn by turn. Your Python owns every gate: run `python3 run.py <guard>`, branch on its exit code, and only then spawn the next pi turn. No conduit subagents at all; pi is just the LLM step, your script is the layer. (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md, https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md)

**B. A `pi-subagents` workflow with `gate` per stage (closest match to Dynamic Workflows).** Port the existing Dynamic-Workflow script almost verbatim (it is claimed to run unchanged). Each gated stage is an `agent(...)` that does the work with `gate: "python3 run.py <guard>"`; a non-zero exit fails it, and a `resume`-based retry loop feeds the failure back. Use `schema` where you need structured output (treating it as pressure, adding `.filter(Boolean)`), `pipeline`/`parallel` for fan-out, and `phase()` for the visible stage tree. This keeps determinism in the JS orchestrator and the shell gate — the conduit subagent disappears. Limits: shell only runs *as a gate on an agent*, `schema` is soft, and `budget.total` is always `null`. (https://github.com/tintinweb/pi-subagents/blob/master/docs/workflows.md)

**C. An extension hook as the hard gate.** For a check that must fire regardless of what the model does, register a `tool_call` (or `agent_settled`) handler that shells out to `python3 run.py <guard>` and returns `{ block: true, reason }` on non-zero. This is the only way to get a deterministic script decision *with no agent turn at all* inside a single pi session — the harness runs the receipt-hashed script and vetoes the step itself. Combine with A or B for defence in depth. (https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)

Recommendation: **A for the orchestration backbone** (it is the same "script owns the state machine, model is one step" architecture you already have, minus the conduit), with **C as the in-session hard gate**. B is the least-effort port if you want to stay inside pi's own workflow tool and can accept gates being bound to agent calls.
