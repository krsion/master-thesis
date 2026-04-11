# Journey: Automerge, Loro, Custom {#chap:journey}

This chapter describes the iterative process of finding the right collaborative editing approach for Denicek. We started with Automerge, moved to Loro when we discovered fundamental limitations with move operations, and ultimately built a custom OT-based event DAG when Loro's opaque ID system proved incompatible with Denicek's path-based programming model. Each transition was motivated by concrete problems discovered during implementation.

## Attempt 1: Automerge {#sec:automerge}

Automerge [@automerge] is a widely-used CRDT library developed by Ink & Switch [@inkandswitch], a research lab where Martin Kleppmann is a key contributor. It provides JSON-like data structures --- maps, lists, text, and counters --- with automatic conflict resolution. It was the natural first choice: the Ink & Switch team has authored many of the foundational papers on local-first software and CRDTs that this thesis builds upon.

Automerge's API is designed so that developers do not need to understand CRDTs. The programmer simply edits a JSON-like document through a `change()` callback, and Automerge handles conflict resolution, history tracking, and synchronization internally. With the `automerge-repo`\footnote{\url{https://github.com/automerge/automerge-repo}} and `@automerge/automerge-react`\footnote{\url{https://www.npmjs.com/package/@automerge/automerge-react}} packages, syncing a document between peers requires just a few lines of code --- the React hook re-renders automatically when remote changes arrive. This low barrier to entry made Automerge an attractive starting point --- it is designed for developers who want collaborative editing without investing deeply in CRDT theory.

### Internal representation

To represent Denicek's tagged document trees in Automerge, we used a *flat map* architecture. Each node was stored as an entry in a dictionary (`Record<string, Node>`), identified by a unique string ID. Parent-child relationships were stored separately as `children` arrays containing child IDs:

```json
{
  "root": "n1",
  "nodes": {
    "n1": { "kind": "element", "tag": "div",
            "children": ["n2", "n3"] },
    "n2": { "kind": "element", "tag": "ul",
            "children": [] },
    "n3": { "kind": "value", "value": "Hello" }
  }
}
```

This flat map design was necessary because Automerge does not support native tree structures with move operations. A node's data (tag, attributes, value) lives in the `nodes` dictionary, while the ordering of children lives in the parent's `children` array. To "move" a node --- for example, to wrap it in a new parent --- we had to remove the node's ID from one `children` array and insert it into another. These are two separate Automerge operations, not an atomic move.

### The concurrent wrap problem {#sec:concurrent-wrap}

The lack of atomic move operations led to a fundamental problem with the *wrap* edit. Wrapping is one of Denicek's core structural operations: it creates a new parent element and moves an existing node into it. In the flat map representation, wrapping a node `li1` in a new `ul` element requires three steps:

1. Create a new node `wrapper` in the `nodes` dictionary with tag `ul`
2. Remove `"li1"` from the original parent's `children` array
3. Add `"li1"` to `wrapper`'s `children` array

When two peers concurrently wrap the same node, both execute these three steps independently, as shown in [@Fig:concurrent-wrap]. After merging:

