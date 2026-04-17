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
| Conf. Budget | `conference-budget` | Formula references, concurrent adds |
| Todo App | `todo` | Multi-step recording, copy |

The conference table example with concurrent editing is the most significant result: it exercises the full OT pipeline --- wildcard expansion, structural transformations (tag updates, wraps), formula creation, and concurrent list insertions all interacting in a single scenario. It demonstrates that the system handles the composition of these features correctly, producing a consistent merged table from independently edited list and table structures.

## Testing strategy {#sec:testing}

The implementation is validated through multiple testing layers:

- **206+ unit tests** covering core operations, OT transformation rules, edge cases, and error handling. Tests verify correct behavior for all edit types, concurrent scenarios (rename + wrap, delete + edit, double pop, triple wrap), and undo/redo.
- **6 formative example tests** that simulate realistic user workflows and verify end-to-end behavior including recording, replay, formula evaluation, and multi-peer convergence.
- **11 sync end-to-end tests** covering basic synchronization, late join, concurrent edits, reconnection, pause/resume, initial document hash validation, and offline convergence.
- **Playwright browser tests** that verify the web application renders correctly and two browser peers can sync edits via the deployed server.
- **Continuous integration** via GitHub Actions: every push triggers lint, type-check, test, build, and deployment.

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

The merge-fan workload exposes the cost of true concurrency: every incoming event from peer $B$ invalidates the cache on peer $A$ (because its parents no longer match $A$'s frontier), forcing a full $O(N)$ materialization on each insert and $O(N^2)$ overall. This is the remaining asymptotic cost, bounded by the number of branch points rather than the total event count. A finer-grained incremental scheme --- e.g., replaying only events in the symmetric difference between the cached frontier and the new event's parents --- is a plausible extension but is left as future work (see [@Sec:future-work]).

The figure $N = 2000$ covers document sizes well beyond any realistic single-session workload for an end-user programming environment; for the Denicek applications studied in [@Chap:formative], the total event count per session is $\le 100$.

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
