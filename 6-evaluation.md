# Evaluation and Discussion {#chap:evaluation}

This chapter evaluates the mydenicek implementation against the original goals, discusses the testing strategy, and identifies limitations.

## Specification divergence {#sec:divergence}

The original project specification prescribed Loro CRDTs as the synchronization substrate with ID-addressed nodes. The implementation diverged to a custom OT-based event DAG with path-addressed selectors. The key divergences are summarized in [@Tbl:divergence].

: Specification vs. implementation divergences. {#tbl:divergence}

| Aspect | Specification | Implementation |
|--------|--------------|----------------|
| CRDT substrate | Loro (Rust/WASM) | Custom OT event DAG |
| Node addressing | Unique IDs (`TreeID`) | Path-based selectors |
| Text editing | `LoroText` with splice | Atomic value replacement |
| Undo/redo | Loro's undo manager | Inverse events in the DAG |
| Runtime | Node.js + npm | Deno 2.x |
| Dependencies | Loro (2 MB WASM) | Zero external CRDT deps |
| Package registry | npm | JSR |

The divergence was justified by the findings described in [@Chap:journey]: the Denicek editing model is inherently OT-shaped because it relies on path-based selectors that must be transformed through concurrent structural changes. Wrapping Loro CRDTs with custom structural edits would have produced a leaky abstraction with two conflicting resolution layers.

## Formative example results {#sec:results}

All six formative examples described in [@Chap:formative] are implemented and pass their respective tests, as shown in [@Tbl:formative-results].

: Formative example test results. {#tbl:formative-results}

| Example | Test file | Features demonstrated |
|---------|-----------|----------------------|
| Hello World | `hello-world-formative.test.ts` | Custom primitive edits, wildcard replay |
| Counter | `counter-formative.test.ts` | Formula engine, recording/replay |
| Conference List | `conference-list-formative.test.ts` | Composer pattern, concurrent pushBack |
| Conference Table | `conference-list-formative.test.ts` | Structural transformation, split formulas |
| Conference Budget | `conference-budget-formative.test.ts` | Formula references, concurrent additions |
| Todo App | `todo-formative.test.ts` | Multi-step recording, pushFront + copy |

The conference table example with concurrent editing is the most significant result: it demonstrates that OT correctly transforms concurrent list insertions through structural changes (tag updates, wraps, formula additions), producing a consistent merged table from independently edited list and table structures.

## Testing strategy {#sec:testing}

The implementation is validated through multiple testing layers:

- **206+ unit tests** covering core operations, OT transformation rules, edge cases, and error handling. Tests verify correct behavior for all edit types, concurrent scenarios (rename + wrap, delete + edit, double pop, triple wrap), and undo/redo.
- **6 formative example tests** that simulate realistic user workflows and verify end-to-end behavior including recording, replay, formula evaluation, and multi-peer convergence.
- **11 sync end-to-end tests** covering basic synchronization, late join, concurrent edits, reconnection, pause/resume, initial document hash validation, and offline convergence.
- **Playwright browser tests** that verify the web application renders correctly and two browser peers can sync edits via the deployed server.
- **Continuous integration** via GitHub Actions: every push triggers lint, type-check, test, build, and deployment.

## Limitations {#sec:limitations}

The current implementation has several known limitations:

**No formal convergence proof.** Convergence is validated empirically through tests but not formally proven. A formal proof would require showing that the OT transformation rules satisfy the TP1 property (transformation preserves intention) for all pairs of concurrent edits. This is left as future work.

**Replay-from-scratch materialization.** Every call to `materialize()` replays all events from the initial document. For documents with thousands of events, this becomes a performance bottleneck. An incremental materialization approach that caches intermediate states would address this.

**No character-level text editing.** Primitive values (strings, numbers, booleans) are replaced atomically. There is no character-level collaborative text editing --- concurrent edits to the same string field are resolved by last-writer-wins based on topological order. Supporting character-level editing would require integrating a text CRDT (such as Fugue) for primitive string values.

**Structural edits do not propagate to concurrent insertions.** When Alice wraps existing items in formula nodes (e.g., `wrapRecord` to add `split-first`), this transformation applies to items that exist at the time of the edit. Items inserted concurrently by Bob receive the structural changes (tag updates, list wraps, pushBack of formula cells) via OT, but the `wrapRecord` on individual field values does not propagate --- Bob's items have the formula cell structure but the formula references point to unwrapped source data.

**In-memory event storage.** The sync server stores all events in memory with JSON file persistence. There is no database-backed storage, which limits scalability for production deployments.
