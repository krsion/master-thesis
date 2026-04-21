# Conclusion {#chap:conclusion}

This thesis investigated collaborative editing for Denicek. We evaluated Automerge (lacks atomic move → concurrent wrap problem) and Loro (opaque IDs → retargeting problem), then built a custom pure operation-based CRDT.

The implementation stores edits as immutable events in a grow-only DAG and materializes documents by deterministic topological replay with selector rewriting. Convergence follows from the pure operation-based CRDT framework [@baquero2017pureop]: the event set is a G-Set, the *eval* function (`materialize`) is deterministic. The main contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits through schema evolution.

The system was validated on five formative examples, 310 tests (including property-based convergence testing with `fast-check`), and a TLA+ model of five edit types. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Optimized materialization.** The `resolveAgainst` step scans all prior events per replayed event ($O(N^2)$). Indexing priors by target prefix would reduce this. The current implementation could serve as a reference oracle for validating faster versions via model-guided fuzzing [@ozkan2025modelfuzz].

**Extended verification.** The TLA+ model covers five edit types on a flat record. Extending it to nested trees and wildcards, or mechanizing the proof in Isabelle/HOL, would provide stronger guarantees.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics.

**Compaction.** The PO-Log is append-only because replay references event IDs. A more principled approach would track which events are referenced and prune only unreferenced stable operations.
