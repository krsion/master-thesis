# Formative Examples {#chap:formative}

This chapter demonstrates the mydenicek system through seven formative examples. Each example illustrates a different aspect of the system's capabilities and is backed by a passing test in the repository. The examples progress from simple operations to complex concurrent structural transformations. Five examples have dedicated test files; the conference table transformation ([@Sec:conf-table]) and its concurrent editing variant ([@Sec:conf-concurrent]) share a single test file (`conference-list-formative.test.ts`) because the concurrent scenario builds directly on the transformation scenario's document state.

## Hello World: custom primitive edits and replay {#sec:hello-world}

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

## Counter: formulas and programming by demonstration {#sec:counter}

The counter example demonstrates the *formula engine* and *recording/replay* (programming by demonstration).

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

## Conference List: adding items with recorded edits {#sec:conf-list}

The conference list demonstrates how recorded edits work with an input field and a button to add items to a list.

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

## Conference Table: structural transformation {#sec:conf-table}

The conference table example is the most complex formative example. It demonstrates *schema evolution* --- refactoring a flat list into a structured table using only the edit operations available in the CRDT. The document tree before and after the transformation:

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
        → "Ada Lovelace"
    </td>
    <td>
      split-rest(source=ref("../../0/contact/source"))
        → "ada@example.com"
    </td>
  </tr>
  <tr>
    <td>
      split-first(source="Grace Hopper, grace@example.com")
        → "Grace Hopper"
    </td>
    <td>
      split-rest(source=ref("../../0/contact/source"))
        → "grace@example.com"
    </td>
  </tr>
</table>
```

Starting from the conference list (a `<ul>` with `<li>` items containing `"Name, email"` strings), Alice performs the following structural transformation:

```typescript
// 1. Change tags: ul -> table, li -> td
alice.updateTag("speakers", "table");
alice.updateTag("speakers/*", "td");

// 2. Wrap each <td> in a <tr> list
alice.wrapList("speakers/*", "tr");

// 3. Wrap contact in split-first formula
// (the original value becomes the "source" field of the wrapper)
alice.wrapRecord(
  /* target */ "speakers/*/0/contact",
  /* field  */ "source",
  /* tag    */ "split-first",
);

// 4. Add email column with split-rest
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

After this transformation, each table row has two cells:

- **Name cell**: the `split-first` formula evaluates the original `"Ada Lovelace, ada@ex.com"` and returns `"Ada Lovelace"`
- **Email cell**: the `split-rest` formula references the same source string and returns `"ada@ex.com"`

The wildcard `*` in all four steps ensures that the transformation is applied to every row simultaneously. All edits are recorded as events in the DAG.

## Conference Table: concurrent editing {#sec:conf-concurrent}

This is the key demonstration of the system's convergence properties. Two peers start from the same conference list, disconnect, and make concurrent edits:

- **Alice** (offline) performs the structural transformation described above --- refactoring the list into a table with split-first/split-rest formula columns.
- **Bob** (offline) adds two new speakers to the list via `insert`.

When they reconnect and sync, the event DAG shows a *concurrent fork*: Alice's structural edits (5 events) and Bob's insertions (2 events) branch from the same parent event and merge at the frontier.

This example demonstrates the *wildcard-affects-concurrent-insertions* property described in [@Sec:wildcard-concurrent]: Alice's wildcard edits (`updateTag("speakers/*", ...)`, `wrapList("speakers/*", ...)`) expand at replay time to include Bob's concurrently inserted items. The result is that Bob's new speakers are automatically wrapped in `<tr>` lists and receive the split formula cells, even though they were inserted as plain `<li>` items into a `<ul>` list. This semantics is a direct consequence of the replay-based OT approach and is uncommon in traditional CRDTs.

The OT transformation rules handle this correctly:

- Bob's `insert` edits originally target a `<ul>` list and insert `<li>` items. After merging with Alice's events, the OT transforms them: `updateTag` changes the inserted items' tags, `wrapList` wraps them in `<tr>` lists, and `insert` adds the split formula cells.
- The result is a table containing all four speakers --- the original two from the initial document plus Bob's two concurrent additions --- each with correctly split name and email columns.

