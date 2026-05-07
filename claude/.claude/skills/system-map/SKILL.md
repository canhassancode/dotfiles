---
name: system-map
description: Build a structured, layered map of how a user journey, entry point, or domain concept flows across multiple repositories in a workspace. Traces UI → API → service → data → external boundaries, records integration contracts, and produces a persistent node-graph artefact using deep-module thinking (interface first, then drill into nodes with progress tracking). Use when the user wants to map a flow end-to-end, trace functionality across repos, understand where a domain concept is referenced, or build domain knowledge before an architectural change.
---

# System Map

Builds an end-to-end map of a flow across a multi-repo workspace. Treats each touchpoint as a deep module — record the **interface** first, then drill into edges. Track progress so deepening can pause and resume.

## Quick start

0. **Grill first if fuzzy.** If the target is vague ("map checkout") or the architectural change driving this exercise isn't crisp, suggest `/grill-with-docs` and wait. A complete map is intractable; a map focused on the seams that will move is achievable. Skip this step only when the user has already framed target + redesign motivation precisely.
1. Confirm the **target** with the user (one of):
   - **Journey**: e.g. "checkout", "user signup"
   - **Entry point**: e.g. `POST /api/orders`, a button, a queue topic
   - **Domain concept**: e.g. "Subscription", "Invoice"
2. Confirm **scope**: what's in, what's explicitly out
3. Confirm **workspace repos** (see Discovery)
4. Bootstrap the artefact at `docs/maps/<target-slug>.md` using [TEMPLATE.md](TEMPLATE.md)
5. Iteratively deepen (see Workflow). Update the file as you go. Summarise progress in chat after each pass

## Discovery

If the user didn't list repos:

```sh
find "$(dirname "$PWD")" -maxdepth 3 -name ".git" -type d 2>/dev/null \
  | xargs -I {} dirname {} | sort -u
```

Also check sub-folders of the current repo. Present the list and ask which are in scope. **Do not scan repos the user excludes.**

## Workflow

For each pass, follow this loop. Stop when the user says enough or no unexplored nodes remain in scope.

### 1. Find anchors

- **Journey** → start at the UI surface (page/component/CLI) the user enters
- **Entry point** → start at that route/handler/topic
- **Domain concept** → grep the term (and obvious aliases) across all in-scope repos; group hits by repo and layer

### 2. Place anchors in the layered map

Fill the layer × repo matrix in the artefact. Layers: **UI**, **API**, **Service/Domain**, **Data**, **External**. One row per layer, one column per repo. Cells reference node IDs. This matrix is approximately a C4 Container × Component view — exportable to Structurizr or similar if the user wants a diagram.

### 3. Deepen one node at a time (deep-module style)

For each unexplored node, record in this order:

1. **Interface** — exact signature: route + body/response, function name + params + return, event name + payload schema, table + columns touched
2. **Port or adapter** — is this node a *port* (an interface/abstraction the system depends on) or an *adapter* (a concrete implementation)? If adapter, name the port it implements. This separates "we change the contract" from "we swap an implementation" — critical for redesign reasoning. If the node is neither (e.g. a UI surface or pure domain logic), say `n/a`
3. **Responsibility** — one line. If you can't write it in one line, the node is too big; split it
4. **Inbound edges** — who calls/triggers this (link to existing node IDs, create new ones if upstream)
5. **Outbound edges** — what this calls (link or create new node IDs)
6. **Status**:
   - `[ ] unexplored` — known to exist, not opened yet
   - `[~] interface mapped` — interface + responsibility recorded, edges not fully traced
   - `[x] traced` — inbound + outbound edges all linked or marked external

**Do not chase outbound edges immediately.** Add them as new `[ ] unexplored` nodes and continue. This keeps breadth before depth and lets the user steer.

### 4. Record integration contracts

Every edge crossing a repo, service, or process boundary goes into the **Integration points** table with:

- Its contract shape (REST schema, event payload, DB columns, RPC proto)
- Its **DDD relationship type** — this names *why* the boundary is brittle, not just that it is. Pick from:
  - `Customer/Supplier` — downstream depends on upstream; coordinated change
  - `Conformist` — downstream conforms to upstream's model with no leverage
  - `Anti-Corruption Layer (ACL)` — downstream translates upstream's model into its own
  - `Shared Kernel` — both sides share a model deliberately (high coordination cost)
  - `Open Host Service` — upstream exposes a stable protocol for many consumers
  - `Published Language` — a well-documented shared language (events, schemas)
  - `Partnership` — mutual dependency, jointly evolved
  - If none fit, write `Unclassified` and note in Open questions

These are the load-bearing seams for any architectural change.

### 5. Cross-reference existing ADRs

Check `docs/adr/` (or the user's ADR location) for decisions that constrain the area being mapped. Link relevant ADRs in the artefact's **ADRs in scope** section. The redesign has to live with these unless one is being explicitly revisited.

### 6. Surface open questions

Anything you couldn't resolve from code (intent, ownership, "why does it do this") goes in **Open questions**. Do not invent answers.

### 7. Report progress

In chat, after each pass, give:

- Count: `traced / interface-mapped / unexplored`
- Next candidate nodes (top 3 unexplored, by importance)
- Any contracts or open questions that need the user's input

## Principles

- **Interface before internals.** A node's interface is enough to map its place in the system. Internals only matter when the user asks (Ousterhout, deep modules)
- **Breadth before depth.** Add new nodes as `[ ] unexplored`; don't recurse
- **Cite file:line for every node.** The map must be navigable back to source
- **Don't summarise from memory.** Read the code. Memory of past sessions is stale
- **Boundaries are first-class.** Cross-boundary edges always get contracts *and* DDD relationship types recorded — this is the whole point of the exercise
- **Ports vs adapters.** Distinguishing the abstraction from its implementation tells you what's expensive to change vs. cheap (Cockburn, hexagonal architecture)

## Vocabulary used

This skill borrows from established frameworks so the artefact is recognisable to teammates and composes with other skills (notably `improve-codebase-architecture`):

- **C4 model** (Brown) — the layered map approximates Container/Component views
- **Strategic DDD** (Evans) — subdomain classification (Core/Supporting/Generic), context map relationship types
- **Hexagonal architecture** (Cockburn) — port vs adapter on each node
- **Team Topologies** (Skelton & Pais) — ownership column on workspace
- **ADRs** (Nygard) — cross-referenced, not duplicated

## Artefact

The persistent map lives at `docs/maps/<target-slug>.md` (confirm path with user; if no `docs/` exists, ask). Re-runnable, diffable, shareable. Structure: see [TEMPLATE.md](TEMPLATE.md).

## When to stop

- User says stop, or
- All in-scope nodes are `[x] traced` or `[~] interface mapped` with explicit "good enough" notes, or
- You've hit the scope boundary the user defined (e.g. "don't go past the payment service")

End with a chat summary: nodes traced, key integration points, open questions, and a one-paragraph narrative of the flow from anchor to terminus.
