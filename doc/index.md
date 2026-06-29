# SWA Tools -- Documentation Index

A suite of structural-analysis tools for Squeak, sharing one tree/view/navigation
layer (`SWANode` / `SWAView` / `SWANavPanel`) and a common
**cross-referencing** mechanism. Each tool visualises a tree of nodes as a
navigable squarified treemap (or flamegraph), and any open panel can be
cross-referenced against another because they all speak the same `crossRefKey`
vocabulary (class names are unique; methods are `'Class>>selector'`).

## Tools

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **[SWACodeMap](SWACodeMap.md)** | What is the *shape* of this code -- size, documentation, coverage, churn? | package -> class -> category -> method | LOC / bytes / methods / execution counts |
| **[SWASpaceTally](SWASpaceTally.md)** | Where does the *memory* go, and who keeps it alive? | live object graph (BFS) | bytes |
| **[SWAMessageTally](SWAMessageTally.md)** *(stub)* | Where does the *time* go at runtime? | sampled call tree | sample count |

## The Shared View Layer

### `SWANode` -- the common tree contract

All data models subclass `SWANode`, which owns the `parent`/`children` structure and
the shared protocol (`depth`, `pathString`, `isLeaf`, `withAllChildrenDo:`,
`crossRefKey`). Subclasses supply `name`, the treemap weight (`totalSize`), and the
cross-reference key.

### `SWAView` -- the common morph

The treemaps and the flamegraph subclass `SWAView`, a `Morph` holding the shared
state (`rootNode`, selection, render cache, cross-reference machinery) and the
chrome link to the nav panel. Subclasses supply layout and palette.

### `SWANavPanel` -- the chrome

Wraps any `SWAView` with the shared header: **Back / Browse / Show**, plus
view-specific controls (the Code Map adds **Size / Color / Cover / Tally / Export /
Load / Clear Cov / Depth**), a breadcrumb, a fullscreen toggle, and -- when the view
is cross-referenceable -- **X-ref / Clear**.

## Cross-Referencing

Pressing **X-ref** on a panel links it to another open panel and tints matching
tiles on a log-scaled cold->hot ramp, rolled up so an ancestor tile is as hot as its
hottest matching descendant. The mechanism is symmetric -- either view can be source
or target -- and lets you answer questions that span two views, e.g.:

- *Colour the static Code Map by how much memory each class measured in the Space
  Tally.*
- *Highlight in the Code Map exactly which methods the profiler sampled, and how
  hot they were.*

## Related Notes (workspace)

- [../../notes/index.md](../../notes/index.md) -- the SqueakXR notes & journal index.
- [../../notes/st-spy.md](../../notes/st-spy.md) -- profiling Squeak with st-spy.
- [../../notes/SQUEAKSPY_ROADMAP.md](../../notes/SQUEAKSPY_ROADMAP.md) -- external
  profiler roadmap.
