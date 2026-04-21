# Background {#chap:background}

This chapter introduces the concepts and systems that form the foundation of this thesis. We describe the Denicek system, explain Operational Transformation, introduce causality and vector clocks, then discuss CRDTs --- focusing on the pure operation-based framework of Baquero et al. that mydenicek adopts.

## Denicek {#sec:denicek}

Denicek [@petricek2025denicek] is a computational substrate for document-oriented end-user programming. It models documents as *tagged trees* --- hierarchical structures where each node carries a structural tag (such as `h1`, `ul`, `tr`) and contains either named fields (records), ordered children (lists), scalar values (primitives), or pointers to other nodes (references). [@Fig:document-tree] shows an example document tree.

![Example Denicek document tree. Blue nodes are records (named fields), orange is a list (ordered children), green nodes are primitives (scalar values). Edge labels show field names and list indices.](img/document-tree.png){#fig:document-tree width=65%}

The Denicek paper demonstrates the substrate through two systems built on top of it. *Webnicek* is a web-based programming system where documents are rendered as interactive web pages and users program by manipulating the document structure. *Datnicek* is a data science notebook that uses the same substrate for tabular data with formulas, supporting datasets of up to thousands of rows. Both systems share the same edit operations, recording/replay mechanism, and collaboration model --- they differ only in how the document tree is rendered and interpreted.

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
- `insert(target, index, item)` --- insert an item into a list at a given index
- `remove(target, index)` --- remove the item at a given index from a list
- `copy(target, source)` --- copy a subtree from one location to another

*Structural edits* change the shape of the document tree:

- `rename(target, oldField, newField)` --- rename a record field
- `updateTag(target, newTag)` --- change a node's structural tag (e.g., `ul` to `table`)
- `wrapRecord(target, field, tag)` --- wrap a node in a new parent record, moving the original value into a named field
- `wrapList(target, tag)` --- wrap a node in a new parent list
- `reorder(target, fromIndex, toIndex)` --- move a list item from one index to another

The distinction matters for collaborative editing: structural edits change the *paths* by which other edits address nodes. When a peer renames `speakers` to `talks`, all concurrent edits targeting `/speakers/...` must be retargeted to `/talks/...`. When a peer wraps a node, concurrent edits must gain an additional path segment. This is the core challenge that any collaborative editing approach for Denicek must solve.

### Denicek's collaboration model

The original Denicek defines three core operations on edit histories:

1. **Apply** --- apply an edit to a document, producing a new document state and extending the history.
2. **Merge** --- merge two edit histories that diverged from a common ancestor, using OT to transform one history's edits against the other's.
3. **Check for conflicts** --- after merging, identify edits that could not be reconciled (e.g., concurrent deletion and modification of the same node) and report them to the user.

Denicek's histories are *linear sequences* of edits. Merging two linear histories produces a new linear history. Importantly, merge is *not commutative* --- merging history A into B may produce a different result than merging B into A, because the OT transformation order differs. The paper mentions that histories could form a graph rather than a linear sequence, but does not elaborate on this direction.

This thesis takes exactly that step: replacing linear histories with a *causal event graph* (DAG), where merge order does not matter because all peers replay the same deterministic topological order. Under the pure operation-based CRDT framework of Baquero et al. [@baquero2017pureop], convergence follows directly from the fact that the event set is a G-Set and the view function is pure (see [@Sec:crdts]).

## Operational Transformation {#sec:ot}

Operational Transformation (OT), introduced by Ellis and Gibbs [@ellis1989concurrency], transforms concurrent operations so that both peers converge to the same state. [@Fig:ot-text-example] illustrates the basic idea with two concurrent text insertions.

![OT text example. Two concurrent insertions are transformed so both peers converge to the same state.](img/ot-text-example.png){#fig:ot-text-example width=75%}

Correctness in the decentralized setting requires two *transformation properties* [@ressel1996integrating]: **TP1** (applying $a$ then $T(b,a)$ reaches the same state as $b$ then $T(a,b)$) and **TP2** (transforming a third operation through two concurrent ones is order-independent). Several published algorithms were later proven to violate TP2 [@imine2003proving], and the number of pairwise rules grows with each new edit type. mydenicek sidesteps TP1/TP2 entirely by using a single deterministic replay order ([@Sec:event-dag]).

Sun et al.~[@sun1998achieving] decompose OT correctness into three properties: **convergence**, **causality preservation**, and **intention preservation** (the effect matches the user's intent). TP1/TP2 address convergence; intention preservation depends on the transformation rules and cannot be derived from them. This thesis proves convergence in [@Sec:crdt-framing] and validates intention preservation empirically through the formative examples of [@Chap:formative].

## Causality {#sec:causality}

Lamport's *happens-before* relation [@lamport1978] defines a partial order over events in a distributed system:

> **Definition (happens-before).** $a \to b$ if (1) $a$ and $b$ are from the same peer and $a$ preceded $b$, (2) $a$ is the sending and $b$ the receipt of the same message, or (3) transitivity. Two events are *concurrent* ($a \parallel b$) if neither $a \to b$ nor $b \to a$.

[@Fig:causality] illustrates these relationships in an event graph.

![Causality in a distributed system. Alice creates two events locally. Bob's first event (bob:0) receives Alice's message, establishing alice:0 $\to$ alice:1 $\to$ bob:0. Cross-peer causality is determined by messages, not by sequence numbers.](img/causality.png){#fig:causality width=55%}

*Vector clocks* [@mattern1989virtual; @fidge1988timestamps] implement happens-before detection. A vector clock $V$ maps each peer ID to its highest known sequence number. $a \to b$ iff $V_a[p] \leq V_b[p]$ for all $p$ with strict inequality for at least one. This allows concurrency detection in O(P) time.

### Event DAG

Causal relationships form a directed acyclic graph (DAG): each event lists its parents (direct causes). The DAG encodes the full causal structure and enables deterministic replay. The *frontier* --- events with no descendants --- compactly represents the current state. When a peer creates a new event, the current frontier becomes its parents; after sync, a new event merges multiple parents back to a single point, analogous to a merge commit.

## Reliable causal delivery {#sec:causal-delivery}

The pure op-based CRDT framework [@baquero2017pureop] requires two delivery guarantees:

> **Causal consistency.** If operation $a$ is delivered, all operations causally before $a$ have already been delivered.
>
> **Eventual delivery.** Every operation generated by a correct process is eventually delivered to all correct processes.

In mydenicek, causal delivery is implemented by buffering: when a message arrives whose parents have not yet been delivered, it is held until they arrive. Eventual delivery is ensured by frontier-based catch-up: on each sync round, a peer sends its frontier, and the server responds with all missing events. If a message is lost, the frontier does not advance and missing events are resent on the next round.

## Conflict-free Replicated Data Types {#sec:crdts}

CRDTs [@shapiro2011crdt] are data structures designed for distributed systems where multiple replicas can be modified independently and merged without conflicts. The key guarantee is *strong eventual consistency*: any two replicas that have received the same set of updates will be in the same state, regardless of the order in which updates were delivered. Preguiça [@preguica2018crdts] provides a comprehensive overview of CRDTs and their variants.

CRDTs come in two main flavors:

- **State-based CRDTs** (CvRDTs) require the set of possible states to form a *join semilattice* --- a partially ordered set where any two states have a least upper bound (join). Replicas periodically send their full state to each other, and the merge operation computes the join. This works over unreliable channels since states can always be re-merged, but sending the full state can be expensive for large data structures.
- **Operation-based CRDTs** (CmRDTs) propagate individual update operations rather than full states. Concurrent operations must be commutative so that applying them in either order produces the same result. This is more bandwidth-efficient, but requires a reliable causal delivery layer as described in [@Sec:causal-delivery].

A hybrid approach, *delta-state CRDTs*, sends only the part of the state that changed (the "delta") rather than the full state. Deltas are joinable like full states (so they tolerate message loss and reordering) but are small like operations (so they are bandwidth-efficient).

### Pure operation-based CRDTs {#sec:pure-op-crdt}

*Pure operation-based CRDTs* [@baquero2017pureop] are the theoretical foundation of mydenicek. Traditional operation-based CRDTs require all concurrent operations to commute pairwise --- a property that is hard to design and prove for complex data types. Baquero et al. sidestep this entirely by making the **replica state the set of all delivered operations** (a *PO-Log* --- partially ordered log). The observable value is computed on demand by a **pure function** (*eval*) over that set.

The key insight is that the operation set is a G-Set (grow-only set), and G-Set merge is set union --- associative, commutative, and idempotent --- making it the simplest possible CRDT. Shapiro et al. [@shapiro2011crdt] proved that state-based CRDTs with a monotonic join-semilattice merge converge; the G-Set satisfies this trivially. Strong eventual consistency then follows from two conditions: (1) every operation is eventually delivered to every replica (reliable broadcast), and (2) the *eval* function is deterministic. Condition (1) is a transport-layer concern; condition (2) is the only property the data type designer must prove.

The framework also defines a **redundancy relation** for compaction: once an operation is *causally stable* (delivered to all replicas), it can be pruned from the PO-Log if a more recent operation subsumes it. mydenicek's server-side compaction ([@Sec:compaction-offline]) corresponds to this mechanism.

This thesis adopts the Baquero framing directly. mydenicek stores the full event DAG including explicit parent pointers, which is strictly richer than a PO-Log and enables checkpoint-based incremental materialization. The mapping is: the event DAG is the PO-Log, `materialize` is the *eval* function, and server-side compaction corresponds to PO-Log pruning. The convergence proof ([@Sec:crdt-framing]) reduces to showing that `materialize` is deterministic --- the G-Set guarantees the rest.

Common CRDT building blocks relevant to this thesis include:

- **G-Set** (grow-only set): elements can be added but never removed. Merging two G-Sets is simply their union.
- **LWW-Register** (last-writer-wins register): a single value where concurrent writes are resolved by a deterministic ordering (typically by timestamp or logical clock).
- **OR-Set** (observed-remove set): elements can be added and removed. Concurrent add and remove of the same element are resolved in favor of the add.

For collaborative editing of tree-structured documents, Kleppmann and Beresford [@kleppmann2017crdt] proposed a JSON CRDT that uses unique identifiers for each node and supports insert, delete, and move operations. This work identified the *move operation problem*: in a flat JSON structure without native move support, moving a node requires deleting it from one location and inserting it at another --- two separate operations that can interleave with concurrent edits, potentially losing data. For collaborative *rich text* (text with formatting spans and block structure), Peritext [@litt2022peritext] extends character-level CRDTs with mark operations whose semantics tolerate concurrent insertions and deletions within the affected range --- a problem closely related to the "wildcard affects concurrent inserts" behavior we describe in [@Sec:wildcard-concurrent].

## Related systems {#sec:related}

Several existing systems and libraries are relevant to this thesis. Automerge [@automerge] and Loro [@loro] are CRDT libraries that we evaluate in detail in [@Chap:journey] as potential backends for Denicek. Yjs [@yjs] is the most widely deployed CRDT library; it implements the YATA algorithm for sequences and provides shared types (YMap, YArray, YText, YXmlFragment) that can represent tree structures. Yjs was not evaluated as a separate empirical attempt because it shares the same fundamental limitations as Automerge for Denicek's use case: it lacks atomic move operations, uses opaque client-ID-based addressing rather than path-based selectors, and does not provide a native tree CRDT --- tree structures must be emulated with nested shared types whose concurrent moves suffer the same two-step remove-and-insert problem described for Automerge in [@Sec:concurrent-wrap].

Eg-walker [@gentle2025egwalker] is a collaborative text editing algorithm that stores operations in a causal event graph and materializes the document by replaying them in a deterministic topological order. mydenicek borrows this architectural idea --- event DAG with topological replay --- but applies it to tree-structured documents with selector rewriting instead of character indices, and frames the result as a pure operation-based CRDT ([@Sec:pure-op-crdt]) rather than an OT/CRDT hybrid. Diamond Types [@diamondtypes] shares the event-graph approach with Eg-walker and is the closest architectural relative to mydenicek among existing implementations, though it targets text editing.

json-joy [@jsonjoy] is an operation-based JSON CRDT that supports Patch and JSON-CRDT-Patch operations; it is closer to mydenicek in spirit (operations over JSON-like structures) but does not support path-based wildcard selectors or structural edits (rename, wrap). Grove [@grove2025] is a calculus for collaborative structure editing on abstract syntax trees using commutative operations. Webstrates [@klokmose2015webstrates] is a platform for shareable dynamic media that inspired the naming lineage: Webstrates, myWebstrates, Denicek, mydenicek.

### The for-each problem {#sec:foreach}

Weidner [@weidner2023foreach] identifies what he calls the *for-each problem*: operations that apply a mutation to every element in a range (such as "change the tag of every list item") miss elements inserted concurrently by other peers. The author proposes a dedicated CRDT for-each operation. This problem is directly relevant to mydenicek's wildcard selector (`speakers/*`). As discussed in [@Sec:wildcard-concurrent], the replay-based approach achieves the same "for-each-including-concurrent-insertions" semantics without a dedicated CRDT operation: the wildcard is expanded at replay time to include all elements that exist at that point, including those inserted concurrently.
