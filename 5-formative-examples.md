# Formative Examples {#chap:formative}

This chapter demonstrates the mydenicek system through five formative examples. Each example illustrates a different aspect of the system's capabilities and is backed by a passing test in the repository. The examples progress from simple operations to complex concurrent structural transformations. Three examples have dedicated test files (`hello-world-formative.test.ts`, `counter-formative.test.ts`, `traffic-accidents-formative.test.ts`); the conference list ([@Sec:conf-list]), the conference table transformation ([@Sec:conf-table]), and its concurrent editing variant ([@Sec:conf-concurrent]) share a single test file (`conference-list-formative.test.ts`) because the concurrent scenario builds directly on the transformation scenario's document state.

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

Starting from the conference list (a `<ul>` with `<li>` items containing `"Name, email"` strings), Alice performs the following structural transformation. Each step shows the intermediate document state, demonstrating how the tree evolves:

**Step 1: Change tags.** Retag the list and its items.

```typescript
alice.updateTag("speakers", "table");
alice.updateTag("speakers/*", "td");
```

```html
<!-- Before -->                    <!-- After -->
<ul>                               <table>
  <li contact="Ada..." />    →      <td contact="Ada..." />
  <li contact="Grace..." />          <td contact="Grace..." />
</ul>                              </table>
```

**Step 2: Wrap each `<td>` in a `<tr>` row.**

```typescript
alice.wrapList("speakers/*", "tr");
```

```html
<!-- Before -->                    <!-- After -->
<table>                            <table>
  <td contact="Ada..." />    →      <tr> <td contact="Ada..." /> </tr>
  <td contact="Grace..." />          <tr> <td contact="Grace..." /> </tr>
</table>                           </table>
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
<!-- Before -->                         <!-- After -->
<tr>                                    <tr>
  <td contact="Ada Lovelace,     →       <td contact=
        ada@example.com" />               split-first(source="Ada Lovelace,
</tr>                                            ada@example.com") />
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

## Button replay after schema evolution {#sec:replay-after-refactor}

The most striking consequence of the replay mechanism is that recorded edit sequences survive structural refactoring. The "Add Speaker" button was recorded against a flat `<ul>` list --- its steps insert a `<li>` item and copy the input value into its `contact` field. After Alice refactors the list into a `<table>` with formula columns, clicking the button still works: `repeatEditsFrom` retargets each recorded step through every structural edit that happened after recording (tag updates, wraps, formula insertions). The replayed insert produces a complete table row with a `split-first` name cell and a `split-rest` email cell, exactly as if the button had been recorded against the table.

This behavior requires no special handling in the button or the application code. The replay mechanism uses the same OT transformations that handle concurrent edits: each recorded edit is resolved against all later events in topological order, and structural edits rewrite the recorded selector. The only difference from concurrent resolution is that replay transforms through *all* later edits, not just concurrent ones --- because the recorded edit's "virtual position" in the DAG is at the recording point, and all subsequent edits are structurally later.


