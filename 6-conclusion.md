# Conclusion {#chap:conclusion}

This thesis investigated collaborative editing for Denicek. We evaluated Automerge (lacks atomic move → concurrent wrap problem) and Loro (opaque IDs → retargeting problem), then built a custom pure operation-based CRDT.

The implementation stores edits as immutable events in a grow-only DAG and materializes documents by deterministic topological replay with selector rewriting. Convergence follows from the pure operation-based CRDT framework [@baquero2017pureop]: the event set is a G-Set, the *eval* function (`materialize`) is deterministic. The main contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits through schema evolution.

The system was validated on five formative examples, 310 tests (including property-based convergence testing with `fast-check`), and a TLA+ model of five edit types. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Incremental eval (reactivity).** Currently, `materialize` recomputes the full document from the PO-Log. Bauwens et al. [@bauwens2021reactivity] propose *reactive pure operation-based CRDTs* that track which parts of the state changed and emit fine-grained notifications. Adapting this to mydenicek would make `materialize` incremental --- instead of replaying all events, the system would propagate only the effect of the new event through the existing document, reducing per-edit cost from $O(N^2)$ to $O(1)$ for the common case of sequential edits. This is essential for scaling to large documents (thousands of events).

**Metadata reduction via causal stability.** Each event carries a vector clock with $O(P)$ entries for $P$ peers. Linde and Leitão [@linde2020stability] show that causally stable operations (delivered to all replicas) can have their vector clock entries pruned, reducing per-event metadata by orders of magnitude. Combining this with mydenicek's replay constraint --- event IDs referenced by replay steps must remain in the PO-Log --- would require a pruning condition of "stable AND unreferenced by any replay step." This would enable scaling to many peers without unbounded clock growth.

**Nested pure operation-based CRDTs.** Bauwens and Gonzalez Boix [@bauwens2023nested] extend the pure op-based framework with systematic composition of nested CRDTs (e.g., a map whose values are themselves CRDTs). mydenicek achieves nesting implicitly through path-based selectors on a monolithic tree. Adopting their composition framework could allow different conflict-resolution strategies for different subtrees --- for example, using a text CRDT for string-valued leaves while keeping selector rewriting for the tree structure.

**Optimized materialization.** The `resolveAgainst` step scans all prior events per replayed event ($O(N^2)$). Indexing priors by target prefix would reduce this. The current implementation could serve as a reference oracle for validating faster versions via model-guided fuzzing [@ozkan2025modelfuzz].

**Extended verification.** The TLA+ model covers five edit types on a flat record. Extending it to nested trees and wildcards, or mechanizing the proof in Isabelle/HOL, would provide stronger guarantees.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics.
