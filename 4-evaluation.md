# Evaluation {#chap:evaluation}

## Formative examples {#sec:formative-examples}


### Hello World: custom primitive edits and replay {#sec:hello-world}

The first example demonstrates two fundamental capabilities: *custom primitive edits* and *wildcard replay*.

We start with a list of messages with inconsistent capitalization. A custom primitive edit `capitalize` is registered that title-cases a string. The edit is applied to one message on a "recorded" peer, then the events are synced to a "replay" peer. The replay peer replays the same edit targeting `messages/*` --- the wildcard causes the capitalize transformation to be applied to every item in the list.

```typescript
// Register a custom primitive edit
registerPrimitiveEdit("capitalize", (value) => {
  if (typeof value !== "string") throw new Error("expects string");
  return value.toLowerCase().split(" ")
    .map(w => w[0].toUpperCase() + w.slice(1)).join(" ");
});

// Apply to one message, sync, then replay on all
const eventId = recordedPeer.applyPrimitiveEdit(
  "messages/0", "capitalize");
sync(recordedPeer, replayPeer);
replayPeer.replayEditFromEventId(eventId, "messages/*");
// Result: all messages title-cased
```

This example shows that the CRDT is extensible --- users can register domain-specific transformations that participate in the event DAG and can be replayed like any other edit.

### Counter: formulas and programming by demonstration {#sec:counter}

The counter example demonstrates the *formula engine* and *recording/replay* (programming by demonstration). [@Fig:formative-counter] shows the counter after one increment.

