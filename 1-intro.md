
# Introduction {-}

Collaborative document editing has become an essential feature of modern software, from Google Docs to Figma. These systems allow multiple users to edit the same document concurrently, with changes merged automatically. However, most collaborative editors are cloud-dependent --- they require a central server to mediate edits and resolve conflicts.

*Local-first software* [@kleppmann2019localfirst] takes a different approach: each user's device holds a full copy of the data, edits are applied immediately without waiting for network round-trips, and synchronization happens in the background when connectivity is available. This model offers better performance, offline support, and data ownership --- but it requires robust algorithms for merging concurrent edits without a central authority.

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. Documents in Denicek are tagged trees --- composed of records, lists, primitives, and references --- addressed by path-based selectors such as `/speakers/0/name` or `/items/*`. Users program by recording sequences of edits and replaying them, enabling a form of programming by demonstration. The system supports four key experiences: programming by demonstration, schema evolution through structural edits, collaborative editing, and formula recomputation.

The original Denicek implementation uses Operational Transformation (OT) for collaborative editing. While OT is a well-established technique, it is notoriously difficult to get right --- several published OT algorithms were later proven incorrect, and the number of transformation rules grows with each new edit type.

This thesis investigates approaches to more robust collaborative editing in Denicek, drawing on concepts from both CRDTs and OT. We evaluate two CRDT libraries --- Automerge and Loro --- and a custom event-sourced design, describing the trade-offs of each with respect to Denicek's unique requirements. The result is a new implementation called *mydenicek* that is best described as a **pure operation-based CRDT**: edits are stored in a grow-only event graph (the replica state), and the document is computed on demand by a deterministic view function that rewrites concurrent selectors through structural edits during a deterministic topological replay. Strong eventual consistency follows from a short argument (set equality + determinism) rather than from the classical OT correctness conditions TP1 and TP2. The implementation is validated on seven formative examples that demonstrate the system's end-user programming capabilities.

The main contributions of this thesis are:

- A systematic evaluation of CRDT libraries (Automerge, Loro) for tree-structured collaborative editing, identifying concrete limitations: the concurrent wrap problem (Automerge) and the retargeting problem (Loro).
- A pure op-based CRDT for tagged-tree documents that uses path-based selectors as the native addressing mode, supporting wildcards, relative references, and strict indices, together with a short proof sketch of strong eventual consistency.
- A two-level polymorphic design for concurrent selector rewriting that avoids $O(n^2)$ transformation rules by separating selector rewriting (default, one method per structural edit type) from payload rewriting (overrides for structural edits that must also modify a concurrent insert's payload).
- Wildcard-affects-concurrent-insertions semantics --- structural edits applied via wildcards automatically affect items inserted concurrently by other peers --- presented as a deliberate design choice enabled by the view-function approach.
- A replay mechanism that retargets recorded edits through later structural changes, enabling programming by demonstration in a collaborative setting.

## Thesis structure {-}

[@Chap:background] provides the theoretical background on CRDTs, operational transformation, and local-first software. [@Chap:journey] explores the design space, describing the iterative path from Automerge through Loro to the custom OT-based event DAG and the motivation for each transition. [@Chap:implementation] presents the architecture and implementation of the mydenicek core engine. [@Chap:formative] demonstrates the system through seven formative examples. [@Chap:evaluation] evaluates the results and discusses limitations. [@Chap:conclusion] concludes with a summary and future work.
