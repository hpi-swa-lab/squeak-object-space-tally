# SWA Code Maps -- Documentation Index

![](_navigation.html)

A suite of program-analysis tools for Squeak covering structure, history,
execution and memory, sharing one tree/view/navigation layer (`SWANode` /
`SWAView` / `SWAPane`, in the `SWA-Base` package) and a common **dataset**
mechanism.
Each tool visualises a tree of nodes as a navigable squarified treemap (or
flamegraph), and any tool can be coloured by another's data -- loaded from a file
or read live from another open panel -- because they all speak the same
`crossRefKey` vocabulary (class names are unique; methods are `'Class>>selector'`).

## Tools

Start at **[views.md](views.md)** for what the suite is for and how well it
covers its subject. The table below is the inventory; where the tools overlap and
what none of them measures is derived in **[landscape.md](landscape.md)**,
individual findings are in **[stories.md](stories.md)**, and the resulting work
items are in **[todo.md](todo.md)**. Testing the suite itself is planned in
**[tests.md](tests.md)**.

<!-- MAINTENANCE
Keep the four groups here in the same order as the four columns of the figure in
landscape.md (structure, history, execution, space), and keep both in step with
the SWA-* categories listed in architecture.md. A new tool needs a row here, a
box in media/swa-landscape.dot, and a re-render of that figure.
-->

**Structure** -- the code as written, nothing runs:

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **[SWACodeMap](SWACodeMap.md)** | What is the *shape* of this code -- size, documentation, coverage, churn? | package -> class -> category -> method | LOC / bytes / methods / execution counts |
| **Class Diagram** ([journal](../../journal/2026-07-13-classdiagram-graphviz-json-and-graph-view.md)) | What is the *inheritance shape* of a package? | class graph | -- (diagram) |
| **Duplication** (`SWACodeSimilarity`) | Which methods are copies of each other? | -- (a Code Map dataset) | Jaccard score |
| **Topic Model** (`SWABitermTopicModel`) | What is this code *about*? | -- (a Code Map dataset) | topic mixture |

**History** -- how the code got there:

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **Change Map** ([journal](../../journal/2026-07-09-swachangeparser-change-treemap-and-recovery.md)) | *When* did the code change, and how much? | `.changes` time buckets | diff lines |
| **[SWAGitMap](SWAGitMap.md)** | What did these *commits* change -- and what is churning? | month -> day -> commit -> package -> class -> method | diff lines |
| **Change Trace** (`SWAChangeTraceRecorder`) | What does one live edit *cost* -- who reacts, for how long, allocating what? | change -> subscriber reaction | us / bytes |
| **OpenCode Access** ([journal](../../journal/2026-08-05-opencode-sessions-in-swa-and-two-sqlite-bugs.md)) | What did the agent *look at* -- as opposed to commit? | session -> tool call, or file tree | reads / writes / sessions |
| **Timeline / Calendar / Flow** ([journal](../../journal/2026-08-06-flow-map-timeline-spans-and-the-calendar.md)) | What was the *rhythm* of this work? | any tree with an `eventTimeStamp` | lines / count / commits |

**Execution** -- what ran, when, for how long:

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **Coverage** (`SWACoverage`) | Did this method run, and which test covered it? | -- (a Code Map dataset) | boolean + covering tests |
| **Invocation Tally** (`SWATallyWrapper`) | How *often* was it called? | call tree | exact counts |
| **Timing Tally** (`SWATimingWrapper`) | How *long* did it take, inclusive and exclusive? | call tree | exact us, overhead-compensated |
| **Sampling Tracer** (`SWASamplingTracer`) | Where does the time go, without instrumenting? | sampled call tree | us (in-image MessageTally) |
| **[Sampling Tally](SWAMessageTally.md)** *(stub)* | Where does the time go across the *whole VM*? | sampled call tree | wall us (external st-spy) |
| **Trace / Flame Chart** (`SWATraceMorph`) | What ran *when*, in which process? | per-process lanes of spans | one box per call |

**Space** -- which objects exist, who made them, who keeps them:

| Tool | Question it answers | Tree | Tile weight |
|---|---|---|---|
| **[SWASpaceTally](SWASpaceTally.md)** | Where does the *memory* go, and who keeps it alive? | live object graph (BFS) | bytes |
| **Heap Diff** ([journal](../../journal/2026-08-14-heap-diff-and-per-frame-allocation-provenance.md)) | What did this one action allocate? | new objects + provenance by home method | bytes |
| **Survivor Diff** ([journal](../../journal/2026-08-18-allocation-survival-flamegraph-and-the-set-dont-new-question.md)) | Of that, what *survived* the scavenge? | as above, post-scavenge | bytes |
| **Young Space Tally** ([journal](../../journal/2026-08-19-young-space-tally-and-two-dead-ends.md)) | What is in young space right now? | young objects + provenance | bytes |
| **Alloc Tracer** (`SWAAllocTracer`) | Which *code paths* allocate these -- and are they kept? | allocation call tree | allocations, coloured by retention |
| **GC Stats / Memory Graph** ([journal](../../journal/2026-08-21c-gc-stats-memory-lanes-and-the-freeze-hunt.md)) | What is the heap doing over time, inside and outside the image? | -- (time series) | bytes / fps / scavenges |

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
  - git churn (`SWAGitChurnData`) JSON -- per-method commits / changed lines /
    recency / authors (see [SWAGitMap](SWAGitMap.md#half-2-git-churn-on-the-code-map)),
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
- *Colour the Code Map by git history* -- how often each method has been committed,
  how recently, and by how many hands ([SWAGitMap](SWAGitMap.md)).
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
