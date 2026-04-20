# Evaluation and Discussion {#chap:evaluation}

This chapter evaluates the mydenicek implementation against Denicek's requirements, compares the three approaches investigated, discusses the testing strategy, and identifies limitations.

## Approach comparison {#sec:comparison}

[@Tbl:approach-comparison] summarizes the three approaches evaluated in this thesis against Denicek's key requirements.

: Comparison of the three approaches against Denicek's requirements. {#tbl:approach-comparison}

| Requirement | Automerge | Loro | mydenicek (custom) |
|---|---|---|---|
| Atomic move/wrap | No (two-step) | Yes (movable tree) | Yes (structural selector rewriting) |
| Path-based addressing | No (opaque IDs) | No (opaque IDs) | Yes (native) |
| Wildcard selectors | No | No | Yes |
| Relative references | No | No | Yes ($ref paths) |
| Replay retargeting | No | No (ID-based) | Yes (selector rewriting) |
| For-each semantics | No | No | Yes (wildcard expansion) |
| Character-level text | Yes | Yes (Fugue) | No (LWW) |
| Runtime deps | WASM + JS | WASM + JS | JS only (Deno `@std`) |

Automerge and Loro excel at general-purpose collaborative JSON editing but lack the path-based features Denicek requires. The custom approach sacrifices character-level text editing (a limitation) but gains native support for all of Denicek's programming-by-demonstration features.

It is important to note that [@Tbl:approach-comparison] is evaluated against *Denicek's* requirements, which are tailored to the path-based programming model. For use cases outside Denicek's niche, Automerge and Loro offer significant advantages:

- **Character-level text.** Both libraries support fine-grained collaborative text editing (Automerge's text type, Loro's Fugue-based text). mydenicek uses last-writer-wins for primitive strings --- concurrent edits to the same string field discard one version entirely, making it unsuitable for document editors where two users type in the same paragraph.
- **Scale.** Automerge uses compact columnar binary encoding and Loro uses a Rope-based representation, both optimized for documents with millions of operations. mydenicek stores events as JSON in memory with no compression; for long-lived documents the memory and bandwidth overhead would be substantially larger.
- **Ecosystem.** Automerge has `automerge-repo`, React/Svelte bindings, and years of production use. mydenicek is a thesis prototype with one React binding and a minimal sync server.
- **Peer-to-peer transport.** Automerge supports sync over any transport (WebRTC, Bluetooth). mydenicek's sync protocol assumes a central relay server; peer-to-peer transport is architecturally possible but not implemented.

## Formative example results {#sec:results}

All seven formative examples described in [@Chap:formative] are implemented and pass their respective tests, as shown in [@Tbl:formative-results].

