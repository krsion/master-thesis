# Journey: Automerge, Loro, Custom {#chap:journey}

This chapter describes the iterative process of finding the right collaborative editing approach for Denicek. We started with Automerge, moved to Loro, and ultimately built a custom OT-based event DAG. Each transition was motivated by concrete problems discovered during implementation.

## Attempt 1: Automerge

\todo{Describe the Automerge-based implementation. Flat map representation (nodes dict + children ID arrays). Advantages: mature library, rich data types. Problems discovered: no atomic move operation, concurrent wrap creates node under two parents, deterministic wrapper ID pattern was fragile. Include the concurrent wrap diagram.}

## Attempt 2: Loro

\todo{Describe the Loro-based implementation. Advantages: movable tree CRDT (atomic move), latest research (Fugue), great docs. Problems discovered: opaque node IDs (not paths), no wildcards, programming by demonstration needed relative references that Loro's ID system couldn't express. Include the retargeting problem example with conference table wrap + ref.}

## Why Not Layer OT on Top of Loro?

\todo{Address the natural question: why reimplement instead of adding a path layer on Loro? Two conflict resolution layers would be hard to reason about and to debug. One coherent system with paths as native addressing is simpler.}

## The Custom Approach

\todo{Motivation for the custom OT-based event DAG. Inspired by Eg-walker: store events in a causal graph, apply OT during deterministic topological replay. Path-based selectors are the native addressing mode. Each structural edit type has hand-written OT transformation rules.}
