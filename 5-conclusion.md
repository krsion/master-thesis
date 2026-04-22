# Conclusion {#chap:conclusion}

This thesis investigated collaborative editing for Denicek. We evaluated Automerge (lacks atomic move → concurrent wrap problem) and Loro (opaque IDs → retargeting problem), then built a custom pure operation-based CRDT.

The implementation stores edits as immutable events in a grow-only DAG and materializes documents by deterministic topological replay with selector rewriting. Convergence follows from the pure operation-based CRDT framework [@baquero2017pureop]: the event set is a G-Set, the *eval* function (`materialize`) is deterministic. The main contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits through schema evolution.

The system was validated on five formative examples, 331 tests (including a concurrent pair matrix, property-based convergence testing with `fast-check`, and intention preservation invariants), and a determinism audit. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Incremental eval (reactivity).** Currently, `materialize` recomputes the full document from the PO-Log. Bauwens et al. [@bauwens2021reactivity] propose *reactive pure operation-based CRDTs* that include buffered (not yet causally delivered) operations in the eval result, giving optimistic local reads. For simpler CRDTs (sets, counters), this is straightforward. For mydenicek, optimistic reads are unsafe: a buffered structural edit whose causal dependencies haven't arrived would corrupt the selector rewriting chain. A safer form of reactivity — incremental eval that propagates only the new event's effect through the existing document — would reduce per-edit cost from $O(N^2)$ to $O(1)$ for sequential edits.

**Client-side metadata pruning.** The causal stability tracker ([@Sec:sync]) identifies stable events; extending this to prune vector clock entries on clients would reduce per-event metadata from $O(P)$ to $O(1)$ for stable events [@bauwens2020stability].

**Nested pure operation-based CRDTs.** Bauwens and Gonzalez Boix [@bauwens2023nested] extend the pure op-based framework with systematic composition of nested CRDTs (e.g., a map whose values are themselves CRDTs). mydenicek achieves nesting implicitly through path-based selectors on a monolithic tree. Adopting their composition framework could allow different conflict-resolution strategies for different subtrees --- for example, using a text CRDT for string-valued leaves while keeping selector rewriting for the tree structure.

**Optimized materialization.** The `resolveAgainst` step scans all prior events per replayed event ($O(N^2)$). Indexing priors by target prefix would reduce this. The current implementation could serve as a reference oracle for validating faster versions via model-guided fuzzing [@ozkan2025modelfuzz].

**Efficient set reconciliation for sync.** The current sync protocol exchanges events via `eventsSince(frontiers)`, which requires the server to retain the full event history. Baquero et al. [@baquero2025sync] show that CRDT states can be split into sets of smaller CRDTs and synchronized using distributed set reconciliation algorithms, reducing bandwidth when replicas share similar content. Applying this to mydenicek's event sync could reduce the data transmitted during reconnection after long offline periods.

**Extended verification.** Encoding the selector rewriting rules in VeriFx [@deporre2023verifx] — an automated verification tool designed specifically for CRDTs — would provide mechanical convergence guarantees. A TLA+ model of the materialization pipeline could further strengthen confidence by exhaustively checking bounded configurations.

**Framework integration.** mydenicek is a standalone implementation. Porting the selector rewriting rules to Flec [@bauwens2023nested] would provide PO-Log management, causal stability tracking, and reactivity as framework-level features rather than custom code. Adopting the `TestingRuntimes` harness from Collabs [@weidner2023collabs] would replace the current random-fuzzing approach with controlled deterministic network interleaving, enabling systematic exploration of concurrent edit orderings. Both integrations would replace ad-hoc implementations with principled, peer-reviewed infrastructure.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics.
