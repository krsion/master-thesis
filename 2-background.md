# Background {#chap:background}

This chapter introduces the concepts and systems that form the foundation of this thesis. We describe the Denicek system, explain Operational Transformation, introduce causality and vector clocks, then discuss CRDTs and the Eg-walker algorithm that inspired our approach.

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

OT is notoriously difficult to get right. Correctness in the decentralized setting requires satisfying two *transformation properties* formalized by Ressel et al. [@ressel1996integrating]. TP1 states that for concurrent operations $a$ and $b$, applying $a$ then $T(b, a)$ must reach the same state as applying $b$ then $T(a, b)$. TP2 states that transforming a third operation $c$ through both $a$ and $b$ must yield the same result regardless of which of $a$ or $b$ is transformed through first: $T(T(c, a), T(b, a)) = T(T(c, b), T(a, b))$. Several published OT algorithms were later proven to violate TP2, causing peers to diverge under specific interleaving patterns; Imine et al.~[@imine2003proving] give an automated-reasoning framework that exhibits concrete counter-examples for the canonical dOPT algorithm. Subsequent OT variants --- SOCT2 and SOCT4 [@suleiman1998soct], the Tombstone Transformation Framework (TTF) [@oster2006ttf], and Jupiter [@nichols1995jupiter] --- differ in whether they require TP2 (peer-to-peer settings), only TP1 (centralized serializer), or neither (transformation-less approaches). The number of transformation rules grows with each new edit type, and the interactions between rules are hard to reason about exhaustively. This fragility is one of the main motivations for exploring CRDT-based alternatives, and it is also why mydenicek sidesteps TP1/TP2 entirely by using a single deterministic replay order (see [@Sec:event-dag]).

Sun et al.~[@sun1998achieving] decompose OT correctness into the **CCI model** with three independent properties: **convergence** (all replicas eventually reach the same state), **causality preservation** (operations are applied in an order consistent with the happens-before relation), and **intention preservation** (the effect visible to each user matches the intent of the operation they issued). TP1/TP2 are sufficient conditions for convergence under peer-local OT; intention preservation is a user-facing property that depends on the specific transformation rules and cannot be derived from TP1/TP2 alone. This thesis proves convergence for mydenicek in [@Sec:crdt-framing], relies on causal delivery for causality preservation ([@Sec:causal-delivery]), and validates intention preservation only empirically through the formative examples of [@Chap:formative].

The Jupiter algorithm [@nichols1995jupiter], used in Google Docs, simplifies OT by requiring a central server that serializes all operations. This makes transformation simpler (only two-way transforms are needed) but introduces a single point of failure and prevents peer-to-peer collaboration.

## Causality {#sec:causality}

A fundamental concept in distributed systems is *causality* --- the relationship between events produced by different peers. Lamport's *happens-before* relation [@lamport1978] defines a partial order over events in a distributed system:

> **Definition (happens-before).** The *happens-before* relation, written $a \to b$, is the smallest relation satisfying:
>
> 1. If $a$ and $b$ were produced by the same peer, and $a$ was produced before $b$, then $a \to b$.
> 2. If $a = \text{send}(m)$ and $b = \text{receive}(m)$ for some message $m$, then $a \to b$.
> 3. If $a \to c$ and $c \to b$, then $a \to b$ (transitivity).
>
> Two events $a$ and $b$ are *concurrent*, written $a \parallel b$, if neither $a \to b$ nor $b \to a$.

[@Fig:causality] illustrates these relationships in an event graph.

