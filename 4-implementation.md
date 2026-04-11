# Implementation {#chap:implementation}

This chapter describes the architecture and implementation of mydenicek --- a custom OT-based CRDT engine for collaborative editing of tagged document trees. The implementation is a Deno monorepo published on JSR as `@mydenicek/core`, `@mydenicek/react`, and `@mydenicek/sync-server`.

## Architecture overview {#sec:architecture}

The system is organized in four layers, as shown in [@Fig:architecture].

![Architecture of the mydenicek monorepo. The web application depends on React bindings and the sync server, both of which depend on the core CRDT engine.](img/architecture.png){#fig:architecture width=70%}

The layers are:

- **`packages/core`** (`@mydenicek/core` [@mydenicek_core]) --- the CRDT engine. Contains the document model, event DAG, edit types, OT transformation rules, undo/redo, formula engine, and recording/replay. Zero external runtime dependencies; pure TypeScript.
- **`packages/react`** (`@mydenicek/react` [@mydenicek_react]) --- React bindings. The `useDenicek` hook provides reactive document state, mutation helpers, and sync lifecycle management.
- **`packages/sync-server`** (`@mydenicek/sync-server` [@mydenicek_sync]) --- sync protocol. WebSocket-based client and server for exchanging events between peers. The server operates in *relay mode*: it stores and forwards events without materializing documents or understanding edit semantics.
- **`apps/mywebnicek`** --- web application. React 19 + Fluent UI interface with a terminal-style command bar, rendered document view, raw JSON view, and event graph DAG visualization.

The layered design ensures that the CRDT engine has no knowledge of the UI or transport layer, and the sync server has no knowledge of edit types. Custom primitive edits (such as `splitFirst` and `splitRest`) are registered only in the application layer and do not need to be known by the server.

### Technology choices

**TypeScript.** Local-first applications target the browser, where JavaScript is the dominant language. TypeScript adds static type safety, which is particularly valuable in a CRDT engine where subtle type errors (e.g., confusing a selector path with a plain string, or passing the wrong event structure) can cause silent convergence failures.

**Deno.** Deno simplifies adhering to best practices: it runs TypeScript natively without a compilation step, includes a built-in formatter, linter, and test runner, and enforces strict mode by default. This eliminates the configuration overhead of separate tools (ESLint, Prettier, Jest, tsconfig) that a Node.js project would require.

**JSR.** JSR (JavaScript Registry) is a package registry developed by the Deno team as an alternative to npm. It accepts TypeScript source directly (npm requires pre-compiled JavaScript), which simplifies the publishing workflow. The three mydenicek packages are published on JSR.

## Document model {#sec:doc-model}

Documents are modeled as tagged trees with four node types:

- **Record** --- a set of named fields, each containing a child node, plus a structural tag.
- **List** --- an ordered sequence of child nodes with a structural tag.
- **Primitive** --- a scalar value: string, number, or boolean.
- **Reference** --- a pointer to another node via a relative or absolute path.

Nodes are addressed by *selectors* --- slash-separated paths that describe how to navigate the tree from the root. The selector `speakers/0/name` navigates to the `speakers` field, then to the first list item (index 0), then to the `name` field. Selectors support three special forms:

- **Wildcards** (`*`): `speakers/*` expands to all children of the `speakers` list. An edit targeting `speakers/*` is applied to every item.
- **Strict indices** (`!0`): `speakers/!0` refers to the item at index 0 *at the time of the edit*. Unlike plain `0`, strict indices are not shifted by concurrent insertions --- they always refer to the original position.
- **Parent navigation** (`..`): used in references to navigate up the tree. `../../0/contact` goes up two levels, then navigates to `0/contact`.

## Event DAG {#sec:event-dag}

The event DAG is the core data structure of the CRDT. Each edit creates an immutable *event* containing:

- **EventId** --- a unique identifier `peer:seq`, where `peer` is the peer's string identifier and `seq` is a monotonically increasing sequence number. For example, `alice:3` is Alice's third event.
- **Parents** --- the set of event IDs that form the *frontier* at the time the event was created. These are the most recent events the peer had seen. An event with multiple parents represents a state that has merged concurrent branches.
- **Edit** --- the actual edit operation (add, delete, rename, set, pushBack, wrapRecord, etc.) with its target selector and arguments.
- **Vector clock** --- a map from peer ID to the highest sequence number seen from that peer. The vector clock enables causal ordering: event A *happens-before* event B if A's vector clock is dominated by B's. Two events are *concurrent* if neither dominates the other.

[@Fig:event-dag] shows an example event DAG with two peers. Alice creates a conference list and refactors it to a table (blue events). Bob concurrently adds speakers (green events). Event `alice:9` is a merge commit with two parents, reducing the frontier to a single point.

![Example event DAG with concurrent editing. Alice (blue) refactors a list to a table while Bob (green) adds speakers. The merge commit has two parents.](img/event-dag.png){#fig:event-dag width=80%}

### Materialization

To reconstruct the document from the event DAG, we perform *deterministic topological replay*:

1. Sort all events in topological order using Kahn's algorithm. When multiple events have no unprocessed dependencies (i.e., they are concurrent), break ties deterministically by comparing their `EventId` values lexicographically.
2. Starting from the initial document, apply each event's edit in order. Before applying, call `resolveAgainst` --- the OT step that transforms the edit's selector through all previously applied concurrent edits.
3. If a transformed edit becomes invalid (e.g., it targets a node that was deleted by a concurrent edit), it becomes a *no-op conflict* that is recorded but does not modify the document.

Because the sort order is deterministic and the OT transformations are deterministic, any two peers that have received the same set of events will produce the same document. This is the strong eventual consistency guarantee.

### Frontier

The *frontier* is the set of event IDs that have no descendants --- the "tips" of the DAG. When a peer creates a new event, the current frontier becomes the event's parents, and the event becomes the new frontier. When two branches merge (a peer receives events from another peer), the frontier may contain events from multiple peers. A post-merge edit creates an event with multiple parents, reducing the frontier back to a single point.

## Edit types and OT rules {#sec:edit-types}

The system supports the following edit types, listed in [@Tbl:edit-types].

: Edit types supported by the mydenicek CRDT engine. {#tbl:edit-types}

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

Each structural edit (rename, wrap, delete) has a `transformSelector` method that rewrites the selector of a concurrent edit. [@Fig:ot-rename] illustrates the rename transformation.

![OT rename transformation. A concurrent edit targeting `speakers/0/name` is transformed to `talks/0/name` after a rename operation.](img/ot-rename.png){#fig:ot-rename width=70%}

The key transformation rules are:

- **Rename**: if a concurrent edit targets `speakers/0/name` and a rename changes `speakers` to `talks`, the concurrent edit's selector is transformed to `talks/0/name`.
- **WrapRecord**: if a concurrent edit targets `speakers/0/value` and a wrap turns `value` into `{$tag: "wrapper", value: <original>}`, the concurrent edit's selector gains a segment: `speakers/0/value/value`.
- **WrapList**: similar to WrapRecord but wraps into a list, adding an index segment.
- **Delete**: if a concurrent edit targets a field that was deleted, the edit becomes a no-op conflict.
- **PushFront**: shifts numeric indices in concurrent selectors (e.g., `items/0` becomes `items/1`).

### Wildcard edits and concurrent insertions {#sec:wildcard-concurrent}

A notable property of the OT-based replay approach is how wildcard edits interact with concurrent insertions. When Alice applies `updateTag("speakers/*", "tr")` --- changing the tag of every item in the list --- and Bob concurrently inserts a new item via `pushBack("speakers", ...)`, the OT transformation ensures that Alice's wildcard edit also affects Bob's newly inserted item.

This happens because during deterministic replay, Bob's `pushBack` is applied first (or after, depending on topological order), and Alice's wildcard `*` expands to include *all items that exist at the point of replay* --- including Bob's concurrent insertion. The result is that the newly added item also receives the tag update, even though it did not exist when Alice made her edit.

This semantics is uncommon in CRDTs. In most CRDT-based systems, an operation only affects the items that existed at the time the operation was created. Newly inserted items are not retroactively affected by concurrent bulk operations. Weidner [@weidner2023foreach] describe this as the *for-each* problem and propose a dedicated CRDT operation to address it. In mydenicek, the replay-based approach naturally achieves the "for-each-including-concurrent-additions" semantics because the wildcard is expanded at replay time, not at creation time --- no special for-each CRDT is needed.

## Undo and redo {#sec:undo}

Each `Edit` subclass implements a `computeInverse(preDoc)` method that returns the inverse edit. For example, the inverse of `RecordAddEdit("field", value)` is `RecordDeleteEdit("field")`, and the inverse of `WrapRecordEdit` is `UnwrapRecordEdit`.

Undo creates a new event containing the inverse edit. This event is a regular event in the DAG --- it syncs to other peers automatically. Redo re-applies the undone edit. The undo/redo stacks are maintained per-peer and only track local events.

## Formula engine {#sec:formulas}

The formula engine supports two kinds of formulas:

- **Tag-based evaluators** --- registered for specific node tags. For example, a node with `$tag: "split-first"` containing a `source` field and a `separator` field evaluates to the substring before the separator. Built-in evaluators include `x-formula-plus`, `x-formula-minus`, `x-formula-times`, `split-first`, and `split-rest`.
- **Operation-based formulas** --- nodes with `$tag: "x-formula"` and an `operation` field. Arguments are provided as a list that may contain primitive values or `$ref` references. Built-in operations include `sum`, `product`, `concat`, `uppercase`, `lowercase`, `countChildren`, and others.

References (`$ref`) in formula arguments are resolved relative to the formula's position in the tree. The formula engine walks the entire document tree, evaluates all formula nodes, and returns a map from path to result. Circular references are detected and reported as errors.

## Recording and replay {#sec:replay}

Programming by demonstration is implemented through event recording and replay:

1. **Recording.** When a user performs an edit, the resulting event ID is stored in a list of *replay steps* --- typically attached to a button node in the document.
2. **Replay.** When the user clicks the button, each step's event ID is passed to `resolveReplayEdit`, which walks the full causal history and transforms the replayed edit through every later structural change. This ensures the replay targets the correct location even if the document structure has changed since recording.
3. **Batch replay.** When replaying multiple steps as a batch (e.g., all steps of an "Add Speaker" button), same-batch events are excluded from retargeting each other. This prevents cascading transformations within a single replay sequence.

The replay mechanism uses the same OT infrastructure as materialization --- the difference is that during replay, only the single replayed event is transformed, not the entire history.

## Sync protocol {#sec:sync}

The sync protocol uses WebSocket connections with a simple message exchange, illustrated in [@Fig:sync-protocol].

![Sync protocol sequence diagram. Alice and Bob connect to the server, exchange initial documents and events, and converge to the same state.](img/sync-protocol.png){#fig:sync-protocol width=80%}

The protocol consists of three phases:

1. **Connect.** The client sends a `hello` message with the room ID. If the room exists, the server responds with the initial document.
2. **Sync.** The client sends its pending events and current frontiers. The server responds with events the client has not seen (computed via `eventsSince(clientFrontiers)`).
3. **Ongoing.** As either peer produces new events, they are exchanged via the same sync message format.

The server maintains a `SyncRoom` for each room, containing a `Denicek` instance in *relay mode*. In relay mode, the event graph stores and forwards events without materializing the document --- the `validateEventAgainstCausalState` step is skipped. This means the server does not need to know about custom primitive edits or formula evaluators; it only needs to understand the event structure.

Initial documents are validated by hash: the first client to sync with a room sets the room's initial document hash, and subsequent clients must match it.

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

The web application (`apps/mywebnicek`) provides three synchronized views of the document:

- **Rendered view** --- the document tree rendered as HTML elements based on node tags. Formula nodes display their evaluated results. Buttons trigger replay of recorded edit sequences.
- **Raw JSON view** --- syntax-highlighted JSON representation of the plain document tree.
- **Event graph view** --- an SVG visualization of the causal DAG showing events as nodes, causal dependencies as edges, peer colors, and frontier indicators. Clicking an event shows its details (edit type, selector, vector clock).

The command bar at the bottom provides a terminal-style interface for executing edits. The syntax is `/selector command args` --- for example, `/speakers updateTag table` or `/speakers/*/0/contact splitFirst , `. Tab completion suggests path segments and valid commands for the selected node type. Registered primitive edits are automatically available as commands.
