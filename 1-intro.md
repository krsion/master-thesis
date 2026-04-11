
# Introduction {-}

Collaborative document editing has become an essential feature of modern software, from Google Docs to Figma. These systems allow multiple users to edit the same document concurrently, with changes merged automatically. However, most collaborative editors are cloud-dependent --- they require a central server to mediate edits and resolve conflicts.

*Local-first software* [@kleppmann2019localfirst] takes a different approach: each user's device holds a full copy of the data, edits are applied immediately without waiting for network round-trips, and synchronization happens in the background when connectivity is available. This model offers better performance, offline support, and data ownership --- but it requires robust algorithms for merging concurrent edits without a central authority.

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. Documents in Denicek are tagged trees --- composed of records, lists, primitives, and references --- addressed by path-based selectors such as `/speakers/0/name` or `/items/*`. Users program by recording sequences of edits and replaying them, enabling a form of programming by demonstration. The system supports four key experiences: programming by demonstration, schema evolution through structural edits, collaborative editing, and formula recomputation.

The original Denicek implementation uses Operational Transformation (OT) for collaborative editing. While OT is a well-established technique, it is error-prone --- the number of transformation rules grows quadratically with each new edit type, and subtle bugs can lead to divergence between peers.

This thesis investigates approaches to more robust collaborative editing in Denicek, drawing on concepts from both CRDTs and OT. We evaluate three approaches --- Automerge, Loro, and a custom OT-based event DAG --- and describe the trade-offs of each with respect to Denicek's unique requirements. The result is a new implementation called *mydenicek* that stores edits in a causal event graph (a CRDT) and uses OT during replay to transform selectors through concurrent structural changes. The implementation is validated on six formative examples that demonstrate the system's end-user programming capabilities.

## Thesis structure {-}

[@Chap:background] provides the theoretical background on CRDTs, operational transformation, and local-first software. [@Chap:journey] describes the journey from Automerge through Loro to the custom OT-based event DAG, explaining the motivation for each transition. [@Chap:implementation] presents the architecture and implementation of the mydenicek core engine. [@Chap:formative] demonstrates the system through six formative examples. [@Chap:evaluation] evaluates the results and discusses limitations. [@Chap:conclusion] concludes with a summary and future work.
