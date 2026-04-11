# Background {#chap:background}

This chapter introduces the concepts and systems that form the foundation of this thesis. We describe the Denicek system, explain the two main approaches to collaborative editing --- Operational Transformation and CRDTs --- and discuss the Eg-walker algorithm that inspired our approach.

## Denicek {#sec:denicek}

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. It models documents as *tagged trees* --- hierarchical structures where each node carries a structural tag (such as `h1`, `ul`, `tr`) and contains either named fields (records), ordered children (lists), scalar values (primitives), or pointers to other nodes (references). [@Fig:document-tree] shows an example document tree.

![Example Denicek document tree. Blue nodes are records (named fields), orange is a list (ordered children), green nodes are primitives (scalar values). Edge labels show field names and list indices.](img/document-tree.png){#fig:document-tree width=65%}

Nodes are addressed by *selector paths* --- slash-separated strings that describe the location of a node in the tree. For example, `/speakers/0/name` refers to the `name` field of the first item in the `speakers` list. Selectors support wildcards: `/speakers/*` addresses all children of the `speakers` list, enabling bulk operations such as "update the tag of every list item."

Denicek provides four key end-user programming experiences:

- **Programming by demonstration.** Users perform edits interactively --- such as adding a list item and copying a value from an input field --- and the system records these edits as a replayable script. When the user clicks a button, the recorded edits are replayed, potentially on different targets.
- **Schema evolution.** Structural edits such as `wrapRecord` (wrap a node in a new parent record), `wrapList` (wrap in a list), `rename` (rename a field), and `updateTag` (change a node's structural tag) allow users to refactor the document's structure without losing data.
- **Collaborative editing.** Multiple peers can edit the same document concurrently, and the system merges their edits deterministically.
- **Formula recomputation.** Nodes can contain formulas that reference other nodes via relative paths. When the referenced data changes, the formula result is recomputed.

The original Denicek uses Operational Transformation to handle concurrent edits. This thesis explores alternatives drawing on both CRDT and OT concepts, ultimately arriving at an approach inspired by Eg-walker [@gentle2025egwalker] that combines a CRDT event graph with OT-based selector transformation during replay.

## Operational Transformation {#sec:ot}

Operational Transformation (OT) is a technique for collaborative editing introduced by Ellis and Gibbs [@ellis1989concurrency] in 1989. The core idea is straightforward: when two users make concurrent edits, one user's operation is *transformed* with respect to the other's so that both operations can be applied in either order and produce the same result.

Consider a simple example with text editing, illustrated in [@Fig:ot-text-example]. Two users start with the string `"Hello"`:

![OT text example. Two concurrent insertions are transformed so both peers converge to the same state.](img/ot-text-example.png){#fig:ot-text-example width=75%}

- User A inserts `"!"` at position 5, producing `"Hello!"`
- User B inserts `" World"` at position 5, producing `"Hello World"`

When User A receives User B's operation `Insert(5, " World")`, it must be transformed: since User A already inserted a character at position 5, User B's insertion point shifts to position 6. The transformed operation `Insert(6, " World")` produces `"Hello! World"` on both peers.

OT becomes significantly more complex for tree-structured documents like Denicek's. When a peer renames a field from `speakers` to `talks`, all concurrent operations that reference `/speakers/...` must have their selector paths transformed to `/talks/...`. When a peer wraps a node in a new parent, selector paths must gain an additional segment. The number of transformation rules grows with each new edit type, and ensuring that all combinations are handled correctly is error-prone --- this is the main motivation for exploring CRDT-based alternatives.

The Jupiter algorithm [@nichols1995jupiter], used in Google Docs, simplifies OT by requiring a central server that serializes all operations. This makes transformation simpler (only two-way transforms are needed) but introduces a single point of failure and prevents peer-to-peer collaboration.

## Conflict-free Replicated Data Types {#sec:crdts}

CRDTs [@shapiro2011crdt] are data structures designed for distributed systems where multiple replicas can be modified independently and merged without conflicts. The key guarantee is *strong eventual consistency*: any two replicas that have received the same set of updates will be in the same state, regardless of the order in which updates were delivered. Preguiça [@preguica2018crdts] provides a comprehensive overview of CRDTs and their variants.

CRDTs come in two main flavors:

- **State-based CRDTs** (CvRDTs) require the set of possible states to form a *join semilattice* --- a partially ordered set where any two states have a least upper bound (join). Replicas periodically send their full state to each other, and the merge operation computes the join. This works over unreliable channels since states can always be re-merged, but sending the full state can be expensive for large data structures.
- **Operation-based CRDTs** (CmRDTs) propagate individual update operations rather than full states. Operations must be commutative so that applying them in any order produces the same result. This is more bandwidth-efficient, but requires a *reliable causal broadcast* layer --- operations must be delivered exactly once and in causal order.

A hybrid approach, *delta-state CRDTs*, sends only the part of the state that changed (the "delta") rather than the full state. Deltas are joinable like full states (so they tolerate message loss and reordering) but are small like operations (so they are bandwidth-efficient).

Common CRDT building blocks relevant to this thesis include:

- **G-Set** (grow-only set): elements can be added but never removed. Merging two G-Sets is simply their union.
- **LWW-Register** (last-writer-wins register): a single value where concurrent writes are resolved by a deterministic ordering (typically by timestamp or logical clock).
- **OR-Set** (observed-remove set): elements can be added and removed. Concurrent add and remove of the same element are resolved in favor of the add.

For collaborative editing of tree-structured documents, Kleppmann and Beresford [@kleppmann2017crdt] proposed a JSON CRDT that uses unique identifiers for each node and supports insert, delete, and move operations. This work identified the *move operation problem*: in a flat JSON structure without native move support, moving a node requires deleting it from one location and inserting it at another --- two separate operations that can interleave with concurrent edits, potentially losing data.

## Eg-walker {#sec:egwalker}

Eg-walker [@gentle2025egwalker] is a collaborative text editing algorithm that takes the best of both OT and CRDTs. The paper observes a fundamental trade-off in existing approaches:

- **OT** is simple and memory-efficient --- operations use plain integer indices, and the document state is just the text itself with no per-character metadata. However, merging long-diverged branches (e.g., after offline editing) requires transforming each operation against all concurrent operations, which is at least O(n²) and can take hours for large editing histories.
- **CRDTs** handle arbitrarily diverged branches efficiently because each character carries a unique identifier that is unaffected by concurrent operations. However, these identifiers (and tombstones for deleted characters) must be loaded into memory whenever the document is opened, consuming an order of magnitude more memory than OT in the steady state.

Eg-walker overcomes this trade-off by storing operations in a *causal event graph* --- a directed acyclic graph where each event records its causal dependencies. In the common case of sequential (non-concurrent) editing, operations are applied directly using plain indices, like OT --- no per-character metadata is needed. Only when the algorithm encounters concurrent events (a fork in the event graph) does it temporarily build the CRDT-style state needed to merge them. After the concurrent region is resolved, the CRDT state is discarded.

The key insight is that OT transformation does not need to happen at the time an operation is received. Instead, all operations are stored in the event graph, and when the document needs to be materialized, the operations are replayed in a deterministic topological order with transformations applied locally. This avoids the need for a central server (the event graph can be merged peer-to-peer) while keeping the simplicity of index-based operations in the steady state.

Eg-walker was designed for text editing (character insertions and deletions). This thesis applies the same principle to tree-structured documents --- selectors replace character indices, and structural edit transformations (rename, wrap, delete) replace the character-level insert/delete transforms. Unlike Eg-walker, our approach does not switch between OT and CRDT modes --- it always replays the full event history with OT. This is simpler to implement but less performant for long histories, as discussed in [@Chap:evaluation].

## Related systems {#sec:related}

Several existing systems and libraries are relevant to this thesis. Automerge [@automerge] and Loro [@loro] are CRDT libraries that we evaluate in detail in [@Chap:journey] as potential backends for Denicek. Shen and Sun [@shen2006grove] study the convergence conditions for OT on tree-structured documents, identifying formal transformation properties (TP1, TP2) required to guarantee that concurrent tree operations converge. Their work is motivated by collaborative XML editing and focuses on achieving provably correct convergence for insert, delete, and update operations on hierarchical structures. Webstrates [@klokmose2015webstrates] is a platform for shareable dynamic media that inspired the naming lineage: Webstrates → myWebstrates → Denicek → myDenicek.

## The for-each problem {#sec:foreach}

Weidner [@weidner2023foreach] identify a common pattern in collaborative apps: operations that apply a mutation to every element in a range, such as "bold all selected text" or "change the tag of every list item." The naive approach --- iterating over elements at the time of the operation --- misses elements inserted concurrently by other peers. For example, if Alice bolds a paragraph while Bob concurrently types a new sentence within it, Bob's sentence is not bolded. The authors call this the *forEachPrior* semantics and propose a dedicated CRDT for-each operation that correctly applies the mutation to both existing and concurrently inserted elements.

This problem is directly relevant to mydenicek's wildcard selector (`speakers/*`). As discussed in [@Sec:wildcard-concurrent], the replay-based approach achieves the same "for-each-including-concurrent-insertions" semantics without a dedicated CRDT operation: the wildcard is expanded at replay time to include all elements that exist at that point, including those inserted concurrently. Weidner's for-each operation is designed for CRDT-based systems where the document state is maintained by CRDT data structures. In mydenicek, the document state is reconstructed by replaying an event graph with OT --- a fundamentally different architecture that achieves the for-each semantics as a natural consequence of replay-time wildcard expansion rather than as an explicit CRDT operation.
