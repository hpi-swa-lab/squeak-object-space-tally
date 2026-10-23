# SWA Tools -- Gallery

![](_navigation.html)

One table. Every tool, every mode it can be put into, the question each one
answers, how to get there, and whether a picture exists.

For what the suite is *for* see [views.md](../views.md); for the systematic
inventory and what none of them measures see [landscape.md](../landscape.md); for
the code structure see [packages.md](../packages.md). Every tool renders a tree of
`SWANode`s through the shared view layer ([view-layer.md](view-layer.md)) and
speaks the same `crossRefKey` vocabulary, so any tool can colour itself by any
other's data.

## Reading the table

- **Tool** -- bold rows are the tool itself; the rows under it are its modes.
- **Kind** -- `referent · cost`. Referent is what the claim is *about* (code /
  object / event / process) and is the Apps-menu grouping. Cost is what happens
  when you click: **Look** opens now and changes nothing, **Record** arms
  instrumentation until you press STOP, **Snap** perturbs the heap immediately.
- **Mode** -- which button, and the mode symbol. `Color` / `Size` / `Tree` /
  `Data` are the four axes of the shared chrome.
- **Open** -- the Apps-menu entry, or the send.
- **Shot** -- a filename means the image is in [`../media/`](../media); **TODO**
  means it still needs capturing, under the name given.

<!-- MAINTENANCE
This table replaces the former by-referent and by-cost tables; do not reintroduce
them, merge new facts into columns here instead.

Mode lists are READ FROM THE IMAGE, not invented. To refresh:
  SWACodeTreemapOverlay new colorModeOptions       "and #sizeModeOptions"
  SWASpaceTallyTreemapOverlay / SWAChangeTreemapOverlay / SWAGitTreemapOverlay
  SWAOpenCodeTreemapMorph / SWAClassDiagram / SWATraceMorph / SWATemporalView
  <view> alternateStructures                        "the Tree menu"
  SWAPane -> all #generate* selectors                "the italic Data entries"
  TheWorldMenu registeredOpenCommands                "the Open column"
Dataset metrics are APPENDED to Color/Size at runtime, so a mode list is only ever
complete relative to what is loaded.

A new tool needs: a page, a bold row here plus its mode rows, a menu entry (or an
explicit note that it has none), and a row in ../index.md.
-->

