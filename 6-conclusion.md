# Conclusion {#chap:conclusion}

This thesis investigated collaborative editing for Denicek. We evaluated Automerge (lacks atomic move → concurrent wrap problem) and Loro (opaque IDs → retargeting problem), then built a custom pure operation-based CRDT.

The implementation stores edits as immutable events in a grow-only DAG and materializes documents by deterministic topological replay with selector rewriting. Convergence follows from the pure operation-based CRDT framework [@baquero2017pureop]: the event set is a G-Set, the *eval* function (`materialize`) is deterministic. The main contribution is **intention preservation** --- selector rewriting rules that keep references valid through structural edits, expand wildcards over concurrent inserts, and retarget recorded edits through schema evolution.

The system was validated on five formative examples, 310 tests (including property-based convergence testing with `fast-check`), and a TLA+ model of five edit types. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Future work {#sec:future-work}

**Incremental eval (reactivity).** Currently, `materialize` recomputes the full document from the PO-Log. Bauwens et al. [@bauwens2021reactivity] propose *reactive pure operation-based CRDTs* that track which parts of the state changed and emit fine-grained notifications. Adapting this to mydenicek would make `materialize` incremental --- instead of replaying all events, the system would propagate only the effect of the new event through the existing document, reducing per-edit cost from $O(N^2)$ to $O(1)$ for the common case of sequential edits. This is essential for scaling to large documents (thousands of events).

**Metadata reduction via causal stability.** Each event carries a vector clock with $O(P)$ entries for $P$ peers. The `CausalStabilityTracker` (implemented and wired into the sync server) identifies causally stable events, but does not yet prune their vector clock entries. Bauwens and Gonzalez Boix [@bauwens2020stability] show that stable entries can have their clock metadata pruned, reducing per-event overhead by orders of magnitude. Extending the tracker to prune clock entries for stable events would enable scaling to many peers without unbounded metadata growth.

**Nested pure operation-based CRDTs.** Bauwens and Gonzalez Boix [@bauwens2023nested] extend the pure op-based framework with systematic composition of nested CRDTs (e.g., a map whose values are themselves CRDTs). mydenicek achieves nesting implicitly through path-based selectors on a monolithic tree. Adopting their composition framework could allow different conflict-resolution strategies for different subtrees --- for example, using a text CRDT for string-valued leaves while keeping selector rewriting for the tree structure.

**Optimized materialization.** The `resolveAgainst` step scans all prior events per replayed event ($O(N^2)$). Indexing priors by target prefix would reduce this. The current implementation could serve as a reference oracle for validating faster versions via model-guided fuzzing [@ozkan2025modelfuzz].

**Efficient set reconciliation for sync.** The current sync protocol exchanges events via `eventsSince(frontiers)`, which requires the server to retain the full event history. Baquero et al. [@baquero2025sync] show that CRDT states can be split into sets of smaller CRDTs and synchronized using distributed set reconciliation algorithms, reducing bandwidth when replicas share similar content. Applying this to mydenicek's event sync could reduce the data transmitted during reconnection after long offline periods.

**Extended verification.** The TLA+ model covers five edit types on a flat record. Extending it to nested trees and wildcards, or encoding the selector rewriting rules in VeriFx [@bauwens2022verifx] — an automated verification tool designed specifically for CRDTs — would provide mechanical convergence guarantees beyond the current bounded model.

**Framework integration.** mydenicek is a standalone implementation. Porting the selector rewriting rules to Flec [@bauwens2023nested] would provide PO-Log management, causal stability tracking, and reactivity as framework-level features rather than custom code. Adopting the `TestingRuntimes` harness from Collabs [@weidner2023collabs] would replace the current random-fuzzing approach with controlled deterministic network interleaving, enabling systematic exploration of concurrent edit orderings. Both integrations would replace ad-hoc implementations with principled, peer-reviewed infrastructure.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics.
