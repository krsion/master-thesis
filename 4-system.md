# System {#chap:system}

This chapter describes the engineering aspects of mydenicek. The implementation is a Deno/TypeScript monorepo published on JSR, organized in three packages ([@Fig:architecture]): `@mydenicek/core` (the CRDT engine --- pure TypeScript, no WASM, single runtime dependency), `@mydenicek/react` (React bindings), and `@mydenicek/sync` (WebSocket relay). Two applications use them: a web frontend (`apps/mywebnicek`) and a deployed sync server (`apps/sync-server`). The core has no knowledge of the transport layer; the server has no knowledge of edit types.

![Architecture of the mydenicek monorepo. The core engine is transport-agnostic; the sync server operates in relay mode.](img/architecture.png){#fig:architecture width=70%}

## Extensibility, formulas, and undo {#sec:extensibility-formulas-undo}

### Extensibility {#sec:extensibility}

The core engine is designed to be extended by application code without modifying the engine itself. Two extension points use the *registry* pattern --- a global map from names to implementations:

**Primitive edits.** Applications can register custom transformations on primitive values via `Denicek.registerPrimitiveEdit(name, fn)`. The function receives the current value and optional arguments, and returns the new value. For example, the conference table app registers `splitFirst` and `splitRest` to split comma-separated strings. Registered edits are stored by name in the event DAG and replayed on all peers --- each peer must register the same implementation before materializing. The sync server does not need to know about primitive edits because it operates in relay mode.

**Formula operations.** Applications can register custom formula operations via `registerFormulaOperation(name, fn)` for operation-based formulas, and `registerTagEvaluator(tag, fn)` for tag-based formulas. Built-in operations (sum, product, concat, etc.) are pre-registered at module load time using the same mechanism, so there is no distinction between built-in and user-defined operations at runtime.

The `Denicek` class itself follows the *facade* pattern: it provides a single entry point for all editing operations (`add`, `rename`, `wrapRecord`, `insert`, `undo`, `replay`, etc.), delegating to the `EventGraph`, `Edit` subclasses, and formula engine internally. The public API uses plain values (`PlainNode` objects and selector strings) rather than exposing internal classes like `Node`, `Edit`, or `EventGraph`.

### Formula engine {#sec:formulas}

The formula engine supports two kinds of formulas:

- **Tag-based evaluators** --- registered for specific node tags. For example, a `RecordNode` with tag `split-first` containing a `source` field and a `separator` field evaluates to the substring before the separator. Pre-registered tag evaluators include `x-formula-plus`, `x-formula-minus`, `x-formula-times`, `split-first`, and `split-rest`.
- **Operation-based formulas** --- `RecordNode`s with tag `x-formula` and an `operation` field. Arguments are provided as a `ListNode` that may contain `PrimitiveNode` values or `ReferenceNode` references. Pre-registered operations include `sum`, `product`, `concat`, `uppercase`, `lowercase`, `countChildren`, and others.

References in formula arguments are resolved relative to the formula's position in the tree. The formula engine walks the entire document tree, evaluates all formula nodes, and returns a map from path to result. Circular references are detected and reported as errors.

The formula engine operates directly on the internal `Node` tree rather than the serialized `PlainNode` representation. This means reference nodes (`ReferenceNode`) are handled natively: their selectors --- already retargeted by `updateReferences` after structural edits --- are resolved via `ReferenceNode.resolveReference` and the resulting absolute path is navigated using `Node.navigate`. No string-based path parsing or re-resolution is needed inside the formula engine; the reference infrastructure used by the edit pipeline is reused as-is.

The evaluation algorithm works as follows. `evaluateAllFormulas` uses `Node.forEach` to walk the tree with its `Selector`-typed path. When it encounters a `RecordNode` whose tag matches a registered tag evaluator or starts with `x-formula`, it calls `evaluateFormulaNode`, which dispatches to the appropriate evaluator. Reference nodes are resolved transparently before any evaluator sees them: an internal `evaluateChild` helper checks the node type --- `PrimitiveNode` values pass through directly, `ReferenceNode` instances are resolved to their target via `ReferenceNode.resolveReference` and `Node.navigate`, and nested formula `RecordNode`s are evaluated recursively. Evaluators only ever receive primitives or nested formula results, never raw reference objects. For tag-based formulas, the evaluator receives the `RecordNode` and a callback that invokes `evaluateChild` on each child field; for operation-based formulas, the engine collects the `args` list items, resolves each argument through the same transparent resolution, and invokes the registered operation function.

Reference resolution supports both absolute paths (starting with `/`, resolved from the document root) and relative paths (resolved from the reference's own position in the tree). Relative paths use `..` segments for parent navigation: `ReferenceNode.resolveReference` combines the reference's base path with its selector segments, then resolves `..` by popping from a stack, producing an absolute `Selector` that is navigated through the `Node` tree. When a wildcard appears in a reference path, `Node.navigate` resolves it to multiple nodes --- all of which are flattened into the argument list. This is how `sum({$ref: "../*/price"})` sums all `price` fields across sibling list items. Circular references are detected by tracking the set of formula paths currently being evaluated; if a formula's path is already in the visiting set, the engine returns a `FormulaError` instead of recursing infinitely. This also handles the edge case where a wildcard reference expands to include the formula node itself --- the self-reference is caught by the same visited-set check before any infinite recursion occurs. Evaluation depth is also capped at 100 levels as a defense-in-depth measure against pathological nesting.

### Undo and redo {#sec:undo}

Each `Edit` subclass implements a `computeInverse(preDoc)` method that returns the inverse edit. For example, the inverse of `RecordAddEdit("field", value)` is `RecordDeleteEdit("field")`, and the inverse of `WrapRecordEdit` is `UnwrapRecordEdit`. The `preDoc` parameter is needed because some inverses depend on the document state before the edit --- for example, to undo a delete, the inverse must know the deleted value so it can re-add it.

Undo creates a new event containing the inverse edit. This event is a regular event in the DAG --- it syncs to other peers automatically, so all peers see the undo. Redo re-applies the original edit as yet another new event. The undo/redo stacks are maintained per-peer and only track local events --- remote events are never undone locally. A new edit after an undo clears the redo stack, matching the undo behavior users expect from desktop applications.

A subtlety arises when undo interacts with concurrent remote events. The inverse edit is computed against the document state at the *original event's parent frontier* --- that is, the state just before the undone edit was first applied --- not the current document state. This is causally correct: the undo cancels exactly the effect of the original edit, regardless of what other events have been applied concurrently. However, the resulting behavior may be unintuitive in some scenarios. For example, if Alice adds a field and Bob concurrently modifies a sibling field, Alice's undo removes her addition but does not interact with Bob's modification --- even if the two fields are semantically related. The undo event is then a new event in the DAG, and other peers apply it through the normal materialization pipeline. This design ensures convergence (the undo is just another event in the G-Set) but means that undo reverses the effect of one specific edit, not the entire document state --- concurrent changes by other peers are preserved.

`CopyEdit` requires special handling because it overwrites a (possibly wildcard-expanded) target subtree. Its `computeInverse` snapshots every target node before the copy, producing a `RestoreSnapshotEdit` (or a `CompositeEdit` of multiple `RestoreSnapshotEdit` instances for wildcard targets) that restores each overwritten subtree on undo. This snapshot-based inverse incurs a per-copy overhead proportional to the size of the overwritten subtrees. For wildcard copies, each expanded target is individually snapshotted and restored.

## Recording and replay {#sec:replay}

Programming by demonstration is implemented through event recording and replay.

A naive approach --- simply re-executing the recorded edit on the current document --- does not work because the document structure may have changed since recording. If Alice recorded `insert("items", 0, ..., true)` but someone later renamed `items` to `speakers`, the original selector no longer resolves. Even if the field still exists, structural edits like wraps may have added extra path segments that the original selector does not account for.

The solution is to use OT to transform the recorded edit's selector through every structural change that happened after the recording. This produces the same result as if the replay had been executed concurrently with the original edit --- the OT transformations account for exactly the same structural changes that a concurrent event from the recording point would encounter during materialization.

The replay mechanism works in three steps:

1. **Recording.** When a user performs an edit, the resulting event ID is stored in a list of *replay steps* --- typically attached to a button node in the document.
2. **Replay.** When the user triggers a replay, the system replays the full event history in topological order. When it reaches the source event, it captures its edit. It then continues replaying --- each later *structural* edit (rename, wrap, delete) transforms the captured edit's selector via OT. The final transformed edit is committed as a new event at the current frontier. For example, if the recorded edits targeted `items` but a later rename changed `items` to `speakers`, the replayed edits target `speakers`.
3. **Batch replay.** When replaying multiple steps as a batch (e.g., all steps of an "Add Speaker" button), all source edits are resolved before any are committed. This prevents the replayed steps from retargeting each other.

Strict indices (`!0`) are essential for replay: a regular index `0` would be shifted by later insertions, causing the copy to target the wrong item. The strict index `!0` refers to position 0 *at the time of the original edit*, which OT does not shift through later insertions.

To avoid re-materializing the entire history on every replay, the event graph caches the resolved edit list from the last full materialization. Subsequent replay calls scan the cached list instead of replaying from scratch. The cache is invalidated when new events are added. This reduces the cost of N consecutive replays from N full materializations to one materialization plus N scans of the cached list.

## Sync protocol {#sec:sync}

The event DAG is a purely peer-to-peer data structure --- convergence requires only that all peers eventually receive the same set of events, regardless of how they are delivered. Peer-to-peer transport (e.g., via WebRTC) is possible but was not the focus of this work. For simplicity, mydenicek uses a centralized relay server that all peers connect to via WebSocket, similarly to how Automerge and Loro provide their own sync servers. The relay server stores and forwards events but does not interpret them --- it could be replaced by any transport that delivers events reliably.

The sync protocol uses WebSocket connections with a simple message exchange, illustrated in [@Fig:sync-protocol].

![Sync protocol sequence diagram. Alice and Bob connect to the server, exchange initial documents and events, and converge to the same state.](img/sync-protocol.png){#fig:sync-protocol width=80%}

The protocol consists of three phases:

1. **Connect.** The client sends a `hello` message with the room ID. If the room exists, the server responds with the initial document.
2. **Sync.** The client sends its locally created events that the server has not yet seen (computed via `eventsSince(knownServerFrontiers)`) along with its current frontiers. The server responds with events the client has not seen (computed via `eventsSince(clientFrontiers)`).
3. **Ongoing.** As either peer produces new events, they are exchanged via the same sync message format.

The server maintains a `SyncRoom` for each room, containing a `Denicek` instance in *relay mode*. In relay mode, the server stores and forwards events without materializing the document --- the `validateEventAgainstCausalState` step is skipped. This means the server does not need to know about custom primitive edits or formula evaluators; it only needs to understand the event structure.

Initial documents are validated by hash: the first client to sync with a room sets the room's initial document hash, and subsequent clients must match it. Room creation is safe under concurrent connections because Deno's event loop guarantees that the bootstrap code (hash check and initial document assignment) runs to completion between `await` suspension points --- two peers connecting simultaneously cannot both set a different initial document. Each incoming WebSocket message triggers event ingestion and response computation, followed by asynchronous file persistence. Different rooms are processed independently; within a room, messages are handled one at a time by the event loop, which is sufficient for the typical workload of a few peers per room.

All messages are JSON-encoded and distinguished by a `type` discriminator field. A sync request from client to server contains `type: "sync"`, the `roomId`, the client's current `frontiers` (an array of event ID strings), and an `events` array of new events to send. The first sync also includes the `initialDocument` (the plain-node tree) and its hash. A sync response from server to client mirrors this structure: `type: "sync"`, the `roomId`, the server's `frontiers`, and the `events` the client has not seen. The `hello` message sent on connection contains just `type: "hello"`, the `roomId`, and optionally the room's `initialDocument` if one has already been set by a prior peer.

Each event in the `events` array is serialized as a JSON object with four fields: `id` (an object with `peer` string and `seq` number), `parents` (an array of such ID objects), `clock` (a plain JSON object mapping peer strings to sequence numbers), and `edit` (the encoded edit payload). The edit payload is a discriminated union keyed by `kind`, for example:

    {"kind": "RecordRenameFieldEdit",
     "target": "speakers", "from": "name", "to": "fullName"}

Structural edits carry their target selector as a string and any additional parameters (the new field name, the wrapper tag, inserted node trees). This encoding is defined by the `EncodedRemoteEdit` type in `remote-edit-codec.ts`, with each edit class implementing `encodeRemoteEdit()` and a corresponding decoder registered via `registerRemoteEditDecoder()`. The decoder registry is populated at module load time, ensuring that all edit types are available for deserialization on any peer.

### Reliability through frontier-based sync {#sec:reliability}

Network communication is unreliable --- WebSocket connections can drop unexpectedly due to network changes, server restarts, or client hibernation. Within a single WebSocket connection, TCP guarantees ordered and reliable delivery: messages arrive exactly once and in the order they were sent. However, when a connection drops, any in-flight messages are lost, and the new connection has no memory of the previous one. The sync protocol handles connection drops through a single mechanism: *frontier-based catch-up*.

Every sync message --- in both directions --- includes the sender's current *frontiers* and new events computed via `eventsSince(knownRecipientFrontiers)`. Each side tracks the last-known frontiers of the other. When the client sends a sync message, the server ingests the client's events and sends back a sync message with its own frontiers and any events the client is missing. By updating `knownServerFrontiers` from the server's message, the client learns which events the server has ingested. There is no separate acknowledgment protocol --- the bidirectional frontier exchange serves double duty as both data sync and confirmation. This design has several important properties:

- **Connection drop with in-flight server message.** The client's known server frontiers do not advance. On reconnection, the client sends the same frontiers, and the server resends the missing events.
- **Connection drop with in-flight client message.** The client never received a reply, so its `knownServerFrontiers` did not advance. On reconnection, the next sync message recomputes `eventsSince(knownServerFrontiers)` and includes the unsent events again.
- **Out-of-order event delivery.** While TCP preserves message order within a connection, events from different peers may arrive in an order that violates causal dependencies (e.g., the server relays Bob's event that depends on Alice's event before Alice's event arrives). The event graph buffers such events until the missing parents arrive. The `ingestEvents` method maintains a buffer of pending events and flushes them in causal order as dependencies are satisfied.
- **Duplicate events.** If an event is received twice (e.g., due to a retry after an ambiguous connection drop), the event graph detects that the event ID already exists and ignores the duplicate. Events are idempotent by design.
- **Reconnection after long offline period.** When a client reconnects, it simply sends its current frontiers. The server computes the difference and sends all missing events --- whether the client was offline for seconds or days.

[@Fig:sync-reliability] illustrates how frontier-based sync recovers from a lost message.

![Frontier-based sync recovery. A message is lost, but on the next sync round Bob sends his frontiers, the server detects the gap, and resends the missing event.](img/sync-reliability.png){#fig:sync-reliability width=80%}

### Compaction and offline edits {#sec:compaction-offline}

When the event graph grows beyond a configurable threshold (50 events by default), the server attempts *compaction*: it waits until all active peers (those seen within a 5-minute activity window) have acknowledged the same frontier, materializes the document at that frontier, and replaces the room's event history with the materialized document as a new initial state. Peers that were offline during compaction receive a `compactedDocument` reset on their next sync.

A key concern is preserving edits that a peer made offline. The `resetToCompactedState` method handles this by saving the peer's unsynced local events before replacing the event graph with the compacted state. After ingesting any remaining events from the server's response, the saved edits are re-applied against the new compacted state. If a saved edit no longer applies --- for instance, because its target was deleted during the compacted history --- the re-apply fails silently and the edit is dropped. **This is a form of silent data loss**: the user's offline work is discarded without notification. A production system should log these failures, surface them as conflicts in the UI, or allow the user to manually resolve them. The current implementation prioritizes convergence over completeness in this edge case.

### Peer-ID uniqueness and threat model {#sec:peer-id}

Convergence in [@Sec:crdt-framing] rests on `EventId`s (pairs of peer identifier and per-peer sequence number) being globally unique. Two distinct events with the same `EventId` would let two different payloads inhabit the same node in the DAG at different peers, silently breaking strong eventual consistency. The implementation assumes an honest-but-fallible network: peer identifiers are assigned on first use and are expected to be unique for the lifetime of a given replica's event history (for example, via a random UUID generated at first launch and stored persistently).

Two concrete failure modes are worth calling out. *Peer-ID collision* --- two replicas independently generating the same peer identifier --- will cause `EventGraph.insertEvent` to detect a duplicate key when the second peer's events reach the first. The implementation raises an explicit error in this case (same key, different payload) rather than silently overwriting, but it cannot *recover* from the collision; the receiving replica must discard the conflicting branch or treat the two replicas as forked applications. *State restoration from a stale backup* --- a peer reusing an already-issued `(peer, seq)` pair after partial state loss --- is indistinguishable on the wire from malicious forgery and is likewise rejected at ingest. In both cases the implementation fails loudly, which is preferable to silent divergence, but we do not claim Byzantine fault tolerance: a truly malicious peer that controls its own `peer` identifier can always fork its own branch, and the honest peers will accept the fork if the `(peer, seq)` pairs do not collide with previously seen ones.

### Server architecture {#sec:server-architecture}

**Server architecture.** The sync server operates in *relay mode*: it stores and forwards events without materializing documents or running OT transformations. The computationally expensive work --- topological replay, `resolveAgainst`, and selector rewriting --- happens entirely on the client side. This means the server's per-message cost is limited to JSON parsing, inserting events into an in-memory `Map`, computing the frontier diff (`eventsSince`), and JSON encoding the response. Disk persistence is asynchronous and non-blocking: new events are appended to the NDJSON log in the background while the event loop continues processing other WebSocket messages. Because the server never calls `resolveAgainst`, the O(N²) materialization cost discussed in [@Sec:performance] does not affect server scalability.

The server uses Deno's single-threaded event loop. Rooms are independent (no shared state), so messages from different rooms are naturally interleaved without locks. For a production deployment with hundreds of concurrent rooms, a Worker-per-room architecture (Deno Workers provide separate JavaScript threads with isolated heaps) would provide stronger isolation, but the relay-mode design makes this unnecessary at the current scale.

**Room eviction.** Rooms are loaded into memory on first client connection and evicted after 10 minutes of inactivity with no connected clients. Evicted rooms remain on disk and are transparently reloaded when a client reconnects. This prevents unbounded memory growth from abandoned rooms while keeping active rooms fast (no disk access on each sync message).

**Disk persistence.** Room state is persisted as two files per room: a metadata file (`{roomId}.meta.json`) containing the initial document and its hash, written once on room creation, and an append-only event log (`{roomId}.events.ndjson`) in newline-delimited JSON format, where each line is one encoded event. New events are appended after each sync message using the POSIX append mode, which avoids rewriting the entire file. On load, the server reads the metadata and replays the event log. This append-only design matches the immutable nature of the event DAG --- events are never modified or deleted (except during compaction, which rewrites both files). A crash between sync and the append completing could lose the most recent events; on restart, rooms are recovered from the last successfully appended state.

## Web application {#sec:webapp}

The web application (`apps/mywebnicek`) demonstrates the core engine and supports interactive exploration of collaborative editing. Built with React 19, it uses the `useDenicek` hook from `@mydenicek/react` for reactive document state and WebSocket sync. The interface provides three panels ([@Fig:webapp-ui]): a rendered HTML view (formula results, clickable replay buttons), a raw JSON view, and an event DAG visualization. A command bar at the bottom executes edits via `/selector command args` syntax with tab completion.

![The mydenicek web application after merging concurrent edits. Left: rendered conference table. Center: raw JSON. Right: event DAG showing a fork-and-merge.](img/concurrent-merged.png){#fig:webapp-ui width=95%}

## CI/CD and hosting {#sec:ci-hosting}

Every push triggers CI (formatting, linting, type checking, tests, build). After CI passes, the web app deploys to GitHub Pages and the sync server to Azure Container Apps (scales to zero). Playwright browser tests verify live two-peer sync. Packages are published to JSR via `deno publish` with Sigstore provenance attestation. Event data is persisted to Azure Files as append-only NDJSON.

The source code is available at <https://github.com/krsion/mydenicek> and the live demo is deployed at <https://krsion.github.io/mydenicek>.