| Tool | Kind | Mode | Question it answers | Open | Shot |
|---|---|---|---|---|---|
| **[Code Map](code-map.md)** | code · Look | -- | What is the *shape* of this code -- size, documentation, coverage, churn? | `SWA Code: Code Map` | `gallery-codemap.png` |
| | | Color `codeKind` | What *kind* is each tile -- package, class, category, method? | | `codemap-default-loc-kind.png` |
| | | Color `byteComposition` | How much of this is **documentation vs string vs code**? | | `codemap-byte-composition.png` |
| | | Color `loc` | Where are the **big methods**? | | `codemap-color-loc-heat.png` |
| | | Color `avgloc` | Which classes are **not decomposed** (high average method length)? | | `codemap-color-avgloc.png` |
| | | Color `versions` | Which code has been **rewritten most often**? | | `codemap-color-versions.png` |
| | | Color `recency` | What was **touched last**? | | `codemap-color-recency.png` |
| | | Color `author` | **Who** owns this area? | | `codemap-color-author.png` |
| | | Size `methods`/`loc`/`bytes` | Which **size** do you mean -- count, lines, or source bytes? | | `codemap-size-menu.png` |
| | | Size `invocations` | Weight by **how often it ran** rather than how big it is | | `codemap-coverage-invocations-weighted.png` |
| | | Size `tests` | Weight by **how many tests cover it** | | `codemap-coverage-tests-weighted.png` |
| | | Tree `timeline` | The same code by **when it was last changed** | | `codemap-tree-timeline.png` |
| | | Tree `calendar` | ...and by **which day** | | `codemap-tree-calendar.png` |
| | | Data coverage | Did this run, and **which test** covered it? | | `codemap-coverage-overlay-on-loc.png` |
| | | Data duplication | Which methods are **copies** of each other? | | `codemap-data-duplication.png` |
| | | Data topic model | What is this code **about**? | | **TODO** `codemap-data-topics.png` |
| | | Data call tally | **How often** was each method called? | | **TODO** `codemap-data-calltally.png` |
| | | Data call timing | **How long**, inclusive and exclusive? | | **TODO** `codemap-data-calltiming.png` |
| | | Data sample tally | Where did the **sampler** land, on the structure? | | **TODO** `codemap-data-sampletally.png` |
| | | Data git churn | How often / recently / by **how many hands** committed? | | `gitmap-churn-on-codemap.png` |
| | | Data space tally | How much **memory** does each class hold? | | **TODO** `codemap-data-spacetally.png` |
| | | Data peer x-ref | Colour by **another open panel's** live weights | | `codemap-data-xref-peer.png` |
| | | Data mask `B \ A` | What is in **B and not in A**? | | **TODO** `codemap-data-mask.png` |
| **[Class Diagram](class-diagram.md)** | code · Look | -- | What is the *inheritance shape* of these packages? | `SWA Code: Class Diagram` | `gallery-classdiagram.png` |
| | | Color `kind` | Flat, by kind | | `gallery-classdiagram.png` |
| | | Color `loc` | LOC heat over the boxes | | `classdiagram-color-loc.png` |
| | | leafKind `class`/`state`/`method` | How much of each class to draw | | `classdiagram-leafkind-state.png` |
| | | leafKind `selected` | Only the **marked** ivars and methods -- what makes a big package legible | | **TODO** `classdiagram-leafkind-selected.png` |
| **[Change Map](change-map.md)** | code · Look | -- | *When* did the code change, and how much? | `SWA Code: Change Map` | `gallery-changemap.png` |
| | | Color `changeKind` | method / doIt / class / comment / removal | | `changemap-color-kind.png` |
| | | Color `status` | current / superseded / in-history / **gone** | | `changemap-color-status.png` |
| | | Color `author`/`recency` | Who, and how long ago | | `changemap-color-recency.png` |
| | | Tree `timeline`/`calendar` | The same edits as a **time axis** or a **day grid** | | `changemap-tree-calendar.png` |
| | | (diff mode) | What does the newer `.changes` have that the baseline lacks? | `SWAChangeParser openInteractiveDiffChangeMap` | **TODO** `changemap-diff.png` |
| **[Git Map](git-map.md)** | code · Look | -- | What did these *commits* change, and what is churning? | `SWA Code: Git Map` | `gitmap-by-commit.png` |
| | | Color `operation` | added / modified / removed | | `gitmap-operation.png` |
| | | Color `commit` | A hue per commit -- **how scattered** was each one? | | `gitmap-by-commit.png` |
| | | Color `package`/`author`/`recency` | Where, who, when | | `gitmap-color-author.png` |
| | | Color `status` | Does this commit's code **still exist** in the image? | | `gitmap-color-status.png` |
| | | **cross** churn on Code Map | Git history as a **colour on the structural map** | | `gitmap-recency-on-codemap.png` |
| **[OpenCode Sessions](opencode.md)** | code · Look | -- | What did the *agent* look at, as opposed to commit? | `SWA Code: OpenCode Sessions` | `gallery-opencode-sessions.png` |
| | | Color `accessMix` | **Read-only attention vs rewritten** (the default) | | `opencode-color-accessmix.png` |
| | | Color `writes`/`reads` | Write intensity, read intensity | | `opencode-color-reads.png` |
| | | Color `recency` | When was this last looked at? | | `opencode-color-recency.png` |
| | | Tree `timeline` | Tool calls **over time** | | `opencode-tree-timeline.png` |
| | | Tree `calendar` | Activity **per day** | | `gallery-opencode-calendar.png` |
| | | sub-view file treemap | Which **files** did the agent touch? | `openFileTreemap` | `opencode-file-treemap.png` |
| | | sub-view session treemap | Which **sessions** were big? | `openSessionTreemap` | `opencode-session-treemap.png` |
| | | sub-view flow | The **conversation** as a zoomable sequence | `openFlow` | `opencode-flow.png` |
| | | **cross** Code Map of one session | Which **code** did *this conversation* touch? | `openCodeMapFor:` | `opencode-codemap-of-session.png` |
| **[Space Tally](space-tally.md)** | object · Look | -- | Where does the *memory* go, and who keeps it alive? | `SWA Object: Space Tally` | `gallery-spacetally.png` |
| | | Color `class` | Which **class** is this tile? | | `swaspacetally-treemap.png` |
| | | Color `children` | Which objects have **many referents** -- the fan-out points? | | `spacetally-color-children.png` |
| | | Color `otherParents` | Which objects are **shared** rather than owned once? | | `swaspacetally-treemap-otherparents.png` |
| | | Color `type` | Morphic vs Collection vs Value vs Other | | `spacetally-color-type.png` |
| | | Color `bitmap` | Render the actual **Forms** in place -- which image is this? | | `spacetally-color-bitmap.png` |
| | | sub-view explorer | The same walk as a **multi-column list** | `SWASpaceTally explore` | `swaspacetally-explorer.png` |
| | | (diff mode) | What did the heap gain between two walks? | `exploreDiffFrom:` | **TODO** `spacetally-diff.png` |
| **[Heap Diff](heap-diff.md)** | object · Snap | -- | What did *one action* allocate? | `SWA Object: Heap Diff (1 Morphic step)` | `gallery-heapdiff.png` |
| | | Provenance branch | **Which code** owns the surviving closures and Contexts? | | `gallery-heapdiff.png` |
| | | survivors variant | Of what it allocated, what **survived a scavenge**? Not in the menu -- needs a step that retains | `SWASurvivorDiff around: [...]` | `heapdiff-survivors.png` |
| **[Young Space](young-space.md)** | object · Look | -- | What is *standing* in young space right now? | `SWA Object: Young Space` | `gallery-youngspace.png` |
| | | `openYoungSpaceNow` | The population as it stands -- **no collection of any kind** | | `gallery-youngspace.png` |
| | | `openRetained` | Survivors and promoted only, garbage left out | | `youngspace-retained.png` |
| | | `openAges` + Color `age` | How many samples has this survived -- **cool = fresh, hot = old**? | | `youngspace-color-age.png` |
| | | `openScavengeFate` + Color `fate` | **Red kept / green collected** at the next scavenge | | `youngspace-color-fate.png` |
| | | `openTreemap` | Fate after a **full GC**, with the old-space captor of each survivor | | **TODO** `youngspace-fullgc-fate.png` |
| **[Sampling Tally](sampling-tally.md)** | event · Record 10s | -- | Where does time go across the *whole VM* -- primitives, VM frames, a wedged image? | `SWA Event: Sampling Tally (10s)` | `gallery-stspy.png` |
| | | sub-view treemap | The same call tree **tiled** instead of stacked | | **TODO** `samplingtally-treemap.png` |
| **[Sampling Tracer](sampling-tracer.md)** | event · Record 10s | -- | Where does time go *inside the image*, with no wrappers to strand? | `SWA Event: Sampling Tracer (10s)` | `gallery-sampling-tracer.png` |
| **[Trace](trace.md)** | event · Record | -- | What ran *when*, in which process? Spans, not totals | `SWA Event: Trace (until stop)` | `gallery-trace.png` |
| | | Color `method` | Stable hue per method -- spot the **repeat** | | `gallery-trace.png` |
| | | Color `duration` | Heat by duration -- spot the **outlier** | | `trace-color-duration.png` |
| | | GC bands | The GC counters drawn **over** the lanes -- the clock join | | **TODO** `trace-gc-bands.png` |
| **[Alloc Tracer](alloc-tracer.md)** | event · Record | -- | Which *code paths* allocate, and is what they make kept? | `SWA Event: Trace Allocations (until stop)` | `gallery-alloctracer.png` |
| | | Color survival | **Red = kept (bad), green = collected (good)** | | `gallery-alloctracer.png` |
| **[Change Trace](change-trace.md)** | event · Record | -- | What does one *live edit* cost -- who reacts, for how long, allocating what? | `SWA Event: Change Trace (until stop)` | `gallery-changetrace.png` |
| | | measure `bytes` | Bucket height = **memory each edit cost** | | `gallery-changetrace.png` |
| | | measure `count` | Bucket height = number of edits | | `changetrace-measure-count.png` |
| | | reaction level | **Which subscriber** is the expensive one? | | **TODO** `changetrace-reactions.png` |
| **[GC Stats](gc-stats.md)** | process · Look | -- | What is the *heap* doing over time? No `crossRefKey` -- joined by **clock**, not key | `SWA Process: GC Stats` | `gallery-gcstats.png` |
| **[Memory Stats](memory-stats.md)** | process · Look | -- | What is the whole *process* doing -- FFI, GPU, VRAM? Also clock-joined only | `SWA Process: Memory Stats` | `gallery-memorystats.png` |
| **[The view layer](view-layer.md)** | -- | -- | Not a tool: the chrome, the dataset machinery, the Packages list | -- | `gallery-viewlayer.png` |
| | | Show row | Details / source / covering-tests panes | | `codemap-show-source-details.png` |
| **Scenarios** -- products of two axes | | | *Where the suite earns its keep: area asks one question, colour asks another, and the answer is the tiles that are extreme in both.* | | |
| | code | Size `loc` × Color coverage | **Big and untested.** The classic: large tiles that stay red. Start here | Code Map, Load coverage | **TODO** `scenario-big-untested.png` |
| | code | Size `invocations` × Color coverage | **Hot but untested.** Runs constantly, no test asserts anything about it -- worse than big-and-untested | Code Map, Load coverage | **TODO** `scenario-hot-untested.png` |
| | code | Size `loc` × Color duplication | **Where the copy-paste mass is.** Big tiles that are also near-duplicates | Code Map, Generate duplication | `codemap-data-duplication.png` |
| | code | Size `loc` × Color `recency` | **Big and stale.** Untouched for a year: either delete it, or it is the riskiest thing to change | Code Map | **TODO** `scenario-big-stale.png` |
| | code | Size `loc` × Color git commits | **Churning out of proportion to size.** A small method committed forty times is a design problem, not a busy one | Code Map, Load git churn | **TODO** `scenario-churn-vs-size.png` |
| | code | Size git commits × Color `author` | **Who owns the churn**, and whether it is one hand or six | Code Map, Load git churn | **TODO** `scenario-churn-authors.png` |
| | code+event | Size git commits × Color sample tally | **Hot in the profiler but never committed.** Performance-critical code nobody has revisited | Code Map, Load churn + sample tally | **TODO** `scenario-hot-never-committed.png` |
| | code+object | Size `loc` × Color space-tally bytes | **Small class, huge footprint.** Where memory is disproportionate to the code that owns it | Code Map, Load space-tally JSON | **TODO** `scenario-small-class-big-memory.png` |
| | code+history | Size opencode reads × Color git commits | **Read repeatedly, never changed.** Where the agent's context budget went with nothing to show | Code Map, Load opencode + churn | **TODO** `scenario-read-never-changed.png` |
| | code+event | Color = peer x-ref to an open alloc flamegraph | **Which of my classes are allocation sites?** No file, no export -- read live from the other window | Code Map, Data > X-ref: *(window)* | `scenario-xref-alloc-peer.png` |
| | code | Mask coverage(after) `\` coverage(before) | **What did this new test actually add?** Set arithmetic over two datasets, not two screenshots compared by eye | Code Map, Data > Mask | **TODO** `scenario-mask-new-coverage.png` |
| | event+process | Trace spans × GC bands | **Did the frame spike coincide with a scavenge?** The only place the key-joined and clock-joined halves meet | Trace | **TODO** `scenario-frame-spike-vs-gc.png` |
| | object→event | Young Space classes → Alloc Tracer | **Where are the retained young objects created?** Young Space names the classes, the tracer catches them at the allocation site -- the workflow that survived the 2026-09-22 dead ends | `SWAAllocTracer traceClasses:` | *(a workflow, not one view -- see `gallery-youngspace.png` then `gallery-alloctracer.png`)* |
| | event | Change Trace bytes × non-logging Workspace | **How much of my GC pressure is my own editing?** ~230 KB per doIt, measured | Change Trace | **TODO** `scenario-editing-cost.png` |

## Three walks of one heap

Space Tally, Heap Diff and Young Space are the rows most often confused. The
distinction is what **bounds** the object set:

> A **diff** is bounded by an *action you supply*. **Young space** is bounded by
> the *collector*. **Space Tally** is bounded by nothing -- it is the standing heap.

So Heap Diff answers *"what did this cost?"*, Young Space *"what is sitting
there?"*, and Space Tally *"what is reachable at all?"*. A step that allocates
nothing still has a young space, and that standing floor is invisible to a diff.

## Two things the table cannot show

**Mode lists are not static.** Every retained dataset **appends** its
colour-capable and size-capable metrics to the Color and Size menus at runtime, so
a Code Map with two coverage datasets loaded has two more `By coverage` entries
than one with none. A screenshot of a menu is a screenshot of one *state*, not of
the tool. The same applies to Young Space: `age` and `fate` only appear as colour
modes when the view that computed them was the one opened.

**The combinations are open-ended.** The **Scenarios** rows name the products
worth knowing, but they are a selection, not an enumeration: with 7 intrinsic
colours, 5 sizes and 10 dataset kinds on the Code Map alone, the space of
area×colour pairs is in the hundreds, and every newly loaded dataset widens it.
The listed ones are those where *being extreme in both axes at once* is a finding
rather than a coincidence. That is the test to apply before adding a row.

## Not in the table

- **Graphviz viewer** (`SWA-Graphviz`) -- the render backend behind the Class
  Diagram, not a user-facing tool.
- **The Sim harness** (`SWASimSpaceTally`, `SimObjectMirror`) -- a parity harness
  for the Space Tally against an image *file*.
- **Coverage, Duplication, Topic Model, Invocation Tally, Timing Tally** -- these
  are Code Map **datasets**, and appear above as `Data` rows rather than as tools.
  They have no menu entry on purpose; a top-level entry would misrepresent them.

## Screenshot recipes

Each tool page carries its picture plus an HTML-comment **recipe** that
regenerates it:

```smalltalk
| w |
w := "...open the tool...".
World displayWorld. (Delay forMilliseconds: 1500) wait.
World displayWorld. (Delay forMilliseconds: 500) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/media/NAME.png'.
w delete.
```

Two `displayWorld`s with a pause between: the first lays out and draws, the second
catches anything deferred to the next cycle (lazily built treemap layouts,
overlays, scrollbars). Paths are relative to the VM's working directory, not to
this file. Images live in [`../media/`](../media), shared with the per-tool docs.

Three caveats learned while capturing these:

- **Record tools cannot be captured in one send.** Arm, act, then `requestStop`,
  then wait for the result window -- the measure phase can take ten seconds.
- **Some openers answer `nil` on purpose.** `openYoungSpaceNow` must not retain the
  young objects it measured, so identify its window by label diff, not by return
  value.
- **Labels collide.** Young Space opens under the label `Space Treemap`, same as the
  Space Tally.