![Causality in a distributed system. Alice creates two events locally. Bob's first event (bob:0) is the receipt of Alice's message, establishing alice:0 $\to$ alice:1 $\to$ bob:0. Note that alice:1 happens-before bob:0 despite the higher sequence number --- cross-peer causality is determined by messages, not by numbering.](img/causality.png){#fig:causality width=55%}

Happens-before is defined abstractly, but an efficient implementation requires a concrete mechanism for detecting it. *Vector clocks* [@mattern1989virtual; @fidge1988timestamps] provide this mechanism.

> **Definition (vector clock).** A vector clock $V$ is a map from peer ID to a non-negative integer. Each event $a$ carries a vector clock $V_a$ where $V_a[p]$ is the highest sequence number from peer $p$ that is a causal ancestor of $a$ (including $a$ itself if $a$ was produced by $p$). Vector clocks are updated as follows:
>
> - **Local event.** When peer $p$ creates an event with sequence number $n$: $V[p] = n$, all other entries unchanged.
> - **Receive event.** When peer $p$ receives a message carrying vector clock $V_m$ and creates event with sequence number $n$: $V[q] = \max(V_{\text{local}}[q], V_m[q])$ for all peers $q \neq p$, and $V[p] = n$.

Vector clocks characterize the happens-before relation:

> $a \to b$ if and only if $V_a[p] \leq V_b[p]$ for all peers $p$, and $V_a[q] < V_b[q]$ for at least one peer $q$.
>
> $a \parallel b$ if and only if neither $a \to b$ nor $b \to a$.

This allows concurrency detection in O(P) time (where P is the number of peers) by comparing two vectors, without traversing the event graph.

### Event DAG

Causal relationships between events can be represented as a *directed acyclic graph* (DAG). Each event is a node, and a directed edge from event $a$ to event $b$ means $a$ directly caused $b$ (i.e., $b$ lists $a$ as a parent). The graph is acyclic because causality cannot be circular --- an event cannot transitively depend on itself, since each event's vector clock strictly advances from its parents.

The event DAG provides a natural data structure for storing the history of a collaborative editing session. Each peer appends new events to the DAG, and synchronization consists of exchanging missing events between peers. The edges encode the causal structure, enabling deterministic replay.

### Frontier

The *frontier* is the set of events with no descendants --- the "tips" of the DAG. [@Fig:frontier] shows a frontier with two events from different peers.

![Frontier of an event DAG. Events `alice:2` and `bob:0` are both frontier events --- neither has a descendant. A new event created by either peer will have both as parents.](img/frontier.png){#fig:frontier width=55%}

A frontier implicitly represents the entire causal history beneath it --- all ancestors of the frontier events are included. This makes frontiers extremely compact: regardless of how many peers have contributed or how long the editing history is, the frontier typically contains just one or two event IDs. By contrast, a vector clock grows linearly with the number of peers.

However, frontiers require access to the event history to be useful. Given only a frontier, a peer cannot determine which events are included without having the DAG to traverse. Vector clocks are self-contained --- a peer can compare two vector clocks without any additional data. This leads to a natural division of roles:

- **Vector clocks** are used for concurrency detection (comparing two events requires no DAG traversal).
- **Frontiers** (explicit parent pointers) represent the DAG structure directly --- each event stores the frontier at its creation time as its parents. This makes DAG traversal, topological sorting, and sync (`eventsSince`) straightforward. The same structure could in principle be reconstructed from vector clocks alone, but this would require recomputing the transitive reduction of the happens-before relation.

When a peer creates a new event, the current frontier becomes the event's parents. After both peers sync and one makes a new edit, the resulting event has *multiple parents* --- one from each branch --- merging the frontier back to a single point. This is analogous to a merge commit in version control.

## Reliable causal delivery {#sec:causal-delivery}

Network messages can *arrive* (be received) in any order --- the network provides no ordering guarantees. *Causal delivery* means that messages are *delivered to the application* in an order consistent with causality: if event $a$ causally precedes event $b$, then $a$ must be delivered before $b$. Concurrent events may be delivered in any order.

In mydenicek, causal delivery is implemented with a buffer: when a message arrives whose causal dependencies have not yet been delivered, it is held until those dependencies arrive. Parent pointers are used to check whether all dependencies are satisfied --- the event graph's `ingestEvents` method buffers out-of-order events and flushes them in causal order once their parent events have been inserted (see [@Sec:sync]).

*Reliability* --- ensuring that no messages are permanently lost --- is a separate concern. In mydenicek, this is handled by frontier-based catch-up: on each sync round, a peer sends its current frontier, and the other peer responds with all events the sender is missing (computed via `eventsSince`). If a message is lost, the sender's frontier does not advance, and the missing events are resent on the next round. This is simple but requires the server to retain the full event history. mydenicek does not use virtual synchrony or any of the more sophisticated reliable broadcast protocols described below; the frontier-based catch-up mechanism is sufficient for the current use cases where the sync server retains the full event history. More efficient approaches exist: the Trans protocol [@melliarsmith1990trans] provides reliable broadcast over local area networks, and Transis [@amir1992transis] extends it with *virtual synchrony* --- dynamic group membership that handles peers connecting and disconnecting while maintaining consistent message delivery guarantees. Tanenbaum and Van Steen [@tanenbaum2017distributed] provide a comprehensive overview of these and other reliable broadcast protocols.

## Conflict-free Replicated Data Types {#sec:crdts}

CRDTs [@shapiro2011crdt] are data structures designed for distributed systems where multiple replicas can be modified independently and merged without conflicts. The key guarantee is *strong eventual consistency*: any two replicas that have received the same set of updates will be in the same state, regardless of the order in which updates were delivered. Preguiça [@preguica2018crdts] provides a comprehensive overview of CRDTs and their variants.

CRDTs come in two main flavors:

- **State-based CRDTs** (CvRDTs) require the set of possible states to form a *join semilattice* --- a partially ordered set where any two states have a least upper bound (join). Replicas periodically send their full state to each other, and the merge operation computes the join. This works over unreliable channels since states can always be re-merged, but sending the full state can be expensive for large data structures.
- **Operation-based CRDTs** (CmRDTs) propagate individual update operations rather than full states. Concurrent operations must be commutative so that applying them in either order produces the same result. This is more bandwidth-efficient, but requires a reliable causal delivery layer as described in [@Sec:causal-delivery].

A hybrid approach, *delta-state CRDTs*, sends only the part of the state that changed (the "delta") rather than the full state. Deltas are joinable like full states (so they tolerate message loss and reordering) but are small like operations (so they are bandwidth-efficient).

*Pure operation-based CRDTs* [@baquero2017pureop] lift the commutativity requirement by reifying the entire operation history as the replica state: the state is the set of all delivered operations (itself a G-Set), and the observable value is computed on demand by a pure function over that set --- typically by replaying the operations in a total order derived from their causal metadata. Because the set of operations trivially satisfies the state-based CRDT axioms (union is associative, commutative, and idempotent) and the view function is pure, strong eventual consistency follows from two replicas having received the same set of operations. This thesis adopts that framing for mydenicek (see [@Sec:event-dag]). The Baquero framework assumes causal delivery and represents the state as a *PO-Log* (partially ordered log with stability markers, pruned as operations become causally stable); mydenicek stores the full event DAG including explicit parent pointers, which is strictly richer than a PO-Log and allows the view function to re-derive any prefix of the history, at the cost of unbounded state growth without compaction.

Common CRDT building blocks relevant to this thesis include:

- **G-Set** (grow-only set): elements can be added but never removed. Merging two G-Sets is simply their union.
- **LWW-Register** (last-writer-wins register): a single value where concurrent writes are resolved by a deterministic ordering (typically by timestamp or logical clock).
- **OR-Set** (observed-remove set): elements can be added and removed. Concurrent add and remove of the same element are resolved in favor of the add.

For collaborative editing of tree-structured documents, Kleppmann and Beresford [@kleppmann2017crdt] proposed a JSON CRDT that uses unique identifiers for each node and supports insert, delete, and move operations. This work identified the *move operation problem*: in a flat JSON structure without native move support, moving a node requires deleting it from one location and inserting it at another --- two separate operations that can interleave with concurrent edits, potentially losing data. For collaborative *rich text* (text with formatting spans and block structure), Peritext [@litt2022peritext] extends character-level CRDTs with mark operations whose semantics tolerate concurrent insertions and deletions within the affected range --- a problem closely related to the "wildcard affects concurrent inserts" behavior we describe in [@Sec:wildcard-concurrent].

## Eg-walker {#sec:egwalker}

Eg-walker [@gentle2025egwalker] is a collaborative text editing algorithm that takes the best of both OT and CRDTs. The paper observes a fundamental trade-off in existing approaches:

- **OT** is simple and memory-efficient --- operations use plain integer indices, and the document state is just the text itself with no per-character metadata. However, merging long-diverged branches (e.g., after offline editing) requires transforming each operation against all concurrent operations, which is O(n²) in decentralized peer-to-peer settings (where TP2 is needed) and can take hours for large editing histories. Centralized approaches like Jupiter reduce this to O(n) by serializing through a single server.
- **CRDTs** handle arbitrarily diverged branches efficiently because each character carries a unique identifier that is unaffected by concurrent operations. In early sequence CRDTs (Yjs, Automerge text, pre-Fugue designs), these identifiers and the tombstones for deleted characters had to be loaded eagerly into memory whenever the document was opened, with a reported overhead of roughly an order of magnitude over plain text in the steady state. More recent designs (Fugue [@weidner2023fugue], Loro's Rope, Diamond Types) substantially reduce this overhead through compact run-length encodings, but some per-character structure is still needed to support arbitrary concurrent merges.

Eg-walker overcomes this trade-off by storing operations in a *causal event graph* --- a directed acyclic graph where each event records its causal dependencies. In the common case of sequential (non-concurrent) editing, operations are applied directly using plain indices, like OT --- no per-character metadata is needed. Only when the algorithm encounters concurrent events (a fork in the event graph) does it temporarily build the CRDT-style state needed to merge them. After the concurrent region is resolved, the CRDT state is discarded.

The key insight is that OT transformation does not need to happen at the time an operation is received. Instead, all operations are stored in the event graph, and when the document needs to be materialized, the operations are replayed in a deterministic topological order with transformations applied locally. This avoids the need for a central server (the event graph can be merged peer-to-peer) while keeping the simplicity of index-based operations in the steady state.

Eg-walker was designed for text editing (character insertions and deletions). This thesis takes two ideas from it --- storing every operation in a causal event graph, and materializing the document by deterministic topological replay --- and applies them to tree-structured documents, where selectors replace character indices and structural edit rewrites (rename, wrap, delete) replace character-level insert/delete transforms. We do **not** adopt Eg-walker's mode-switching optimization that temporarily builds CRDT-style state only in concurrent regions: mydenicek always replays the full event history, which keeps the implementation simple at the cost of performance on long-diverged histories (discussed in [@Chap:evaluation]). Conversely, the design is explicitly framed as a *pure operation-based CRDT* (see [@Sec:crdts]), whereas Eg-walker is presented as an OT/CRDT hybrid optimized for text.

## Related systems {#sec:related}

Several existing systems and libraries are relevant to this thesis. Automerge [@automerge] and Loro [@loro] are CRDT libraries that we evaluate in detail in [@Chap:journey] as potential backends for Denicek. Yjs [@yjs] is the most widely deployed CRDT library; it implements the YATA algorithm for sequences and provides shared types (YMap, YArray, YText, YXmlFragment) that can represent tree structures. Yjs was not evaluated as a separate empirical attempt because it shares the same fundamental limitations as Automerge for Denicek's use case: it lacks atomic move operations (YArray supports insert and delete but not move), uses opaque client-ID-based addressing rather than path-based selectors, and does not provide a native tree CRDT --- tree structures must be emulated with nested shared types whose concurrent moves suffer the same two-step remove-and-insert problem described for Automerge in [@Sec:concurrent-wrap]. Since the wrap problem was what motivated the transition from Automerge to Loro, Yjs would have hit the same barrier. json-joy [@jsonjoy] is an operation-based JSON CRDT that supports Patch and JSON-CRDT-Patch operations; it is closer to mydenicek in spirit (operations over JSON-like structures) but does not support path-based wildcard selectors or the structural edits (rename, wrap) that Denicek requires. Diamond Types [@diamondtypes] shares the event-graph approach with Eg-walker (one of its authors is the same) and uses run-length encoding for compact storage; it targets text editing rather than tree structures, but its event-graph design is the closest architectural relative to mydenicek among existing implementations.

Grove [@grove2025] is a calculus for collaborative structure editing that operates on abstract syntax trees. It models all edits as commutative operations (a CmRDT), eliminating patch synthesis and three-way merge. While Grove targets collaborative code editing rather than document-oriented end-user programming, it shares the goal of conflict-free concurrent editing on tree structures. Webstrates [@klokmose2015webstrates] is a platform for shareable dynamic media that inspired the naming lineage: Webstrates, myWebstrates, Denicek, mydenicek.

### The for-each problem {#sec:foreach}

Weidner [@weidner2023foreach] identifies what he calls the *for-each problem*: operations that apply a mutation to every element in a range (such as "change the tag of every list item") miss elements inserted concurrently by other peers. The author proposes a dedicated CRDT for-each operation. This problem is directly relevant to mydenicek's wildcard selector (`speakers/*`). As discussed in [@Sec:wildcard-concurrent], the replay-based approach achieves the same "for-each-including-concurrent-insertions" semantics without a dedicated CRDT operation: the wildcard is expanded at replay time to include all elements that exist at that point, including those inserted concurrently.
