# System {#chap:system}

This chapter describes the engineering aspects of mydenicek. The implementation is a Deno/TypeScript monorepo published on JSR, organized in three packages ([@Fig:architecture]): `@mydenicek/core` (the CRDT engine --- pure TypeScript, no WASM, single runtime dependency), `@mydenicek/react` (React bindings), and `@mydenicek/sync` (WebSocket relay). Two applications use them: a web frontend (`apps/mywebnicek`) and a deployed sync server (`apps/sync-server`). The core has no knowledge of the transport layer; the server has no knowledge of edit types.

![Architecture of the mydenicek monorepo. The core engine is transport-agnostic; the sync server operates in relay mode.](img/architecture.png){#fig:architecture width=70%}

## Extensibility {#sec:extensibility}

The core engine is extended via two registries:

- **Primitive edits.** Applications register custom transformations on primitive values via `registerPrimitiveEdit(name, fn)` — for example, `splitFirst` and `splitRest` for the conference table.
- **Formula operations.** Custom formula evaluators are registered via `registerFormulaOperation` and `registerTagEvaluator`.

Both are stored by name in the event DAG and replayed on all peers. The sync server does not need to know about them.

## Formula engine {#sec:formulas}

The formula engine supports two kinds of formulas: **tag-based** (a `RecordNode` with a specific tag, e.g., `split-first`, evaluates based on its fields) and **operation-based** (a `RecordNode` with tag `x-formula` and an `operation` field applied to an argument list).

The engine operates on the internal `Node` tree, not the serialized `PlainNode` representation. References in formula arguments are `ReferenceNode` instances whose selectors have already been retargeted by `updateReferences` after structural edits. An `evaluateChild` helper resolves references transparently before evaluators see them: `PrimitiveNode` values pass through, `ReferenceNode` instances resolve via `Node.navigate`, and nested formulas recurse. Circular references are detected by a visited-set check. Wildcards in reference paths expand to multiple nodes, enabling patterns like `sum({$ref: "../*/price"})`.

## Undo and redo {#sec:undo}

Each `Edit` implements `computeInverse(preDoc)` returning the inverse edit (e.g., `RecordAddEdit` → `RecordDeleteEdit`). Undo creates a new event containing the inverse, computed against the document state at the original event's parent frontier. This event syncs to all peers like any other edit. Redo re-applies the original edit. `CopyEdit` snapshots every target subtree before the copy, producing a `RestoreSnapshotEdit` that restores each overwritten subtree on undo.

## Recording and replay {#sec:replay}

Programming by demonstration stores event IDs as replay steps (typically in a button node). On replay, the system replays the full event history in topological order, captures the source event's edit, and transforms its selector through every later edit — both structural edits (which rewrite the selector) and wildcard-targeting data edits (which modify the inserted payload). This is the same OT pipeline used for concurrent resolution. The result is a new event at the current frontier with a retargeted selector and payload. Strict indices (`!0`) ensure the replayed edit targets the same logical position rather than being shifted by later insertions.

## Sync and server {#sec:sync}

Convergence requires only that all peers eventually receive the same event set. mydenicek uses a centralized WebSocket relay server ([@Fig:sync-protocol]). On connection, the server sends a **hello** with the room's initial document. After that, both sides exchange **sync** messages containing their current frontiers and any events the other side is missing (computed via `eventsSince`). The same sync message format is used for the initial catch-up and for every subsequent exchange.

![Sync protocol sequence diagram.](img/sync-protocol.png){#fig:sync-protocol width=80%}

The server operates in **relay mode**: it stores and forwards events without materializing documents or running OT. The O(N²) materialization cost is entirely client-side. Rooms are loaded on first connection and evicted after 10 minutes of inactivity. Events are persisted to append-only NDJSON files.

**Reliability** is achieved through frontier-based catch-up: each sync message includes frontiers, so dropped connections are recovered by resending missing events on reconnection. Duplicate events are detected by event ID and ignored. Out-of-order events are buffered until their parents arrive.

**Causal stability.** Following Bauwens and Gonzalez Boix [@bauwens2020stability], the server tracks each peer's observation progress via a `CausalStabilityTracker`. On every sync exchange, the tracker is updated with the room's merged frontier clock. An event is *causally stable* when all known peers have observed it. Stability information is useful for observability (detecting lagging peers) and as a prerequisite for future client-side metadata pruning ([@Sec:future-work]). However, **the server cannot use stability for compaction**: since it operates in relay mode and does not register application-specific edit implementations (e.g., `splitFirst`, `splitRest`), it cannot materialize the document. Compaction would require either (a) the server knowing all edit types (breaking the relay abstraction) or (b) a client sending a materialized snapshot (trading memory savings for network overhead). Neither is justified for the current use case.

**Peer-ID uniqueness** is assumed: `EventId = (peer, seq)` must be globally unique. Collisions are detected at ingest and rejected rather than silently overwritten.

## Web application {#sec:webapp}

The web application (`apps/mywebnicek`) uses the `useDenicek` React hook for reactive document state and WebSocket sync. The interface provides three panels ([@Fig:webapp-ui]): rendered HTML, raw JSON, and an event DAG visualization. A command bar executes edits via `/selector command args` syntax.

![The mydenicek web application after merging concurrent edits. Left: rendered conference table. Center: raw JSON. Right: event DAG showing a fork-and-merge.](img/concurrent-merged.png){#fig:webapp-ui width=95%}

## CI/CD and hosting {#sec:ci-hosting}

Every push triggers CI (formatting, linting, type checking, tests, build). The web app deploys to GitHub Pages; the sync server to Azure Container Apps. Playwright browser tests verify live two-peer sync. Packages are published to JSR with Sigstore provenance attestation. The source code is at <https://github.com/krsion/mydenicek> and the live demo at <https://krsion.github.io/mydenicek>.
