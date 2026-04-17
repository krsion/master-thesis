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

## Formative example results {#sec:results}

All seven formative examples described in [@Chap:formative] are implemented and pass their respective tests, as shown in [@Tbl:formative-results].

: Formative example test results. {#tbl:formative-results}

| Example | Test file | Features |
|---------|-----------|----------|
| Hello World | `hello-world` | Custom edits, wildcard replay |
| Counter | `counter` | Formulas, recording/replay |
| Conf. List | `conference-list` | Recorded adds, concurrent pushBack |
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

The tests run against four document schemas (flat list, flat record, nested list-of-records, deeply nested lists, document with references) and exercise all twelve edit types. Peers are modeled as three `Denicek` instances; operations are either local edits or pairwise sync actions; each test generates sequences of 5 to 40 operations per run, with `fast-check` shrinking to the minimal failing sequence on any violation.

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
| local-append  | 500  | 10.6  | 21   | 0.15  |
| local-append  | 2000 | 13.7  | 6.8  | 0.27  |
| sync-linear   | 500  | 10.1  | 20   | 0.11  |
| sync-linear   | 2000 | 18.9  | 9.5  | 0.35  |
| merge-fan     | 500  | 673   | 1346 | 33.7  |
| merge-fan     | 2000 | 37746 | 18873| 450   |

*local-append* is a single peer issuing $N$ sequential `pushBack` edits. *sync-linear* builds $N$ events on peer $A$ and delivers them to peer $B$ in causal order. *merge-fan* has peer $A$ and peer $B$ edit disjoint subtrees concurrently and then sync.

The linear workloads (local and sync) scale linearly in $N$ and stay below a millisecond per event for $N \le 2000$. This is due to an **incremental materialization cache** (`EventGraph.cachedDoc`) which is extended in place whenever a new event's parents exactly equal the current frontier --- a *linear extension* of the graph. In that common case, inserting an event costs an `edit.validate` against the cached document plus an in-place `edit.apply`, avoiding a full replay.

The merge-fan workload exposes the **asymptotic cost of true concurrency**: every incoming event from peer $B$ invalidates the cache on peer $A$ (because its parents no longer match $A$'s frontier), forcing a full $O(N)$ materialization on each insert and $O(N^2)$ overall. At $N=2000$ this is 37.7 seconds and $\sim 19$ ms per event --- clearly too slow to treat as a solved problem. For a local-first system where offline editing is an explicit goal, a large merge after a long divergence is exactly the workload that *must* be fast, and the current implementation does not meet that bar.

Two points soften this conclusion for present use without dissolving it:

- The ceiling is bounded by the number of *branch points*, not by the total event count. A long run of local edits followed by a single sync merge with a small remote branch costs $O(N \cdot B)$ where $B$ is the size of the remote branch, not $O(N^2)$.
- For the Denicek applications studied in [@Chap:formative], the total event count per session is typically $\le 100$, and merges happen after short offline intervals. Within that envelope the implementation is fast enough to feel interactive.

A finer-grained incremental scheme --- replaying only events in the symmetric difference between the cached frontier and the new event's parents --- is a plausible extension but is left as future work (see [@Sec:future-work]).

**Memory footprint.** Events are held in memory as a `Map<string, Event>`. Each `Event` carries an `EventId`, a `parents` array, an `Edit` subclass instance with its own fields, and a `VectorClock`. On the sync-linear N=2000 workload the serialized on-disk JSON is approximately 0.4 MB (roughly 200 bytes per event, dominated by the vector-clock and edit payloads); in-memory the `Map` overhead adds a constant factor. This linear growth in event count is the main scalability constraint, mitigated by `compact()` (see [@Sec:future-work]).

## Determinism audit {#sec:determinism-audit}

The paper proof of strong eventual consistency in [@Sec:crdt-framing] reduces convergence to the determinism of three pure functions: `topologicalOrder`, `resolveAgainst`, and `apply`. This section audits the implementation of those functions against the JavaScript-level pitfalls that could silently break the proof.

- **Topological order.** `EventGraph.computeTopologicalOrder` uses a binary-heap priority queue (`@std/data-structures/binary-heap`) keyed on the lexicographic order of `EventId`s. `EventId`s are `(peerId, seq)` pairs serialized with a fixed format; peer identifiers are generated by the application as strings. Ties are broken by the queue's comparator, not by iteration order. The algorithm touches the event `Map` only via `Map.get(key)`, never via iteration, so `Map` insertion order is irrelevant.
- **`resolveAgainst`.** This iterates over `applied`, which is itself produced by the topological order above, and so inherits its determinism. The inner call to `transformLaterConcurrentEdit` is a method dispatch on `edit.constructor`, which is fixed at module load.
- **`apply`.** The `apply` methods of each edit type are small pure functions over the current node. `RecordNode.fields` is iterated with `Object.keys` only in serialization paths (`toPlain`), which does not feed back into subsequent materialization; the materialization paths use direct keyed access. `ListNode` is backed by an array and indexed numerically.
- **Formula evaluation.** Registered formula operations are arithmetic and string manipulation; none use `Math.random`, `Date.now`, or other non-deterministic sources. Floating-point operations are order-dependent but the order is fixed by the topological replay.
- **References.** `resolveReference` normalizes relative paths using a deterministic stack-based walk (see [@Sec:doc-model]).

Two sources of non-determinism are deliberately allowed because they do not affect the view: validation error *messages* include selector formats that may embed runtime-generated text, and logging uses `console.debug`. Neither is part of the materialized document. The audit is informal --- a mechanical check (e.g., an ESLint rule banning `Object.keys`, `for..in`, and `Math.random` outside of an allow-list) is left as future work.

## Limitations {#sec:limitations}

The current implementation has several known limitations:

**Convergence is proven on paper but not mechanically verified.** The proof in [@Sec:crdt-framing] establishes strong eventual consistency by identifying the replica state as a G-Set of events and the document as a pure deterministic view function, but the argument relies on the implementation-level determinism of `topologicalOrder`, `resolveAgainst`, and `apply`. This is audited informally in [@Sec:determinism-audit]; mechanical verification in a proof assistant or model checker (e.g., a TLA+ spec bounded to a few peers and events) is left as future work (see [@Sec:future-work]). Note that the earlier concern about TP1/TP2 does not apply here: TP1/TP2 are correctness conditions for peer-local operational transformation, whereas mydenicek derives the document from the full event set by a single canonical replay.

**Materialization is incremental only for linear extensions.** Every call to `materialize()` after a *merge* (two concurrent events joining) replays all events from the initial document. Linear extensions (the common case during local editing and live sync) now extend a cached document in place, reducing ingestion of $N$ linearly-delivered events from $O(N^3)$ to $O(N)$ (see [@Sec:performance]). True merges still cost $O(N)$ per event and therefore $O(N^2)$ over a workload dominated by concurrent branching.

**No character-level text editing.** Primitive values (strings, numbers, booleans) are replaced atomically. There is no character-level collaborative text editing --- concurrent edits to the same string field are resolved by last-writer-wins based on topological order. Supporting character-level editing would require integrating a text CRDT (such as Fugue) for primitive string values.

**In-memory event storage.** The sync server stores all events in memory with JSON file persistence. There is no database-backed storage, which limits scalability for production deployments.

**CopyEdit cannot be undone.** The `CopyEdit` operation does not support undo because a faithful inverse would need to restore every overwritten subtree at the (possibly wildcard-expanded) target, which requires snapshotting the full target subtree before each copy. This means that if a user workflow involves a copy step (e.g., the "Add Speaker" button that copies from an input field), pressing undo immediately after will raise an error. Application code must handle this by either disabling undo after copy-containing workflows or implementing a custom rollback strategy. This is the only edit type that lacks undo support.

**Formula references are not retargeted through concurrent structural edits.** When a formula node contains a relative reference (e.g., `$ref: "../input/value"`) and a concurrent rename changes the referenced field, the reference becomes invalid and the formula evaluates to a `FormulaError`. The OT selector-rewriting rules transform edit selectors, not values already stored in the document tree. This means that formula references created *before* a concurrent structural edit are not updated to reflect the new path. In contrast, formulas created *by* a replayed or retargeted edit have their selectors rewritten correctly. This limitation affects only formula nodes with `$ref` paths that traverse a concurrently renamed or wrapped field; formulas using tag-based evaluation (e.g., `split-first`, `x-formula-plus`) are unaffected because they evaluate their children directly.

**Vector clocks grow linearly with the number of peers.** Each event carries a vector clock with one entry per peer that has contributed to its causal history. For a session with $P$ peers, each vector clock has up to $P$ entries, and the serialized size of each event grows as $O(P)$. For the typical use case of 2--5 peers, this overhead is negligible (a few hundred bytes per event). For large peer counts (hundreds or more), the vector clock becomes a significant fraction of the event payload. Alternative representations, such as tree clocks or interval-based encodings, could reduce this overhead but are not implemented.

**Sync server has no rate limiting or payload size enforcement.** The relay server accepts sync messages without per-client rate limits and does not enforce maximum payload sizes on events or initial documents. A misbehaving client could exhaust server memory by sending very large node values or by creating many rooms. Room state is never evicted, so abandoned rooms accumulate until the server is restarted. These are acceptable trade-offs for a thesis prototype but would need to be addressed for a production deployment.
