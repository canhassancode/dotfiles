# System Map: <target>

> Generated <YYYY-MM-DD>. Re-run to refresh. Last pass: <YYYY-MM-DD>.

## Target

<one-line description: the journey / entry point / domain concept being mapped>

## Scope

- **In**: <what's explicitly being traced>
- **Out**: <what's deliberately excluded — and why>

## Workspace

Subdomain classification per Strategic DDD: **Core** (competitive differentiator), **Supporting** (necessary, not differentiating), **Generic** (commodity, often buyable).

| Repo | Path | Role | Subdomain | Owner / team |
|------|------|------|-----------|--------------|
| repo-a | `../repo-a` | <e.g. web frontend> | Supporting | <team> |
| repo-b | `../repo-b` | <e.g. orders service> | Core | <team> |

## Layered map

Approximately a C4 Container × Component view. Cells reference node IDs (e.g. `N3`). Empty cell = no touchpoint at this layer in this repo.

| Layer            | repo-a | repo-b | repo-c |
|------------------|--------|--------|--------|
| UI               | N1     | —      | —      |
| API              | N2     | N5     | —      |
| Service / Domain | N3     | N6, N7 | N9     |
| Data             | N4     | N8     | —      |
| External         | —      | —      | Stripe |

## Nodes

Each node = one deep module touchpoint. Record the interface first, edges second.

### N1. `<NodeName>` — `[ ] unexplored` | `[~] interface mapped` | `[x] traced`

- **Repo**: repo-a
- **Path**: `src/path/to/file.ts:42`
- **Interface**:
  ```
  <exact signature: route + body/response | function sig | event name + payload | table + columns>
  ```
- **Port / adapter**: `port` | `adapter implementing <PortName>` | `n/a` (UI surface, pure domain, etc.)
- **Responsibility**: <one line. If you need two, split the node>
- **Inbound**: <list of node IDs or external triggers> — e.g. `← UI form submit`, `← N0`
- **Outbound**: <list of node IDs> — e.g. `→ N2`, `→ Stripe.charge` (see Integration points)
- **Notes**: <anything non-obvious from the code>

### N2. ...

<repeat per node, ordered by traversal not by ID>

## Integration points

Every cross-boundary edge. This is the surface area for architectural change.

`Relationship` uses Strategic DDD context-map types: `Customer/Supplier`, `Conformist`, `ACL`, `Shared Kernel`, `Open Host Service`, `Published Language`, `Partnership`, or `Unclassified`.

| Edge ID | From (node) | To (node / external) | Contract | Transport | Versioning | Relationship |
|---------|-------------|----------------------|----------|-----------|------------|--------------|
| E1 | N3 (repo-a) | N5 (repo-b) | `POST /orders` body `{cartId, userId}` → `201 {orderId}` | HTTP/JSON | unversioned | Customer/Supplier |
| E2 | N5 (repo-b) | `order.created` | event `{orderId, userId, total, currency, ts}` | Kafka topic `orders.v2` | v2 (v1 deprecated) | Published Language |
| E3 | N9 (repo-c) | Stripe | `POST /v1/charges` (Stripe REST) | HTTPS | Stripe API 2024-06-20 | Conformist |

## ADRs in scope

Existing decisions that constrain anything in this map. The redesign must live with these unless one is being explicitly revisited.

| ADR | Title | Constraint on this map |
|-----|-------|------------------------|
| `docs/adr/0007-event-bus.md` | Use Kafka for cross-service events | E2 transport choice is fixed by this decision |
| `docs/adr/0012-no-shared-db.md` | Services own their data | Rules out a shared-kernel relationship between repo-a and repo-b |

## Open questions

- [ ] <thing you couldn't resolve from code — needs the user, a teammate, or a doc>
- [ ] ...

## Progress

- Traced: `<n>`
- Interface mapped: `<n>`
- Unexplored: `<n>`
- Next candidates: `<top 3 unexplored node IDs, with one-line reason for prioritising each>`

## Narrative

<one paragraph, written last: the flow from anchor to terminus in plain English, naming nodes by ID. This is the version a teammate reads first.>
