# Formative Examples {#chap:formative}

This chapter demonstrates the mydenicek system through six formative examples. Each example illustrates a different aspect of the system's capabilities and is backed by a passing test in the repository. The examples progress from simple operations to complex concurrent structural transformations.

## Hello World: Custom Primitive Edits and Replay

\todo{Capitalize example: register custom edit, apply to one item, replay with wildcard to all items. Shows extensibility and wildcard replay.}

## Counter: Formulas and Programming by Demonstration

\todo{Start with value=0. Record: wrapRecord in x-formula-plus, rename to left, add right=1. Button replays these 3 edits. Each click creates nested formula tree. Shows formula recomputation + recording/replay.}

## Conference List: The Composer Pattern

\todo{Flat list with "Name, email" entries. Add button: pushFront empty item + copy from input. Two peers add speakers concurrently --- both appear after sync. Shows basic concurrent list editing.}

## Conference Table: Structural Transformation

\todo{Start from the conference list. Alice refactors: updateTag table, updateTag td, wrapList tr, wrapRecord split-first, pushBack split-rest with $ref. Shows schema evolution --- structural edits transform a flat list into a two-column table with formula-based splitting.}

## Conference Table: Concurrent Editing

\todo{The key demo: Alice refactors list to table (offline). Bob adds speakers to list (offline, concurrent). After merge: Bob's items appear as table rows --- OT transformed li->tr/td through Alice's structural changes. Show the 4 screenshots: initial, Alice, Bob, merged. Event graph shows the concurrent fork.}

## Conference Budget: Formulas with References

\todo{Table with speaker fees. Sum formula references all fee cells via wildcard $ref. Concurrent add of a new speaker --- the sum formula automatically includes the new row. Shows formula + concurrent editing integration.}
