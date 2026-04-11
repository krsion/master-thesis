# Background {#chap:background}

This chapter provides the theoretical foundation for the rest of the thesis. We introduce the Denicek system, describe the key concepts of collaborative editing — Operational Transformation and CRDTs — and discuss local-first software principles.

## Denicek

\todo{Describe the Denicek system: tagged trees, selectors, four experiences (programming by demonstration, schema evolution, collaborative editing, formula recomputation). Reference the paper.}

## Operational Transformation

\todo{OT basics: operations on shared state, transformation functions, the need for a total order. Classical OT requires a central server or complex history management. Reference Ellis & Gibbs 1989, Jupiter (Nichols et al. 1995).}

## Conflict-free Replicated Data Types

\todo{CRDTs: state-based vs operation-based. G-Set, LWW-Register, OR-Set. Strong eventual consistency. No central coordination needed. Reference Shapiro et al. 2011.}

## Eg-walker: Combining OT and CRDTs

\todo{Describe the Eg-walker approach: store operations in a causal event graph, apply OT locally during replay. Combines the simplicity of OT (integer indexes, no per-character metadata) with the robustness of CRDTs (no central server, peer-to-peer). Reference Gentle & Kleppmann, EuroSys 2025.}

## Local-first Software

\todo{Principles of local-first software: data ownership, offline support, peer-to-peer sync, no cloud dependency. Reference Kleppmann et al. 2019 "Local-first software: you own your data, in spite of the cloud".}

## Related Systems

\todo{Brief overview of Automerge, Loro, Grove, Webstrates/myWebstrates. Position Denicek relative to these.}
