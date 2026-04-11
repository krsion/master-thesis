# Conclusion {#chap:conclusion}

This thesis investigated the use of CRDTs to enable collaborative editing in the Denicek system --- a computational substrate for document-oriented end-user programming. We evaluated three approaches: Automerge, Loro, and a custom OT-based event DAG.

Automerge's flat map representation lacked atomic move operations, making the wrap edit --- one of Denicek's core structural operations --- unreliable under concurrent editing. Loro solved this with a native movable tree CRDT, but its opaque ID-based addressing proved incompatible with Denicek's path-based programming model: recorded edits could not use relative references, and replayed edits could not be retargeted through concurrent structural changes.

The final implementation uses a custom OT-based event DAG inspired by Eg-walker [@gentle2025egwalker]. All edits are stored as immutable events in a causal directed acyclic graph --- effectively a grow-only set CRDT. Documents are materialized by replaying events in deterministic topological order with selector-based operational transformation. This approach preserves Denicek's native path-based addressing, supports wildcards and relative references, and enables programming by demonstration with automatic retargeting through structural changes.

The implementation was validated on six formative examples demonstrating custom primitive edits, formula recomputation, the composer pattern, structural transformation (list to table), concurrent editing with fork-and-merge, and formula references with wildcard expansion. All examples pass their tests and are available as interactive demos in the deployed web application.

## Future work {#sec:future}

**Optimized materialization.** The current replay-from-scratch approach replays all events on every materialization. An incremental version that caches the materialized state at known frontiers and only replays new events would improve performance for long-lived documents. The current implementation could serve as a *reference oracle* for validating the optimized version: generate random edit sequences, run both implementations, and compare outputs. This approach could be further strengthened by model-guided fuzzing [@ozkan2025modelfuzz], which uses an abstract formal model (such as the reference implementation) to guide test generation and achieve higher coverage of subtle concurrency-related bugs than random fuzzing alone.

**Formal convergence analysis.** The OT transformation rules have been tested empirically but not formally verified. A formal analysis --- potentially using a model checker or proof assistant --- would strengthen the convergence guarantees.

**Character-level text editing.** Integrating a text CRDT such as Fugue for primitive string values would enable character-level collaborative editing, replacing the current atomic last-writer-wins semantics for strings.

**myDatnicek.** A data-oriented variant of Denicek, built on the optimized core, could handle larger datasets (spreadsheets, databases) while preserving local-first collaborative editing. The tagged tree model naturally extends to tabular data with formula columns.

**Event compaction.** Garbage-collecting old events once all peers have acknowledged them would reduce DAG size and improve materialization performance. The `compact()` method exists but requires further work on distributed acknowledgment tracking.
