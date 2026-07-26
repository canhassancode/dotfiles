# Upstream drift audit: `mattpocock/skills` vs `~/Repos/skills`

Research for [canhassancode/dotfiles#6](https://github.com/canhassancode/dotfiles/issues/6), under the wayfinder map [#4](https://github.com/canhassancode/dotfiles/issues/4).

**Date of audit:** 2026-07-26
**Upstream snapshot:** `mattpocock/skills` @ `ed37663` (2026-07-21), full clone at `/tmp/mp-skills-full`, 314 commits
**Local snapshot:** `canhassancode/skills` @ `cea7d80`, 51 commits
**Primary sources used:** both git histories, upstream `CHANGELOG.md` (changesets carry Matt's own stated rationale per change), upstream `.agents/adr/`, upstream `CLAUDE.md`, the `writing-great-skills` SKILL.md, and the two secondary web sources cited for the Nick Nisi talk.

---

## Headline: the premise in the ticket is half wrong

The charting measurement — "upstream got thinner, the fork stayed fat" — holds for **four specific skills** and is **false in aggregate and inverted for two others**.

| Measure | Upstream (promoted buckets) | Local (`engineering/` + `productivity/`) |
| --- | --- | --- |
| Skill count | 22 | 26 |
| Total `SKILL.md` words | 16,211 | 18,377 |

Local carries ~13% more prose across ~18% more skills. That is not a fat fork against a thin upstream; it is two libraries of comparable weight that have shed and grown in different places. Per-skill, the picture is sharply bimodal — see the table below.

Two skills are **byte-identical** to upstream HEAD (`research`, `wayfinder`), and three more differ by a single deliberate line (`tdd`, `to-spec`, `prototype`). The library is far better synced than "no upstream remote exists" implies. Hassan has been hand-syncing, and doing it accurately.

---

## 1. Per-shared-skill diff, characterised

Diff counts are `diff -w` changed lines between `~/Repos/skills/<path>/SKILL.md` and the upstream equivalent.

| Skill | Δ lines | What actually differs | Verdict |
| --- | --- | --- | --- |
| **`research`** | 0 | Byte-identical. | **Synced** |
| **`wayfinder`** | 0 | Byte-identical, including the 2026-07-13 "burn research tickets down with subagents" change (upstream `2602257`, local `c6bf690`). | **Synced** |
| **`to-spec`** | 2 | Only `/setup-matt-pocock-skills` → `/bootstrap`. | **Deliberate (rename)** |
| **`tdd`** | 1 | Local adds one bullet: *"Green climbs the ladder"* — encoding the rung ladder from Hassan's `CLAUDE.md`. Upstream's v1.1 reshape (drop refactor stage, `seam` as leading word, tautological-test anti-pattern) is already absorbed locally (`a29a821`). | **Deliberate adaptation** |
| **`prototype`** | 8 | Upstream `d627460`/`371b9c9`/`cdec9f6` reframed disposal: the prototype is now **captured as a primary source** on a throwaway branch with a context pointer on the issue, rather than deleted. Local still says *"delete it"* and keeps the old `## When done` section upstream collapsed into rule 6 (`0375c88`). | **Decay — small, real** |
| **`domain-modeling`** | 16 | Local pushes `CONTEXT-FORMAT.md` / `ADR-FORMAT.md` / `DOMAIN-AWARENESS.md` out as external reference files and points at them; upstream keeps it inline and has no such files. Local also softens *"totally devoid of implementation details"* into *"don't couple"*. | **Deliberate — local applies progressive disclosure harder than upstream** |
| **`implement`** | 11 | Local adds: branch-from-fresh-main discipline, the no-code-comments rule + JSDoc exception (lifted from `CLAUDE.md`), ticket-state transition on start, and a `/code-review` instruction to fix Structure regressions before committing. Upstream added `disable-model-invocation: true`; local deliberately removed it (`68f723d`). | **Deliberate adaptation** |
| **`grill-me`** | 7 | Upstream is a two-line pointer (`Run a /grilling session.`). Local is the same pointer plus a `/log` close step. | **Deliberate** |
| **`grill-with-docs`** | 49 | Upstream is now literally one sentence: *"Run a `/grilling` session, using the `/domain-modeling` skill."* Local keeps that composition **and** a 600-word "four-pass discipline" (trace-don't-list, consumer grep, `CONTEXT.md` sketch, feature-flag awareness), an at-close routing table, and an Obsidian log step. The four-pass block is Hassan's own (local `949243d`, 2026-05-16) — it never existed upstream. | **Deliberate — the single biggest local addition** |
| **`grilling`** | 25 | Local = upstream + a second-brain sweep block and capture-at-close block (~160 words of Obsidian integration). Two genuine misses: upstream `170ad48` generalised *"exploring the codebase"* → *"exploring the environment (filesystem, tools, etc.)"* so the primitive works outside code, and `3bb587f` renamed **design tree → decision tree** across the set. Local still says "design tree" in `grilling` and `improve-codebase-architecture`. | **Deliberate + small decay** |
| **`to-tickets`** | 33 | Local is on the **v1.1 shape** (single `tickets.md`); upstream moved to **one file per ticket** under `.scratch/<slug>/issues/NN-slug.md` with a `Status:` line (`44eed54`). Local also still carries the stray `</content>` tag upstream removed in `19c50d5`, and the redundant tail upstream cut in `ed37663`. | **Decay — carries two fixed upstream bugs** |
| **`code-review`** | 48 | Local adds a **third axis, Structure** (eliminable structure, 1000-line file growth, scattered conditionals, canonical-layer discipline, the ladder) with three binding rules, and a third parallel sub-agent. Upstream ships two axes (Standards + Spec) with the Fowler smell baseline inside Standards. Local has the Fowler baseline too. | **Deliberate — genuine local extension** |
| **`diagnose` / `diagnosing-bugs`** | 45 | Upstream renamed it and hardened Phase 1 into a **checkable completion criterion**: name one command you have *already run*, red-capable / deterministic / fast / agent-runnable, with an explicit stop-gate ("no red-capable command, no Phase 2"), plus a new **minimise** stage in Phase 2 and the `tight`/`red` leading words (per `writing-great-skills`' leading-word doctrine). Local has none of this — it still says *"a loop you believe in"*, the exact fuzzy gate the doctrine names as the thing `red` replaces. | **Decay — the most consequential single gap** |
| **`triage`** | 82 | **Upstream added, local lacks:** external-PR triage (a PR is an issue with attached code, same state machine), the **redundancy check** (search for an existing implementation by domain concept before anything else; already-implemented ⇒ `wontfix` without polluting `.out-of-scope/`), and reproduce → **verify the claim** generalisation. **Local added, upstream lacks:** a Linear adapter, a GitHub `## Status` block convention, triaging a local markdown file as an issue, `promote-to-spec`, an Obsidian log step, and a configurable AI disclaimer. | **Both directions; local is ~50% bespoke** |
| **`codebase-design`** | 88 | **Inverted** — local 594w vs upstream 865w. Local hoisted every term definition into `LANGUAGE.md` and kept a bullet gloss in `SKILL.md`. Upstream keeps full definitions inline plus a Relationships section and a **Rejected framings** section (explicitly rejecting Ousterhout's lines-ratio definition of depth). Local also dropped the pointers to `DEEPENING.md` / `DESIGN-IT-TWICE.md` — the files exist locally but under `improve-codebase-architecture/`, and `DESIGN-IT-TWICE.md` is named `INTERFACE-DESIGN.md`. Content is otherwise identical; only the home differs. | **Deliberate, but structurally divergent** |
| **`improve-codebase-architecture`** | 49 | **Inverted** — local 605w vs upstream 914w. Upstream added two things local lacks: (a) **YAGNI scoping** (`45afd80`) — walk `git log` for hot spots and let recently-changed paths pull attention, rather than scanning everything; (b) an **HTML report** output (Tailwind + Mermaid via CDN, before/after diagrams, recommendation-strength badges, written to `$TMPDIR` and opened) with a `HTML-REPORT.md` reference file. Local keeps the plain numbered list. | **Decay — upstream added capability local didn't take** |
| **`writing-great-skills`** | 8 | Identical but for smart-quote/arrow typography and `Examples:` vs `Examples include:`. | **Synced** |

### The `review` / `code-review` duplication

Upstream had an in-progress skill called `review`; on 2026-07-01 (`14c13c5`) it **renamed `review` → `code-review`** and promoted it to `engineering/`. Local did the rename in the *opposite* direction on 2026-06-03 (`edc019a`, "improved review skill. renamed from code-review"), then re-imported upstream's `code-review` fresh during the v1.1 adoption (`3090773`). The result: local carries **both** — a 1,300-word `review` (Hassan's voice, GitHub inline PR comments) and a 1,542-word `code-review` (upstream + Structure axis). Around 2,800 words of near-overlapping review instruction, both model-invocable.

---

## 2. New upstream skills absent locally

Load-bearing means promoted (`engineering/` or `productivity/`), shipped in the Claude plugin, and referenced by other skills. Experiment means `in-progress/` or `misc/` — upstream's own `CLAUDE.md` states these are explicitly **not promoted** and get no docs page.

| Skill | Bucket | Size / age | Assessment | Recommendation |
| --- | --- | --- | --- | --- |
| `resolving-merge-conflicts` | engineering (promoted) | 134w, 2026-06-12, 2 commits | Tiny, self-contained, zero config dependency. Fills a real hole — nothing local covers a mid-rebase conflict. | **Adopt.** Cheapest win in the audit. |
| `setup-matt-pocock-skills` | engineering (promoted) | 539w equiv | Already present locally as `bootstrap`, with a **superset** (adds a Linear adapter upstream lacks, and dual-lane config). | **Already covered.** Keep `bootstrap`; fix the dangling reference (§5). |
| `ask-matt` | engineering (promoted) | 1,276w, 14 commits | A **router**: one user-invoked skill naming every other and when to reach for it. `writing-great-skills` names this as the cure for cognitive load once user-invoked skills outnumber what you can remember. Upstream's `CLAUDE.md` makes keeping it accurate a hard maintenance rule. Local has 26 promoted + 7 personal skills and **no router at all**. | **Adopt in principle, rewrite from scratch.** Upstream's copy routes to Matt's flow (triage-heavy), which is the wrong map for a wayfinder-heavy mode. The *pattern* is load-bearing; the *content* is not portable. |
| `teach` | productivity (promoted) | 1,490w, 13 commits | Explains a concept in-workspace. No local counterpart. Well-developed but orthogonal to the SWE loop. | **Defer.** Real skill, no evidenced demand. |
| `handoff` | productivity (promoted) | 134w | Local has a larger, Obsidian-wired version. Upstream's is temp-dir only. | **Local wins.** |
| `claude-handoff` | in-progress | 196w, 2026-07-02 | Hands off to a fresh *background* agent immediately, rather than writing a doc for a future human-initiated session. A different primitive from `handoff`/`receive`. | **Watch.** Only interesting if `handoff`/`receive` survive #4 at all — issue #4 records them as near-dead (last used 2 July). |
| `batch-grill-me` | in-progress | 270w, added 2026-07-16 (10 days old) | Asks every frontier question at once, round by round, instead of one at a time. A direct challenge to the one-question-at-a-time core of `grilling`. Two commits, both in one day. | **Watch, don't adopt.** Too young. But relevant: grilling is Hassan's dominant mode, so if upstream's one-at-a-time primitive is under revision, that matters here more than anywhere. |
| `to-questionnaire` | in-progress | 477w, 2026-07-14 | Turn a decision you can't answer into a questionnaire for someone else. Nearest local analogue is `to-proposal` (Notion, for a decision-maker). | **Reject for now.** `to-proposal` has never been used (per #4); a second "ask someone else" skill has no demand. |
| `loop-me` | in-progress | 426w, 2026-06-24 | Grill about specs for workflows to build. Narrow. | **Reject.** |
| `wizard` | in-progress | 683w, 2026-06-29 | Generates an interactive bash wizard for manual third-party setup, `.env` files, GH Actions secrets. Genuinely useful and unrelated to anything local. | **Watch.** Standalone utility; adopt if the need arises, not on principle. |
| `setup-ts-deep-modules` | in-progress | 1,131w, 2026-07-10 | Wires `dependency-cruiser` so each package is a deep module reachable only through entry points. This is the **enforcement layer** under `codebase-design` — the one place upstream makes deep modules mechanically checkable rather than advisory. | **Watch closely.** The most interesting in-progress skill: it converts a *prose principle* into a *machine gate*. That is the same move Nisi argues for (§4), and it's the only upstream skill that makes it. |
| `writing-fragments` / `writing-shape` / `writing-beats` | in-progress | 603/1043/869w, all 2026-05-06, ≤4 commits since | A three-stage explore→exploit writing pipeline. Stagnant for ~11 weeks. | **Reject.** No local writing workflow to plug into. |
| `git-guardrails-claude-code` | misc | 302w | Claude Code hooks blocking `push`/`reset --hard`/`clean`/`branch -D`. This is a **dotfiles** concern, not a skills concern — `~/dotfiles/claude/.claude` already carries hooks. | **Adopt the mechanism, not the skill.** Read it, port the hook config directly. |
| `setup-pre-commit` | misc | 333w | Husky + lint-staged scaffold. | **Reject** — one-line-of-docs territory, and the ladder in `CLAUDE.md` argues against it existing. |
| `scaffold-exercises`, `migrate-to-shoehorn` | misc | 442/415w | Both specific to Matt's course/library business. | **Reject.** |
| `edit-article` | personal | 114w | Matt's own. | **Reject.** |

---

## 3. Local-only skills: gap-filling vs duplication

| Skill | Verdict |
| --- | --- |
| `commit` (280w), `pr` (205w) | **Real gap.** Upstream has no commit or PR skill at all — Matt's flow ends at `/implement` → `/code-review`. These are the two most-used skills in Hassan's loop per #4. Keep. |
| `code-review` Structure axis | **Real gap** (extension, not a skill). Encodes the `CLAUDE.md` ladder as a review gate. Upstream has no equivalent. Keep. |
| `review` (1,300w) | **Duplicate.** Upstream's ancestor of `code-review`, kept alive locally after a rename collision. ~2,800 words of overlapping review instruction now live side by side. Strongest deletion candidate in the library. |
| `challenge` (588w) | **Probable duplicate.** Socratic coaching before committing to an approach — that is `grilling` with a teaching frame, and upstream covers the teaching frame with `teach`. Never used per #4. |
| `to-proposal` (573w) | **Real gap, zero demand.** Nothing upstream publishes to Notion for a decision-maker. Never invoked. Gap that nobody walks through. |
| `diagnose` | Shared skill, not local-only — it's upstream's `diagnosing-bugs` under the pre-rename name. See §1 and §5. |
| `bootstrap` (+ 5 adapters) | **Rename + superset** of `setup-matt-pocock-skills`. The Linear adapter is genuinely local-only — upstream ships GitHub / GitLab / local-markdown and no Linear. Keep; reconcile the name. |
| `pickup` (574w) | **Retired by decision** in #4. Its input (`ready-for-human`) never occurs in solo work. Delete. |
| `system-map` (1,180w, `in-progress/`) | **Real gap.** Cross-repo journey tracing. Nothing upstream does this — upstream is single-repo throughout. But never used per #4. |
| `handoff` / `receive` (438w) | **Real gap over upstream** (upstream's `handoff` is 134w with no receive side), but the gap only matters if the Obsidian vault survives #4. Both near-dead since 2 July. |
| `personal/*` — `log`, `ask`, `ingest`, `inbox`, `lint`, `morning-brief`, `eod-summary` (3,100w total) | **Entirely local.** Upstream's only vault skill is `personal/obsidian-vault`, which local **deprecated**. Per #4 only `log` is alive; the other six are dead. This whole bucket is out of scope for a drift audit — its fate is the second half of map #4. |

---

## 4. The thinning thesis

**Verdict: upstream is not thinning. It is applying a *pruning discipline* whose net effect on total size is roughly zero, and the four skills that got dramatically shorter did so because their content moved into a *composed* skill, not because it was deleted.**

### The evidence against "thinning"

Aggregate word counts are near-parity (16,211 upstream vs 18,377 local). Over the audit window upstream **grew** `codebase-design` (+271w vs local), `improve-codebase-architecture` (+309w), `diagnosing-bugs` (+188w), and added `HTML-REPORT.md`, `DEEPENING.md`, `DESIGN-IT-TWICE.md`, and eleven new skills. The four skills that collapsed — `grill-with-docs` (34w), `grill-me` (20w), `grilling` (136w), `implement` (70w) — all collapsed for the *same* structural reason, extracted in one PR:

> `2dd8056` (local mirror of upstream's change): *"extract grilling core, thin grill-me + grill-with-docs"*

`grilling` became a **shared primitive**; `grill-me` and `grill-with-docs` became **compositions over it**. Total prose in the grilling family is roughly conserved — it just stopped being duplicated three times. That is deduplication, not deletion.

### What upstream's stated rationale actually is

It is written down, in the library itself, in `skills/productivity/writing-great-skills/SKILL.md` (added 2026-06-17, `bc4cf90`). Two currencies, explicitly named:

- **Context load** — a model-invoked skill's `description` sits in the context window *every turn*.
- **Cognitive load** — a user-invoked skill costs zero context but *you* become the index that must remember it exists.

Every editing move upstream makes serves one of these. The named failure modes are the whole doctrine:

> **Sediment** — stale layers that settle because adding feels safe and removing feels risky. The default fate of any skill without a pruning discipline.
>
> **No-op** — a line the model already obeys by default, so you pay load to say nothing. The test: does it change behaviour versus the default?
>
> **Sprawl** — a skill simply too long, even when every line is live and unique. […] The cure is the ladder: disclose reference behind pointers, and split by branch or sequence.

And the pruning instruction, sharpened by `aa7ed40` (*"Make writing-great-skills hunt no-ops at the sentence level"*):

> Hunt **no-ops** sentence by sentence, not just line by line […] when one fails, delete the whole sentence rather than trim words from it. Be aggressive — most prose that fails should go, not be rewritten.

This is visible right through the commit log as a routine editing pass, not a one-off purge: `1e5074a` "pruning pass — cut no-ops and duplication", `97dca07` "Duplication pass: collapse restated out-of-scope mechanics", `09a72ba` "prune no-ops from the two-readings intro", `575d14b` "Trim Notes block to its definition (cut no-op behavioral prose)", `7f68c06` "Cut no-op justification", `0375c88` "collapse the when-done section into rule 6".

The complementary lever is **leading words** — recruiting a concept already in the model's pretraining so one token does the work of a paragraph. `writing-great-skills` gives the exact examples upstream then executed on: *"fast, deterministic, low-overhead"* → `tight`; *"a loop you believe in"* → `red`. Both landed in `diagnosing-bugs`. **Local still carries both original phrases verbatim** — which is a precise, checkable measure of how far behind the doctrine local has fallen on that one skill.

A second, older rationale is recorded as an ADR:

> **`.agents/adr/0001-explicit-setup-pointer-only-for-hard-dependencies.md`:** *"Hard dependency (`to-tickets`, `to-spec`, `triage`) — include an explicit one-liner […] Soft dependency (`diagnose`, `tdd`, `improve-codebase-architecture`) — reference […] in vague prose only. […] The split keeps soft-dependency skills token-light and avoids cargo-culting the setup pointer into places where it isn't load-bearing."*

Its commit (`7afa86d`, **2026-04-28**) is titled *"migrate engineering skills to vague prose"*.

### Is upstream acting on the Nick Nisi argument? No.

The vault note `~/Obsidian/Library/sources/Deleting 95% of Agent Skills (Nick Nisi, WorkOS).md` records the AI Engineer Europe talk of **30 May 2026**: a 10,000-line auto-generated skill library cut to 553 hand-written "gotchas", accuracy 77% → 97%, eval runtime 68 min → 6 min.

Three reasons to conclude upstream converged independently rather than following it:

1. **Chronology.** Upstream's "vague prose" / token-light ADR is dated **28 April 2026**, a month *before* the talk. The doctrine predates the argument.
2. **No trace.** `grep -ri` across the entire upstream repo for `nisi`, `workos`, `95%`, and `state machine` returns nothing. No commit, changeset, ADR, or doc references it.
3. **Different mechanism, opposite conclusion.** Nisi's causal claim is that *the skills were redundant because a TypeScript state machine outside the model held the control flow* — enforced gates, cryptographic evidence of completion, "every failure is a harness bug". Upstream has **no enforcement layer at all**. Its skills are prose that the model may or may not obey; the entire library is the thing Nisi deleted. Upstream's answer to unreliability is *better prose* (sharper completion criteria, stronger leading words, positive rather than negated instruction); Nisi's is *less prose plus a machine that cannot be talked out of its gates*.

Where the two arguments genuinely touch is a single upstream in-progress skill: **`setup-ts-deep-modules`**, which wires `dependency-cruiser` so the deep-module rule is enforced by a linter rather than asserted in a paragraph. That is the only place upstream converts doctrine into a gate. It is 16 days old and unpromoted.

**Honest reading for #4:** the "upstream is thinning, we are fat" framing should not survive into the decision document. The real upstream signal is narrower and more useful — *a maintained pruning discipline with named failure modes, run as a routine pass*. Local has no such pass. That, rather than any word count, is the thing worth importing.

---

## 5. Upstream deprecations the local library still carries live

| Local skill | Upstream status | Evidence |
| --- | --- | --- |
| `engineering/review` (live, 1,300w) | **Renamed** `review` → `code-review` and promoted, 2026-07-01 | `14c13c5`. Local carries both as live model-invocable skills. |
| `engineering/diagnose` (live) | **Renamed** `diagnose` → `diagnosing-bugs`, and substantially rewritten | The rename is cosmetic; the missed rewrite (§1) is not. |
| `engineering/improve-codebase-architecture/INTERFACE-DESIGN.md` | **Renamed** to `DESIGN-IT-TWICE.md` and **rehomed** to `codebase-design/` | Content is byte-identical bar the relative link. Local also keeps `DEEPENING.md` under the wrong skill. |
| `deprecated/write-a-skill` | Correctly retired; upstream's replacement `writing-great-skills` is adopted and in sync. | — |
| `deprecated/to-prd`, `deprecated/to-issues`, `deprecated/setup-tracker` | Matches upstream's v1.1 unification into `to-spec` + `to-tickets`. | Correctly handled. |
| `deprecated/obsidian-vault` | Upstream still ships it live in `personal/`. Local deliberately replaced it with the seven-skill `personal/` bucket. | Deliberate; no action. |
| `deprecated/validate` | No upstream counterpart. | Local-only retirement. |
| `engineering/pickup` (live) | Never existed upstream; **retired by decision in #4**, still live in the tree. | Founding decision 2 of map #4. |

Upstream skills local never had and never needs: `deprecated/design-an-interface` (absorbed into `codebase-design` as design-it-twice — local absorbed the same content, differently homed), `deprecated/qa`, `deprecated/request-refactor-plan`, `deprecated/ubiquitous-language` (superseded by `domain-modeling`), plus `zoom-out` (`e112a6b`) and `caveman` (`7d3ada9`), both deleted outright in June.

**Live defect (already noted in #4, confirmed here):** `engineering/wayfinder/SKILL.md:25` instructs the agent to run `/setup-matt-pocock-skills`, which does not exist locally. `to-spec`, `to-tickets`, and `code-review` were all updated to `/bootstrap`; `wayfinder` was missed because it is byte-identical to upstream — i.e. **the perfect sync is what caused the bug**.

---

## 6. Where the fork point is, and whether an `upstream` remote is feasible

### There is no fork point in the git sense

`~/Repos/skills` begins with `14d3d0d Initial commit` (2026-05-13 21:10) followed 3 minutes later by `474075e feat: migrated all of my used skills`. It is a **copy-paste import into a fresh repository**, not a `git fork` or `git clone`. The two histories share **no commit objects whatsoever**. `git merge-base` between them is undefined.

Two content-level fork points can be established:

| Event | Local commit | Corresponding upstream state |
| --- | --- | --- |
| **Original import** | `474075e`, 2026-05-13 21:13 | Nearest upstream commit `e74f006`, 2026-05-13 14:05 — 7 hours earlier. Confident match. |
| **Manual re-sync** *(the one that matters)* | `3090773` "feat: adopt Matt Pocock v1.1 — triage-free planning lane (#15)", 2026-07-08 18:51 | Tag **`v1.1.0`** = `d574778`, 2026-07-08 14:20 — 4.5 hours earlier. Very confident match; the commit adopts exactly v1.1's `to-spec`/`to-tickets` unification, `code-review` promotion, `prototype` split, and `wayfinder` graduation. |

Since then Hassan has hand-picked further upstream changes (`c6bf690` wayfinder research-subagents mirrors upstream `2602257`; `2dd8056`/`1e5937c`/`7b16e9a`/`c01d7e7` mirror the grilling/codebase-design/domain-modeling extractions). **`v1.1.0` is the honest baseline; upstream has shipped 40 commits since.**

### Is a clean `upstream` remote feasible?

**Adding the remote: yes, trivially, and it is strictly useful even with no merging.** `git remote add upstream https://github.com/mattpocock/skills.git && git fetch upstream` costs nothing and immediately enables the diff commands used throughout this audit. Right now the library has no mechanical way to answer "what changed upstream?" — that is the actual defect, not the divergence.

**Merging: no.** Three independent blockers:

1. **No common ancestor.** Any `git merge upstream/main` is an unrelated-histories merge; every file conflicts in full. Cherry-picking is equally impossible — the commits touch paths that do not exist locally.
2. **Path divergence.** Upstream is `skills/<bucket>/<name>/SKILL.md`; local is `<bucket>/<name>/SKILL.md`. Upstream also carries `docs/`, `.changeset/`, `.agents/`, `agents/openai.yaml` per skill, and a `marketplace.json` — none of which local wants.
3. **Semantic divergence on ~40% of shared skills.** `triage`, `code-review`, `grill-with-docs`, `grilling`, `implement`, `codebase-design`, `domain-modeling`, and `handoff` all carry deliberate local content that a merge would have to preserve by hand anyway.

The realistic mechanisms, laid out without a recommendation (that is #12's call):

| Option | Shape | Cost | What it gives up |
| --- | --- | --- | --- |
| **A. Read-only remote + manual diff** | Add `upstream`, never merge. Diff on demand, port by hand as today. | ~zero to set up; per-sync cost unchanged. | Nothing beyond status quo — but it *is* the status quo made legible. Strictly dominates doing nothing. |
| **B. Remote + a `sync` skill** | A, plus a skill that diffs every shared `SKILL.md` against a recorded upstream SHA, classifies each hunk as adopt / reject / already-diverged, and updates the recorded SHA. | One skill (~300w). Turns sync into a repeatable pass. | Requires a per-skill "we deliberately diverge here" record to avoid re-litigating the same hunks every run. |
| **C. Pin to plugin, fork only what differs** | Install upstream as the Claude Code plugin (`/plugin install mattpocock-skills@mattpocock`, shipped 2026-07-13, `42a5b70`) and keep local as an override layer of only the ~12 genuinely bespoke skills. | Largest restructure; upstream skills become read-only and always current. | All local edits to shared skills — the `implement` ladder, the Structure axis, four-pass grilling, Obsidian hooks. These would need re-expressing as separate composed skills, which is exactly the pattern upstream itself uses. |
| **D. Declare the fork independent** | Drop the pretence of tracking. Prune to what the wayfinder-heavy loop actually uses; consult upstream as inspiration, never as source. | Zero mechanism. | The free flow of upstream's genuine improvements — `diagnosing-bugs`' completion criterion, triage's redundancy check, YAGNI scoping — all of which this audit shows are real. |

The measurement in #4 — Matt triage-heavy (82 triage-labelled, 13 wayfinder) vs Hassan wayfinder-heavy (50 wayfinder, 4 triage) — argues that **B and C are not obviously better than D on the shared planning skills**, but says nothing about the primitives. `diagnose`, `prototype`, `improve-codebase-architecture`, and `resolving-merge-conflicts` are mode-independent: their upstream improvements would help regardless of working mode, and their local staleness is pure decay with no adaptive story.

---

## Decay vs deliberate adaptation — the honest split

**Decay (local copies rotted; no adaptive justification found):**

- `diagnose` — missing the entire Phase-1 completion criterion, the minimise stage, and both `tight`/`red` leading words. Largest single quality gap.
- `to-tickets` — carries a stray `</content>` tag and a redundant tail, both fixed upstream; one-file-per-ticket not adopted.
- `prototype` — still "delete it" rather than capture-as-primary-source.
- `improve-codebase-architecture` — no YAGNI hot-spot scoping, no HTML report.
- `triage` — no PR triage, no redundancy check.
- `grilling` / `improve-codebase-architecture` — "design tree" not renamed to "decision tree".
- `review` alongside `code-review` — a rename collision left unresolved for 8 weeks.
- `wayfinder`'s dangling `/setup-matt-pocock-skills` reference.

**Deliberate adaptation (defensible, keep):**

- Everything Obsidian-facing in `grilling`, `grill-me`, `grill-with-docs`, `handoff`, `triage`, and the whole `personal/` bucket.
- The `code-review` Structure axis and the `implement` / `tdd` ladder rules — these encode `CLAUDE.md` and have no upstream equivalent.
- The four-pass discipline in `grill-with-docs`.
- The Linear adapter in `bootstrap` / `triage`.
- `commit` and `pr` — real holes in upstream's flow.
- `domain-modeling` / `codebase-design` progressive disclosure into reference files — local applying upstream's own doctrine more aggressively than upstream does.
- Removing `disable-model-invocation` on three skills (`68f723d`) — a considered inversion of upstream's default.

**Undecided, belongs to #4 not here:** `challenge`, `to-proposal`, `system-map`, `receive`, `pickup`, and the six dead `personal/` skills.

---

## Sources

Primary:

- `mattpocock/skills` git history, full clone (314 commits), specifically: `7afa86d`, `bc4cf90`, `aa7ed40`, `14c13c5`, `e112a6b`, `7d3ada9`, `1e5074a`, `97dca07`, `575d14b`, `45afd80`, `d627460`, `371b9c9`, `cdec9f6`, `44eed54`, `19c50d5`, `ed37663`, `170ad48`, `3bb587f`, `2602257`, `42a5b70`, `697d4ce`
- `mattpocock/skills` `CHANGELOG.md` — changeset entries for v1.0.0 and v1.1.0, authored by Matt, carrying per-change rationale
- `mattpocock/skills` `.agents/adr/0001-explicit-setup-pointer-only-for-hard-dependencies.md` and `0002-ship-as-a-claude-code-plugin.md`
- `mattpocock/skills` `CLAUDE.md` — bucket promotion rules, docs-page and `ask-matt` maintenance rules
- `mattpocock/skills` `skills/productivity/writing-great-skills/SKILL.md` — the pruning doctrine
- `canhassancode/skills` git history (51 commits), specifically: `14d3d0d`, `474075e`, `949243d`, `edc019a`, `3090773`, `2dd8056`, `1e5937c`, `7b16e9a`, `c01d7e7`, `68f723d`, `a29a821`, `c6bf690`
- `~/Obsidian/Library/sources/Deleting 95% of Agent Skills (Nick Nisi, WorkOS).md`

Secondary (Nisi talk, no primary transcript available):

- [How I deleted 95% of my agent skills and got better results — Nick Nisi, WorkOS (YouTube)](https://www.youtube.com/watch?v=vy7o1g2iHY8)
- [Sean Weldon's write-up](https://www.sean-weldon.com/blog/2026-06-03-how-i-deleted-95-of-my-agent-skills-and-got-better-results-nick-nisi-workos)
- [The /writing-great-skills Skill — aihero.dev](https://www.aihero.dev/skills-writing-great-skills)
