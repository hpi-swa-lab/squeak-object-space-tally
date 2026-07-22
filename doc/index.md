# SWA Code Maps -- Documentation Index

> See the **[gallery](gallery.md)** for a one-look, screenshot-per-tool overview,
> and **[packages.md](packages.md)** for the package map, dependency graph, and
> class hierarchy.
>
> **Two doc layers.** The tool docs below are *user-facing*. For the *engineering*
> view -- read end-to-end from source as a static as-is snapshot -- see:
> - **[architecture.md](architecture.md)** -- the layering, the view/data/dataset
>   spines, the instrumentation substrate, the walker, extension points.
> - **[api.md](api.md)** -- the important public protocols, grouped by class.
> - **[smells.md](smells.md)** -- duplications, dead/legacy code, design debt, and
>   open ends -- a scaffold for refactoring/evolution discussions.
>
> Note: the user-facing docs predate several shipped features -- **Marks** (global
> cross-view bookmarks), the **Mask (B\A)** dataset combinator, the async
> **Generate** dataset entries, the **topic model**, and the **live
> class-diagram-of-marks** -- which are described in architecture.md/api.md but not
> yet in the tool docs (see smells.md §7).

A suite of structural-analysis tools for Squeak, sharing one tree/view/navigation
layer (`SWANode` / `SWAView` / `SWAPane`, in the `SWA-Base` package) and a common
**dataset** mechanism.
Each tool visualises a tree of nodes as a navigable squarified treemap (or
flamegraph), and any tool can be coloured by another's data -- loaded from a file
or read live from another open panel -- because they all speak the same
`crossRefKey` vocabulary (class names are unique; methods are `'Class>>selector'`).

## Tools

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **[SWACodeMap](SWACodeMap.md)** | What is the *shape* of this code -- size, documentation, coverage, churn? | package -> class -> category -> method | LOC / bytes / methods / execution counts |
| **[SWASpaceTally](SWASpaceTally.md)** | Where does the *memory* go, and who keeps it alive? | live object graph (BFS) | bytes |
| **[SWAMessageTally](SWAMessageTally.md)** *(stub)* -- Sampling Tally | Where does the *time* go at runtime (statistical sampling)? | sampled call tree | wall time (us) |
| **Change Map** ([journal](../../journal/2026-07-09-swachangeparser-change-treemap-and-recovery.md)) | *When* did the code change, and how much? | `.changes` time buckets | diff lines |
| **Class Diagram** ([journal](../../journal/2026-07-13-classdiagram-graphviz-json-and-graph-view.md)) | What is the *inheritance shape* of a package? | class graph | -- (diagram) |

See the **[gallery](gallery.md)** for a screenshot of each.

## The Shared View Layer

### `SWANode` -- the common tree contract

All data models subclass `SWANode` (in `SWA-Base`), which owns the `parent`/`children`
structure and the shared protocol (`depth`, `pathString`, `isLeaf`,
`withAllChildrenDo:`, `crossRefKey`). The concrete per-tool node classes live in
the `SWA-Nodes` package (`SWACode*Node`, `SWASpaceTallyNode`, `SWASamplingTallyNode`,
`SWAChangeNode`). Subclasses supply `name`, the treemap weight (`totalSize`), and
the cross-reference key.

### `SWAView` -- the common morph

The treemaps and the flamegraph subclass `SWAView`, a `Morph` holding the shared
state (`rootNode`, selection, render cache, the `keyIndex`) **and the dataset
layer**: every SWA view can host named `SWADataset`s, mint their metrics onto its
Color/Size menus, and pick an active one (`datasets`, `addDataset:`,
`selectDataset:`, `setDataMode:`, `metricForMode:`). Colour is the axis every view
shares; the intrinsic default is an overridable hook (`intrinsicColorMode`).
Subclasses supply layout, palette, and any richer axes (the Code Map adds size and
link axes and coverage provenance).

### `SWAPane` -- the chrome

Wraps any `SWAView` with the shared header: **Back / Browse / Show**, plus
view-driven controls -- **Data** (pick a data source), **Tree** (pick the base
structure), **Size / Color / Links**, and Code-Map-only **Tally / Export / Load /
Depth** -- a breadcrumb, and a fullscreen toggle. The header is rebuilt per view
(capability-gated), so it changes as you morph one tool into another.

## Datasets: the unified data path

A **`SWADataset`** is a named, retained data source bound to a view. Each carries
one or more **metrics** (e.g. *By coverage*, *By instance bytes*), each bindable to
the colour (and where supported size/links) axis. Loading the same kind twice gives
two coexisting, switchable entries.

Sources:

- **Loaded from a file** via the Code Map's **Load** button, dispatched by content:
  - coverage (`SWACoverageData`) and duplication (`SWADuplicationData`) JSON,
  - space-tally JSON -- either a full node tree or a flat per-class census
    (see [SWASpaceTally](SWASpaceTally.md#decorating-the-code-map-with-per-class-bytes)).
- **Read live from another open panel** (`#peer`): every open treemap/flamegraph
  appears in the **Data** menu as "X-ref: `<window>`". Picking it colours this map
  by that peer's per-key weight (`SWAPeerViewSource` reads the peer's live
  `keyIndex`). This replaces the former dedicated **X-ref / Clear** buttons --
  cross-referencing is now just another dataset you can mix and match, and picking
  **None** clears it.

So one **Data** menu answers questions that span views, e.g.:

- *Colour the Code Map by how much memory each class measured in a Space Tally.*
- *Highlight in the Code Map which methods a live profiler sampled, and how hot* --
  container tiles (class, package) roll up the weight of their sampled methods, so
  a class lights up even when only its methods carry data.

## Structure: morph one tool into another

Beyond colouring, the **Tree** button picks which node tree IS the base structure.
A space tally loaded from a node-tree JSON retains its tree, so the Code Map can
**morph in place into that Space Tally** (same window/chrome) and back -- both views
are cached, so the switch is instant and lossless (the Code Map keeps its datasets,
the tally keeps its layout). See
[SWASpaceTally](SWASpaceTally.md#the-tree-button-morph-one-tool-into-another).

## Related Notes (workspace)

- [../../notes/index.md](../../notes/index.md) -- the SqueakXR notes & journal index.
- [../../notes/st-spy.md](../../notes/st-spy.md) -- profiling Squeak with st-spy.
- [../../notes/SQUEAKSPY_ROADMAP.md](../../notes/SQUEAKSPY_ROADMAP.md) -- external
  profiler roadmap.