![The concurrent wrap problem in Automerge. Both Alice and Bob wrap the same node, resulting in the node appearing under two parents.](img/concurrent-wrap.png){#fig:concurrent-wrap width=85%}

- Both peers created a wrapper node. We used a deterministic ID scheme (`wrapper-${wrappedNodeId}`) so that both peers create the "same" wrapper, and Automerge's LWW resolution picks one tag.
- Both peers removed `"li1"` from the original parent --- this converges correctly.
- Both peers added `"li1"` to the wrapper's `children` --- but if the wrappers are different (because the deterministic ID scheme failed, or the wraps target different parent types), the node ends up referenced from *two parents*, breaking the tree invariant that each node has exactly one parent.

The deterministic ID workaround was fragile: it did not scale to nested wraps, and any mismatch in the wrapper creation logic would produce an inconsistent tree. Automatic cleanup of duplicate parent references is not possible either --- a node appearing in two `children` arrays is *observationally indistinguishable* from an intentional structure where the user added the same reference to two lists. Any cleanup algorithm would risk deleting legitimate user data.

These problems motivated the move to Loro, which provides a native movable tree CRDT.

## Attempt 2: Loro {#sec:loro}

Loro [@loro] is a newer CRDT library that implements the latest research in collaborative data structures, including a *movable tree CRDT* [@kleppmann2021move] that supports atomic move operations and the *Fugue* algorithm [@weidner2023fugue] for text editing. It solved the concurrent wrap problem completely: moving a node from one parent to another is a single atomic operation, and concurrent moves are resolved deterministically.

### Advantages

Loro addressed the three main problems we had with Automerge:

- **Atomic move.** `LoroTree` supports native move operations, solving the concurrent wrap problem from Automerge. Concurrent moves to different parents are resolved by Last-Writer-Wins, and the node always ends up under exactly one parent.
- **Rich data model.** Loro provides a movable tree [@kleppmann2021move], rich text (Fugue algorithm [@weidner2023fugue]), maps, and lists --- all with well-defined concurrent semantics.
- **Good developer experience.** Well-documented API with TypeScript bindings.

### The retargeting problem {#sec:retargeting}

Despite solving the structural issues, Loro proved incompatible with Denicek's *programming by demonstration* model. The problem is in how recorded edits reference nodes.

In Denicek, users record edits and replay them. A recorded edit might say: "push a new item to the speakers list, then copy the value from the input field into the new item." The copy operation needs a *relative reference* --- it refers to `../input/value`, meaning "the input field that is a sibling of the list I just pushed to."

Loro uses opaque node IDs. A recorded edit would reference `nodeId_abc123` --- the specific ID of the input field at recording time. This works for simple replay, but breaks when the document structure changes between recording and replay.

Consider the conference table example from [@Chap:formative]. Alice records a sequence of edits on the first row of a speakers table:

1. `wrapRecord /speakers/0/contact` --- wraps the contact string in a `split-first` formula node
2. `pushBack /speakers/0` --- adds a second table cell with a `split-rest` formula that references `../../0/contact/source`

The `split-rest` formula uses a relative path (`../../0/contact/source`) to navigate from the second cell back to the first cell's wrapped contact value. When this edit sequence is replayed on a different row, the relative path still navigates correctly --- it always points to the first cell of *the current row*.

With Loro's opaque IDs, the reference would point to `nodeId_abc123` --- the specific node from row 0. Replaying on row 1 would still reference row 0's data, producing incorrect results. Even worse, after the `wrapRecord` operation, the original contact value moved one level deeper in the tree (it became the `source` field of the formula node). Loro's ID still points to the formula node, not to the `source` child where the actual value now lives.

This is not a bug in Loro --- it is a fundamental mismatch between ID-based and path-based addressing, illustrated in [@Fig:retargeting]. Denicek's programming model requires paths that can be *retargeted* through structural changes, and Loro's design does not support this.

![The retargeting problem. Loro's ID-based reference points to the original node (wrong after wrap). mydenicek's relative path navigates correctly from the current position.](img/retargeting.png){#fig:retargeting width=90%}

### Why not add path OT on top of Loro? {#sec:why-not-layer}

A natural question is: why not keep Loro for the CRDT layer and add a path transformation layer on top? We considered this approach but rejected it for a key reason: it would create *two conflict resolution layers* that interact in complex ways.

Loro resolves conflicts using its internal CRDT semantics --- LWW for map values, movable tree for structure. A path OT layer would resolve conflicts by transforming selector paths. The interactions between these two layers would be hard to reason about and to debug: when Loro resolves a concurrent structural change one way, the path layer might expect a different resolution, leading to subtle inconsistencies.

Instead, we chose to build a single coherent system where path-based selectors are the native addressing mode and OT operates directly on them. This eliminates the translation layer and gives us full control over conflict resolution semantics.

## The Custom Approach {#sec:custom}

Inspired by Eg-walker [@gentle2025egwalker], we built a custom OT-based event DAG that combines the robustness of CRDTs (peer-to-peer sync without a central server) with the simplicity of OT (path-based addressing, no per-node metadata).

The key design decisions are:

- **Event DAG as CRDT.** All edits are stored as immutable events in a causal directed acyclic graph. The event set is a grow-only set (G-Set) --- the simplest CRDT. Two peers that have received the same set of events will produce the same document.
- **Deterministic topological replay.** To materialize the document, events are sorted in deterministic topological order (using Kahn's algorithm with `EventId` tie-breaking) and replayed against the initial document. Each edit is transformed against previously materialized concurrent edits using hand-written OT rules.
- **Path-based selectors.** All operations use slash-separated selector paths, matching Denicek's native addressing. Wildcards, relative paths, and strict indices are first-class.
- **Zero external dependencies.** The core engine is pure TypeScript with no runtime dependencies, making it portable across Deno, Node.js, and browser environments.

The following chapter describes the implementation in detail.
