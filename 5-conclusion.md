# Conclusion {#chap:conclusion}

This thesis built mydenicek, a pure operation-based CRDT for collaborative editing of Denicek's tagged document trees. Edits are stored as immutable events in a grow-only DAG; documents are materialized by deterministic topological replay with selector rewriting. Convergence follows from the G-Set state and deterministic eval. The main contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits through schema evolution.

The system was validated on five formative examples and 331 tests (including property-based convergence testing). All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Incremental eval.** Currently, `materialize` recomputes the full document. Incremental eval that propagates only new events through the existing document would reduce per-edit cost for sequential editing.

**Client-side metadata pruning.** Tracking causal stability --- identifying events that all peers have observed --- would allow pruning vector clock entries, reducing per-event metadata from $O(P)$ to $O(1)$ for stable events [@bauwens2020stability].

**Formal verification.** Encoding the selector rewriting rules in VeriFx [@deporre2023verifx] or TLA+ would provide mechanical correctness guarantees beyond empirical testing.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics.
