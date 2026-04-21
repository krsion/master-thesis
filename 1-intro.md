
# Introduction {-}

Collaborative document editing --- from Google Docs to Figma --- lets multiple users edit the same document concurrently, merging changes automatically. Most such systems depend on a central server to mediate edits.

*Local-first software* [@kleppmann2019localfirst] takes a different approach: each device holds a full copy of the data, edits apply immediately, and synchronization happens in the background. This offers better performance, offline support, and data ownership --- but requires robust algorithms for merging concurrent edits without a central authority.

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. Its documents are tagged trees --- records, lists, primitives, and references --- addressed by path-based selectors such as `/speakers/0/name` or `/items/*`. Users program by recording edit sequences and replaying them (programming by demonstration). The original Denicek uses Operational Transformation (OT) for collaboration, but OT is notoriously fragile --- several published algorithms were later proven incorrect, and rules grow with each new edit type.

This thesis investigates more robust collaborative editing for Denicek. We evaluate two CRDT libraries --- Automerge and Loro --- and build a custom design, describing the trade-offs of each. The result, *mydenicek*, is a **pure operation-based CRDT** [@baquero2017pureop]: edits are stored in a grow-only event graph, and the document is computed by a pure view function that rewrites concurrent selectors during deterministic topological replay. Convergence follows from a short argument (set equality + determinism) rather than from TP1/TP2. The main engineering challenge is **intention preservation** --- ensuring that references survive structural edits, wildcards expand over concurrent inserts, and recorded edits replay correctly after schema evolution.

The main contributions are:

- Evaluation of Automerge and Loro for tree-structured collaborative editing, identifying concrete limitations: the concurrent wrap problem (Automerge) and the retargeting problem (Loro).
- A pure op-based CRDT for tagged-tree documents with path-based selectors, wildcards, relative references, and strict indices, together with a proof sketch of strong eventual consistency.
- A two-level polymorphic design for selector rewriting that avoids $O(n^2)$ transformation rules: one `transformSelector` per structural edit type, plus virtual methods (`rewriteInsertedNode`, `applyListIndexShift`) for payload and index adjustments.
- Wildcard-affects-concurrent-insertions semantics --- structural edits via wildcards automatically affect items inserted concurrently by other peers.
- A replay mechanism that retargets recorded edits through later structural changes, enabling programming by demonstration in a collaborative setting.

## Thesis structure {-}

[@Chap:background] covers CRDTs, OT, and related work. [@Chap:implementation] presents the mydenicek CRDT. [@Chap:system] describes the system engineering. [@Chap:evaluation] demonstrates formative examples and evaluates correctness and performance. [@Chap:conclusion] concludes with future work.
