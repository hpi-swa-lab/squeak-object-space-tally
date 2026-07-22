# SWACodeMap -- Static Code-Structure Treemap for Squeak

> **Engineering cross-refs:** this is the user-facing tour. For the as-is
> architecture (dataset layer, node rollup caches, the coverage-overlay-vs-dataset
> split) see [architecture.md](architecture.md) §3/§4/§6, the protocols in
> [api.md](api.md), and known debt -- notably the *legacy coverage overlay running in
> parallel with datasets* -- in [smells.md](smells.md) §3.2. Undocumented-here but
> shipped: duplication links, topic coloring, Marks, and the Mask (B\A) combinator.

## Motivation

Where **SWASpaceTally** answers *"where does the memory go?"* by walking the live
object graph, the **Code Map** answers the static, source-side question: *"what is
the shape of this code, and where is the weight?"* It renders a package's
`package -> class -> category -> method` tree as a squarified treemap, where each
tile's **area** is a metric you choose (lines of code, source bytes, method count,
or -- with profiling data -- execution counts) and each tile's **colour** is an
orthogonal property you choose (kind, author, recency, churn, or the
documentation/string/code composition).

Because area and colour are independent and both switch live, one map answers many
questions: *which classes are large? which are comment-heavy? who last touched the
hot code? which methods did the tests actually exercise, and how often?*

All examples below use the **SqueakXR** package (74 classes, ~980 methods) and a
coverage data set generated from its own SUnit tests.

```smalltalk
SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.
```

![Code Map of SqueakXR, sized by LOC, coloured by kind](codemap-default-loc-kind.png)

<!-- SCREENSHOT codemap-default-loc-kind.png
| w |
w := SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.
World displayWorld. (Delay forMilliseconds: 500) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'codemap-default-loc-kind.png'.
w delete.
-->

The header chrome -- **Back / Browse / Show / Data / Tree / Size / Color / Links /
Tally / Export / Load / Depth** -- is shared with the other SWA treemaps via
`SWAPane`. The two-line info area below shows whole-run info and the current
selection.

There is no longer a dedicated **X-ref / Clear** button pair. Cross-referencing
another open view is now just an entry in the **Data** menu: every open peer
treemap/flamegraph appears there as "X-ref: `<window>`", and picking it colours
this map by that peer's per-key weight (a `#peer` `SWADataset`) -- so a
cross-reference mixes and matches like any loaded dataset, and picking **None**
clears it. The dataset mechanism itself moved down to the shared `SWAView`, so
*every* SWA tool (Code Map, Space Tally, and any peer) can host datasets and be a
cross-reference source or colour target uniformly.


## One Tool, Many Modes

The Code Map is a *single* tool. The various `open...` class methods are just
**presets** that preconfigure two live-switchable settings -- the **size metric**
and the **colour mode** -- and optionally load a coverage file. Everything they set
is reachable at runtime from the **Size** and **Color** header buttons (and the
right-click context menu), so you can move between any two modes without reopening:

| Opener | Size metric | Colour mode | Coverage data |
|---|---|---|---|
| `openOnPackageNamed:leafKind:` | LOC | by kind | -- |
| `openByteCompositionOnPackageNamed:` | source bytes | byte composition | -- |
| `openCoverage:onPackageNamed:` | covering-test count | coverage overlay | loaded |
| `openInvocations:onPackageNamed:` | invocation count | coverage overlay | loaded |

The only constraint is that the two **execution** size metrics (call count /
covering tests) need a coverage data set present, so they appear in the Size menu
only after one is loaded (via the opener or the **Load** button).


## Size: what the tile AREA means

Right-click -> **Size**, or the header **Size** button (always reachable, even if a
metric collapses the map to empty). The size metric is a rolled-up weight: an
aggregate tile is the sum of its descendants.

![The Size menu](codemap-size-menu.png)

<!-- SCREENSHOT codemap-size-menu.png (captures a Display REGION so the popped-up menu is included)
| w panel overlay menu rect form |
w := SWAPane openByteCompositionOnPackageNamed: 'SqueakXR' leafKind: nil.
panel := w allMorphs detect: [:m | m isKindOf: SWAPane].
overlay := panel treemapOverlay.
World displayWorld. (Delay forMilliseconds: 300) wait.
menu := overlay sizeMenuMorph.
menu popUpAt: (w position + (300@95)) forHand: World activeHand in: World.
World displayWorld. (Delay forMilliseconds: 300) wait.
rect := w bounds.
form := Form extent: rect extent depth: 32.
form copy: (0@0 extent: rect extent) from: rect origin in: Display rule: Form over.
PNGReadWriter putForm: form onFileNamed: 'codemap-size-menu.png'.
menu delete. w delete.
-->

- **Number of methods** -- tiles sized by how many method leaves they contain.
  Pure "how much API is here", ignoring method length.
