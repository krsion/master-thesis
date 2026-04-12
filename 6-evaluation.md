# Evaluation and Discussion {#chap:evaluation}

This chapter evaluates the mydenicek implementation against Denicek's requirements, compares the three approaches investigated, discusses the testing strategy, and identifies limitations.

## Approach comparison {#sec:comparison}

[@Tbl:approach-comparison] summarizes the three approaches evaluated in this thesis against Denicek's key requirements.

: Comparison of the three approaches against Denicek's requirements. {#tbl:approach-comparison}

| Requirement | Automerge | Loro | mydenicek (custom) |
|---|---|---|---|
| Atomic move/wrap | No (two-step) | Yes (movable tree) | Yes (OT) |
| Path-based addressing | No (opaque IDs) | No (opaque IDs) | Yes (native) |
| Wildcard selectors | No | No | Yes |
| Relative references | No | No | Yes ($ref paths) |
| Replay retargeting | No | No (ID-based) | Yes (OT-based) |
| For-each semantics | No | No | Yes (wildcard expansion) |
| Character-level text | Yes | Yes (Fugue) | No (LWW) |
| Zero dependencies | No (WASM) | No (WASM) | Yes (pure TS) |

Automerge and Loro excel at general-purpose collaborative JSON editing but lack the path-based features Denicek requires. The custom approach sacrifices character-level text editing (a limitation) but gains native support for all of Denicek's programming-by-demonstration features.

## Formative example results {#sec:results}

All six formative examples described in [@Chap:formative] are implemented and pass their respective tests, as shown in [@Tbl:formative-results].

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

## Limitations {#sec:limitations}

The current implementation has several known limitations:

**No formal convergence proof.** Convergence is validated empirically through tests but not formally proven. A formal proof would require showing that the OT transformation rules satisfy the TP1 property (transformation preserves intention) for all pairs of concurrent edits. This is left as future work.

**Replay-from-scratch materialization.** Every call to `materialize()` replays all events from the initial document. For documents with thousands of events, this becomes a performance bottleneck. An incremental materialization approach that caches intermediate states would address this.

**No character-level text editing.** Primitive values (strings, numbers, booleans) are replaced atomically. There is no character-level collaborative text editing --- concurrent edits to the same string field are resolved by last-writer-wins based on topological order. Supporting character-level editing would require integrating a text CRDT (such as Fugue) for primitive string values.

**In-memory event storage.** The sync server stores all events in memory with JSON file persistence. There is no database-backed storage, which limits scalability for production deployments.
