# Implementation {#chap:implementation}

This chapter describes the architecture and implementation of mydenicek --- a collaborative editing engine for tagged document trees. As motivated in [@Chap:journey], the engine uses operational transformation on an event DAG rather than layering on top of an existing CRDT library. The implementation is a Deno monorepo published on JSR as `@mydenicek/core`, `@mydenicek/react`, and `@mydenicek/sync`.

## Architecture overview {#sec:architecture}

The system is organized in five packages, as shown in [@Fig:architecture].

![Architecture of the mydenicek monorepo. The web application depends on React bindings and the sync package, both of which depend on the core engine. The deployed sync server (apps/sync-server) also uses the sync package.](img/architecture.png){#fig:architecture width=70%}

The packages are:

- **`packages/core`** (`@mydenicek/core` [@mydenicek_core]) --- the collaborative editing engine. Contains the document model, event DAG, edit types, OT transformation rules, undo/redo, formula engine, and recording/replay. Zero external runtime dependencies; pure TypeScript.
- **`packages/react`** (`@mydenicek/react` [@mydenicek_react]) --- React bindings. The `useDenicek` hook provides reactive document state, mutation helpers, and sync lifecycle management.
- **`packages/sync`** (`@mydenicek/sync` [@mydenicek_sync]) --- sync protocol. WebSocket-based client and server for exchanging events between peers. The server operates in *relay mode*: it stores and forwards events without materializing documents or understanding edit semantics.
- **`apps/mywebnicek`** --- web application. React 19 + Fluent UI interface with a terminal-style command bar, rendered document view, raw JSON view, and event graph DAG visualization.
- **`apps/sync-server`** --- deployed sync server. A Deno HTTP server that hosts WebSocket rooms using `@mydenicek/sync`, persists events to disk, and runs on Azure Container Apps.

The layered design ensures that the core engine has no knowledge of the UI or transport layer, and the sync server has no knowledge of edit types. Custom primitive edits (such as `splitFirst` and `splitRest`) are registered only in the application layer and do not need to be known by the server.

### Core class architecture {#sec:core-classes}

The core engine is organized around five main class hierarchies:

- **`Denicek`** is the top-level facade. It owns an `EventGraph` and a peer ID, and exposes all editing operations (`add`, `delete`, `rename`, `pushBack`, `wrapRecord`, etc.) as methods that create `Edit` objects and commit them as `Event` objects to the graph. It also manages undo/redo stacks and replay.
- **`EventGraph`** stores all `Event` objects in a map keyed by `EventId`, maintains the current frontier, and implements materialization (deterministic topological replay), `resolveReplayEdit` (for recording/replay), and `ingestEvents` (for sync with causal delivery buffering).
- **`Event`** is an immutable value object containing an `EventId`, a list of parent `EventId`s, an `Edit`, and a `VectorClock`. Its `resolveAgainst` method transforms the edit through all previously applied concurrent edits during materialization.
- **`Node`** is the abstract base class for the four document node types: `RecordNode`, `ListNode`, `PrimitiveNode`, and `ReferenceNode`. Nodes support navigation by `Selector`, cloning, and structural mutation (used during materialization).
- **`Edit`** is the abstract base class for all edit types, described in detail in [@Sec:ot-architecture]. Each edit knows how to `apply` itself to a document, `transform` its selector through a prior edit, and `computeInverse` for undo.

`Selector` and `VectorClock` are value objects. `Selector` handles parsing, matching, wildcard expansion, and prefix comparison. `VectorClock` supports merge (component-wise max), dominance comparison, and advancement.

### Technology choices {#sec:tech-choices}

**TypeScript.** Local-first applications target the browser, where JavaScript is the dominant language. TypeScript adds static type safety, which is particularly valuable in a collaborative editing engine where subtle type errors (e.g., confusing a selector path with a plain string, or passing the wrong event structure) can cause silent convergence failures.

**Deno.** Deno is a JavaScript and TypeScript runtime created by Ryan Dahl, the original creator of Node.js. Unlike Node.js, Deno runs TypeScript natively without a compilation step and includes a built-in formatter, linter, and test runner. This eliminates the configuration overhead of separate tools (ESLint, Prettier, Jest, tsconfig) that a Node.js project would require.

**React.** React is a widely-used JavaScript library for building user interfaces, developed by Meta. The core engine is framework-agnostic, but the `@mydenicek/react` package provides React-specific bindings because React is the most mainstream frontend framework, making the library accessible to the widest audience.

**JSR.** JSR (JavaScript Registry) is a package registry developed by the Deno team as an alternative to npm. It accepts TypeScript source directly (npm requires pre-compiled JavaScript), which simplifies the publishing workflow. The three mydenicek packages are published on JSR.

## Document model {#sec:doc-model}

Documents are modeled as tagged trees with four node types:

- **Record** --- a set of named fields, each containing a child node, plus a structural tag.
- **List** --- an ordered sequence of child nodes with a structural tag.
- **Primitive** --- a scalar value: string, number, or boolean.
- **Reference** --- a pointer to another node via a relative or absolute path.

Reference nodes are unusual in collaborative editing systems. In most CRDT-based systems (Automerge, Loro, json-joy), nodes reference each other via opaque unique IDs --- stable across moves and structural changes, but unable to express relative relationships like "my sibling at index 0." CRDT spreadsheets (e.g., Sypytkowski's work) similarly use stable UIDs for cell references, avoiding the need for reference transformation entirely. In mydenicek, references are *path-based* (`../0/source`), meaning they navigate the tree relative to their position. This enables patterns like formula nodes referencing sibling data, but requires OT to keep references valid when structural edits (rename, wrap) change the paths they traverse.

Nodes are addressed by *selectors* --- slash-separated paths that describe how to navigate the tree from the root. The selector `speakers/0/name` navigates to the `speakers` field, then to the first list item (index 0), then to the `name` field. Selectors support three special forms:

- **Wildcards** (`*`): `speakers/*` expands to all children of the `speakers` list. An edit targeting `speakers/*` is applied to every item.
- **Strict indices** (`!0`): `speakers/!0` refers to the item at index 0 *at the time of the edit*. Unlike plain `0`, strict indices are not shifted by concurrent insertions --- they always refer to the original position.
- **Parent navigation** (`..`): used in references to navigate up the tree. `../../0/contact` goes up two levels, then navigates to `0/contact`.

## Event DAG {#sec:event-dag}

The event directed acyclic graph (DAG) is the core data structure of mydenicek. It is a grow-only, append-only structure --- events are immutable once created, and new events can only be added, never modified or removed. This makes the event set a G-Set (grow-only set), which is the simplest CRDT: two peers that have received the same set of events will always produce the same document. Each edit creates an *event* containing:

- **EventId** --- a unique identifier `peer:seq`, where `peer` is the peer's string identifier and `seq` is a monotonically increasing sequence number. For example, `alice:3` is Alice's third event.
- **Parents** --- the set of event IDs that form the *frontier* at the time the event was created. These are the most recent events the peer had seen. An event with multiple parents is the first edit after receiving another peer's events, merging the concurrent branches.
- **Edit** --- the actual edit operation (add, delete, rename, set, pushBack, wrapRecord, etc.) with its target selector and arguments.
- **Vector clock** --- a map from peer ID to the highest sequence number seen from that peer. The vector clock enables causal ordering: event A *happens-before* event B if A's vector clock is dominated by B's. Two events are *concurrent* if neither dominates the other.

Parents and vector clocks serve complementary roles. Parents define the direct edges of the DAG --- they are needed for topological sorting and for the sync protocol's `eventsSince(frontiers)` computation. Vector clocks summarize the full causal ancestry of an event, enabling efficient concurrency detection during OT: checking whether two events are concurrent requires only comparing their vector clocks (O(P) where P is the number of peers) rather than traversing the DAG to test reachability. For example, Alice's event with clock `{alice: 5, bob: 3}` and Bob's event with clock `{alice: 2, bob: 4}` are concurrent because neither clock dominates the other (`alice: 5 > 2` but `bob: 3 < 4`).

For wire transport and persistence, events are serialized as JSON using a codec layer (`remote-edit-codec.ts` and `remote-events.ts`). Each event is encoded into a plain JSON object with four fields: `id` (peer string + sequence number), `parents` (array of parent IDs), `clock` (a flat object mapping peer names to integers), and `edit` (the encoded edit). The edit payload is a discriminated union keyed by a `kind` string --- for instance, `"RecordRenameFieldEdit"` or `"WrapRecordEdit"` --- followed by the edit's target selector and type-specific parameters (new field names, inserted node trees, tag strings). Each `Edit` subclass implements `encodeRemoteEdit()` to produce its serialized form, and a corresponding decoder is registered via `registerRemoteEditDecoder(kind, decoderFn)`. Decoder registration happens at module load time through side-effect imports, so the codec is extensible without modifying a central switch statement. Decoding an incoming event (`decodeRemoteEvent`) reconstructs the `EventId`, parent list, `VectorClock`, and the concrete `Edit` subclass, producing an internal `Event` ready for ingestion into the local event graph.

### Materialization

To reconstruct the document from the event DAG, we perform *deterministic topological replay*:

1. Sort all events in topological order using Kahn's algorithm. When multiple events have no unprocessed dependencies (i.e., they are concurrent), break ties deterministically by comparing their `EventId` values lexicographically.
2. Starting from the initial document, apply each event's edit in order. Before applying, call `resolveAgainst` --- the OT step that transforms the edit's selector through all previously applied concurrent edits.
3. If a transformed edit becomes invalid (e.g., it targets a node that was deleted by a concurrent edit), it becomes a *no-op conflict* that is recorded but does not modify the document.

The `resolveAgainst` step is the heart of convergence. When the materializer is about to apply event E, it iterates over every event that has already been applied in the current replay. For each prior event P, it checks whether E's vector clock dominates P's clock --- if so, E causally depends on P, and no transformation is needed. If neither clock dominates the other, the events are concurrent, and the materializer calls `transformLaterConcurrentEdit(P.edit, E.edit)`, which rewrites E's selector (and potentially its payload) through P's structural effect. This transformed edit replaces E's original edit for the remainder of the loop, so transformations compose: if E is concurrent with priors P₁, P₂, and P₃, the edit is first transformed through P₁, then the result through P₂, then through P₃. After all priors have been processed, the materializer checks whether the final transformed edit can still be applied to the current document state (via `canApply`). If not --- for example, because a concurrent delete removed the target node --- the edit is downgraded to a no-op conflict. An additional `validate` check catches cases where concurrent rewrites retarget an edit onto a protected node or leave a reference pointing at a missing target.

Because the sort order is deterministic and the OT transformations are deterministic, any two peers that have received the same set of events will produce the same document. This is the strong eventual consistency guarantee.

## Edit types and OT rules {#sec:edit-types}

The system supports the following edit types, listed in [@Tbl:edit-types].

: Edit types supported by the mydenicek engine. {#tbl:edit-types}

| Edit type | Description | Target |
|-----------|-------------|--------|
| `RecordAddEdit` | Add a named field to a record | Record |
| `RecordDeleteEdit` | Delete a named field from a record | Record |
| `RecordRenameFieldEdit` | Rename a field | Record |
| `ListPushBackEdit` | Append an item to a list | List |
| `ListPushFrontEdit` | Prepend an item to a list | List |
| `ListPopBackEdit` | Remove the last item from a list | List |
| `ListPopFrontEdit` | Remove the first item from a list | List |
| `UpdateTagEdit` | Change a node's structural tag | Record or List |
| `WrapRecordEdit` | Wrap a node in a new parent record | Any |
| `WrapListEdit` | Wrap a node in a new parent list | Any |
| `CopyEdit` | Copy a subtree from a source to a target | Any |
| `ApplyPrimitiveEdit` | Apply a registered custom edit | Primitive |

Each structural edit (rename, wrap, delete) has a `transformSelector` method that rewrites the selector of a concurrent edit. The key transformation rules are:

- **Rename**: if a concurrent edit targets `speakers/0/name` and a rename changes `speakers` to `talks`, the concurrent edit's selector is transformed to `talks/0/name`.
- **WrapRecord**: if a concurrent edit targets `speakers/0/value` and a wrap turns `value` into `{$tag: "wrapper", value: <original>}`, the concurrent edit's selector gains a segment: `speakers/0/value/value`.
- **WrapList**: similar to WrapRecord but wraps into a list, adding an index segment.
- **Delete**: if a concurrent edit targets a field that was deleted, the edit becomes a no-op conflict.
- **PushFront**: shifts numeric indices in concurrent selectors (e.g., `items/0` becomes `items/1`).

To illustrate how transformations compose, consider a conference list where Alice, Bob, and Carol make concurrent edits: Alice renames the field `speakers` to `talks`, Bob wraps each item in a `<tr>` record (so `talks/0` becomes `talks/0/value`), and Carol edits the first speaker's name at `speakers/0/name`. During deterministic replay, suppose the topological order is Alice → Bob → Carol. Carol's selector `speakers/0/name` is first transformed through Alice's rename: the `speakers` prefix matches the rename, so the selector becomes `talks/0/name`. It is then transformed through Bob's wrap: the `talks/0` prefix matches the wrap target `talks/*`, so a `value` segment is inserted, yielding `talks/0/value/name`. Carol's edit now correctly targets the name field inside the new wrapper structure --- even though Carol's original selector knew nothing about the rename or the wrap. Each transformation examines only whether the concurrent edit's selector is a prefix of (or overlaps with) the edit being transformed, making the composition both local and linear in the number of prior concurrent edits.

### OT architecture {#sec:ot-architecture}

A naive OT implementation requires O(n²) transformation rules, one for every pair of edit types. mydenicek avoids this through a two-level object-oriented design, shown in [@Fig:edit-class-diagram].

![Edit class hierarchy with two-level OT. Level 1: every edit implements `transformSelector`, handling all edit-type pairs via selector rewriting. Level 2: structural edits override `transformLaterConcurrentEdit` to also rewrite the payloads of concurrent list inserts.](img/edit-class-diagram.png){#fig:edit-class-diagram width=75%}

**Level 1: Selector transformation (default).** The abstract `Edit` base class defines `transformSelector(sel)` --- each edit type implements this to describe how it changes the path structure. The default `transformLaterConcurrentEdit(concurrent)` simply calls `concurrent.transform(this)`, which rewrites the concurrent edit's target selector through `transformSelector`. This single dispatch handles all edit-type pairs with O(n) methods, not O(n²) rules. Data edits (add, set, copy, pushBack, popBack, primitives) return the identity transformation since they do not change the document's path structure.

**Level 2: Payload rewriting (overrides).** Selector transformation alone is insufficient when a structural edit interacts with a concurrent list insert --- the inserted node's *payload* must also be transformed. For example, when `updateTag("items/*", "tr")` is concurrent with `pushBack("items", {$tag: "li", ...})`, the inserted node must change its tag from `<li>` to `<tr>`. Only structural edits that change the document shape override `transformLaterConcurrentEdit`: `UpdateTagEdit` changes the inserted node's tag, `WrapRecordEdit` wraps it in a record, and `WrapListEdit` wraps it in a list. This scales linearly with the number of structural edit types, not quadratically.

### CopyEdit and mirroring {#sec:copy-edit}

`CopyEdit` extends `Edit` directly (not `NoOpOnRemovedTargetEdit`) because it has two selectors --- `target` and `source` --- both of which must be checked for removal. If either is deleted by a concurrent edit, the copy becomes a no-op. More importantly, `CopyEdit` *mirrors* concurrent edits: when a concurrent edit modifies the source, the same modification is replicated onto the copy target. This is implemented by `transformLaterConcurrentEdit` wrapping the concurrent edit in a `CompositeEdit` that applies it to both the original target and the mirrored copy target. This ensures that copied data stays consistent with its source as both evolve under concurrent editing.

### Wildcard edits and concurrent insertions {#sec:wildcard-concurrent}

A notable property of the OT-based replay approach is how wildcard edits interact with concurrent insertions, illustrated in [@Fig:wildcard-diamond]. This property is important because wildcard edits are a core feature of Denicek's end-user programming model --- users apply structural transformations to all items in a list (e.g., refactoring a conference list into a table, as demonstrated in [@Sec:conf-concurrent]). When one user refactors the list while another concurrently adds new items, the new items should also be refactored.

When Alice applies `updateTag("speakers/*", "tr")` --- changing the tag of every item in the list --- and Bob concurrently inserts a new item via `pushBack("speakers", ...)`, the result is that Alice's tag update also affects Bob's newly inserted item.

![Wildcard edit and concurrent insertion. Alice's wildcard `updateTag` and Bob's `pushBack` are concurrent. After merge, Bob's inserted `<li> C` becomes `<tr> C` --- the wildcard edit affects the concurrent insertion.](img/wildcard-diamond.png){#fig:wildcard-diamond width=55%}

This holds regardless of replay order, but the mechanism differs in each case:

- **Insert first** (Bob's `pushBack` is replayed before Alice's wildcard edit): Bob's new item is added to the list. When Alice's `updateTag("speakers/*", "tr")` is then replayed, the wildcard `*` expands to include *all items that exist at the point of replay* --- including Bob's concurrent insertion. The tag update naturally applies to the new item without any transformation needed.
- **Edit first** (Alice's wildcard edit is replayed before Bob's `pushBack`): Alice's `updateTag` is applied to the existing items. When Bob's `pushBack` is then transformed against Alice's preceding wildcard edit, the OT transformation modifies the inserted item: instead of inserting a `<li>` item, the transformed insert produces a `<tr>` item. This works because materialization replays events in a canonical order --- when Bob's insert comes after Alice's wildcard edit in that order, the insert is transformed to be consistent with the already-applied edit.

This semantics is uncommon in CRDTs. In most CRDT-based systems, an operation only affects the items that existed at the time the operation was created. Newly inserted items are not retroactively affected by concurrent bulk operations. Weidner [@weidner2023foreach] describes this as the *for-each* problem and proposes a dedicated CRDT operation to address it. In mydenicek, the replay-based approach naturally achieves the "for-each-including-concurrent-additions" semantics because the wildcard is expanded at replay time, not at creation time --- no special for-each CRDT is needed.

## Extensibility, formulas, and undo {#sec:extensibility-formulas-undo}

### Extensibility {#sec:extensibility}

The core engine is designed to be extended by application code without modifying the engine itself. Two extension points use the *registry* pattern --- a global map from names to implementations:

**Primitive edits.** Applications can register custom transformations on primitive values via `Denicek.registerPrimitiveEdit(name, fn)`. The function receives the current value and optional arguments, and returns the new value. For example, the conference table app registers `splitFirst` and `splitRest` to split comma-separated strings. Registered edits are stored by name in the event DAG and replayed on all peers --- each peer must register the same implementation before materializing. The sync server does not need to know about primitive edits because it operates in relay mode.

**Formula operations.** Applications can register custom formula operations via `registerFormulaOperation(name, fn)` for operation-based formulas, and `registerTagEvaluator(tag, fn)` for tag-based formulas. Built-in operations (sum, product, concat, etc.) are registered using the same mechanism as user-defined ones.

The `Denicek` class itself follows the *facade* pattern: it provides a single entry point for all editing operations (`add`, `rename`, `wrapRecord`, `pushBack`, `undo`, `replay`, etc.), delegating to the `EventGraph`, `Edit` subclasses, and formula engine internally. The public API uses plain values (`PlainNode` objects and selector strings) rather than exposing internal classes like `Node`, `Edit`, or `EventGraph`.

### Formula engine {#sec:formulas}

The formula engine supports two kinds of formulas:

- **Tag-based evaluators** --- registered for specific node tags. For example, a node with `$tag: "split-first"` containing a `source` field and a `separator` field evaluates to the substring before the separator. Built-in evaluators include `x-formula-plus`, `x-formula-minus`, `x-formula-times`, `split-first`, and `split-rest`.
- **Operation-based formulas** --- nodes with `$tag: "x-formula"` and an `operation` field. Arguments are provided as a list that may contain primitive values or `$ref` references. Built-in operations include `sum`, `product`, `concat`, `uppercase`, `lowercase`, `countChildren`, and others.

References (`$ref`) in formula arguments are resolved relative to the formula's position in the tree. The formula engine walks the entire document tree, evaluates all formula nodes, and returns a map from path to result. Circular references are detected and reported as errors.

The evaluation algorithm works in two phases. First, `evaluateAllFormulas` performs a depth-first walk of the entire plain-node tree, building a path string (e.g., `speakers/0/total`) for each node. When it encounters a node whose `$tag` matches a registered tag evaluator or starts with `x-formula`, it calls `evaluateFormulaNode`, which dispatches to the appropriate evaluator. For tag-based formulas, the evaluator receives the formula record and a callback that recursively evaluates child fields; for operation-based formulas, the engine collects the `args` list, resolves each argument (primitives pass through, `$ref` nodes are resolved, nested formulas are evaluated recursively), and invokes the registered operation function.

Reference resolution (`$ref`) supports both absolute paths (starting with `/`, resolved from the document root) and relative paths (resolved from the formula's own position in the tree). Relative paths use `..` segments for parent navigation: the engine combines the formula's own path segments with the reference's segments, then resolves `..` by popping from a stack, producing an absolute path that is navigated segment-by-segment through the plain-node tree. The `navigatePlainNode` function handles record field access, list index access, wildcard expansion (`*` iterates over all children), and parent navigation via an explicit parent stack. When a wildcard appears in a `$ref` path, the reference resolves to multiple values --- all of which are flattened into the argument list. This is how `sum({$ref: "../*/price"})` sums all `price` fields across sibling list items. Circular references are detected by tracking the set of formula paths currently being evaluated; if a formula's path is already in the visiting set, the engine returns a `FormulaError` instead of recursing infinitely. Evaluation depth is also capped at 100 levels.

### Undo and redo {#sec:undo}

Each `Edit` subclass implements a `computeInverse(preDoc)` method that returns the inverse edit. For example, the inverse of `RecordAddEdit("field", value)` is `RecordDeleteEdit("field")`, and the inverse of `WrapRecordEdit` is `UnwrapRecordEdit`.

Undo creates a new event containing the inverse edit. This event is a regular event in the DAG --- it syncs to other peers automatically. Redo re-applies the undone edit. The undo/redo stacks are maintained per-peer and only track local events.

## Recording and replay {#sec:replay}

Programming by demonstration is implemented through event recording and replay.

A naive approach --- simply re-executing the recorded edit on the current document --- does not work because the document structure may have changed since recording. If Alice recorded `pushFront("items", ...)` but someone later renamed `items` to `speakers`, the original selector no longer resolves. Even if the field still exists, structural edits like wraps may have added extra path segments that the original selector does not account for.

The solution is to use OT to transform the recorded edit's selector through every structural change that happened after the recording. This produces the same result as if the replay had been executed concurrently with the original edit --- the OT transformations account for exactly the same structural changes that a concurrent event from the recording point would encounter during materialization.

The replay mechanism works in three steps:

1. **Recording.** When a user performs an edit, the resulting event ID is stored in a list of *replay steps* --- typically attached to a button node in the document.
2. **Replay.** When the user triggers a replay, the system replays the full event history in topological order. When it reaches the source event, it captures its edit. It then continues replaying --- each later *structural* edit (rename, wrap, delete) transforms the captured edit's selector via OT. The final transformed edit is committed as a new event at the current frontier. For example, if the recorded edits targeted `items` but a later rename changed `items` to `speakers`, the replayed edits target `speakers`.
3. **Batch replay.** When replaying multiple steps as a batch (e.g., all steps of an "Add Speaker" button), all source edits are resolved before any are committed. This prevents the replayed steps from retargeting each other.

Strict indices (`!0`) are essential for replay: a regular index `0` would be shifted by later insertions, causing the copy to target the wrong item. The strict index `!0` refers to position 0 *at the time of the original edit*, which OT does not shift through later insertions.

To avoid re-materializing the entire history on every replay, the event graph caches the resolved edit list from the last full materialization. Subsequent replay calls scan the cached list instead of replaying from scratch. The cache is invalidated when new events are added. This reduces the cost of N consecutive replays from N full materializations to one materialization plus N scans of the cached list.

## Sync protocol {#sec:sync}

The sync protocol uses WebSocket connections with a simple message exchange, illustrated in [@Fig:sync-protocol].

![Sync protocol sequence diagram. Alice and Bob connect to the server, exchange initial documents and events, and converge to the same state.](img/sync-protocol.png){#fig:sync-protocol width=80%}

The protocol consists of three phases:

1. **Connect.** The client sends a `hello` message with the room ID. If the room exists, the server responds with the initial document.
2. **Sync.** The client sends its pending events and current frontiers. The server responds with events the client has not seen (computed via `eventsSince(clientFrontiers)`).
3. **Ongoing.** As either peer produces new events, they are exchanged via the same sync message format.

The server maintains a `SyncRoom` for each room, containing a `Denicek` instance in *relay mode*. In relay mode, the server stores and forwards events without materializing the document --- the `validateEventAgainstCausalState` step is skipped. This means the server does not need to know about custom primitive edits or formula evaluators; it only needs to understand the event structure.

Initial documents are validated by hash: the first client to sync with a room sets the room's initial document hash, and subsequent clients must match it.

All messages are JSON-encoded and distinguished by a `type` discriminator field. A sync request from client to server contains `type: "sync"`, the `roomId`, the client's current `frontiers` (an array of event ID strings), and an `events` array of new events to send. The first sync also includes the `initialDocument` (the plain-node tree) and its hash. A sync response from server to client mirrors this structure: `type: "sync"`, the `roomId`, the server's `frontiers`, and the `events` the client has not seen. The `hello` message sent on connection contains just `type: "hello"`, the `roomId`, and optionally the room's `initialDocument` if one has already been set by a prior peer.

Each event in the `events` array is serialized as a JSON object with four fields: `id` (an object with `peer` string and `seq` number), `parents` (an array of such ID objects), `clock` (a plain JSON object mapping peer strings to sequence numbers), and `edit` (the encoded edit payload). The edit payload is a discriminated union keyed by `kind` --- for example, `{"kind": "RecordRenameFieldEdit", "target": "speakers/0/name", "to": "fullName"}` or `{"kind": "WrapRecordEdit", "target": "items/*", "field": "value", "tag": "tr"}`. Structural edits carry their target selector as a string and any additional parameters (the new field name, the wrapper tag, inserted node trees). This encoding is defined by the `EncodedRemoteEdit` type in `remote-edit-codec.ts`, with each edit class implementing `encodeRemoteEdit()` and a corresponding decoder registered via `registerRemoteEditDecoder()`. The decoder registry is populated at module load time by side-effect imports, ensuring that all edit types are available for deserialization on any peer.

### Reliability through frontier-based sync {#sec:reliability}

Network communication is unreliable --- messages can be lost, duplicated, delayed, or delivered out of order. WebSocket connections can drop unexpectedly due to network changes, server restarts, or client hibernation. The sync protocol handles all of these cases through a single mechanism: *frontier-based catch-up*.

Every sync message includes the sender's current *frontiers* --- the set of event IDs that represent the sender's latest known state. When the server receives a sync message, it compares the client's frontiers against its own event graph and responds with all events the client has not seen (computed via `eventsSince(clientFrontiers)`). This design has several important properties:

- **Lost messages.** If a message from the server to a client is lost, the client's frontiers will not advance. On the next sync, the client sends the same frontiers, and the server resends the missing events. No explicit acknowledgment or retry mechanism is needed.
- **Duplicate messages.** If an event is received twice, the event graph detects that the event ID already exists and ignores the duplicate. Events are idempotent by design.
- **Out-of-order delivery.** If events arrive before their causal dependencies, the event graph buffers them until the missing parents arrive. The `ingestEvents` method maintains a buffer of pending events and flushes them in causal order as dependencies are satisfied.
- **Reconnection.** When a client reconnects after a disconnection, it simply sends its current frontiers. The server computes the difference and sends all missing events --- whether the client was offline for seconds or hours.

[@Fig:sync-reliability] illustrates how frontier-based sync recovers from a lost message.

![Frontier-based sync recovery. A message is lost, but on the next sync round Bob sends his frontiers, the server detects the gap, and resends the missing event.](img/sync-reliability.png){#fig:sync-reliability width=80%}

## Web application {#sec:webapp}

The web application (`apps/mywebnicek`) serves as both a demonstration of the core engine and a tool for interactively exploring collaborative editing scenarios. It is built with React 19 and Microsoft's Fluent UI component library, and connects to the sync server via WebSocket.

### Integration with the core engine

The application uses the `useDenicek` hook from `@mydenicek/react`, which wraps the core `Denicek` instance and provides:

- **Reactive document state** --- the hook re-renders the component whenever the document changes, whether from local edits or remote events arriving via sync.
- **Sync lifecycle** --- the hook manages the WebSocket connection, automatically sending local events to the server and ingesting remote events. Connection status (connected, connecting, disconnected) is displayed in the header.
- **Peer identity** --- each browser tab generates a unique peer ID (stored in `sessionStorage` to survive page refreshes) that identifies events in the causal DAG.

### User interface

The interface provides three synchronized panels, each showing a different aspect of the same document state:

- **Rendered view** --- the document tree rendered as HTML elements based on node tags. Formula nodes display their evaluated results. Buttons trigger replay of recorded edit sequences.
- **Raw JSON view** --- syntax-highlighted JSON representation of the materialized document tree, useful for understanding the exact structure.
- **Event graph view** --- an SVG visualization of the causal DAG showing events as nodes, causal dependencies as edges, peer colors, and frontier indicators. Clicking an event shows its details (edit type, selector, vector clock).

### Command bar

The command bar at the bottom provides a terminal-style interface for executing edits. The syntax is:

    /selector command args

For example, `/speakers updateTag table` changes the tag of the speakers node, and `/speakers/*/0/contact splitFirst ,` applies the `splitFirst` edit to every row's contact field. Tab completion suggests path segments based on the current document structure, and valid commands for the selected node type. All registered primitive edits (including application-defined ones like `splitFirst` and `splitRest`) are automatically available as commands via `listRegisteredPrimitiveEdits()`.

### Document initialization

On first load, the application initializes a template document (a conference list) and registers application-specific primitive edits and recorded action sequences. When joining an existing room, the application fetches the current document state from the sync server instead of using the template.

## CI/CD and hosting {#sec:ci-hosting}

### Continuous integration and deployment {#sec:ci}

The project uses GitHub Actions for continuous integration. Every push to the `main` branch triggers five parallel CI jobs: formatting check, linting (including JSDoc validation), type checking, tests (206+ unit tests, 6 formative example tests, sync tests), and build verification. All five must pass before any deployment proceeds.

After CI passes, the web application is deployed to GitHub Pages as a static site, and the sync server is deployed to Azure (see [@Sec:hosting]). After both deployments complete, Playwright browser tests run against the live site to verify that two browser peers can connect, sync edits, and produce consistent document states.

JSR package publishing is a separate workflow (`deno publish`) triggered manually on demand, since package versions should be bumped deliberately rather than on every push. Publishing through GitHub Actions rather than locally is important for *provenance*: JSR uses GitHub's OIDC tokens to generate a cryptographic attestation (via Sigstore) that links each published package version to a specific Git commit and CI workflow. This allows consumers to verify that the package was built from the claimed source code and was not modified after the fact. Local publishing cannot provide this guarantee because there is no trusted build environment.

### Hosting {#sec:hosting}

**Web application.** The Vite build output is deployed as a static site to GitHub Pages. The application is a single-page app that connects to the sync server via WebSocket.

**Sync server.** The sync server runs as a Docker container on Azure Container Apps. Several Azure hosting options were considered:

- **Azure App Service** provides managed web hosting but requires an always-running plan even with no traffic. The sync server is a lightweight WebSocket relay that is only needed when users are actively collaborating, making always-on hosting wasteful.
- **Azure Container Instances (ACI)** supports running containers on demand, but does not support scale-to-zero --- a container instance is billed for the entire time it is running, and must be explicitly started and stopped. ACI also lacks built-in HTTPS ingress and automatic restarts.
- **Azure Kubernetes Service (AKS)** provides full container orchestration for architectures where multiple containers communicate together. Running a single container on AKS would introduce unnecessary complexity (cluster management, networking, scaling policies) with no benefit.
- **Azure Container Apps** combines the simplicity of ACI with automatic scale-to-zero, built-in HTTPS ingress, and managed infrastructure. It incurs no cost when idle and scales up automatically when WebSocket connections arrive.

Container Apps was chosen as the best fit: minimal operational overhead, zero cost at rest, and sufficient for a single-container research deployment. The trade-off is a *cold start* delay: when the container has scaled to zero, the first WebSocket connection takes a few seconds while the container starts up.

The deployment builds a Docker image via Azure Container Registry, then deploys it using a Bicep infrastructure-as-code template. Event data is persisted to an Azure Files share mounted into the container --- Azure Files was chosen over Blob Storage or Table Storage because it provides a POSIX file system interface, allowing the sync server to read and write JSON files directly without needing a storage SDK.

The source code is available at `https://github.com/krsion/mydenicek` and the live demo is deployed at `https://krsion.github.io/mydenicek`.