- **Lines of code** -- non-blank source lines (the default).
- **Source byte size** -- raw source-text byte size. Slightly different from LOC:
  long lines, heavy comments, and big string literals weigh more than line count
  alone suggests. Pairs naturally with the byte-composition colour (below).
- **Execution: call count** -- how many times each method actually ran during a
  profiled test run (raw invocation count). *Requires coverage data.*
- **Execution: covering tests** -- how many distinct tests exercised each method.
  *Requires coverage data.*

Uncovered methods have zero execution weight, so the two execution metrics collapse
untested code to nothing and show -- proportionally -- only what ran.


## Color: what the tile COLOUR means

Right-click -> **Color**, or the header **Color** button. Recolouring is **instant**
(no relayout -- only the cached image is redrawn), so you can flip through colour
modes on a fixed layout.

- **By kind** -- package / class / category / method (and a distinct teal for
  class-comment nodes, purple for class-side methods). The structural default.
- **By byte composition** -- the doc/string/code bar (see below).
- **By LOC (heat)** -- green (small) to red (large), log-scaled.
- **By avg LOC / method** -- average method length, surfacing classes of long methods.
- **By avg versions / method** -- change churn from the `.changes`/`.sources` history.
- **By recency (last changed)** -- newest code brightest.
- **By author (last changed)** -- a hue per author.

![Coloured by LOC heat](codemap-color-loc-heat.png)

![Coloured by author](codemap-color-author.png)

![Coloured by recency](codemap-color-recency.png)

<!-- SCREENSHOT codemap-color-loc-heat.png / codemap-color-author.png / codemap-color-recency.png
| w tm cap |
w := SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.
tm := w allMorphs detect: [:m | m isKindOf: SWACodeTreemapMorph].
cap := [:name | World displayWorld. (Delay forMilliseconds: 400) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
	PNGReadWriter putForm: w imageForm onFileNamed: name].
tm colorMode: #loc.     cap value: 'codemap-color-loc-heat.png'.
tm colorMode: #author.  cap value: 'codemap-color-author.png'.
tm colorMode: #recency. cap value: 'codemap-color-recency.png'.
w delete.
-->



## Byte Composition: documentation / strings / code

Selecting **Color -> By byte composition** (or the `openByteComposition...` preset)
paints, inside every method tile, a horizontal proportional bar splitting the
method's source bytes into three lexical buckets:

- **teal** -- documentation (method-comment bytes),
- **amber** -- string-literal bytes,
- **green-gray** -- the rest (code).

```smalltalk
SWAPane openByteCompositionOnPackageNamed: 'SqueakXR' leafKind: nil.
```

![Byte composition: doc (teal) / string (amber) / code (green-gray)](codemap-byte-composition.png)

<!-- SCREENSHOT codemap-byte-composition.png
| w |
w := SWAPane openByteCompositionOnPackageNamed: 'SqueakXR' leafKind: nil.
World displayWorld. (Delay forMilliseconds: 500) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'codemap-byte-composition.png'.
w delete.
-->

