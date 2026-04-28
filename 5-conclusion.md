# Conclusion {#chap:conclusion}

This thesis designed and implemented mydenicek, a pure operation-based CRDT for collaborative editing of Denicek's tagged document trees. Edits are stored as immutable events in a grow-only DAG; documents are materialized by deterministic topological replay with edit transformation. Convergence follows from the G-Set state and deterministic eval. The central technical contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits after schema changes.

The implementation is published as `@mydenicek/core` and `@mydenicek/sync` on JSR. Materialization runs in $O(N + C_\text{total})$ time, completing under 4 ms on average for typical sessions ($N \le 100$). The system was validated on five formative examples, 358 tests (including property-based convergence testing) with 90% branch coverage, and scaling benchmarks up to $N = 100{,}000$. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Incremental eval.** Currently, `materialize` recomputes the full document. Incremental eval that propagates only new events through the existing document would reduce per-edit cost for sequential editing.

**History compaction.** The grow-only event DAG grows without bound. Snapshotting the materialized state and pruning old events would reduce storage and replay cost for long-lived documents and new replicas joining late.

**Formal verification.** Encoding the selector rewriting rules in VeriFx [@deporre2023verifx] or TLA+ would provide mechanical correctness guarantees beyond empirical testing.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics, though the interaction with selectors, undo, and the formula engine would require careful design.