![Counter example: the value 1 is computed by the `x-formula-plus` formula node wrapping the original 0. The "Increment" button replays three recorded edits.](img/formative-counter.png){#fig:formative-counter width=40%}

The document starts with a simple `counter/value = 0`. We record three edits that implement "increment":

```typescript
// Step 1: Wrap the value in a formula node.
// Before: { counter: { value: 0 } }
const wrapId = doc.wrapRecord(
  /* target */ "counter/value",
  /* field  */ "value",
  /* tag    */ "x-formula-plus",
);
// After:  { counter: { value: { $tag: "x-formula-plus",
//                                value: 0 } } }

// Step 2: Rename "value" to "left" inside the formula.
const renameId = doc.rename(
  /* target */ "counter/value",
  /* from   */ "value",
  /* to     */ "left",
);
// After:  { counter: { value: { $tag: "x-formula-plus",
//                                left: 0 } } }

// Step 3: Add the "right" operand.
const addRightId = doc.add(
  /* target */ "counter/value",
  /* field  */ "right",
  /* value  */ 1,
);
// After:  { counter: { value: { $tag: "x-formula-plus",
//                                left: 0, right: 1 } } }
```

The three event IDs are stored as replay steps in a button node. The `insert` call with index `-1` appends to the end of the list. Negative indices are end-relative --- `-1` means the last position, `-2` means before the last item, and so on. They are resolved at replay time relative to the current list length, so concurrent insertions do not shift them:

```typescript
doc.insert(
  /* target */ "counter/btn/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: wrapId },
);
doc.insert(
  /* target */ "counter/btn/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: renameId },
);
doc.insert(
  /* target */ "counter/btn/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: addRightId },
);
```

Each time the button is "clicked" (the steps are replayed), a new `x-formula-plus` layer wraps the previous result:

```
0 -> { $tag: "x-formula-plus",
       left: 0, right: 1 }           = 1
  -> { $tag: "x-formula-plus",
       left: { $tag: "x-formula-plus",
               left: 0, right: 1 },
       right: 1 }                     = 2
```

The formula engine evaluates the nested structure recursively, computing `((0+1)+1) = 2`. This pattern works for any operation --- multiplication, concatenation, or custom formulas.

### Conference List: adding items with recorded edits {#sec:conf-list}

The conference list demonstrates how recorded edits work with an input field and a button to add items to a list. [@Fig:formative-conf-list] shows the rendered list.

![Conference list example: an input field, an "Add" button, and a bullet list of speakers. The button replays two recorded edits (insert + copy from input).](img/formative-conf-list.png){#fig:formative-conf-list width=40%}

The document contains a list of speakers (each with a `"Name, email"` string), an input field, and an "Add" button. We record two edits:

```typescript
// Record the "add speaker" recipe
const pushId = doc.insert(
  /* target */ "conferenceList/items",
  /* index  */ 0,
  /* value  */ { $tag: "li", text: "" },
  /* strict */ true,
);
const copyId = doc.copy(
  /* target */ "conferenceList/items/!0/text",
  /* source */ "conferenceList/composer/input/value",
);

// Store as replay steps in the button
doc.insert(
  /* target */ "conferenceList/composer/addAction/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: pushId },
);
doc.insert(
  /* target */ "conferenceList/composer/addAction/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: copyId },
);
```

The `!0` strict index is crucial: it refers to the item at position 0 *at the time of recording*. During replay, OT transforms this index if concurrent insertions have shifted it.

When the button is replayed, it creates a new item and fills it with whatever text is currently in the input field. Two peers can concurrently add speakers --- after sync, both items appear in the list.

### Conference Table: structural transformation {#sec:conf-table}

The conference table example is the most complex formative example. It demonstrates *schema evolution* --- refactoring a flat list into a structured table using only the edit operations available in the CRDT. [@Fig:formative-conf-table] shows the final table after the transformation. The document tree before and after the transformation:

**Before** --- a flat conference list:

```html
<ul>
  <li contact="Ada Lovelace, ada@example.com" />
  <li contact="Grace Hopper, grace@example.com" />
</ul>
```

**After** --- a two-column table with formula cells:

```html
<table>
  <tr>
    <td>
      split-first(source="Ada Lovelace, ada@example.com")
        = "Ada Lovelace"
    </td>
    <td>
      split-rest(source=ref("../../0/contact/source"))
        = "ada@example.com"
    </td>
  </tr>
  <tr>
    <td>
      split-first(source="Grace Hopper, grace@example.com")
        = "Grace Hopper"
    </td>
    <td>
      split-rest(source=ref("../../0/contact/source"))
        = "grace@example.com"
    </td>
  </tr>
</table>
```

![Conference table after structural transformation: names and emails are split into separate columns using `split-first` and `split-rest` formula nodes. The "Add Speaker" button adds complete table rows.](img/formative-conf-table.png){#fig:formative-conf-table width=40%}

Starting from the conference list (a `<ul>` with `<li>` items containing `"Name, email"` strings), Alice performs the following structural transformation. Each step shows the intermediate document state, demonstrating how the tree evolves:

**Step 1: Change tags.** Retag the list and its items.

```typescript
alice.updateTag("speakers", "table");
alice.updateTag("speakers/*", "td");
```

```html
<!-- Before -->
<ul>
  <li contact="Ada..." />
  <li contact="Grace..." />
</ul>

<!-- After -->
<table>
  <td contact="Ada..." />
  <td contact="Grace..." />
</table>
```

**Step 2: Wrap each `<td>` in a `<tr>` row.**

```typescript
alice.wrapList("speakers/*", "tr");
```

```html
<!-- Before -->
<table>
  <td contact="Ada..." />
  <td contact="Grace..." />
</table>

<!-- After -->
<table>
  <tr> <td contact="Ada..." /> </tr>
  <tr> <td contact="Grace..." /> </tr>
</table>
```

**Step 3: Wrap the contact string in a `split-first` formula.** The original value becomes the `source` field of the wrapper node.

```typescript
alice.wrapRecord(
  /* target */ "speakers/*/0/contact",
  /* field  */ "source",
  /* tag    */ "split-first",
);
```

```html
<!-- Before -->
<tr>
  <td contact="Ada Lovelace,
        ada@example.com" />
</tr>

<!-- After -->
<tr>
  <td contact=
    split-first(source="Ada Lovelace,
           ada@example.com") />
</tr>
```

After formula evaluation, the cell displays `"Ada Lovelace"`.

**Step 4: Add the email column.** Insert a second `<td>` into each `<tr>`, with a `split-rest` formula whose `source` is a reference to the name cell's source string.

```typescript
alice.insert(
  /* target */ "speakers/*",
  /* index  */ -1,
  /* value  */ {
    $tag: "td",
    email: {
      $tag: "split-rest",
      source: { $ref: "../../0/contact/source" },
    },
  },
);
```

```html
<!-- Final result after formula evaluation -->
<table>
  <tr>
    <td> "Ada Lovelace" </td>
    <td> "ada@example.com" </td>
  </tr>
  <tr>
    <td> "Grace Hopper" </td>
    <td> "grace@example.com" </td>
  </tr>
</table>
```

The wildcard `*` in all four steps ensures that the transformation is applied to every row simultaneously. All edits are recorded as events in the DAG. Importantly, the "Add Speaker" button recorded in the list phase continues to work after the refactoring --- see [@Sec:replay-after-refactor].

### Conference Table: concurrent editing {#sec:conf-concurrent}

Two peers start from the same conference list, disconnect, and make concurrent edits: **Alice** refactors the list into a table (as above), while **Bob** adds two new speakers via `insert`. When they reconnect and sync, Alice's wildcard edits automatically expand to include Bob's concurrently inserted items: `updateTag` changes their tags, `wrapList` wraps them in `<tr>` lists, and `insert` adds the split formula cells. The result is a table with all four speakers --- each with correctly split name and email columns --- even though Bob inserted plain `<li>` items into a `<ul>` list. This *wildcard-affects-concurrent-insertions* property ([@Sec:wildcard-concurrent]) is a direct consequence of the replay-based OT approach.

[@Fig:concurrent-initial;@Fig:concurrent-alice;@Fig:concurrent-bob;@Fig:concurrent-merged] show the four stages of this process.

![Initial state: both peers synced with a flat conference speaker list.](img/concurrent-initial.png){#fig:concurrent-initial width=95%}

![Alice (offline) refactors the list into a two-column table with split-first/split-rest formulas.](img/concurrent-alice.png){#fig:concurrent-alice width=95%}

![Bob (offline) adds two speakers to the original list structure.](img/concurrent-bob.png){#fig:concurrent-bob width=95%}

![After merge: all four speakers appear in the table. The event graph shows the concurrent fork merging at a single commit.](img/concurrent-merged.png){#fig:concurrent-merged width=95%}

### Button replay after schema evolution {#sec:replay-after-refactor}

Recorded edit sequences survive structural refactoring. The "Add Speaker" button was recorded against a flat `<ul>` list --- its steps insert a `<li>` item and copy the input value. After Alice refactors the list into a `<table>` with formula columns, clicking the button still works: each recorded step is retargeted through all structural edits that happened after recording. The replayed insert produces a complete table row with split-first and split-rest cells, as if recorded against the table.

This uses the same OT transformations as concurrent editing. The only difference is that replay transforms through *all* later edits (not just concurrent ones), because the recorded edit's position in the DAG is at the recording point.



## Approach comparison {#sec:comparison}

[@Tbl:approach-comparison] summarizes the three approaches evaluated in this thesis against Denicek's key requirements.

: Comparison of the three approaches against Denicek's requirements. {#tbl:approach-comparison}

| Requirement | Automerge | Loro | mydenicek (custom) |
|---|---|---|---|
| Atomic move/wrap | No (two-step) | Yes (movable tree) | Yes (structural selector rewriting) |
| Path-based addressing | No (opaque IDs) | No (opaque IDs) | Yes (native) |
| Wildcard selectors | No | No | Yes |
| Relative references | No | No | Yes ($ref paths) |
| Replay retargeting | No | No (ID-based) | Yes (selector rewriting) |
| For-each semantics | No | No | Yes (wildcard expansion) |
| Character-level text | Yes | Yes (Fugue) | No (LWW) |
| Runtime deps | WASM + JS | WASM + JS | JS only (Deno `@std`) |

Automerge and Loro excel at general-purpose collaborative JSON editing but lack the path-based features Denicek requires. The custom approach sacrifices character-level text editing (a limitation) but gains native support for all of Denicek's programming-by-demonstration features.

**Comparison with the original Denicek.** The original Denicek uses a Git-like model: peers work on local branches and merge manually. mydenicek replaces this with automatic merge — the CRDT's deterministic replay resolves concurrent edits without user intervention. The trade-off is that automatic resolution follows fixed rules (topological order determines winners), whereas manual merge lets the user choose.

[@Tbl:approach-comparison] is evaluated against Denicek's requirements. For other use cases, Automerge and Loro offer advantages: character-level text editing, compact binary encoding for millions of operations, mature ecosystems, and peer-to-peer transport. mydenicek sacrifices these for native path-based selectors, wildcards, and structural edit rewriting.

## Formative example results {#sec:results}

All six formative examples pass their tests. The conference table with concurrent editing is the most significant: it exercises the full OT pipeline — wildcard expansion, structural transformations, formula creation, and concurrent list insertions — in a single scenario, producing a consistent merged table from independently edited structures.

## Testing strategy {#sec:testing}

Testing distributed systems is fundamentally harder than testing sequential programs: bugs arise from specific interleavings of concurrent events, message orderings, and failure patterns that are difficult to reproduce [@ozkan2025modelfuzz]. mydenicek addresses this through multiple testing layers, combining unit tests for individual edit types with property-based randomized testing for concurrent interactions:

- **Unit tests** (over 280 cases) covering core operations, OT transformation rules, edge cases, and error handling.
- **Property-based tests** using `fast-check`, described in detail in [@Sec:property-tests].
- **6 formative example tests** that simulate realistic multi-peer workflows including recording, replay, formula evaluation, and button replay after schema evolution.
- **11 sync end-to-end tests** covering synchronization, late join, concurrent edits, reconnection, and offline convergence.
- **Playwright browser tests** verifying two browser peers can sync edits via the deployed server.
- **Continuous integration** via GitHub Actions on every push.

## Property-based tests {#sec:property-tests}

The file `tests/core-properties.test.ts` uses the `fast-check` library to randomize edit sequences, sync operations, and delivery orders, then asserts invariants on the resulting document states. This approach is a form of *randomized concurrency testing* [@ozkan2025modelfuzz]: instead of enumerating all possible interleavings (infeasible for concurrent edit operations on tree structures), the fuzzer samples random edit sequences and `fast-check`'s shrinking algorithm reduces failing cases to minimal counterexamples.

The tests run against five document schemas (flat list, flat record, nested list-of-records, deeply nested lists, document with references) and exercise all eleven edit types. The default configuration models three `Denicek` peers; a separate test suite uses five peers to verify that convergence holds beyond pairwise interactions. Operations are either local edits or pairwise sync actions; each test generates sequences of 5 to 50 operations per run.

The invariants checked are:

- **Convergence.** After a final full sync round, all peers serialize to the same JSON. This directly exercises the theorem of [@Sec:crdt-framing].
- **Idempotency.** Re-delivering an already-ingested event has no effect.
- **Commutativity.** For two disjoint remote event batches, ingesting them in either order produces the same document.
- **Associativity.** For three peers producing disjoint events, any pairwise merge order yields the same state.
- **Intent preservation.** Non-conflicting concurrent additions all appear in the merged document.
- **Out-of-order delivery tolerance.** Shuffled event delivery with the causal buffer produces the same state as causal delivery.

The property suite caught several bugs during development: wildcard-over-concurrent-insert failures and copy-then-rename retargeting errors were both discovered by shrunk counterexamples.

## Performance {#sec:performance}

[@Tbl:perf-bench] reports wall-clock ingest and materialize times for three synthetic workloads measured on a single thread (`tools/bench-materialize.ts`, Deno 2 on Windows x64). Times are milliseconds; per-event is microseconds.

: Ingest and materialize cost on three workloads of size $N$. {#tbl:perf-bench}

| Workload | $N$ | Total (ms) | Per event (μs) | Materialize (ms) |
|---|---:|---:|---:|---:|
| local-append  | 100  | 4.1   | 41   | 0.11  |
| local-append  | 500  | 4.5   | 9    | 0.02  |
| local-append  | 2000 | 11.6  | 5.8  | 0.04  |
| sync-linear   | 100  | 1.7   | 17   | 0.08  |
| sync-linear   | 500  | 4.3   | 9    | 0.05  |
| sync-linear   | 2000 | 10.0  | 5.0  | 0.21  |
| merge-fan     | 100  | 13    | 129  | 3.0   |
| merge-fan     | 500  | 414   | 828  | 24    |
| merge-fan     | 2000 | 21625 | 10813| 278   |

*local-append* is a single peer issuing $N$ sequential insert edits. *sync-linear* builds $N$ events on peer $A$ and delivers them to peer $B$ in causal order. *merge-fan* has peer $A$ and peer $B$ edit disjoint subtrees concurrently and then sync.

For typical Denicek sessions ($N \le 100$), all workloads complete in under 15 ms. At $N = 100$, merging two 50-event concurrent branches costs 14 ms total --- well within the interactive threshold. The linear workloads stay below a millisecond per event up to $N = 2000$. This is due to an **incremental materialization cache** (`EventGraph.cachedDoc`) which is extended in place whenever a new event's parents exactly equal the current frontier --- a *linear extension* of the graph. In that common case, inserting an event costs an `edit.validate` against the cached document plus an in-place `edit.apply`, avoiding a full replay.

The merge-fan workload exposes the **asymptotic cost of true concurrency**: every incoming event from peer $B$ invalidates the linear cache on peer $A$ (because its parents no longer match $A$'s frontier). However, the checkpoint cache mitigates this: before invalidation, the current state is saved as a checkpoint keyed by the pre-merge frontier. On the next materialization, replay resumes from that fork point rather than from the initial document. The remaining cost is proportional to the events *after* the fork point, not the total event count. At $N=2000$ the merge-fan workload costs 21.6 seconds --- still too slow for a large offline divergence, because the $O(N)$ `resolveAgainst` scan runs for every event in both branches, yielding $O(N^2)$ overall. For a local-first system where offline editing is an explicit goal, further optimization of the per-event resolution step would be needed.

Two observations mitigate this cost in practice:

- The ceiling is bounded by the number of *branch points*, not by the total event count. A long run of local edits followed by a single sync merge with a small remote branch costs $O(N \cdot B)$ where $B$ is the size of the remote branch, not $O(N^2)$.
- For the Denicek applications studied in [@Sec:formative-examples], the total event count per session is typically $\le 100$, and merges happen after short offline intervals. Within that envelope the implementation is fast enough to feel interactive.

Further reducing the per-event cost of `resolveAgainst` --- for instance, by skipping priors whose structural effect provably cannot overlap the current edit's selector --- is left as future work.

**Memory footprint.** Events are held in memory as a `Map<EventId, Event>`. Each `Event` carries an `EventId`, a `parents` array, an `Edit` subclass instance with its own fields, and a `VectorClock`. On the sync-linear N=2000 workload the serialized on-disk JSON is approximately 0.4 MB (roughly 200 bytes per event, dominated by the vector-clock and edit payloads); in-memory the `Map` overhead adds a constant factor. This linear growth in event count is the main scalability constraint, mitigated by the server-side compaction mechanism described in [@Sec:sync], which materializes the document and discards old events once all active peers have acknowledged a common frontier.

## Determinism audit {#sec:determinism-audit}

The convergence proof requires that `topologicalOrder`, `resolveAgainst`, and `apply` are deterministic. We audited the implementation for JavaScript-level non-determinism:

- **Topological order** uses a `BinaryHeap` keyed on `EventId` lexicographic order. The event `Map` is accessed only via `Map.get`, never iterated.
- **`resolveAgainst`** iterates the `applied` list (produced by the topological order) sequentially. `transformLaterConcurrentEdit` dispatches on the edit's class.
- **`apply`** methods are local mutations. `Object.keys` appears only in serialization paths (`toPlain`) and vector clock comparisons (order-independent). The formula engine keys results by absolute path strings.
- **No hidden non-determinism**: no `Math.random`, `Date.now`, or hash-map iteration dependence in the materialization path.

The audit is informal. A mechanical check (e.g., a lint rule banning `Object.keys` outside an allow-list) is left as future work.

## Limitations {#sec:limitations}

The current implementation has several known limitations:

**Materialization cost is quadratic for concurrent branches.** Linear extensions (the common case during local editing and live sync) extend a cached document in place at O(1) amortized cost. Merges resume from a checkpoint at the fork point rather than replaying from the initial document, but the `resolveAgainst` step still scans all prior events for each event being replayed, giving $O(N^2)$ in the worst case for a workload dominated by concurrent branching.

**No character-level text editing.** Primitive values (strings, numbers, booleans) are replaced atomically. There is no character-level collaborative text editing --- concurrent edits to the same string field are resolved by last-writer-wins based on topological order. Supporting character-level editing would require integrating a text CRDT (such as Fugue) for primitive string values.

**CopyEdit undo snapshots the full target subtree.** The `CopyEdit` operation supports undo via `RestoreSnapshotEdit`, which snapshots every (possibly wildcard-expanded) target subtree before the copy and restores it on undo. This approach is correct and convergent --- the undo event syncs to all peers like any other edit --- but incurs memory overhead proportional to the size of the overwritten subtrees.

**Vector clocks grow linearly with the number of peers.** Each event carries a vector clock with one entry per peer that has contributed to its causal history. For a session with $P$ peers, each vector clock has up to $P$ entries, and the serialized size of each event grows as $O(P)$. For the typical use case of 2--5 peers, this overhead is negligible. For large peer counts, alternative representations such as tree clocks could reduce this overhead but are not implemented.

**In-memory event storage and no server hardening.** The sync server stores all events in memory with append-only JSON file persistence. There is no database-backed storage, rate limiting, or payload size enforcement. Rooms are evicted from memory after 10 minutes of inactivity, but room data files on disk are never deleted. These are acceptable trade-offs for a thesis prototype but would need to be addressed for a production deployment.


