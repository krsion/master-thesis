# Conclusion {#chap:conclusion}

This thesis set out to find a robust approach to collaborative editing for Denicek --- a document-oriented end-user programming system where users program by recording and replaying edit sequences over tree-structured documents. The original Denicek relied on Operational Transformation, which is fragile and scales poorly with the number of edit types. We asked whether a CRDT-based approach could provide the same semantic richness --- path-based addressing, wildcards, structural edits, programming by demonstration --- while guaranteeing strong eventual consistency.

We evaluated three approaches. Two established CRDT libraries, Automerge and Loro, proved strong for general-purpose JSON collaboration but exhibited a fundamental mismatch with Denicek's requirements: their opaque unique identifiers cannot express relative paths, wildcard expansion, or replay retargeting. This evaluation identified concrete limitations --- the concurrent wrap problem and the retargeting problem --- that motivated a custom design.

A key contribution of this thesis is identifying the right theoretical framework for the problem. Baquero et al.'s pure operation-based CRDT framework [@baquero2017pureop] turned out to be an excellent fit: the replica state is simply a grow-only set of tagged events (a G-Set), and the document is computed by a deterministic *eval* function that replays events in topological order. This separation of concerns --- append-only state for convergence, deterministic replay for semantics --- made it possible to focus the design effort on intention preservation rather than on consistency mechanics. Arriving at this choice required evaluating several CRDT families and recognizing that the pure op-based model could accommodate Denicek's domain-specific edits without the pairwise transformation matrices that plague classical OT.

The central technical contribution built on this framework is **intention preservation** through selector rewriting. When the document structure changes concurrently --- fields are renamed, nodes are wrapped, items are inserted or removed --- each operation must still reach its intended target and produce its intended effect. The rewriting rules ensure that references survive structural edits, wildcards expand over concurrent inserts, strict indices remain stable, and recorded edit sequences replay correctly after schema evolution. New edit types integrate through three generic virtual methods (`mapInsertedPayload`, `rewriteInsertedNode`, `applyListIndexShift`) rather than $O(n^2)$ pairwise rules, keeping the system extensible.

The resulting implementation, mydenicek, is published as `@mydenicek/core` and `@mydenicek/sync` on JSR. Materialization runs in $O(N + C_\text{total})$ time, completing under 4 ms on average for typical sessions ($N \le 100$). The system was validated on formative examples that exercise each requirement from the approach comparison, 358 tests (including a concurrent pair matrix and property-based convergence testing) with 90% branch coverage, and scaling benchmarks up to $N = 100{,}000$. Property-based tests provide evidence for the convergence claim beyond individual examples; benchmarks demonstrate practical feasibility. All examples are available as interactive demos at <https://krsion.github.io/mydenicek>.

## Discussion {#sec:discussion}

The design involves deliberate tradeoffs. Path-based selectors make Denicek's domain-specific operations natural --- wildcards, relative references, and replay retargeting all work directly on the tree structure --- but this comes at the cost of a specialized design not directly reusable for general JSON collaboration. The most notable omission is character-level text editing: mydenicek uses last-writer-wins for primitive strings, whereas Automerge and Loro support fine-grained text CRDTs. For Denicek's current use cases --- structured documents with formulas and recorded edit sequences --- this is an acceptable tradeoff, but it limits applicability to prose-heavy collaborative documents.

The event graph architecture is clean: append-only writes, deterministic reads, no mutable shared state. However, it has inherent limitations. The grow-only DAG grows without bound, and full materialization replays the entire history. The linear extension cache mitigates this for sequential appends, but concurrent events still trigger full recomputation. These costs are manageable for the session sizes observed in practice ($N \le 100$), but they define the boundary of the current design.

Finally, the evaluation scope supports practical viability rather than formal proof. The convergence argument rests on the pure op-based CRDT framework (G-Set state + deterministic eval) and is supported by property-based testing, but the selector rewriting rules have not been mechanically verified. The formative examples and concurrent pair matrix cover the interactions we identified, but they cannot exhaust all possible concurrent scenarios in an open-ended system.

## Future work {#sec:future-work}

The limitations above point to several directions for future work. Near-term improvements --- incremental evaluation and history compaction --- would extend the system's practical reach. Longer-term directions --- formal verification, peer-to-peer sync, and character-level text --- would broaden its applicability.

**Scaling to large peer counts.** The complexity analysis treats the number of peers $P$ as a constant (2--5 peers). For larger groups, vector clock operations become $O(P)$ and start to matter. Analyzing and optimizing materialization for large $P$ is an open problem.

**Incremental eval.** The linear extension cache already makes sequential appends incremental --- only new events are replayed. However, after receiving concurrent remote events, `materialize` still recomputes from scratch. Incremental re-evaluation that patches only the affected portion of the document would reduce cost for concurrent edits.

**History compaction.** The grow-only event DAG grows without bound. Snapshotting the materialized state and pruning old events would reduce storage and replay cost for long-lived documents and new replicas joining late.

**Formal verification.** Encoding the selector rewriting rules in VeriFx [@deporre2023verifx] or TLA+ would provide mechanical correctness guarantees beyond empirical testing.

**Peer-to-peer sync.** The current sync protocol relies on a centralized WebSocket relay server. Enabling true peer-to-peer sync would remove the single point of failure and reduce latency for co-located peers.

**Network-efficient encoding.** Events are currently serialized as JSON. A compact binary encoding would reduce bandwidth and improve sync performance, especially for large event histories.

**Fine-grained retransmission.** When a single event is lost, the frontier-based catch-up resends all events that causally depend on it. A protocol that tracks individual missing events would avoid redundant retransmission.

**Character-level text.** Integrating a text CRDT (e.g., Fugue) for primitive strings would replace last-writer-wins semantics, though the interaction with selectors, undo, and the formula engine would require careful design.
