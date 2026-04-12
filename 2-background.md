# Background {#chap:background}

This chapter introduces the concepts and systems that form the foundation of this thesis. We describe the Denicek system, explain Operational Transformation, introduce causality and vector clocks, then discuss CRDTs and the Eg-walker algorithm that inspired our approach.

## Denicek {#sec:denicek}

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. It models documents as *tagged trees* --- hierarchical structures where each node carries a structural tag (such as `h1`, `ul`, `tr`) and contains either named fields (records), ordered children (lists), scalar values (primitives), or pointers to other nodes (references). [@Fig:document-tree] shows an example document tree.

![Example Denicek document tree. Blue nodes are records (named fields), orange is a list (ordered children), green nodes are primitives (scalar values). Edge labels show field names and list indices.](img/document-tree.png){#fig:document-tree width=65%}

The Denicek paper demonstrates the substrate through two systems built on top of it. *Webnicek* is a web-based programming system (inspired by Webstrates [@klokmose2015webstrates]) where documents are rendered as interactive web pages and users program by manipulating the document structure. *Datnicek* is a data science notebook that uses the same substrate for tabular data with formulas, supporting datasets of up to thousands of rows. Both systems share the same edit operations, recording/replay mechanism, and collaboration model --- they differ only in how the document tree is rendered and interpreted.

Nodes are addressed by *selector paths* --- slash-separated strings that describe the location of a node in the tree. For example, `/speakers/0/name` refers to the `name` field of the first item in the `speakers` list. Selectors support wildcards: `/speakers/*` addresses all children of the `speakers` list, enabling bulk operations such as "update the tag of every list item."

Denicek provides four key end-user programming experiences:

- **Programming by demonstration.** Users perform edits interactively --- such as adding a list item and copying a value from an input field --- and the system records these edits as a replayable script. When the user clicks a button, the recorded edits are replayed, potentially on different targets.
- **Schema evolution.** Structural edits allow users to refactor the document's structure without losing data.
- **Collaborative editing.** Multiple peers can edit the same document concurrently, and the system merges their edits deterministically. Notably, Denicek supports wildcard selectors (`speakers/*`) that target all children of a node. When combined with concurrent insertions, this produces a unique semantics: a wildcard edit affects not only items that existed when the edit was made, but also items inserted concurrently by other peers. This *edit-all-including-concurrent-additions* property is discussed further in [@Sec:foreach] and [@Sec:wildcard-concurrent].
- **Formula recomputation.** Nodes can contain formulas that reference other nodes via relative paths. When the referenced data changes, the formula result is recomputed.

### Edit operations

Denicek provides two categories of edit operations. *Data edits* modify the content of the document:

- `add(target, field, value)` --- add a named field to a record
- `delete(target, field)` --- remove a field from a record
- `set(target, value)` --- replace a primitive value
- `pushBack(target, item)` / `pushFront` --- append or prepend to a list
- `popBack(target)` / `popFront` --- remove from the end or start of a list
- `copy(target, source)` --- copy a subtree from one location to another

*Structural edits* change the shape of the document tree:

- `rename(target, oldField, newField)` --- rename a record field
- `updateTag(target, newTag)` --- change a node's structural tag (e.g., `ul` to `table`)
- `wrapRecord(target, field, tag)` --- wrap a node in a new parent record, moving the original value into a named field
- `wrapList(target, tag)` --- wrap a node in a new parent list

The distinction matters for collaborative editing: structural edits change the *paths* by which other edits address nodes. When a peer renames `speakers` to `talks`, all concurrent edits targeting `/speakers/...` must be retargeted to `/talks/...`. When a peer wraps a node, concurrent edits must gain an additional path segment. This is the core challenge that any collaborative editing approach for Denicek must solve.

### Denicek's collaboration model

The original Denicek defines three core operations on edit histories:

1. **Apply** --- apply an edit to a document, producing a new document state and extending the history.
2. **Merge** --- merge two edit histories that diverged from a common ancestor, using OT to transform one history's edits against the other's.
3. **Check for conflicts** --- after merging, identify edits that could not be reconciled (e.g., concurrent deletion and modification of the same node) and report them to the user.

Denicek's histories are *linear sequences* of edits. Merging two linear histories produces a new linear history. Importantly, merge is *not commutative* --- merging history A into B may produce a different result than merging B into A, because the OT transformation order differs. The paper mentions that histories could form a graph rather than a linear sequence, but does not elaborate on this direction.

This thesis takes exactly that step: replacing linear histories with a *causal event graph* (DAG), where merge order does not matter because all peers replay the same deterministic topological order. This is inspired by Eg-walker [@gentle2025egwalker], which applies the same principle to text editing.

## Operational Transformation {#sec:ot}

Operational Transformation (OT) is a technique for collaborative editing introduced by Ellis and Gibbs [@ellis1989concurrency] in 1989. The core idea is straightforward: when two users make concurrent edits, one user's operation is *transformed* with respect to the other's so that both operations can be applied in either order and produce the same result.

Consider a simple example with text editing, illustrated in [@Fig:ot-text-example]. Two users start with the string `"Hello"`:

![OT text example. Two concurrent insertions are transformed so both peers converge to the same state.](img/ot-text-example.png){#fig:ot-text-example width=75%}

- User A inserts `"!"` at position 5, producing `"Hello!"`
- User B inserts `" World"` at position 5, producing `"Hello World"`

When User A receives User B's operation `Insert(5, " World")`, it must be transformed: since User A already inserted a character at position 5, User B's insertion point shifts to position 6. The transformed operation `Insert(6, " World")` produces `"Hello! World"` on both peers.

OT is notoriously difficult to get right. Correctness requires satisfying two *transformation properties*: TP1 states that applying two concurrent operations in either order must produce the same result, and TP2 states that transforming a third operation against two concurrent operations must yield the same result regardless of the order the two are applied. Several published OT algorithms were later proven to violate these properties, causing peers to diverge under specific interleaving patterns. The number of transformation rules grows with each new edit type, and the interactions between rules are hard to reason about exhaustively. This fragility is one of the main motivations for exploring CRDT-based alternatives.

The Jupiter algorithm [@nichols1995jupiter], used in Google Docs, simplifies OT by requiring a central server that serializes all operations. This makes transformation simpler (only two-way transforms are needed) but introduces a single point of failure and prevents peer-to-peer collaboration.

## Causality {#sec:causality}

A fundamental concept in distributed collaborative editing is *causality* --- the relationship between events produced by different peers. Lamport's *happens-before* relation defines a partial order over events in a distributed system:

> **Definition (happens-before).** Event $a$ *happens-before* event $b$, written $a \to b$, if and only if:
>
> 1. $a$ and $b$ were produced by the same peer, and $a$ was produced before $b$; or
> 2. $a$ was produced by one peer and $b$ was produced by another peer *after* receiving $a$; or
> 3. there exists an event $c$ such that $a \to c$ and $c \to b$ (transitivity).
>
> Two events $a$ and $b$ are *concurrent*, written $a \parallel b$, if neither $a \to b$ nor $b \to a$.

[@Fig:causality] illustrates these relationships in an event graph.

![Causality in an event graph. alice:0 happens-before alice:1 (Alice created them sequentially). alice:1 and bob:0 are concurrent --- neither peer had seen the other's event when creating their own.](img/causality.png){#fig:causality width=70%}

Happens-before is defined abstractly, but an efficient implementation requires a concrete mechanism for detecting it. *Vector clocks* provide this mechanism.

> **Definition (vector clock).** A vector clock $V$ is a map from peer ID to a non-negative integer. Each event $a$ carries a vector clock $V_a$ where $V_a[p]$ is the highest sequence number from peer $p$ that is a causal ancestor of $a$ (including $a$ itself if $a$ was produced by $p$).
>
> When a peer $p$ creates an event with sequence number $n$, its vector clock is computed as the component-wise maximum of all parents' vector clocks, with $V[p] = n$.

Vector clocks characterize the happens-before relation:

> $a \to b$ if and only if $V_a[p] \leq V_b[p]$ for all peers $p$, and $V_a \neq V_b$.
>
> $a \parallel b$ if and only if there exist peers $p, q$ such that $V_a[p] > V_b[p]$ and $V_a[q] < V_b[q]$.

This allows concurrency detection in O(P) time (where P is the number of peers) by comparing two vectors, without traversing the event graph.

The *frontier* is the set of events with no descendants --- the "tips" of the DAG, representing the most recent state each peer has reached. [@Fig:frontier] shows a frontier with two events from different peers.

![Frontier of an event DAG. Events `alice:2` and `bob:0` are both frontier events --- neither has a descendant. A new event created by either peer will have both as parents.](img/frontier.png){#fig:frontier width=55%}

When a peer creates a new event, the current frontier becomes the event's parents. After both peers sync and one makes a new edit, the resulting event has *multiple parents* --- one from each branch --- merging the frontier back to a single point. This is analogous to a merge commit in version control.

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

Several existing systems and libraries are relevant to this thesis. Automerge [@automerge] and Loro [@loro] are CRDT libraries that we evaluate in detail in [@Chap:journey] as potential backends for Denicek. Grove [@grove2025] is a calculus for collaborative structure editing that operates on abstract syntax trees. It models all edits as commutative operations (a CmRDT), eliminating patch synthesis and three-way merge. While Grove targets collaborative code editing rather than document-oriented end-user programming, it shares the goal of conflict-free concurrent editing on tree structures. Webstrates [@klokmose2015webstrates] is a platform for shareable dynamic media that inspired the naming lineage: Webstrates, myWebstrates, Denicek, myDenicek.

## The for-each problem {#sec:foreach}

Weidner [@weidner2023foreach] identifies a common pattern in collaborative apps: operations that apply a mutation to every element in a range, such as "bold all selected text" or "change the tag of every list item." The naive approach --- iterating over elements at the time of the operation --- misses elements inserted concurrently by other peers. For example, if Alice bolds a paragraph while Bob concurrently types a new sentence within it, Bob's sentence is not bolded. The author calls this the *forEachPrior* semantics and proposes a dedicated CRDT for-each operation that correctly applies the mutation to both existing and concurrently inserted elements.

This problem is directly relevant to mydenicek's wildcard selector (`speakers/*`). As discussed in [@Sec:wildcard-concurrent], the replay-based approach achieves the same "for-each-including-concurrent-insertions" semantics without a dedicated CRDT operation: the wildcard is expanded at replay time to include all elements that exist at that point, including those inserted concurrently. Weidner's for-each operation is designed for CRDT-based systems where the document state is maintained by CRDT data structures. In mydenicek, the document state is reconstructed by replaying an event graph with OT --- a fundamentally different architecture that achieves the for-each semantics as a natural consequence of replay-time wildcard expansion rather than as an explicit CRDT operation.
