# Implementation {#chap:implementation}

This chapter describes the architecture and implementation of the mydenicek system --- a custom OT-based CRDT engine for collaborative editing of tagged document trees.

## Architecture Overview

\todo{Monorepo structure: packages/core, packages/react, packages/sync-server, apps/mywebnicek. Diagram showing the layers. Published on JSR.}

## Document Model

\todo{Four node types: Record (named fields + tag), List (ordered items + tag), Primitive (string/number/boolean), Reference ($ref with relative paths). PlainNode type. Selectors: /path/to/field, wildcards /items/*, strict indices /items/!0.}

## Event DAG

\todo{Events: immutable, identified by EventId (peer:seq). Parents: the frontier at creation time. Vector clocks for causal ordering. Kahn's algorithm for deterministic topological sort with EventId tie-breaking. Materialization: replay all events in topological order against the initial document.}

## Edit Types and OT Rules

\todo{List of edit types: add, delete, rename, set, pushBack, pushFront, popBack, popFront, updateTag, wrapRecord, wrapList, copy, applyPrimitiveEdit. For each structural edit, describe the OT transformation rule: how it rewrites selectors of concurrent edits. Focus on the most interesting ones: rename transforms paths, wrap adds/removes path segments.}

## Undo and Redo

\todo{Each Edit computes its own inverse. Undo creates a new event with the inverse edit. Redo re-applies the undone edit. All inverses are regular events that sync normally.}

## Formula Engine

\todo{Tag-based formula evaluators: x-formula-plus, split-first, split-rest. References via $ref with relative path resolution. evaluateAllFormulas walks the plain tree and evaluates all formula nodes.}

## Recording and Replay

\todo{Programming by demonstration: record edit event IDs, store as replay steps. repeatEditsFrom replays a sequence. resolveReplayEdit transforms the replayed edit through all later structural changes via OT. Batch-aware replay excludes same-batch events from retargeting.}

## Sync Protocol

\todo{WebSocket-based: drain pending events, send to server, receive from server via applyRemote. Server is a pure relay (relayMode) --- stores and forwards events without materializing. Initial document hash validation. Pause/resume support.}

## Web Application

\todo{React UI: command bar with tab completion, rendered document view, raw JSON view, event graph DAG visualization. Multi-document tabs with template system. DebouncedInput for efficient editing.}
