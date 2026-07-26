# Second-brain architectures in mid-2026

Research note for [issue #5](https://github.com/canhassancode/dotfiles/issues/5), under map [issue #4](https://github.com/canhassancode/dotfiles/issues/4).
Compiled 26 July 2026. Every claim is cited. Where a claim is my inference from cited evidence rather than something a source says, it is marked **(inference)**.

## The question

What do personal knowledge systems operated by or alongside LLM agents actually look like in mid-2026, and what — if anything — addresses a system that writes reliably but is never read?

Concrete case: an Obsidian vault, 226 markdown files, densely interlinked, written automatically by Claude Code skills. Measured on disk 26 July 2026:

| Directory | Files | Words |
| --- | ---: | ---: |
| `Ventures/` | 52 | 33,083 |
| `Journal/` | 51 | 27,558 |
| `Library/` | 44 | 40,995 |
| `Archive/` | 30 | 27,444 |
| `Personal/` | 12 | 2,391 |
| `Profile/` | 11 | 1,322 |
| `Handoffs/` | 9 | 6,838 |
| `Employment/` | 5 | 3,566 |
| `Inbox/` | 4 | 2,422 |
| Other | 8 | 6,460 |
| **Total** | **226** | **152,079** |

That is ~1.4 MB, roughly 200k tokens of prose — about one full context window's worth of material, accumulated over months. The read path (`/ask`) has fired twice.

One number worth holding onto: the two directories issue #4 records as having *demonstrably earned their keep* — `Personal/` and `Profile/` — total **23 files and 3,713 words**, about 5k tokens. **(inference)** That is small enough to sit in a system prompt permanently, which reframes the retrieval problem for that subset entirely.

---

## 1. The live design patterns and their trade-offs

### 1.1 The three-way memory taxonomy is settled vocabulary, not a settled design

The episodic / semantic / procedural split, formalised for LLM agents in CoALA ([arXiv:2309.02427](https://arxiv.org/abs/2309.02427)), is the shared vocabulary of the field. The February 2026 survey *Rethinking Memory Mechanisms of Foundation Agents in the Second Half* ([arXiv:2602.06052](https://arxiv.org/pdf/2602.06052), Huang, Zhang, Liang, Bei et al., 11 Feb 2026, 50+ authors) organises the literature on exactly those three axes and describes the retrieval trigger for each: episodic by temporal proximity or explicit query against history; semantic by structured query, embedding similarity, or graph traversal; procedural by task context or learned routing.

The same survey is blunt about the plain-files end of the spectrum: it finds that "plain unstructured files and simple note-taking lack effective filtering, leading to information overload", and that simple textual note repositories "lack principled retrieval; they depend heavily on manual curation and fail to scale with agent complexity" ([arXiv:2602.06052](https://arxiv.org/pdf/2602.06052)).

Read that against the case at hand: a 226-file interlinked markdown vault written by an agent *is* an unstructured note repository with no principled retrieval. The survey names the failure mode directly.

### 1.2 Context engineering: the dominant frame, and it is a subtractive discipline

Anthropic's *Effective context engineering for AI agents* ([anthropic.com/engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), 29 Sep 2025) defines the field as "strategies for curating and maintaining the optimal set of tokens (information) during LLM inference", and states the governing principle as: "find the smallest set of high-signal tokens that maximize the likelihood of your desired outcome." Its core economic claim is that attention is a finite budget — "Every new token introduced depletes this budget by some amount."

The empirical basis is Chroma's *Context Rot* report ([trychroma.com/research/context-rot](https://www.trychroma.com/research/context-rot), Kelly Hong, Anton Troynikov, Jeff Huber, 14 Jul 2025). Across 18 frontier models (Claude 4, GPT-4.1, Gemini 2.5, Qwen3) they find "model performance degrades as input length increases, often in surprising and non-uniform ways"; that even a single distractor degrades performance; and — counterintuitively — that "models perform better on shuffled haystacks than on logically structured ones". On LongMemEval, focused ~300-token prompts substantially outperformed the same task with the full ~113k-token context.

That last finding cuts directly against the intuition behind a densely interlinked wiki. **(inference)** A well-structured, heavily cross-referenced corpus is not automatically easier for a model to use than a pile of relevant snippets; the Chroma result says structural coherence can *hurt* at length.

### 1.3 Memory as compaction / context distillation

Anthropic describes three complementary techniques and, usefully, says when each applies ([anthropic.com/engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)):

- **Compaction** — summarise history when approaching the limit and reinitialise. Recommended for "extensive back-and-forth requiring conversational flow". Claude Code "discards redundant tool outputs while preserving architectural decisions and unresolved bugs."
- **Structured note-taking** — the agent writes a scratchpad *outside* the context window and re-reads on demand. Recommended for "iterative development with clear milestones".
- **Sub-agents** — clean context windows returning condensed 1,000–2,000 token summaries. Recommended for complex research.

The 2026 research direction extends compaction into offline consolidation: *Language Models Need Sleep: Learning to Self-Modify and Consolidate Memories* ([arXiv:2606.03979](https://arxiv.org/abs/2606.03979)) and *SCM: Sleep-Consolidated Memory with Algorithmic Forgetting* ([arXiv:2604.20943](https://arxiv.org/html/2604.20943v1)), which implements working-memory limits, importance tagging, offline NREM/REM-analogue consolidation, and **intentional value-based forgetting**. Letta's sleep-time compute framing ([letta.com/blog/sleep-time-compute](https://www.letta.com/blog/sleep-time-compute/)) is the productised version: use idle time to convert "raw context" into "learned context".

The common thread across all of these is *reduction*. None of them describes a system whose health is measured by how much it has written.

### 1.4 The strongest 2026 critique of the whole file-memory category

Two papers are worth taking seriously as opposition:

**"Contextual Agentic Memory is a Memo, Not True Memory"** (Binyan Xu, Xilin Dai, Kehuan Zhang, [arXiv:2604.27707](https://arxiv.org/pdf/2604.27707)) argues that file/note-based memory — MemGPT-style note files, RAG, in-context examples — is not memory at all but a memo appended to a prompt. It does not modify learned behaviour, occupies scarce context, and lacks compositional learning: the agent cannot abstract across what it "remembers" the way genuine learning would. The paper is largely theoretical (formal theorems, limited empirics), so treat it as a conceptual challenge rather than an empirical result.

**"MemDelta: Controlled Baselines and Hidden Confounds in Agent Memory Evaluation"** (Kuan Wang, [arXiv:2606.29914](https://arxiv.org/pdf/2606.29914)) is the more damaging one. It finds that memory-framework benchmark wins are confounded by uncontrolled architecture, retrieval mechanism, context length, and summarisation strategy — and that once controlled, plain retrieval, full-context injection, and naive summarisation "frequently match" or exceed specialised memory systems. Its term for the field's headline numbers is the "benchmark illusion".

This matters because vendor benchmark claims in this space are actively contested. Mem0's published figure for Zep was corrected downward, and Zep publicly rebutted with a different number again, alleging misconfiguration ([mem0.ai/blog/ai-memory-benchmarks-in-2026](https://mem0.ai/blog/ai-memory-benchmarks-in-2026)). Do not treat any single vendor number as load-bearing.

### 1.5 Structured notes vs embeddings vs plain files — the small-corpus answer is plain files

The clearest primary evidence comes from Claude Code's own history. Boris Cherny, its creator, on X: *"Early versions of Claude Code used RAG + a local vector db, but we found pretty quickly that agentic search generally works better. It is also simpler and doesn't have the same issues around security, privacy, staleness, and reliability."* ([x.com/bcherny/status/2017824286489383315](https://x.com/bcherny/status/2017824286489383315)). Vector search was removed from Claude Code in May 2025; glob and grep replaced it.

Karpathy's own gist makes the same call for a personal wiki of roughly this size: an index file "works surprisingly well at moderate scale (~100 sources, ~hundreds of pages) and avoids the need for embedding-based RAG infrastructure" ([gist.github.com/karpathy](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)).

At 226 files and 152k words, this vault is squarely inside the range where the evidence says **don't build embeddings** — read an index, then grep. **(inference)**

Where embeddings do get used for markdown, the shipped tool is `qmd` ([github.com/tobi/qmd](https://github.com/tobi/qmd)) — local SQLite with FTS5 + sqlite-vec, BM25 plus vector plus an on-device qwen3 reranker, exposed as both CLI and MCP server. Karpathy names it as the escalation path *after* the index file stops sufficing, not before.

---

## 2. Where the retrieval trigger sits, and what each costs

This is the crux of the case at hand. Four distinct trigger designs are shipping in 2026.

### (a) Deliberate query — user must ask

The user invokes a command; the agent reads an index, drills in, answers. This is `/ask`. It is also Karpathy's design: "You ask questions against the wiki. The LLM searches for relevant pages, reads them, and synthesises an answer with citations" ([gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)).

**Context cost: zero when not invoked.** That is its entire appeal, and it is why `autoMemoryEnabled: false` was set here.

**Failure mode: it requires the user to already know they have a question the vault can answer.** Karpathy's version survives because his use case *is* research — sourcing and questioning are the activity, and the wiki is the workspace. He describes "a large fraction of my recent token throughput" going into manipulating knowledge. **(inference)** In a workflow where the writes are *by-products of engineering sessions* rather than the object of study, there is no moment where a question naturally arises, so a zero-cost-when-unused trigger reliably costs zero.

### (b) Bounded ambient index + on-demand body — the current mainstream

This is the pattern both Anthropic and OpenAI have converged on, and it is materially different from "ambient injection" as usually declined.

**Claude Code auto memory** ([code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory.md)): a `MEMORY.md` index lives at `~/.claude/projects/<project>/memory/`. "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation." Topic files "are not loaded at startup. Claude reads them on demand using its standard file tools when it needs the information." Since v2.1.210 Claude Code actively polices index size, erroring if `MEMORY.md` exceeds the read limit because "everything past the limit is dropped on the next load."

**Anthropic memory tool** (Messages API, GA) ([platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)): "Memory supports just-in-time context retrieval. Rather than loading all relevant information up front, an agent records what it learns in memory files and reads them back on demand." The API auto-injects a system prompt: *"IMPORTANT: ALWAYS VIEW YOUR MEMORY DIRECTORY BEFORE DOING ANYTHING ELSE."* Note what that costs — a `view /memories` directory listing, not the contents.

**OpenAI Agents SDK memory** ([openai.github.io/openai-agents-python](https://openai.github.io/openai-agents-python/sandbox/memory/)) calls it "progressive disclosure": inject "a small summary (`memory_summary.md`) of generally useful tips, user preferences, and available memories into the agent's developer prompt", then "the agent searches the configured memory index (`MEMORY.md`) for keywords from the current task" and opens detail only when needed. It also documents when to switch it off: latency-sensitive runs, or `Memory(read=None)` when "the user doesn't want the run to be influenced by existing memory."

**Context cost: capped and knowable.** Claude Code's cap is 25 KB / 200 lines — call it ~6k tokens worst case, typically far less. **(inference)** An index of 226 note titles with one-line summaries is roughly 3–5k tokens, i.e. within that envelope. The thing that was declined ("ambient injection, too expensive") is not what these systems do; they inject a *table of contents*, not the library.

### (c) Hook-driven injection at prompt time

A third pattern injects retrieved fragments on every user turn via lifecycle hooks rather than tool calls. ClawMem ([github.com/yoloshii/clawmem](https://github.com/yoloshii/clawmem)) runs a `context-surfacing` hook on `UserPromptSubmit` doing hybrid search over a SQLite FTS5 + sqlite-vec index, with tiered HOT/WARM/COLD injection under a token budget. Its stated split: *"Hooks handle ~90% of retrieval automatically - the agent never needs to call tools for routine context"*, with MCP tools reserved for the remaining 10% (cross-session questions, pre-irreversible checks). Its `postcompact-inject` hook runs on a 1,200-token budget; an optional session bootstrap costs "~2000 tokens before user types anything".

**Context cost: a per-turn tax, but explicitly budgeted.** This is the design that most directly attacks "never read": it removes the user's decision to retrieve entirely. It is also the design most exposed to the Chroma distractor finding — every irrelevant injected fragment is a distractor ([trychroma.com](https://www.trychroma.com/research/context-rot)). **(inference)**

### (d) No retrieval step, because the material lives where the work happens

The fourth option is to stop treating retrieval as a problem. Anthropic's own guidance for long-running agents, *Effective harnesses for long-running agents* ([anthropic.com/engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), Justin Young et al., 26 Nov 2025), puts durable state in the **project repository**: a `claude-progress.txt` log, a `feature_list.json` checklist, and git history. New sessions "read the git logs and progress files to get up to speed on what was recently worked on." No separate memory store is recommended.

Claude Code's own layering says the same thing in miniature ([code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory.md)): facts that must be present every session go in `CLAUDE.md`; instructions that only matter for part of the codebase go in path-scoped `.claude/rules/` which "only load into context when Claude works with matching files"; multi-step procedures go in skills.

**Context cost: zero marginal.** The material is already in the working set because the working set is the repo. There is no trigger to fire because there is no separate place to go.

### (e) The trigger nobody mentions: make the read path model-invocable

A narrow, mechanical point specific to this setup. Claude Code skills default to being invocable by *both* the user and the model; `disable-model-invocation: true` restricts a skill to user-only, and `user-invocable: false` restricts it to model-only, intended "for background knowledge that isn't actionable as a command" ([code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills.md)). Skill bodies "load only when used, so long reference material costs almost nothing until you need it."

**(inference)** If `/ask` is currently a user-invoked command, the two-invocations-ever figure may be measuring the trigger, not the value of the content. A skill whose description advertises what the vault knows, invocable by the model, converts a deliberate query into an ambient *option* at roughly the cost of one description line in context.

### Summary table

| Trigger | Who initiates | Steady-state context cost | Shipping example |
| --- | --- | --- | --- |
| Deliberate query | User | 0 when unused | `/ask`; Karpathy's LLM Wiki |
| Bounded index + on-demand body | Model, every session | Capped (≤25 KB / 200 lines) | Claude Code auto memory; OpenAI Agents SDK |
| Directory-listing probe | Model, every task | One `view` call | Anthropic memory tool |
| Hook injection | System, every turn | Per-turn budget (~1–2k tokens) | ClawMem |
| None (co-located) | n/a | 0 marginal | Anthropic long-running-agent harness; `CLAUDE.md`, ADRs |
| Model-invocable skill | Model, when relevant | ~1 description line | Claude Code skills |

---

## 3. The case against the AI-operated personal wiki

Yes, several people argue this credibly, on four separate grounds. Presented without softening.

### 3.1 The write-only vault is a recognised, named failure — and the PKM community named it first

Joan Westenberg, *I Deleted My Second Brain* (16 Jun 2025), deleted ~10,000 notes accumulated over seven years across Obsidian, Zettelkasten and Apple Notes: *"Instead of accelerating my thinking, it began to replace it… Instead of aiding memory, it froze my curiosity into static categories."* The vault had become *"a dusty collection of old selves, old interests, old compulsions, piled on top of each other like geological strata."* What followed deletion: *"Relief. And a comforting silence where the noise used to be."* ([joanwestenberg.com](https://www.joanwestenberg.com/i-deleted-my-second-brain-692aa40d59d5f06dd5131e43/))

The HN thread (~600 points, [item?id=44402470](https://news.ycombinator.com/item?id=44402470)) contains the exact diagnosis — commenter **motorest**: *"Most of these logs are write only. They can help as a kind of written rubber duck."* Note what the *pro-vault* commenters in that thread defend: operational recall — howtos for infrequent tasks, project state, maintenance logs. Not synthesis, not a knowledge graph. **(inference)** The defensible artefact in that thread is a lookup table.

The Zettelkasten community's own self-critique, the **Collector's Fallacy** ([zettelkasten.de](https://zettelkasten.de/posts/collectors-fallacy/)), states it plainly: *"to know about something"* is not *"knowing something"*; having a text at hand *"does nothing to increase our knowledge — we have to work with it instead."* The forum has since extended this to a *Collector's Fallacy for Thinking* — collecting your own thoughts is the same trap ([forum.zettelkasten.de/discussion/3210](https://forum.zettelkasten.de/discussion/3210/a-collectors-fallacy-for-thinking)).

Earlier but sharper statements: Sasha Chapin, *Notes Against Note-Taking Systems* — getting lost in your KM system is *"a fantastic way to avoid creating things"* ([sashachapin.substack.com](https://sashachapin.substack.com/p/notes-against-note-taking-systems)); Justin Murphy — *"A perpetually expanding web of hyperlinked notes is not impressive but oppressive. It's not useful, and it's not illuminating"* ([letter.otherlife.co](https://letter.otherlife.co/p/personal-knowledge-management-bullshit)).

**Andy Matuschak** is the most credible name and he cuts against the genre from inside it: *"'Better note-taking' misses the point; what matters is 'better thinking'"*, and *"People who write extensively about note-writing rarely have a serious context of use"* ([notes.andymatuschak.org](https://notes.andymatuschak.org/About_these_notes)). He also notes that note-writing practices provide weak feedback, so they resist falsification.

To be straight about the record: **there is no 2025–26 Matuschak recantation of evergreen notes.** His current work has moved to attention and learning ([andymatuschak.org](https://andymatuschak.org/)). The nearest thing is a practitioner post-mortem concluding after two years that evergreen notes serve frontier research, not learning or skill acquisition ([engineeringideas.substack.com](https://engineeringideas.substack.com/p/reflection-on-two-years-of-writing)).

Applied here: 18 log writes in a month against 2 reads ever is a read:write ratio around 1:100. Matuschak's "serious context of use" test is failed outright.

### 3.2 The empirical result on pre-organised personal corpora is negative

This is the strongest evidence in the whole note, and it is not blog anecdote. Whittaker, Matthews, Cerruti, Badenes & Tang, *Am I wasting my time organizing email?* (CHI 2011) instrumented **345 long-term users and over 85,000 logged refinding actions** — behavioural logs, not self-report ([ACM DL](https://dl.acm.org/doi/10.1145/1978942.1979457), [PDF](https://www.mytimemanagement.com/support-files/wasting_time_organizing_email.pdf)):

- Opportunistic access (scroll, search, sort) accounted for **87% of all accesses**; scrolling 62%, search 18%, folder-access 12%, tags **1%**.
- *"preparatory activities (folder- and tag-accesses combined) are not prevalent. They account for just 13% of all access operations overall."*
- *"People who create complex folders indeed rely on these for retrieval, but these preparatory behaviors are inefficient and do not improve retrieval success."*
- Folder-access averaged 58.8s against 17.2s for search, so heavy filers took marginally *longer* overall despite fewer operations.

Whittaker's 2011 review reaches the same conclusion for overkeeping generally: it complicates retrieval ([Wiley](https://asistdl.onlinelibrary.wiley.com/doi/abs/10.1002/aris.2011.1440450108)). **(inference)** Dense `[[wikilinks]]` are this study's folder hierarchy: costly pre-organisation with no demonstrated retrieval benefit.

**Gap flagged honestly:** there is no credible quantitative data on Obsidian-specific retrieval rates. Anyone citing one is inventing it.

### 3.3 If the note's purpose is your memory, an agent writing it destroys the benefit

The mechanism is the **generation effect** and it has genuine primary literature. Slamecka & Graf (1978), *JEP: Human Learning & Memory* 4(6):592–604, established it. Bertsch, Pesta, Wiscott & McDaniel (2007) meta-analysed it: *"445 effect sizes over 86 studies… The size of the generation effect across the 86 studies was .40 — a benefit of almost half a standard deviation of generation over reading"* ([PDF](https://mcdaniel97.github.io/Publications/Bertsch%20et%20al.%202007.pdf)).

The closest direct test of the LLM case: Kreijkes et al. (Nov 2025), *Effects of LLM use and note-taking on reading comprehension and memory*, *Computers & Education* — 405 students randomised across LLM-only, note-taking, and both. Note-taking alone and note-taking+LLM both significantly beat LLM-alone on retention and comprehension, and students *preferred* the condition they performed worse in. The recommendation is to take notes separately from the LLM to avoid copying it ([ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0360131525002829)).

Kosmyna et al., *Your Brain on ChatGPT: Accumulation of Cognitive Debt* (MIT Media Lab, [arXiv:2506.08872](https://arxiv.org/abs/2506.08872), Jun 2025): 54 participants, EEG across sessions; connectivity scaled down with external support (Brain-only > Search > LLM), and **over 80% of LLM users could not quote from the essay they had just produced.** Caveat properly: n=54, only 18 in the final session, preprint, wildly over-claimed in press. It supports direction, not magnitude.

The honest limit of this argument, stated adversarially against itself: the generation-effect paradigm is word pairs, anagrams and arithmetic, not engineering logs, and desirable difficulties are known to reverse under high element interactivity ([Chen et al., PMC6099118](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6099118/)). So the defensible form is narrow: **if the note exists to encode something in *your* head, having Claude write it forfeits the entire effect, because the effect accrues to the generator. If the note exists as an artefact for another agent to read, the generation effect is irrelevant.** This vault is nominally the second and, at 2 reads, functionally neither.

### 3.4 The corpus may be redundant, and worse, stale

Boris Cherny (creator of Claude Code): *"Early versions of Claude Code used RAG + a local vector db, but we found pretty quickly that agentic search generally works better. It is also simpler and doesn't have the same issues around security, privacy, **staleness**, and reliability"* ([x.com/bcherny](https://x.com/bcherny/status/2017824286489383315)).

Sen, Kasturi, Lumer, Gulati & Subbiah, *Is Grep All You Need? How Agent Harnesses Reshape Agentic Search* ([arXiv:2605.15184](https://arxiv.org/abs/2605.15184), 14 May 2026) tested it across Chronos, Claude Code, Codex and Gemini CLI on a 116-question LongMemEval sample: *"Across Chronos and the provider CLIs, grep generally yields higher accuracy than vector retrieval in our comparisons"* — and *"overall scores still depend strongly on which harness and tool-calling style is used, even when the underlying conversation data are the same."* The HN comment worth keeping ([item?id=48460863](https://news.ycombinator.com/item?id=48460863)) cuts both ways: *"If you think grep is great, it's because you've been social engineered to organize your content to be findable."*

The sharpest version of the objection came from HN on the Karpathy-wiki-in-Obsidian thread ([item?id=48351115](https://news.ycombinator.com/item?id=48351115)), commenter **cyanydeez**: *"this is great for when you want to feel like you have a lot of data and structure but dont want to validate it. imagine wanting your own well graphed dataset wiki thats 70% reliable."*

**(inference)** This is the genuinely dangerous case, and it is worse than "no benefit". An unread, unvalidated, agent-written note about a codebase that has since changed is a confident stale index. If it *is* eventually read, it outranks the source in the agent's context. Not reading it has been protective.

On the same thread, **qazxcvbnmlp** on why the write path can't be automated: *"Coding agents won't tell you what is good and bad. They have some limited heuristics, but they don't understand nuance at all unless you prompt them on it"* ([item?id=46742800](https://news.ycombinator.com/item?id=46742800)). That is exactly the judgement the daily-log skill was asked to exercise 18 times.

**Gap flagged honestly:** there is no consolidated HN thread arguing "agent-written markdown vaults are over-engineered." The scepticism is scattered across replies.

### 3.5 The null option has published backing

Martin Fowler, *ArchitectureDecisionRecord* (updated 24 Mar 2026): ADRs belong in `doc/adr` in the source repo — *"This way they are easily available to those working on the code base"* — in lightweight markup so they are *"easily read and diffed just like any code."* He also states the boundary: repo storage *"won't work for ADRs that cover a broader ecosystem than a single code base"* ([martinfowler.com](https://www.martinfowler.com/bliki/ArchitectureDecisionRecord.html)).

The docs-as-code version of the argument: documentation *"living in the same repository as the code, written in the same review workflow, with the same automation, stayed honest in ways the wiki never did… The diagram on the wiki is wrong by next sprint"* ([catio.tech](https://www.catio.tech/blog/architecture-as-code)).

And the agent-era argument *for* keeping written rationale somewhere: *"Code shows what was built, not why… An AI agent refactoring 'verbose' retry logic doesn't know that code was written that way after a Black Friday incident. The verbosity was the decision"* ([mnemehq.com](https://mnemehq.com/insights/how-ai-coding-agents-use-adrs/)). Note precisely what that endorses: **ADRs in the repo, reviewed at write time.** It does not endorse a daily log in a separate vault. The null option in issue #4 is the position this literature actually supports.

### 3.6 The honest counter-case

Three things genuinely cut the other way, and they should not be waved past.

**(a) Karpathy's LLM Wiki is a direct 2026 endorsement of this exact design** — see §5. Its own logic is compilation-over-retrieval: *"the LLM is rediscovering knowledge from scratch on every question. There's no accumulation."* If you accept that, grep-the-source loses.

But the practitioner critiques of the pattern are the real argument: no first-class contradiction detection (the wiki silently overwrites rather than flags conflicts); no provenance log of what entered from where, so *"hallucinations can become permanently embedded as facts"*; and index files that break past ~4,000 notes ([gist by Joi Ito](https://gist.github.com/Joi/120f86eb39758ef75deb5e6145e5a717), [LLM Wiki v2](https://gist.github.com/rohitg00/2067ab416f7bbe447c1977edaaa681e2)). Karpathy's pattern has three operations — **Ingest, Query, Lint**. This vault has Ingest. Query has run twice. Lint does not exist. **(inference)** One third of the pattern was implemented, and the pattern is being judged on that.

**(b) Context rot argues for a *tight curated* corpus, which is a defence of curation, not of accumulation.** Chroma's result that semantically similar distractors are the worst case ([trychroma.com](https://www.trychroma.com/research/context-rot)) applies with force to 18 near-identical daily logs about one project. **(inference)** Under this research, this specific vault's shape makes retrieval worse.

**(c) Cal Newport, *Forget Chatbots. You Need a Notebook.* (10 Nov 2025)** is the honest defence of the write path — the notebook as the instrument of depth beyond working memory, framed as *"a strong rebuke to the current vision of a fast-paced, digitized, AI-dominated workplace"* ([calnewport.com](https://calnewport.com/forget-chatbots-you-need-a-notebook/)). It defends **you writing, by hand**. It is a counter-case to deleting the *practice*, not to deleting the vault.

---

## 4. What substrate people land on

The convergence in 2026 is unusually strong: **plain markdown files on a filesystem, navigated by an index and grep.** Databases and vector stores appear only as an escalation for scale, and agent-native memory products are themselves file-shaped.

### 4.1 The labs chose files, explicitly

Anthropic's memory tool is six file operations — `view`, `create`, `str_replace`, `insert`, `delete`, `rename` — over a `/memories` directory, client-side, with storage entirely under the developer's control ([platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)). The reported rationale is that Claude is heavily trained on file operations, so a filesystem beats a key-value store ([shloked.com](https://www.shloked.com/writing/claude-memory-tool) — secondary, treat as commentary not doctrine).

Memory for Claude Managed Agents (public beta, 23 Apr 2026) made the same call at product level: *"Memory on Claude Managed Agents mounts directly onto a filesystem, so Claude can rely on the same bash and code execution capabilities that make it effective at agentic tasks."* Memories are files that can be exported and managed via API, with scoped read/write permissions, per-write audit logs, and rollback/redaction ([claude.com/blog](https://claude.com/blog/claude-managed-agents-memory)). Notably absent from that announcement: any episodic/semantic/procedural split, and any embeddings. Customer figures quoted there (Rakuten 97% fewer first-pass errors, 34% lower latency; Wisedocs 30% faster verification) are vendor-attributed and unaudited.

OpenAI's Agents SDK sandbox memory writes markdown — `memory_summary.md`, `MEMORY.md`, `rollout_summaries/` — in the workspace ([openai.github.io](https://openai.github.io/openai-agents-python/sandbox/memory/)).

Claude Code's auto memory writes markdown to `~/.claude/projects/<project>/memory/` with a `MEMORY.md` index and topic files, and is explicit that these are *"plain markdown you can edit or delete at any time"* ([code.claude.com](https://code.claude.com/docs/en/memory.md)).

### 4.2 The code repo itself is a first-class answer

Anthropic's long-running-agent harness guidance puts durable state in the project repository — a progress log, a JSON feature checklist, and git history — and recommends **no separate memory store** ([anthropic.com/engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), 26 Nov 2025).

Claude Code's instruction layering is the same idea at a finer grain ([code.claude.com](https://code.claude.com/docs/en/memory.md)): `CLAUDE.md` for facts needed every session (target under 200 lines; *"Longer files consume more context and reduce adherence"*); `.claude/rules/` with `paths:` frontmatter for instructions that *"only load into context when Claude works with matching files"*; skills for procedures, whose bodies *"load only when used, so long reference material costs almost nothing until you need it"* ([code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills.md)). There is even a `/doctor` trim check that removes from `CLAUDE.md` anything Claude can derive from the codebase, keeping only *"pitfalls, rationale, and conventions that differ from tool defaults."*

**(inference)** That trim heuristic is a usable filter for the 226 files: keep what cannot be derived from the code, bin the rest.

For rationale specifically, the docs-as-code / ADR position is the mainstream engineering answer — Fowler's `doc/adr` in-repo, lightweight markup, diffable (§3.5).

### 4.3 Obsidian/markdown as the human-facing layer

Karpathy runs the LLM Wiki in Obsidian and frames it as an IDE over a markdown "codebase", with `index.md` and a greppable `log.md` ([gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)). The community's pro-Obsidian argument is that the files are plain text, the backlinks form a real graph, and *"the human can read, edit, and search the same memory the agent uses."* The counter-argument circulating in the same discourse is that a vault is not memory: memory is what a system *does* with stored material — selective retrieval, persistence across resets, navigable structure at scale — and a folder of markdown has none of that on its own ([Medium, Jun 2026](https://medium.com/@roanmonteiro/obsidian-your-ai-second-brain-isnt-memory-and-here-s-the-architecture-that-actually-is-bf944929e144)). Both are commentary, not primary; the substantive version of each is in §1 and §3.

The most interesting shipped design here inverts the usual write/read balance. `second-brain-mcp` ([github.com/noesskeetit/second-brain-mcp](https://github.com/noesskeetit/second-brain-mcp), v1.0.0, 15 Apr 2026) exposes **four read-only tools** (`obsidian_overview`, `obsidian_search`, `obsidian_read`, `obsidian_backlinks`) plus a single prompt that drives a human-approved write flow. Its README states the thesis directly: *"memory is what you chose to remember. Nothing reaches the vault by accident"*; *"Most agent-memory systems default to the archival model: capture everything… then rely on semantic search to pull the right thing back later"*; and on their own testing, *"on realistic queries a small set of human-approved notes outperformed a much larger raw conversation archive."* Its estimate is that ~95% of session output is *"working noise — code, syntactic back-and-forth, tactical detail that expires with the task"*, with ~5% worth an approval gate. *"The approval gate is the whole point."*

**(inference)** This is the precise mirror image of the system under review: read-heavy, write-gated, human-in-the-loop on writes. Worth weighing seriously, because it was designed by someone who hit the same problem.

### 4.4 Databases, vectors and graphs — where they legitimately appear

Not for a corpus this size. Where they do appear:

- `qmd` ([github.com/tobi/qmd](https://github.com/tobi/qmd)) — local SQLite (FTS5 + sqlite-vec), BM25 + vector + on-device qwen3 reranker, CLI *and* MCP server, all on-device. Karpathy names it as the step after `index.md` stops scaling.
- ClawMem ([github.com/yoloshii/clawmem](https://github.com/yoloshii/clawmem)) — a single SQLite file at `~/.cache/clawmem/index.sqlite` with FTS5 + sqlite-vec, but markdown documents remain the source of truth in `_clawmem/` directories. Hooks do the retrieval (§2c).
- Temporal knowledge graphs (Zep/Graphiti) and extraction-based stores (Mem0, Letta/MemGPT) hold the benchmark leaderboards, but see §1.4: the numbers are contested between vendors, and MemDelta finds the gaps largely vanish under controlled baselines ([arXiv:2606.29914](https://arxiv.org/pdf/2606.29914)).

The pattern across all of them is that **markdown stays the substrate and the index is an accelerator over it**, not a replacement for it.

### 4.5 The 2026 numbers on files vs vectors, and where the crossover sits

Three results, in descending order of how much weight they deserve.

**LongMemEval-V2** ([arXiv:2605.12493](https://arxiv.org/abs/2605.12493), 12 May 2026) — 451 questions over trajectories up to 115M tokens, testing static recall, dynamic state tracking, workflow knowledge, environment gotchas and premise awareness. A coding-agent-over-files method (AgentRunbook-C) scored **72.5%** against a RAG variant (AgentRunbook-R) at **48.5%**, with an off-the-shelf coding-agent baseline at 69.3%. The file approach carries markedly higher latency.

**Is Grep All You Need?** ([arXiv:2605.15184](https://arxiv.org/abs/2605.15184), 14 May 2026) — 116 LongMemEval questions across Chronos, Claude Code, Codex and Gemini CLI. With standard inline tool results grep won every harness–model pair (e.g. 93.1 vs 83.6 on Chronos+Opus 4.6; 93.1 vs 75.9 on Codex+GPT-5.4). **But the paper's own caveat is the important bit:** with *programmatic / file-based* delivery of results the ordering flips on 5 of 10 pairs (Codex+GPT-5.4 becomes grep 55.2 vs vector 67.2). Its conclusion is that the **harness dominates the retriever** — how results are delivered into context matters as much as which retriever produced them.

**LlamaIndex's scale sweep** ([llamaindex.ai](https://www.llamaindex.ai/blog/did-filesystem-tools-kill-vector-search)) — vendor-authored, weight accordingly, but it is the cleanest statement of the crossover. At 5 documents, filesystem search beat RAG on correctness 8.4 vs 6.4; at 100 docs 7.8 vs 7.6; at 1,000 docs 7.6 vs 7.4. The quality advantage of plain files decays to noise as the corpus grows, while RAG wins latency at every size.

**BEAM** (ICLR 2026, [github.com/mohammadtavakoli78/BEAM](https://github.com/mohammadtavakoli78/BEAM)) — 100 procedurally generated conversations, 2,000 validated questions, up to 10M tokens, ten memory dimensions including contradiction resolution and abstention. Its answer to "can a 10M-token window replace a memory system?" is no; the accompanying framework reports +3.5% to +12.7% over the strongest long-context baselines, widening with scale.

**Do not cite LoCoMo as a bar.** Its conversations average ~16–26k tokens — inside any 2026 context window — its gold answers contain known errors, and it does not score knowledge updates. The Mem0-vs-Zep numbers circulating from it are vendor-on-vendor and contested in both directions ([Zep's rebuttal](https://blog.getzep.com/lies-damn-lies-statistics-is-mem0-really-sota-in-agent-memory/)). Use BEAM and LongMemEval-V2.

### 4.6 Practitioner-reported limits of plain files, at roughly this scale

Worth recording because they bound option B and option E. Practitioners running Claude Code over Obsidian vaults report ([Code With Seb](https://www.codewithseb.com/blog/claude-code-obsidian-second-brain-guide), [youcanbuildthings.com](https://youcanbuildthings.com/articles/claude-code-subagents-obsidian-vault/)):

- Glob/Grep can choke past ~2,000 files without a `.claudeignore`.
- Grep does no semantic matching, so conceptually related but lexically different notes are missed.
- Token cost is real: a 20-note search can burn ~50k tokens.
- Reports of it working daily at 400–500 notes; above ~500, several add a search layer.

At 226 files this vault is comfortably inside the working range, which is consistent with Karpathy's own ~100-sources / hundreds-of-pages boundary. **(inference)** Scale is not this system's problem. Demand is.

### 4.7 What the memory vendors' own docs say about when *not* to use them

| System | Substrate | Retrieval trigger | Its own caveat |
| --- | --- | --- | --- |
| Anthropic memory tool | Plain files under `/memories`, client-side | Tool-called; API injects "always view your memory directory" | Cap file sizes; *"periodically delete memory files that haven't been accessed in a long time"*; path traversal is your responsibility ([docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)) |
| Claude Code auto memory | Markdown, `MEMORY.md` index + topic files | Index every session (≤200 lines/25 KB), bodies on demand | Index over-limit content *"is dropped on the next load"* ([docs](https://code.claude.com/docs/en/memory.md)) |
| OpenAI Agents SDK | Markdown in workspace | Progressive disclosure: summary injected, index searched | Disable for latency-sensitive runs; `Memory(read=None)` when the run shouldn't be influenced ([docs](https://openai.github.io/openai-agents-python/sandbox/memory/)) |
| OpenAI Responses API | `previous_response_id` / Conversations | Automatic replay | Transcript state, not knowledge; responses persist 30 days; over-window tokens may be truncated ([docs](https://developers.openai.com/api/docs/guides/conversation-state)) |
| Letta / MemGPT | **MemFS — git-backed markdown filesystem** (moved off V1 memory blocks) | Directory tree pinned in system prompt; files read on demand | Ships `/doctor` to audit placement, duplication and token usage — i.e. Karpathy's lint ([docs](https://docs.letta.com/letta-agent/memory), [Context Repositories](https://www.letta.com/blog/context-repositories/)) |
| mem0 | Layered conversation/session/user/org | `memory.search()` within query | *"Avoid storing secrets or unredacted PII… Mem0 is retrievable by design"* ([docs](https://docs.mem0.ai/core-concepts/memory-types)) |
| Zep / Graphiti | Temporal knowledge graph, bi-temporal edges | Hybrid vector + BM25 + graph traversal | Concedes GraphRAG remains better for static document summarisation ([docs](https://help.getzep.com/graphiti/getting-started/overview)) |
| LangGraph store / LangMem | JSON docs, **embeddings optional** | Filter or semantic search | Concedes *"no universal solution"*; hot-path vs background-write is an explicit tradeoff ([docs](https://docs.langchain.com/oss/python/langgraph/memory)) |
| Cursor memories | Workspace rules files, `.cursor/rules/*.md` or `AGENTS.md` | Rules engine injects; background model proposes, user approves | Scoped per project *and* per individual; does not travel ([docs](https://cursor.com/docs/context/rules)) |
| GitHub Copilot instructions | Markdown, `applyTo` globs | Auto-appended on save | *"must be no longer than 2 pages"* and *"must not be task specific"* ([docs](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)) |

Two things stand out. First, **every one of them ships a pruning or scoping story**; not one is designed to accumulate indefinitely. Second, the human-approval gate keeps reappearing — Cursor proposes and the user approves; `second-brain-mcp` gates every write; Karpathy stays in the loop per source.

**Gaps flagged:** no primary Google doc found for Project Mariner memory; Gemini personal context is documented for Gemini Enterprise ([Google Cloud](https://docs.cloud.google.com/gemini/enterprise/docs/configure-personalization)) but the consumer mechanism is only in secondary coverage. Windsurf memories unverified.

### 4.8 The convergence worth noticing

`AGENTS.md` is now a de facto standard — 60,000+ open-source projects, supported across Codex, Jules, Cursor, Aider, VS Code and Copilot, stewarded by the Agentic AI Foundation under the Linux Foundation ([agents.md](https://agents.md/)). Its stated split: READMEs are for humans, `AGENTS.md` carries the technical context agents need. Claude Code reads `CLAUDE.md`, not `AGENTS.md`, but documents the import and symlink patterns to keep one source of truth ([code.claude.com](https://code.claude.com/docs/en/memory.md)).

More striking: in the space of six months, three unrelated teams shipped the same shape — **git-tracked plain-text memory, a periodic maintenance pass, and a background consolidation step.** Letta has MemFS + `/doctor` + `/sleeptime`; Karpathy has the wiki + `lint`; OpenAI shipped background cross-conversation synthesis it also calls *dreaming* (4 Jun 2026, [openai.com](https://openai.com/index/chatgpt-memory-dreaming/)), including temporal revision of stale facts. **(inference)** If there is a consensus architecture in 2026, that is it — and the maintenance pass is the component this vault is missing entirely.

---

## 5. Karpathy

He is relevant — directly, and more so than expected. In April 2026 he published the **LLM Wiki** pattern, which is essentially a specification of the system already built here.

Primary source, his gist ([gist.github.com/karpathy/442a6bf555914893e9891c11519de94f](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)), announced on X ([status/2039805659525644595](https://x.com/karpathy/status/2039805659525644595)). Verbatim, the core claim:

> Most people's experience with LLMs and documents looks like RAG… This works, but the LLM is rediscovering knowledge from scratch on every question. There's no accumulation… Instead of just retrieving from raw documents at query time, the LLM **incrementally builds and maintains a persistent wiki** — a structured, interlinked collection of markdown files that sits between you and the raw sources… **the wiki is a persistent, compounding artifact.**

The architecture is three layers — immutable `raw/` sources, an LLM-owned markdown wiki, and a schema file (`CLAUDE.md` / `AGENTS.md`) that "makes the LLM a disciplined wiki maintainer rather than a generic chatbot". Two special files: `index.md` (content catalogue, read first on every query) and `log.md` (append-only chronology, deliberately greppable: `grep "^## \[" log.md | tail -5`). He runs it in Obsidian: *"Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase."*

Three things in that document bear on the read-path problem, and they are the whole point:

**(i) The pattern has three operations, not one.** *Ingest*, *Query*, and *Lint*. Lint is a periodic health check for *"contradictions between pages, stale claims that newer sources have superseded, orphan pages with no inbound links, important concepts mentioned but lacking their own page, missing cross-references."* Ingest here fires 18 times a month; Query has fired twice; Lint has never existed. **(inference)** Evaluating the pattern on Ingest alone is evaluating a third of it.

**(ii) The human's job is explicitly sourcing and questioning.** *"You never (or rarely) write the wiki yourself — the LLM writes and maintains all of it. **You're in charge of sourcing, exploration, and asking the right questions.**"* And in practice he stays in the loop: *"I prefer to ingest sources one at a time and stay involved — I read the summaries, check the updates, and guide the LLM on what to emphasize."* His retrieval trigger is a human with a research question.

**(iii) Karpathy's use case supplies the trigger; a SWE workflow does not.** His wiki is fed by curated external sources — clipped articles, papers, repos, datasets — for *"topics of research interest"*, and he reports "a large fraction of my recent token throughput" going into manipulating knowledge rather than code. **(inference)** That is the load-bearing difference. In his setup, the wiki *is* the work; questions arise constantly because asking them is the activity. Here the writes are by-products of engineering sessions whose actual object is a codebase, so no question ever arises that the vault is the natural place to answer. The pattern does not solve "never read" — it *presumes* a reader who already has questions.

He is also candid about the failure modes: drift when the agent under-updates cross-references, the need for schema co-evolution, and scale limits — the flat index approach *"works surprisingly well at moderate scale (~100 sources, ~hundreds of pages)"*, beyond which you want `qmd` or similar. And the closing framing of *why* it works is about maintenance, not retrieval: *"Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored."*

**Say plainly what this does and does not settle.** Karpathy answers "can an LLM maintain a personal wiki cheaply?" — yes. (Secondary coverage reports one of his research wikis reaching ~100 concept articles and ~400k words, e.g. [DAIR.AI Academy](https://academy.dair.ai/blog/llm-knowledge-bases-karpathy); I could not verify that figure against the X post itself, which is behind auth.) He does not answer "what makes a person read one." His own answer to that is implicit and unhelpful here: *have research questions*.

### 5.1 The surrounding Karpathy positions, and one correction

He re-affirmed the pattern at Sequoia Ascent, 30 Apr 2026 ([karpathy.bearblog.dev](https://karpathy.bearblog.dev/sequoia-ascent-2026/)): *"My LLM Wiki pattern is the clearest example… No classical program could robustly maintain that kind of knowledge base across messy human documents. But an LLM can."* And: *"This is why I am interested in LLM knowledge bases. They are not just answer machines. They are tools for transforming information into understanding."*

On text-as-substrate, from *Animals vs Ghosts*, 1 Oct 2025 ([karpathy.bearblog.dev](https://karpathy.bearblog.dev/animals-vs-ghosts/)): *"A lot of recent work is also very interested in memory (think CLAUDE.md files) as a mechanism for test-time learning that uses the text/context as the substrate instead of weights."* His `karpathy/autoresearch` repo (Mar 2026) applies the same idea: *"you are not touching any of the Python files… Instead, you are programming the `program.md` Markdown files."*

On missing consolidation, from the Dwarkesh Patel interview, Oct 2025 ([dwarkesh.com](https://www.dwarkesh.com/p/andrej-karpathy)): weights are *"only a hazy recollection of what happened in training time"* while context is *"very directly accessible"*; the KV cache is *"more like a working memory"*. On sleep: *"There's some process of distillation into the weights of my brain. This happens during sleep… **We don't have an equivalent of that in large language models.**"*

The **cognitive core** framing from the same interview is the one that cuts *for* an external vault: *"I'd love to have them have less memory so that they have to look things up, and they only maintain the algorithms for thought."* Taken at face value, that is an argument for externalised notes, not against them. **(inference)** It is also silent on who reads them.

**Two corrections to the framing in the ticket.** First, "context rot" is not Karpathy's term — it is Chroma's, from their July 2025 report ([github.com/chroma-core/context-rot](https://github.com/chroma-core/context-rot)); attributing it to him would be wrong. Second, the "LLMs lack a hippocampus" gloss is other people's; what he actually claims is the absence of a sleep-consolidation analogue. His own coinage that *is* load-bearing here is "context engineering over prompt engineering" (X, 25 Jun 2025, [status/1937902205765607626](https://x.com/karpathy/status/1937902205765607626); [HN 44379538](https://news.ycombinator.com/item?id=44379538)).

**One telling inconsistency.** For his own human note-taking, Karpathy rejects structure outright. *The append-and-review note*, 19 Mar 2025 ([karpathy.bearblog.dev](https://karpathy.bearblog.dev/the-append-and-review-note/)): a *single* Apple Notes note, appended at the top, periodically scroll-reviewed, ideas sinking *"towards the bottom, almost as if under gravity"*, rarely deleted — because *"maintaining more than one note and… folders costs way too much cognitive bloat."* Structure only becomes affordable in the LLM Wiki because the LLM pays the maintenance cost. **(inference)** The man who designed the 226-file pattern keeps his own thinking in one flat file that he re-reads. That is worth sitting with.

---

## What this implies for the decision

The decision belongs to a later grilling ticket. This section lays out the genuine options and what each one is betting on. It does not choose.

### First, the prior stated in issue #5 did not survive

Hassan predicted the research would argue *for* a second brain and against the null option. It does not, cleanly. It splits:

- The **strongest single endorsement** of this exact design (agent-written interlinked markdown in Obsidian) is Karpathy's April 2026 LLM Wiki, and it is a serious endorsement, not a fad post (§5).
- The **strongest empirical evidence** — Whittaker's 85,000 logged retrieval actions, the MemDelta confound analysis, the grep-beats-vectors results, Chroma's distractor findings — points the other way, or at minimum says the pre-organisation effort is unrecovered (§1.4, §3.2, §3.4).
- **Nothing in the literature defends a write path without a read path.** Every source that endorses an agent-maintained wiki also specifies a Query operation and, in Karpathy's case, a Lint operation. Neither exists here.

The research does not settle the question. It sharpens it into a smaller one.

### The question the evidence actually poses

Not "is a second brain worth it?" but: **is the absent read path a broken trigger, or an absent demand?**

Those have opposite remedies, and the evidence supports both readings:

- *Broken trigger.* `/ask` requires deliberate invocation, and every shipped 2026 system has moved retrieval off the human — Claude Code auto memory, the Anthropic memory tool's "ALWAYS VIEW YOUR MEMORY DIRECTORY", OpenAI's progressive disclosure, ClawMem's hooks (§2). Under this reading, 2 invocations measures the UI, not the content, and the fix is mechanical and cheap.
- *Absent demand.* Karpathy's pattern works because sourcing and questioning *are* his activity; here they are not (§5). Whittaker says organising a personal corpus does not improve retrieval success (§3.2). Under this reading, a better trigger just moves an unread corpus into context and buys distractors.

**(inference)** The cheapest way to discriminate is empirical, not further reading: instrument a read path that costs almost nothing and see whether it gets used or gets ignored. Both `disable-model-invocation` inversion and a bounded index injection are one-line changes.

### The five genuine options

**A. Null — delete the vault.** Decisions live in tracker issues and ADRs next to the code; personal admin stays hand-edited. Backed by Fowler on ADR placement, docs-as-code staleness arguments, Cherny on grep-over-index, and the read-path evidence (§3.5, §3.4, §3.2). Bets that nothing in the 226 files is unrecoverable from git, issues and code. Cost: irreversible; loses `Personal/` and `Profile/`, which issue #4 records as having earned their keep.

**B. Retrieval-trigger fix, content unchanged.** Make the read path model-invocable rather than user-invocable, or expose an `index.md` under a bounded ambient budget (§2b, §2e). Bets on "broken trigger". Cheap, reversible, and directly testable in a fortnight. Does nothing about staleness or the unvalidated 70%-reliable-wiki problem (§3.4).

**C. Radical narrowing — keep only what has a reader.** `Personal/` + `Profile/` is 23 files and 3,713 words, ~5k tokens. That fits inside the context budget every 2026 system reserves for ambient memory, so it needs no retrieval mechanism at all: it can simply be present. Everything else — `Library/` (41k words), `Journal/`, `Ventures/`, `Archive/` — is archived or deleted. Bets that the "earned its keep" observation in issue #4 is the whole signal.

**D. Relocate to where the work happens.** Engineering rationale moves into ADRs and `CLAUDE.md`/rules in the repos; the vault stops receiving engineering output entirely. This is Anthropic's own recommendation for long-running agents — state in the repo, no separate memory store (§2d). Bets that co-location beats retrieval. Compatible with C.

**E. Complete the Karpathy pattern properly.** Add Query and Lint; add provenance; add a raw sources layer; make ingest human-in-the-loop rather than automatic, as both Karpathy and the second-brain-mcp "editorial over archival" design do — *"the approval gate is the whole point"* ([second-brain-mcp](https://github.com/noesskeetit/second-brain-mcp)). Bets that the pattern was under-implemented rather than wrong. The most expensive option, and the one most exposed to the §3.4 staleness objection.

### What to test before deciding, whichever way

One question is answerable with a couple of hours and settles a lot: **does any of the 226 files contain rationale that is not recoverable from git history, issues, or the code itself?** That class of content is the only thing with an unambiguous claim on survival — and if it exists, the literature says it belongs in `doc/adr`, not in a daily log.

Second, if a success metric is wanted for whichever option is chosen: the read:write ratio is the honest one. It is currently ~1:100. Any option that does not move it is not working, and should be killed on schedule rather than allowed to accumulate quietly.

### Four things that are settled and should not be re-litigated

1. **Do not build embeddings for this corpus.** At 226 files, index-then-grep is the evidenced choice: Cherny removed vectors from Claude Code, LongMemEval-V2 put a file-agent at 72.5% against RAG's 48.5%, LlamaIndex's sweep shows the file advantage is largest at small corpus sizes, and Karpathy says the index file suffices at this scale (§1.5, §3.4, §4.5). `qmd` is the escalation path if the vault ever passes ~thousands of pages. Note the one real caveat from `Is Grep All You Need?`: *how* results are delivered into context matters as much as the retriever.
2. **"Ambient injection is too expensive" is based on an outdated picture.** No 2026 system injects the corpus. They inject a capped index — Claude Code's is 200 lines / 25 KB — and load bodies on demand (§2b).
3. **Markdown files in a directory is the correct substrate** regardless of which option wins. Anthropic chose a filesystem over a key-value store, Managed Agents mounts memory as files, OpenAI's SDK writes markdown, Letta moved *to* a git-backed markdown filesystem, and Karpathy's wiki is a git repo of `.md` (§4).
4. **Whatever survives needs a maintenance pass.** Lint (Karpathy), `/doctor` (Letta), expiry (Anthropic memory-tool docs), index-size policing (Claude Code), consolidation (OpenAI "dreaming") — every shipped design in §4.7 has one. This vault has none (§4.8).