: Formative example test results. {#tbl:formative-results}

| Example | Test file | Features |
|---------|-----------|----------|
| Hello World | `hello-world` | Custom edits, wildcard replay |
| Counter | `counter` | Formulas, recording/replay |
| Conf. List | `conference-list` | Recorded adds, concurrent insert |
| Conf. Table | `conference-list` | Structural transform, split formulas |
| Conf. Table (concurrent) | `conference-list` | Concurrent structural + data edits, wildcard expansion |
| Conf. Budget | `conference-budget` | Formula references, concurrent adds |
| Todo App | `todo` | Multi-step recording, copy |

The conference table example with concurrent editing is the most significant result: it exercises the full OT pipeline --- wildcard expansion, structural transformations (tag updates, wraps), formula creation, and concurrent list insertions all interacting in a single scenario. It demonstrates that the system handles the composition of these features correctly, producing a consistent merged table from independently edited list and table structures.

## Testing strategy {#sec:testing}

The implementation is validated through multiple testing layers:

- **Unit tests** (over 200 cases) covering core operations, OT transformation rules, edge cases, and error handling. Tests verify correct behavior for all edit types, concurrent scenarios (rename + wrap, delete + edit, double pop, triple wrap), and undo/redo.
- **Property-based tests** using `fast-check`, described in detail in [@Sec:property-tests].
- **7 formative example tests** that simulate realistic user workflows and verify end-to-end behavior including recording, replay, formula evaluation, and multi-peer convergence.
- **11 sync end-to-end tests** covering basic synchronization, late join, concurrent edits, reconnection, pause/resume, initial document hash validation, and offline convergence.
- **Playwright browser tests** that verify the web application renders correctly and two browser peers can sync edits via the deployed server.
- **Continuous integration** via GitHub Actions: every push triggers lint, type-check, test, build, and deployment.

## Property-based tests {#sec:property-tests}

The file `tests/core-properties.test.ts` uses the `fast-check` library to randomize edit sequences, sync operations, and delivery orders, then asserts invariants on the resulting document states. Unlike unit tests, property tests explore the space of concurrent interactions that a human author would not write down exhaustively.

The tests run against five document schemas (flat list, flat record, nested list-of-records, deeply nested lists, document with references) and exercise all eleven edit types. The default configuration models three `Denicek` peers; a separate test suite uses five peers to verify that convergence holds beyond pairwise interactions --- with five peers, the topological sort encounters richer tie-breaking patterns and the transformation pipeline processes longer chains of concurrent edits. Operations are either local edits or pairwise sync actions; each test generates sequences of 5 to 50 operations per run, with `fast-check` shrinking to the minimal failing sequence on any violation.

The invariants checked are:

- **Convergence.** After a final full sync round, all peers serialize to the same JSON. This directly exercises the theorem of [@Sec:crdt-framing].
- **Idempotency.** Re-delivering an already-ingested event has no effect on the document.
- **Commutativity.** For two disjoint remote event batches, ingesting them in either order produces the same document.
- **Associativity.** For three peers producing disjoint events, any pairwise merge order yields the same merged state.
- **Intent preservation for non-conflicting edits.** Non-conflicting concurrent additions (to disjoint record fields or to a list) all appear in the merged document --- no intent is silently lost.
- **Out-of-order delivery tolerance.** Shuffled event delivery with a causal-buffer layer produces the same state as causal delivery.

The property suite has been effective as a regression guard during development --- earlier iterations of the selector-rewriting rules were caught by shrunk counter-examples that exposed wildcard-over-concurrent-insert bugs and copy-then-rename retargeting errors. We make no claim of exhaustive coverage; `fast-check` samples from a large but not complete space. The tests complement, rather than replace, the paper argument of [@Sec:crdt-framing] and the informal audit of [@Sec:determinism-audit].

## Performance {#sec:performance}

[@Tbl:perf-bench] reports wall-clock ingest and materialize times for three synthetic workloads measured on a single thread (`tools/bench-materialize.ts`, Deno 2 on Windows x64). Times are milliseconds; per-event is microseconds.

: Ingest and materialize cost on three workloads of size $N$. {#tbl:perf-bench}

| Workload | $N$ | Total (ms) | Per event (μs) | Materialize (ms) |
|---|---:|---:|---:|---:|
| local-append  | 100  | 4.1   | 41   | 0.11  |
| local-append  | 500  | 4.5   | 9    | 0.02  |
| local-append  | 2000 | 11.6  | 5.8  | 0.04  |
| sync-linear   | 100  | 1.7   | 17   | 0.08  |
| sync-linear   | 500  | 4.3   | 9    | 0.05  |
| sync-linear   | 2000 | 10.0  | 5.0  | 0.21  |
| merge-fan     | 100  | 13    | 129  | 3.0   |
| merge-fan     | 500  | 414   | 828  | 24    |
| merge-fan     | 2000 | 21625 | 10813| 278   |

*local-append* is a single peer issuing $N$ sequential insert edits. *sync-linear* builds $N$ events on peer $A$ and delivers them to peer $B$ in causal order. *merge-fan* has peer $A$ and peer $B$ edit disjoint subtrees concurrently and then sync.

For typical Denicek sessions ($N \le 100$), all workloads complete in under 15 ms. At $N = 100$, a full fan-merge of two 50-event concurrent branches costs 14 ms total --- well within the interactive threshold. The linear workloads stay below a millisecond per event up to $N = 2000$. This is due to an **incremental materialization cache** (`EventGraph.cachedDoc`) which is extended in place whenever a new event's parents exactly equal the current frontier --- a *linear extension* of the graph. In that common case, inserting an event costs an `edit.validate` against the cached document plus an in-place `edit.apply`, avoiding a full replay.

The merge-fan workload exposes the **asymptotic cost of true concurrency**: every incoming event from peer $B$ invalidates the linear cache on peer $A$ (because its parents no longer match $A$'s frontier). However, the checkpoint cache mitigates this: before invalidation, the current state is saved as a checkpoint keyed by the pre-merge frontier. On the next materialization, replay resumes from that fork point rather than from the initial document. The remaining cost is proportional to the events *after* the fork point, not the total event count. At $N=2000$ the merge-fan workload costs 21.6 seconds --- still too slow for a large offline divergence, because the $O(N)$ `resolveAgainst` scan runs for every event in both branches, yielding $O(N^2)$ overall. For a local-first system where offline editing is an explicit goal, further optimization of the per-event resolution step would be needed.

Two points soften this conclusion for present use without dissolving it:

- The ceiling is bounded by the number of *branch points*, not by the total event count. A long run of local edits followed by a single sync merge with a small remote branch costs $O(N \cdot B)$ where $B$ is the size of the remote branch, not $O(N^2)$.
- For the Denicek applications studied in [@Chap:formative], the total event count per session is typically $\le 100$, and merges happen after short offline intervals. Within that envelope the implementation is fast enough to feel interactive.

Further reducing the per-event cost of `resolveAgainst` --- for instance, by skipping priors whose structural effect provably cannot overlap the current edit's selector --- is left as future work.

**Memory footprint.** Events are held in memory as a `Map<string, Event>`. Each `Event` carries an `EventId`, a `parents` array, an `Edit` subclass instance with its own fields, and a `VectorClock`. On the sync-linear N=2000 workload the serialized on-disk JSON is approximately 0.4 MB (roughly 200 bytes per event, dominated by the vector-clock and edit payloads); in-memory the `Map` overhead adds a constant factor. This linear growth in event count is the main scalability constraint, mitigated by the server-side compaction mechanism described in [@Sec:compaction-offline], which materializes the document and discards old events once all active peers have acknowledged a common frontier.

## Determinism audit {#sec:determinism-audit}

The proof sketch of strong eventual consistency in [@Sec:crdt-framing] reduces convergence to the determinism of three pure functions: `topologicalOrder`, `resolveAgainst`, and `apply`. This section audits the implementation of those functions against the JavaScript-level pitfalls that could silently break the proof.

- **Topological order.** `EventGraph.computeTopologicalOrder` uses a binary-heap priority queue (`@std/data-structures/binary-heap`) keyed on the lexicographic order of `EventId`s. `EventId`s are `(peerId, seq)` pairs serialized with a fixed format; peer identifiers are generated by the application as strings. Ties are broken by the queue's comparator, not by iteration order. The algorithm touches the event `Map` only via `Map.get(key)`, never via iteration, so `Map` insertion order is irrelevant.
- **`resolveAgainst`.** This iterates over `applied`, which is itself produced by the topological order above, and so inherits its determinism. The inner call to `transformLaterConcurrentEdit` is a method dispatch on `edit.constructor`, which is fixed at module load.
- **`apply`.** The `apply` methods of each edit type are small pure functions over the current node. `RecordNode.fields` is iterated with `Object.keys` only in serialization paths (`toPlain`), which does not feed back into subsequent materialization; the materialization paths use direct keyed access. `ListNode` is backed by an array and indexed numerically.
- **`Object.keys` in other paths.** `Object.keys` also appears in `VectorClock.equals`. In `VectorClock.equals`, `Object.keys` is used only for a length comparison; the actual equality check is per-key via `this.entries[k]`, so iteration order is irrelevant. The topological sort (`computeTopologicalOrder`) uses `Object.keys` on a locally-constructed `indegree` record only to seed the priority queue; since all zero-indegree keys enter the same deterministic `BinaryHeap`, the iteration order of `Object.keys` does not affect the output sequence. The formula engine walks the `Node` tree using `Node.forEach`, which visits `RecordNode` fields via `Object.keys`; however, results are keyed by absolute path strings (e.g., `speakers/0/total`), not by `Object.keys` iteration order, so key enumeration order does not affect the output map.
- **Formula evaluation.** Registered formula operations are arithmetic and string manipulation; none use `Math.random`, `Date.now`, or other non-deterministic sources. Floating-point operations are order-dependent but the order is fixed by the topological replay.
- **References.** `resolveReference` normalizes relative paths using a deterministic stack-based walk (see [@Sec:doc-model]).

Two sources of non-determinism are deliberately allowed because they do not affect the view: validation error *messages* include selector formats that may embed runtime-generated text, and logging uses `console.debug`. Neither is part of the materialized document. The audit is informal --- a mechanical check (e.g., an ESLint rule banning `Object.keys`, `for..in`, and `Math.random` outside of an allow-list) is left as future work.

## Limitations {#sec:limitations}

The current implementation has several known limitations:

**Convergence is verified by TLA+ model checking but only for a bounded model.** The TLA+ specification (`spec/MydenicekCRDT.tla`) models five edit types (Add, Rename, Insert, Delete, WrapRecord) on a flat record with two peers, two events per peer, and two fields. TLC exhaustively verifies TypeOK, CausalClosure, and Convergence (strong eventual consistency) on all reachable states of this bounded model. However, the specification does not cover the full 11 edit types, nested trees, wildcards, or list-based operations --- these are validated by the property-based tests instead. Extending the TLA+ model to nested trees and additional edit types is feasible but would require further reducing other dimensions to keep the state space tractable; adding a single edit type to the current configuration roughly triples the state space. The proof sketch in [@Sec:crdt-framing] establishes the logical structure of the convergence argument for the general (unbounded) case, and the determinism audit in [@Sec:determinism-audit] verifies the implementation-level assumptions informally.

**Materialization cost is quadratic for concurrent branches.** Linear extensions (the common case during local editing and live sync) extend a cached document in place at O(1) amortized cost. Merges resume from a checkpoint at the fork point rather than replaying from the initial document, but the `resolveAgainst` step still scans all prior events for each event being replayed, giving $O(N^2)$ in the worst case for a workload dominated by concurrent branching.

**Strict-index concurrency semantics.** The `insert` and `remove` operations accept an optional `strict` flag. When `strict=true`, the index is fixed and not shifted by concurrent OT --- this matches the `!N` convention used in selectors. For example, `insert(target, 0, value, true)` always inserts at the front, and `remove(target, -1, true)` always removes the last item, regardless of concurrent insertions or removals. A concurrent strict-front-insert and strict-front-remove can still cancel each other out --- this is inherent to the "always index 0" semantic, not a bug. The non-strict (default) variants provide better concurrent behavior because their indices are transformed through concurrent operations. The `reorder(target, from, to)` operation implements drag-and-drop with concurrent index transformation, resolving conflicting reorders deterministically.

**No character-level text editing.** Primitive values (strings, numbers, booleans) are replaced atomically. There is no character-level collaborative text editing --- concurrent edits to the same string field are resolved by last-writer-wins based on topological order. Supporting character-level editing would require integrating a text CRDT (such as Fugue) for primitive string values.

**In-memory event storage.** The sync server stores all events in memory with JSON file persistence. There is no database-backed storage, which limits scalability for production deployments.

**CopyEdit undo snapshots the full target subtree.** The `CopyEdit` operation supports undo via `RestoreSnapshotEdit`, which snapshots every (possibly wildcard-expanded) target subtree before the copy and restores it on undo. This approach is correct and convergent --- the undo event syncs to all peers like any other edit --- but incurs memory overhead proportional to the size of the overwritten subtrees. A wildcard copy that overwrites many large subtrees could produce a substantial snapshot payload in the undo event.

**Formula references are retargeted through structural edits.** Formula nodes contain `ReferenceNode` children whose selectors are rewritten by `updateReferences` after structural edits (rename, wrap, reorder) --- the same mechanism that retargets all references in the tree. Because the formula engine operates directly on the internal `Node` tree, it uses each `ReferenceNode`'s already-retargeted selector via `ReferenceNode.resolveReference` and `Node.navigate`, with no separate path-parsing step. The formula engine never distinguishes references from inline values --- an `evaluateChild` helper resolves references transparently before any evaluator sees the argument, so retargeting is entirely a concern of the edit pipeline, not the evaluation pipeline. The combined effect is that formula references survive concurrent structural edits in all cases tested by the formative examples and the property-based test suite.

**Vector clocks grow linearly with the number of peers.** Each event carries a vector clock with one entry per peer that has contributed to its causal history. For a session with $P$ peers, each vector clock has up to $P$ entries, and the serialized size of each event grows as $O(P)$. For the typical use case of 2--5 peers, this overhead is negligible (a few hundred bytes per event). For large peer counts (hundreds or more), the vector clock becomes a significant fraction of the event payload. Alternative representations, such as tree clocks or interval-based encodings, could reduce this overhead but are not implemented.

**Sync server has no rate limiting or payload size enforcement.** The relay server accepts sync messages without per-client rate limits and does not enforce maximum payload sizes on events or initial documents. A misbehaving client could exhaust server memory by sending very large node values or by creating many rooms. Rooms are evicted from memory after 10 minutes of inactivity, but room data files on disk are never deleted. These are acceptable trade-offs for a thesis prototype but would need to be addressed for a production deployment.
