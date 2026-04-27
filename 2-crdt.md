# The mydenicek CRDT {#chap:implementation}

mydenicek is a pure operation-based CRDT for collaborative editing of tagged document trees. The replica state is a grow-only set of edit events; the document is computed by a deterministic *eval* function (`materialize`) that replays events in topological order, rewriting selectors through concurrent structural edits. [@Fig:data-flow] shows the data flow. This chapter describes the document model, the convergence argument, and the selector-rewriting rules that achieve intention preservation.

![Data flow in mydenicek. A user edit is prepared into a tagged Event, added to the PO-Log (a G-Set of events = the CRDT state), and synced to peers. The *eval* function (`materialize`) sorts events topologically, rewrites concurrent selectors, and applies each edit to produce the document.](img/data-flow.png){#fig:data-flow width=50%}

## Document model {#sec:doc-model}

Documents are modeled as tagged trees with four node types:

- **Record** --- a set of named fields, each containing a child node, plus a structural tag.
- **List** --- an ordered sequence of child nodes with a structural tag.
- **Primitive** --- a scalar value: string, number, or boolean.
- **Reference** --- a pointer to another node via a relative or absolute path.

Reference nodes are unusual in collaborative editing systems. In most CRDT-based systems (Automerge, Loro, json-joy), nodes reference each other via opaque unique IDs --- stable across moves and structural changes, but unable to express relative relationships like "my sibling at index 0." In mydenicek, references are *path-based* (`../0/source`), meaning they navigate the tree relative to their position. This enables patterns like formula nodes referencing sibling data, but requires OT to keep references valid when structural edits (rename, wrap) change the paths they traverse.

Nodes are addressed by *selectors* --- slash-separated paths that describe how to navigate the tree from the root. The selector `speakers/0/name` navigates to the `speakers` field, then to the first list item (index 0), then to the `name` field. Unless stated otherwise, examples in this thesis use selectors *relative to the document root*, without a leading `/`. A leading `/` is only significant in reference nodes (see `Reference` above), where it distinguishes absolute paths from paths relative to the reference's own position. Selectors support three special forms:

- **Wildcards** (`*`): `speakers/*` expands to all children of the `speakers` list. An edit targeting `speakers/*` is applied to every item.
- **Negative indices** (`-1`, `-2`): end-relative list addressing, added in mydenicek. `-1` means the last position (append for insert, last item for remove), `-2` means second-to-last, and so on. Resolved to absolute positions at replay time using a stored `listLength`.
- **Strict indices** (`!0`): `speakers/!0` refers to the item at index 0 *at the time of the edit*, also added in mydenicek. Unlike plain `0`, strict indices are not shifted by concurrent insertions --- they always refer to the original position. This is essential for the recording and replay mechanism described in [@Sec:replay].
- **Parent navigation** (`..`): used in references to navigate up the tree. `../../0/contact` goes up two levels, then navigates to `0/contact`.

Reference nodes (described as the fourth node type above) store their target as a selector path in a `$ref` field: `{$ref: "../0/source"}` means "navigate up one level from this reference node's position, then down to `0/source`." The `$ref` notation distinguishes references from ordinary record fields in the serialized JSON representation.

[@Tbl:selector-notation] summarizes the selector notation used throughout this thesis.

: Selector notation summary. {#tbl:selector-notation}

| Form | Example | Meaning |
|------|---------|---------|
| Field name | `speakers/0/name` | Navigate by field name or list index (root-relative) |
| Wildcard | `speakers/*` | Expand to all children of the target node |
| Negative index | `insert(items, -1, ...)` | End-relative: `-1` = last position, `-2` = second-to-last |
| Strict index | `speakers/!0` | Index at edit-creation time; not shifted by concurrent inserts |
| Parent (`..`) | `../../0/contact` | Navigate up the tree (used in `$ref` paths) |
| Absolute `$ref` | `$ref: "/speakers/0"` | Reference resolved from document root |
| Relative `$ref` | `$ref: "../0/source"` | Reference resolved from the reference node's own position |

## Event DAG {#sec:event-dag}

The event directed acyclic graph (DAG) is the core data structure of mydenicek. It is a grow-only, append-only structure --- events are immutable once created, and new events can only be added, never modified or removed. This makes the event set a G-Set (grow-only set), one of the simplest CRDTs: two peers that have received the same set of events will always produce the same document. Each edit creates an *event* containing:

- **EventId** --- a unique identifier `peer:seq`, where `peer` is the peer's string identifier and `seq` is a monotonically increasing sequence number.[^eventid] For example, `alice:3` is Alice's third event.
- **Parents** --- the set of event IDs that formed the *frontier* of the creating peer's DAG immediately before this event was appended. Equivalently, they are the most recent events the peer had seen. After the new event is inserted, those parents are no longer on the frontier --- the frontier collapses to this new event alone. An event with multiple parents therefore corresponds to the first edit after a sync that brought in another peer's branch, and is the merge point of the two branches.
- **Edit** --- the actual edit operation (add, delete, rename, set, insert, wrapRecord, etc.) with its target selector and arguments.
- **Vector clock** --- a map from peer ID to the highest sequence number seen from that peer. The vector clock enables causal ordering: event A *happens-before* event B if A's vector clock is dominated by B's. Two events are *concurrent* if neither dominates the other.

[^eventid]: In the implementation, `EventId` is serialized as a single string `"peer:seq"` for use as a map key.

Parents and vector clocksserve complementary roles. Parents define the direct edges of the DAG --- they are needed for topological sorting and for the sync protocol's `eventsSince(frontiers)` computation. Vector clocks are an optimization: they enable O(P) concurrency detection (where P is the number of peers) during `resolveAgainst`, which must classify every prior event as either a causal ancestor (skip) or concurrent (transform). Without them, the same information could be computed by traversing the DAG to test reachability, but at greater cost. For example, Alice's event with clock `{alice: 5, bob: 3}` and Bob's event with clock `{alice: 2, bob: 4}` are concurrent because neither clock dominates the other (`alice: 5 > 2` but `bob: 3 < 4`).


## Materialization {#sec:materialization}

To reconstruct the document from the event DAG, we perform *deterministic topological replay*:

1. **Order.** Compute a total order consistent with the causal partial order, using `EventId` lexicographic comparison as tie-breaker for concurrent events.
2. **Resolve and apply.** Starting from the initial document, apply each event's edit in order. Before applying, call `resolveAgainst`, which finds all previously applied *concurrent* edits and transforms the current edit's selector through each of them. Applied events are grouped by peer in a per-peer index; since sequence numbers are contiguous, the first concurrent event from peer Y is at index $V_E[Y] + 1$ --- an $O(1)$ lookup per peer. The concurrent events from all peers are then iterated in topological order, transforming the edit through each one.
3. **Conflicts.** If a transformed edit becomes invalid (e.g., it targets a node deleted by a concurrent edit), it becomes a *no-op conflict* --- recorded but not applied. The original event remains in the DAG (events are immutable).

Because the sort order and the selector-rewriting transformations are both deterministic, any two peers that have received the same set of events produce the same document. This is the strong eventual consistency guarantee, stated precisely in [@Sec:crdt-framing].

### Caching

Two optimizations avoid replaying from scratch on every call:

- **Linear extension cache.** When a new event's parents exactly match the current frontier (the common case during local editing), the event is a *linear extension* of the graph. In that case, `resolveAgainst` is a no-op (every prior is a causal ancestor), so the edit is applied directly to the cached document in O(1) amortized time.
- **Geometric checkpoint resumption.** When another peer's incoming event invalidates the linear cache, the materializer must rematerialize from scratch. During replay, it saves intermediate checkpoints at geometrically-spaced positions (after 1, 2, 4, 8, 16, ... events). On the next rematerialization, `findBestCheckpoint` looks for a checkpoint whose saved topological order is an exact *prefix* of the new topological order. A checkpoint is valid if and only if its prefix matches --- this is because `resolveAgainst` transforms each event through all prior concurrent events, so any event inserted in the middle of a checkpoint's order would invalidate the resolved edits after it. Geometric spacing ensures that short prefixes --- the common causal ancestors of the local and remote branches, whose relative order is stable across concurrent insertions --- are always captured. For a typical sync scenario where a long local history ($N$ events) receives a small concurrent branch ($B$ events), the checkpoint covers the shared causal prefix and only $B$ events need to be replayed, reducing the cost from $O(N^2)$ to $O(a \cdot B)$ where $a$ is the local branch length since the fork (derived in [@Sec:complexity]).

### Complexity {#sec:complexity}

The event DAG under the happens-before relation is a **partially ordered set** (poset). Events from the same peer are totally ordered by sequence number, forming a **chain**. Two events are **comparable** (one is an ancestor of the other) or **incomparable** (concurrent). We treat the number of peers $P$ as a constant and let $N$ be the total number of events and $D$ the number of document-tree nodes.

The materializer groups applied events by peer in a **per-peer index**. Since sequence numbers are contiguous, the first incomparable event from peer Y is at index $V_E[Y] + 1$ --- skipping all comparable predecessors in $O(1)$:

```
function materialize(events):
  order <- topologicalSort(events)          -- O(N log N)
  doc <- initialDocument
  peerIndex <- {} (peer -> [(event, edit, topoPos)])
  for i, E in order:                        -- N iterations
    concurrent <- []
    for each peer Y in peerIndex:            -- O(P) = O(1)
      start <- E.clock[Y] + 1                -- O(1) direct index
      concurrent.addAll(peerIndex[Y][start:])
    merge concurrent by topoPos              -- O(Ci) with P pointers
    edit <- E.edit
    for P in concurrent:                     -- Ci iterations
      edit <- transform(P.edit, edit)         -- O(1)
    apply(edit, doc)
    peerIndex[E.peer].append(E, edit, i)
  return doc
```

The per-event cost is $O(C_i)$, where $C_i$ is the number of incomparable predecessors. The total cost is $O(N + C_\text{total})$, where $C_\text{total} = \sum C_i$ is the total number of incomparable pairs in the poset. The cost is **output-sensitive**: it depends on the actual concurrency in the DAG.

#### Concurrency structure

$C_\text{total}$ has a closed form for common DAG shapes:

- **Chain** (fully sequential): $C_\text{total} = 0$.
- **Fork-and-merge** (common prefix, then two branches of lengths $a$ and $b$): every event in one branch is incomparable with every event in the other, so $C_\text{total} = a \cdot b$.
- **$m$-way fork** (branches $a_1, \ldots, a_m$): $C_\text{total} = \sum_{i < j} a_i \cdot a_j$.

**Lower bound.** The quadratic cost for concurrent branches is inherent to pairwise selector rewriting, not an implementation artifact. Each incomparable predecessor must be examined because the structural impact of a concurrent edit depends on its type and arguments, not only on the selector prefix. In the worst case --- all events targeting the same list --- every incomparable pair requires a transformation, giving $\Omega(C_\text{total})$. Systems that avoid this cost (such as Automerge and Loro) replace path-based selectors with unique opaque node IDs, so concurrent edits never need rewriting. mydenicek retains path-based selectors because they are essential to Denicek's programming model: wildcards, relative references, and programming by demonstration all rely on structural paths.

### mydenicek as a pure op-based CRDT {#sec:crdt-framing}

As described in [@Sec:pure-op-crdt], mydenicek is a *pure operation-based CRDT* [@baquero2017pureop]. The replica state is a grow-only set (G-Set) that stores the event DAG. The document is produced by `materialize` (described above) --- a pure function that takes the event DAG and returns the document tree. Convergence requires only that `materialize` is deterministic; the G-Set guarantees eventual agreement on the event set ([@Sec:sync]).

**Assumption (peer-ID uniqueness).** Every `EventId = (peer, seq)` produced across all replicas is globally unique, enforced at ingest.

**Theorem (deterministic eval).** If two replicas hold the same event set, `materialize` produces the same document on both.

**Proof sketch.** `materialize` is a pure function: it composes `topologicalOrder` (deterministic — `EventId` comparison is a strict total order, no iteration-order dependence), `resolveAgainst` (pure — sequential walk dispatching stateless class methods), and `apply` (pure — local mutations, no randomness). Given the same event set, each step produces the same result. $\square$

**Strong eventual consistency** follows: the G-Set ensures replicas eventually hold the same event set; deterministic `materialize` produces the same document. TP1/TP2 are not needed — the replay order is fixed by the DAG.

**Convergence vs. intention preservation.** Convergence follows from the G-Set and deterministic *eval*. The hard part is **intention preservation**: references must survive structural edits, wildcards must expand over concurrent inserts, indices must shift through concurrent modifications, and recorded edits must replay after schema evolution. These are design choices validated empirically ([@Sec:formative-examples]; [@Sec:property-tests]).

**Concurrent structural conflicts.** Several concurrent scenarios illustrate the resolution semantics.

*Concurrent renames of the same field.* Alice renames `name` -> `fullName`, Bob renames `name` -> `title`. The first rename in replay order succeeds. The second's source selector is transformed through the first (`name` becomes `fullName`), so it renames `fullName` -> `title`. The field ends up as `title` on both peers.

*Concurrent wraps of the same target.* Alice wraps `value` into a `formula` record, Bob wraps `value` into a `container` record. Both wraps succeed in sequence: the second wrap's selector is transformed through the first, producing a doubly-wrapped structure. Neither peer intended double nesting; this is a known compromise that preserves both edits.

*Concurrent indexed insert and remove.* Starting from `["a", "b", "c"]`, Alice inserts `"NEW"` at index 0, Bob removes index 0. With non-strict indices, OT shifts the remove's target past the insertion: the remove still targets `"a"` (now at index 1), and the insert lands at 0. Both replay orders converge to `["NEW", "b", "c"]`.

*Strict indices.* With `strict=true`, the index is not shifted by OT --- it refers to the position at replay time. A concurrent strict insert and strict remove at index 0 can cancel each other: if the insert replays first, the remove targets the *newly inserted* item, not the original. Non-strict indices provide better intent preservation for concurrent list modifications.

*Negative indices.* Non-strict negative indices (e.g., `-1` for append) are resolved to absolute positions using a stored `listLength` and then shifted like positive indices. Strict negative indices are resolved at replay time and not shifted.

*Double remove.* When both peers remove the same index concurrently, the second becomes a no-op conflict.

## Edit types and selector transformation rules {#sec:edit-types}

The system supports 11 edit types: record operations (`RecordAdd`, `RecordDelete`, `RecordRename`), list operations (`ListInsert`, `ListRemove`, `ListReorder`), structural operations (`UpdateTag`, `WrapRecord`, `WrapList`), `CopyEdit` (subtree copy with managed mirroring), and `ApplyPrimitiveEdit` (extensible custom edits). Three additional inverse types (`UnwrapRecord`, `UnwrapList`, `RestoreSnapshot`) are produced only by `computeInverse()` for undo.

### Selector rewriting rules {#sec:selector-rules}

Each structural edit implements a `transformSelector` method that rewrites a concurrent edit's selector through its structural effect. [@Tbl:selector-rules] summarizes the rules.

: Selector rewriting rules. Each structural edit transforms concurrent selectors. {#tbl:selector-rules}

+--------------------+------------------------------------------+----------------------------------------------+
| Edit               | Rule                                     | Example                                      |
+====================+==========================================+==============================================+
| Rename a to b      | a/… becomes b/…                          | speakers/0/name becomes talks/0/name         |
+--------------------+------------------------------------------+----------------------------------------------+
| WrapRecord(f)      | a/… becomes a/f/…                        | x/value becomes x/inner/value                |
+--------------------+------------------------------------------+----------------------------------------------+
| WrapList           | a/… becomes a/\*/…                       | x/data becomes x/\*/data                     |
+--------------------+------------------------------------------+----------------------------------------------+
| Delete             | a/… removed                              | concurrent edit becomes no-op                |
+--------------------+------------------------------------------+----------------------------------------------+
| Insert at i        | indices $\geq$ i shift +1                | items/3 becomes items/4                      |
+--------------------+------------------------------------------+----------------------------------------------+
| Remove at i        | index i removed; indices $>$ i shift −1  | items/3 becomes items/2                      |
+--------------------+------------------------------------------+----------------------------------------------+
| Reorder(f, t)      | f becomes t; range shifts                | items/1 becomes items/3                      |
+--------------------+------------------------------------------+----------------------------------------------+

Negative indices are resolved to absolute positions using a stored `listLength` before shifting. Strict indices (`strict=true`) shift concurrent selectors but are not themselves shifted by concurrent edits.

**Composition.** Transformations compose sequentially. If Alice renames `speakers` -> `talks`, Bob wraps each item in a `<tr>` record, and Carol edits `speakers/0/name`, then Carol's selector is first transformed through Alice's rename (`talks/0/name`), then through Bob's wrap (`talks/0/value/name`). Each transformation is local --- it examines only whether the prior edit's target overlaps with the selector being transformed.

### Two-level polymorphic design {#sec:ot-architecture}

A naive transformation implementation requires a rule for every pair of edit types --- $n^2$ rules for $n$ edit types. With 11 edit types, that would be 121 hand-written rules. mydenicek avoids this through a two-level object-oriented design, shown in [@Fig:edit-class-diagram].

![Edit class hierarchy with two-level OT. All edit types extend `Edit` directly. Structural edits (blue) override `transformSelector` and optionally `transformLaterConcurrentEdit`. Data edits (green) return the identity transformation. CopyEdit (red) has two selectors and mirrors concurrent edits. Insert edits (orange) carry a payload and override virtual methods (`rewriteInsertedNode`, `applyListIndexShift`, `mapInsertedPayload`) for generic OT dispatch.](img/edit-class-diagram.png){#fig:edit-class-diagram width=75%}

The design rests on two key methods in the `Edit` base class:

- **`transformSelector(sel)`** --- given another edit's selector, returns the transformed selector after this edit's structural effect. For example, a rename from `speakers` to `talks` transforms the selector `speakers/0/name` into `talks/0/name`. Non-structural edits (add, set, etc.) return the selector unchanged. This corresponds to the "transform matching references" operation in the original Denicek [@petricek2025denicek, Appendix B2].
- **`transformLaterConcurrentEdit(concurrent)`** --- given a concurrent edit that will replay *after* this one, returns a transformed version of the concurrent edit. The default implementation simply calls `concurrent.transform(this)`, which rewrites the concurrent edit's target selector through `transformSelector`. This handles the vast majority of edit pairs.

**Why this avoids $n^2$ rules.** The default `transformLaterConcurrentEdit` delegates to `transformSelector`, which each edit type implements once. A `RenameFieldEdit` knows how to transform *any* selector (not just selectors from specific edit types), so one method handles all pairs involving rename. This gives $n$ methods total instead of $n^2$. No `instanceof` checks are used for OT dispatch: list index shifting is handled by two complementary virtual methods (`applyListIndexShift` for the forward direction, `listIndexEffect` for the reverse), and `CopyEdit` avoids double-wrapping `CompositeEdit` via a `skipMirroring` flag rather than a type test.

**When the default is insufficient.** Selector rewriting alone does not handle cases where a structural edit must modify the *payload* of a concurrent list insert (this corresponds to the "apply to newly added" operation in the original Denicek [@petricek2025denicek, Appendix B1]). Consider: `updateTag("items/*", "tr")` is concurrent with `insert("items", -1, {$tag: "li", ...})`. The default would only transform the insert's target selector (which is `items`, unchanged by the tag edit). But the *inserted node* should also change its tag from `<li>` to `<tr>`. To handle this, structural edits call `concurrent.rewriteInsertedNode(target, rewriteFn)` --- a virtual method on `Edit` that is overridden by `ListInsertEdit` to modify its inserted payload. The caller provides the rewrite logic; the callee provides the payload. This avoids `instanceof` checks: structural edits do not need to know the concrete type of the concurrent edit.

Similarly, list edits that shift indices (insert shifts by +1, remove shifts by −1) use `concurrent.applyListIndexShift(target, threshold, delta)` --- another virtual method where each list edit type knows how to shift its own indices. `ListInsertAtEdit` shifts its single index, `ListRemoveAtEdit` shifts and detects same-position collisions (returning a no-op), and `ListReorderEdit` shifts both its `from` and `to` indices. This replaces what would otherwise be $3 \times 3 = 9$ pairwise `instanceof` checks with three single-method overrides.

### CopyEdit and mirroring {#sec:copy-edit}

`CopyEdit` extends `Edit` directly because it has two selectors --- `target` and `source` --- both of which must be checked for removal. If either is deleted by a concurrent edit, the copy becomes a no-op. More importantly, `CopyEdit` *mirrors* concurrent edits: when a concurrent edit modifies the source, the same modification is replicated onto the copy target. This is implemented by `transformLaterConcurrentEdit` wrapping the concurrent edit in a `CompositeEdit` that applies it to both the original target and the mirrored copy target. `CompositeEdit` is a proper `Edit` subclass that overrides all key methods (`apply`, `transform`, `transformLaterConcurrentEdit`, `computeInverse`) by delegating to its sub-edits internally. No other edit type needs to know about it --- it is transparent to the rest of the OT pipeline.

This mirroring mechanism is different from the concurrent insert payload rewriting described in [@Sec:ot-architecture]. Payload rewriting modifies *what gets inserted* --- the inserted node's content is changed before it enters the document. CopyEdit mirroring duplicates *where an edit applies* --- the concurrent edit itself is replicated to a second target. The two cannot be unified because they operate at different levels: one modifies a payload, the other duplicates an edit. The original Denicek takes a different approach that avoids this distinction: instead of modifying payloads, it copies the *edit sequence* and replays it on the copy target [@petricek2025denicek, Appendix B1]. That design uses a single mechanism for both concurrent inserts and copies, at the cost of tracking which edits to replay.

### Wildcard edits and concurrent insertions {#sec:wildcard-concurrent}

A notable property of the replay-based *eval* is how wildcard edits interact with concurrent insertions, illustrated in [@Fig:wildcard-diamond]. *This is a deliberate design choice*, not a consequence of the convergence proof: both "wildcard includes concurrent inserts" and "wildcard does not include concurrent inserts" produce a deterministic *eval* and therefore both yield strong eventual consistency. We choose the former because wildcard edits are a core feature of Denicek's end-user programming model --- users apply structural transformations to all items in a list (e.g., refactoring a conference list into a table, as demonstrated in [@Sec:conf-concurrent]). When one user refactors the list while another concurrently adds new items, the new items should also be refactored.

When Alice applies `updateTag("speakers/*", "tr")` --- changing the tag of every item in the list --- and Bob concurrently inserts a new item via `insert("speakers", -1, ...)`, the result is that Alice's tag update also affects Bob's newly inserted item.

![Wildcard edit and concurrent insertion. Alice's wildcard `updateTag` and Bob's `insert` are concurrent. After merge, Bob's inserted `<li> C` becomes `<tr> C` --- the wildcard edit affects the concurrent insertion.](img/wildcard-diamond.png){#fig:wildcard-diamond width=55%}

This holds regardless of replay order, but the mechanism differs in each case:

- **Insert first** (Bob's `insert` is replayed before Alice's wildcard edit): Bob's new item is added to the list. When Alice's `updateTag("speakers/*", "tr")` is then replayed, the wildcard `*` expands to include *all items that exist at the point of replay* --- including Bob's concurrent insertion. The tag update naturally applies to the new item without any transformation needed.
- **Edit first** (Alice's wildcard edit is replayed before Bob's `insert`): Alice's `updateTag` is applied to the existing items. When Bob's `insert` is then resolved against Alice's preceding wildcard edit, the selector-rewriting step modifies the inserted item: instead of inserting a `<li>` item, the transformed insert produces a `<tr>` item. This works because materialization replays events in a deterministic order --- when Bob's insert comes after Alice's wildcard edit in that order, the insert is transformed to be consistent with the already-applied edit.

This semantics is uncommon in CRDTs. In most CRDT-based systems, an operation only affects the items that existed at the time the operation was created. Items inserted concurrently by other peers are not affected. Weidner [@weidner2023foreach] describes this as the *for-each* problem and proposes a dedicated CRDT operation to address it. In mydenicek, the replay-based *eval* naturally achieves the "for-each-including-concurrent-additions" semantics because the wildcard is expanded at replay time, not at creation time --- no special for-each CRDT is needed.



