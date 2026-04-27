
# Introduction {-}

Denicek [@petricek2025denicek] is a computational substrate for *document-oriented end-user programming* [@petricek2025designchoices]. Its documents are tagged trees (records, lists, primitives, and references) addressed by path-based selectors such as `speakers/0/name` or `items/*`. Users program by recording edit sequences and replaying them (programming by demonstration). The original Denicek uses Operational Transformation (OT) for collaboration, but OT is notoriously fragile: several published algorithms were later proven incorrect [@imine2003proving], and the number of pairwise rules grows with each new edit type.

This thesis investigates more robust collaborative editing for Denicek. We evaluate two CRDT libraries --- Automerge and Loro --- and build a custom design, describing the trade-offs of each. The result, *mydenicek*, is a **pure operation-based CRDT** [@baquero2017pureop]: edits are stored in a grow-only event graph, and the document is computed by a deterministic *eval* function that rewrites concurrent selectors during topological replay.

Convergence --- all peers reaching the same state --- is the baseline guarantee. The harder problem is **intention preservation** [@sun1998achieving]: the effect of an operation in the merged document should match the effect that the operation had on the document state from which it was generated. For tree-structured documents with path-based selectors, this means that when the document structure changes concurrently --- fields are renamed, nodes are wrapped, items are inserted --- each operation must still reach its intended target. Defining merge rules that preserve intent is the central challenge of this thesis.

The main contributions are:

- Evaluation of document-based representations in two CRDT libraries (Automerge, Loro) for tree-structured collaborative editing, identifying concrete limitations: the concurrent wrap problem and the retargeting problem ([@Chap:background]).
- A novel pure operation-based CRDT for tagged-tree documents with path-based selectors, wildcards, relative references, and strict indices, together with a proof sketch of strong eventual consistency ([@Chap:implementation]).
- A selector rewriting technique that avoids $O(n^2)$ transformation rules through a two-level polymorphic design: one rewriting rule per structural edit type, plus virtual methods for payload and index adjustments ([@Chap:implementation]).
- Semantics that preserves user intent across concurrent edits, including explicit invariants: wildcard edits affect concurrent insertions, references survive structural changes, and indices shift correctly ([@Chap:evaluation]).
- Programming-by-demonstration support built on the same underlying event graph: recorded edits are retargets through later structural changes, enabling replay after schema evolution ([@Chap:evaluation]).

## Thesis structure {-}

[@Chap:background] covers CRDTs, OT, causality, and related work. [@Chap:implementation] presents the mydenicek CRDT design and implementation. [@Chap:evaluation] evaluates correctness and performance on formative examples. [@Chap:conclusion] concludes with future work.