This is most useful sized by **Source byte size** (the preset's default), so a
method's tile area *is* its byte size and the bar splits that area -- but size and
colour are independent, so you can keep any size metric and just turn the bar on.
Aggregate tiles (class, category) roll the composition up over their methods; when a
tile is too small to show its method children the bar still conveys the mix, the
same fallback the coverage overlay uses.

The **class comment** is a first-class node in the tree (a teal `class comment`
leaf, sibling to the method categories), so a class's prose documentation has its
own measurable tile -- entirely documentation bytes.

### Implementation: the lexical classifier and its cache

A single left-to-right state machine (`SWACodeMethodNode class>>classifyBytes:`)
charges every source character to comment / string / code, honouring Smalltalk's
quoting rules (`""` and `''` escapes, `$'` character literals, a quote inside the
other kind of region). Parsing is more expensive than counting lines, so results
are cached in a **weak dictionary keyed on the `CompiledMethod`**
(`SWACodeMethodNode class>>byteAnalysisCache`). The entry survives tree rebuilds
(each reopen builds fresh transient nodes) yet is collected automatically when a
method is recompiled or removed -- no manual flushing -- and is validated against
the current source length so a stale entry can never mis-sum.


## Coverage: which tests exercised which methods

The Code Map doubles as a **test-coverage** viewer. A `SWACoverageData` set records,
for each method, which tests covered it and how many times it was called; it is
persisted as image-independent `Class>>selector`-keyed JSON. Generate one for a
package and its tests:

```smalltalk
SWACoverage generatePackages: #('SqueakXR')
    tests: (SWACoverage testClassesForPackages: #('SqueakXR'))
    toFile: 'squeakxr-coverage.json'.
```

### Coverage overlay

Loading the data (the **Load** button, or `showCoverageData:`) tints the map:
**green** covered methods (graded by the metric), **blue** executed tests and
TestCase classes, **red** methods evicted during the run, gray untouched. Aggregate
tiles get a proportional green/red/blue/gray bar summarising their leaves. The
overlay works on *any* size metric -- here on a LOC-sized structural layout:

![Coverage overlay (green covered, blue tests) on a LOC-sized map](codemap-coverage-overlay-on-loc.png)

<!-- SCREENSHOT codemap-coverage-overlay-on-loc.png (overlay tint on a LOC-sized layout)
| w tm |
w := SWAPane openOnPackageNamed: 'SqueakXR' leafKind: nil.
tm := w allMorphs detect: [:m | m isKindOf: SWACodeTreemapMorph].
tm showCoverageData: (SWACoverageData fromFile: 'squeakxr-coverage.json') weightMode: #tests.
(w allMorphs detect: [:m | m isKindOf: SWAPane]) treemapCoverageStatus: 'Coverage overlay on LOC-sized map'.
World displayWorld. (Delay forMilliseconds: 500) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'codemap-coverage-overlay-on-loc.png'.
w delete.
-->

### Coverage-weighted layout

`openCoverage:onPackageNamed:` additionally *sizes* tiles by covering-test count, so
untested code collapses and the map shows, proportionally, what the tests
exercised:

```smalltalk
SWAPane openCoverage: 'squeakxr-coverage.json' onPackageNamed: 'SqueakXR'.
```

![Sized by covering-test count](codemap-coverage-tests-weighted.png)

Switch the Size metric to **Execution: call count** for raw invocation counts (or
use `openInvocations:onPackageNamed:`):

![Sized by invocation count](codemap-coverage-invocations-weighted.png)

<!-- SCREENSHOT codemap-coverage-tests-weighted.png + codemap-coverage-invocations-weighted.png
| w tm cap |
w := SWAPane openCoverage: 'squeakxr-coverage.json' onPackageNamed: 'SqueakXR' leafKind: nil.
tm := w allMorphs detect: [:m | m isKindOf: SWACodeTreemapMorph].
cap := [:name | World displayWorld. (Delay forMilliseconds: 400) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
	PNGReadWriter putForm: w imageForm onFileNamed: name].
cap value: 'codemap-coverage-tests-weighted.png'.
tm weightMetric: #invocations.
cap value: 'codemap-coverage-invocations-weighted.png'.
w delete.
-->

### Provenance on selection

Press **Show** to reveal the bottom row: a **Details** box (left), the **source**
pane (center, Shout-highlighted), and a **Covered by N tests** pane (right) listing
the tests that exercised the selected method. Selecting a method green-filters the
map to it; selecting a test blue-filters to the methods it covered.

![Show mode: details, source, and covering-tests panes](codemap-show-source-details.png)

<!-- SCREENSHOT codemap-show-source-details.png (selects a covered method, then opens the Show row)
| w tm panel data leaf |
data := SWACoverageData fromFile: 'squeakxr-coverage.json'.
w := SWAPane openCoverage: 'squeakxr-coverage.json' onPackageNamed: 'SqueakXR' leafKind: nil.
tm := w allMorphs detect: [:m | m isKindOf: SWACodeTreemapMorph].
panel := w allMorphs detect: [:m | m isKindOf: SWAPane].
leaf := nil.
tm rootNode withAllChildrenDo: [:n |
	(leaf isNil and: [(n isKindOf: SWACodeMethodNode) and: [(data coveringTestCountFor: n crossRefKey) >= 2]])
		ifTrue: [leaf := n]].
tm selectTileNode: leaf.
panel toggleSource.
World displayWorld. (Delay forMilliseconds: 500) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'codemap-show-source-details.png'.
w delete.
-->


## Architecture

### The node tree (`SWANode` / `SWACodeNode`)

The data model is a tree of `SWACodeNode`s, sharing the `SWANode` contract
(`parent`/`children`, `depth`, `pathString`, `crossRefKey`) with the Space Tally and
Sampling Tally node types.

```
SWANode
  SWACodeNode
    SWACodeRootNode       -- aggregates one or many packages (glob-matched)
    SWACodePackageNode    -- a package
    SWACodeClassNode      -- a class (builds a comment node + category children)
    SWACodeCategoryNode   -- a method category (instance- or class-side)
    SWACodeMethodNode     -- a method leaf (source/LOC/byte metrics, all cached)
      SWACodeCommentNode  -- the class comment as a leaf (100% documentation)
```

Children are built lazily; metrics (`loc`, `byteSize`, `byteComposition`,
`changeCount`, ...) are cached per node, and each size metric has its own rolled-up
cache (`rollupLoc`, `rollupBytes`, `rollupCoverage`, `rollupMethodCount`) so
switching size metrics is a fast relayout, never a re-walk. `SWACodeNode>>totalSize`
is the single dispatch point that maps the active `weightMetric` to the right
rolled-up weight.

Reading source from the `.changes`/`.sources` file is the one genuinely expensive
step, so each method's source string is read once and held on the node; LOC and the
byte analysis derive from that cached string.

### The view (`SWAView` / `SWATreemapMorph` / `SWACodeTreemapMorph`)

The treemap morph subclasses the shared `SWAView` (selection, cross-ref key index,
cached-Form rendering) and `SWATreemapMorph` (squarified layout, zoom in/out, the
`drawTileContent:in:on:` hook). `SWACodeTreemapMorph` supplies the code-specific
colour palettes and overrides `drawTileContent:` to paint the byte-composition and
coverage bars.

**Size vs colour are deliberately decoupled.** Changing the colour mode flushes only
the cached Form (instant redraw); changing the size metric invalidates the layout
and re-lays-out, keeping the current zoom and selection. This is why "recolouring is
instant" while "resizing reflows".

### The chrome (`SWAPane`) and the menus

`SWAPane` wraps the morph with the shared header. The **Size** and **Color**
buttons and the right-click context menu are driven by a *single* menu source
(`SWATreemapOverlay>>sizeMenuMorph` / `colorMenuMorph`), so the header buttons and
the context menu can never drift apart. The header buttons exist because a size
metric can legitimately collapse the map to an empty canvas (e.g. call-count sizing
when nothing in scope was covered) -- the tile-based right-click menu would then be
unreachable, but the buttons never are. **Clear Cov** also reverts a dynamic size
metric back to LOC so clearing coverage can't strand you on an empty map.


## Cross-Referencing via the Data menu

Like the Space Tally and Sampling Tally, the Code Map speaks the shared `crossRefKey`
vocabulary (class names are unique; methods are `'Class>>selector'`). Cross-
referencing another open view is no longer a dedicated button: every open peer
treemap/flamegraph appears in the **Data** menu as "X-ref: `<window>`". Picking one
wraps that peer as a `#peer` `SWADataset` (`SWAPeerViewSource` reads the peer's live
`keyIndex`, weighting by each node's `totalSize`) and colours this map by it -- so
it mixes and matches with loaded datasets like any other, and **None** clears it.

Container tiles aggregate: a class (or package) tile is coloured by the summed
weight of its matching descendants (`SWADatasetMetric>>valueForNode:` rolls up when
a node's own key has no value). So highlighting *which methods a live profiler
sampled* also lights up the classes and packages that own them, even though the
peer is keyed at method granularity. And a Space Tally can equally colour a Code
Map (per-class bytes) -- the same path, no special case.


## Quick Start

From the world menu: **open... -> Code Map**, or:

```smalltalk
"Static structure, sized by LOC, to the class level."
SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.

"Down to methods, sized + coloured by source byte composition."
SWAPane openByteCompositionOnPackageNamed: 'SqueakXR'.

"Test coverage, sized by covering-test count."
SWAPane openCoverage: 'squeakxr-coverage.json' onPackageNamed: 'SqueakXR'.

"Test coverage, sized by raw invocation count."
SWAPane openInvocations: 'squeakxr-coverage.json' onPackageNamed: 'SqueakXR'.
```

`leafKind:` stops *rendering* at a given level (`#package` / `#class` / `#category`
/ `#method`); the full tree and all roll-ups are still built. With a broad glob
(`'*'`) use `#class` to avoid tiling tens of thousands of method nodes.


## Regenerating the Screenshots

Each image above is followed by an HTML comment containing the exact Smalltalk that
produced it. The snippets use bare relative file names; they resolve against the
image's working directory (`FileDirectory default`), so either evaluate them from a
`doc/`-rooted image or prepend the `doc/` path to each file name. They all assume the
coverage data file `squeakxr-coverage.json` sits next to the images; regenerate it
first with:

```smalltalk
SWACoverage generatePackages: #('SqueakXR')
    tests: (SWACoverage testClassesForPackages: #('SqueakXR'))
    toFile: 'squeak-object-space-tally/doc/squeakxr-coverage.json'.
```

The captures use a fixed window size (`SWAPane class>>defaultWindowBounds`,
`568@205 corner: 1935@1264`) so the full button bar fits on one row and the map does
not overflow; on a smaller display the window is clipped to the screen and the button
bar wraps onto extra rows.


## See Also

- **[SWASpaceTally](SWASpaceTally.md)** -- structural memory analysis (the sibling
  treemap over the live object graph).
- **SWAMessageTally** -- the Sampling Tally: a statistical message-tally profiler
  and flamegraph (driven by the external st-spy sampler), documented separately.
- **[index](index.md)** -- the shared SWA tools index.