The event graph visualization in the web application shows this fork-and-merge pattern clearly: two branches of events with different peer colors converging at a merge point. [@Fig:concurrent-initial;@Fig:concurrent-alice;@Fig:concurrent-bob;@Fig:concurrent-merged] show the four stages of this process.

![Initial state: both peers synced with a flat conference speaker list.](img/concurrent-initial.png){#fig:concurrent-initial width=95%}

![Alice (offline) refactors the list into a two-column table with split-first/split-rest formulas.](img/concurrent-alice.png){#fig:concurrent-alice width=95%}

![Bob (offline) adds two speakers to the original list structure.](img/concurrent-bob.png){#fig:concurrent-bob width=95%}

![After merge: all four speakers appear in the table. The event graph shows the concurrent fork merging at a single commit.](img/concurrent-merged.png){#fig:concurrent-merged width=95%}

## Conference Budget: formulas with references {#sec:conf-budget}

The conference budget example demonstrates formulas that reference other nodes via `$ref` paths, combined with concurrent editing.

The document contains a table of speakers with fee columns. A `sum` formula references all fee cells via a wildcard path (`/speakers/*/fee`). When a new speaker is added concurrently by another peer, the wildcard reference automatically includes the new row --- the sum formula produces the correct total without any manual update.

This example validates that the formula engine correctly handles references that resolve to different sets of nodes as the document evolves through concurrent edits.

## Todo App: multi-step macros and repeatable replay {#sec:todo}

The todo app demonstrates the **composer pattern**: a UI scaffold in which an input field and a button jointly record and replay a multi-step edit sequence. Every click of the "Add" button executes the same recorded script against the current input value, producing a new item at the top of the list.

The document holds three logical pieces --- a `composer` record containing an `input` value and an `addAction` button with a list of `steps`, and an `items` list representing the todo entries:

```typescript
const doc = new Denicek("alice", {
  $tag: "app",
  composer: {
    $tag: "composer",
    input: { $tag: "input", value: "Review feedback" },
    addAction: {
      $tag: "button",
      steps: { $tag: "event-steps", $items: [] }
    },
  },
  items: {
    $tag: "ul",
    $items: [
      { $tag: "li", $items: ["Ship prototype"] },
      { $tag: "li", $items: ["Write paper"] },
    ],
  },
});
```

The "Add" recipe is two edits: prepend an empty list item, then copy the current input value into that item's first child. The event IDs of those edits are recorded as replay steps on the button:

```typescript
const insertId = doc.insert(
  /* target */ "items",
  /* index  */ 0,
  /* value  */ { $tag: "li", $items: [""] },
  /* strict */ true,
);
const copyId = doc.copy(
  /* target */ "items/!0/0",
  /* source */ "composer/input/value",
);

doc.insert(
  /* target */ "composer/addAction/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: insertId },
);
doc.insert(
  /* target */ "composer/addAction/steps",
  /* index  */ -1,
  /* value  */ { $tag: "replay-step", eventId: copyId },
);
```

The strict index `!0` in the copy target is essential: during replay it refers to the list position at the *time of replay*, not at recording time, and is not shifted by concurrent insertions ([@Sec:replay]).

To "click" the button, the user changes the input value and invokes `repeatEditsFrom`, which replays each recorded step as a new event at the current frontier:

```typescript
doc.set("composer/input/value", "Book venue");
doc.repeatEditsFrom("composer/addAction/steps");
```

The result is a new `<li>Book venue</li>` at the head of `items`, followed by the original entries. Clicking the button again with a different input value prepends another item, and so on. Each click is a pair of committed events in the DAG, so the sequence is fully auditable and is synchronized to other peers exactly like any other edit.

This example exercises (a) the composer pattern --- button + input + replay steps --- that is reused across the conference-list and conference-table examples; (b) strict-index semantics under replay; (c) multi-step macro recording with internal dependencies between steps (the copy depends on the prior push creating its target); (d) the `CopyEdit` type, including its mirroring behavior under concurrent source edits described in [@Sec:copy-edit]. The full scenario is backed by `todo-formative.test.ts`.

