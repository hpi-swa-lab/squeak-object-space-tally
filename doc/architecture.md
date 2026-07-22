# SWA Architecture -- As-Is Overview

![](_navigation.html)

## 1. SWA Maps

SWA Maps is a suite of **interactive structural-analysis visualizations** for Squeak.
Every tool renders a tree of nodes as a navigable **squarified treemap** (or a
flamegraph, or a Graphviz diagram), and any tool can be coloured/sized by another
tool's data because they all share one identity vocabulary: the **`crossRefKey`**
(class names are unique; methods are `'Class>>selector'`, ivars `'Class>>#ivar'`).

Five user-facing tools, plus a shared substrate and supporting data models:

| Tool | Question | Tree | Tile weight |
|---|---|---|---|
| **Code Map** | shape of code -- size, docs, coverage, churn, duplication, topics | package -> class -> category -> method | LOC / bytes / methods / execution counts / dataset metric |
| **Space Tally** | where memory goes, who retains it | live object graph (BFS spanning tree) | bytes |
| **Sampling Tally** | where wall-clock time goes | external-sampler call tree | microseconds |
| **Change Map** | when code changed, how much | `.changes` time buckets | diff lines |
| **Class Diagram** | inheritance shape | class/inheritance graph (Graphviz) | -- (diagram) |

## 2. Architecture

```
                 SWAPane            (window chrome, ~130 methods, 43 ivars)
                   |  wraps
                 SWAView            (abstract Morph: selection, keyIndex,
                   |                  datasets, cross-ref, coverage, search, marks)
       +-----------+-----------+
   SWATreemapMorph      SWASamplingTallyFlamegraphMorph
       |                SWAClassDiagram
   concrete treemaps
   (Code/Space/Sampling/Change)

                 SWANode            (tree contract: parent/children/crossRefKey/markKey)
                   |
   SWACodeNode*  SWASpaceTallyNode  SWASamplingTallyNode  SWAChangeNode

                 SWADataset / SWADatasetMetric   (retained, named overlays, axis-bindable)
                 SWAMarkSet                       (global cross-view bookmarks)
                 SWAMethodWrapper / SWACapturingLayer  (instrumentation substrate)
```

Two independent inheritance spines meet at the view:

- **Data spine** -- `SWANode` and its per-tool subclasses model the *tree*.
- **View spine** -- `SWAView` -> `SWATreemapMorph` -> concrete treemaps model the
  *rendering + interaction*. `SWAView` also directly parents the flamegraph and the
  class diagram.

`SWAPane` composes (not subclasses) a `SWAView`, supplying all window chrome.

### Package map (as read earlier from the image)

| Package | Classes | Role |
|---|---:|---|
| SWA-Base | 12 | `SWANode`, `SWAView`, `SWATreemapMorph`, `SWATreemapOverlay`, `SWAPane`, `SWADataset`, `SWADatasetMetric`, `SWAMarkSet`, `SWAMaskSource`, `SWAPeerViewSource`, `SWAMethodWrapper`, `SWACapturingLayer` |
| SWA-Nodes | 11 | code-node hierarchy, `SWASamplingTallyNode`, `SWASpaceTallyNode` |
| SWA-CodeMap | 3 | `SWACodeTreemapMorph`/`Overlay`, `SWASampleTallyData` |
| SWA-SpaceTally | 14 | `SWASpaceTally`(+Sim), nodes, explorer, treemap/overlay, class summary, JSON reader/writer, highlight, bucket wrapper, `SimObjectMirror` |
| SWA-Coverage | 5 | `SWACoverage`, `SWACoverageData`, `SWACoverageWrapper`, `SWACoverageLogTailer`, `SWACoverageRunPanel` |
| SWA-MessageTally | 6 | `SWASamplingTally`, flamegraph, treemap/overlay, `SWAStructure`, `SWATallyWrapper` |
| SWA-ChangeMap | 4 | `SWAChangeNode`, `SWAChangeParser`, `SWAChangeTreemapMorph`/`Overlay` |
| SWA-TopicModel | 2 | `SWABitermTopicModel`, `SWATopicData` |
| SWA-Duplication | 3 | `SWACodeSimilarity`, `SWADuplicationData`, `SWADuplicationPartnerStub` |
| SWA-Graphviz | 4 | `GraphvizMorph`, `GraphvizPane`, `GraphvizJsonParser`, `GraphvizPlainParser` |
| SWA-ClassDiagram | 1 | `SWAClassDiagram` |
| SWA-Widgets | 4 | `SWAMarksListMorph`, `SWASearchFieldMorph`, `SWASelectionPainter`, `SWASplitter` |
| SWA-Tests | 3 | `SWADatasetTest`, `GraphvizPlainParserTest`, container fixture |

> Empty/absorbed categories: `SWA-CodeMap-Duplication`, `SWA-SpaceTally-Sim`,
> `SWA-Tmp`, `SWA-TopicModel`(shared), `SWA-MessageTally`(shared) show as categories
> but their classes physically live in the packages above.

## 3. The tree contract (`SWANode`)

`SWANode` (2 ivars: `parent`, `children`) is the minimal shared tree protocol.
Everything a view walks goes through it:

- structure: `children`, `parent`, `depth`, `isLeaf`, `withAllChildrenDo:`, `pathString`
- weight: `totalSize` (subclass-defined; drives tile area)
- identity: `crossRefKey` (cross-view links; nil = not cross-referenceable),
  `markKey` (defaults to `crossRefKey`; packages/categories override to their name),
  `nodeKind` (a Symbol: `#class`/`#package`/`#method`/`#spaceTally`/... recorded in
  mark provenance)

### Per-tool node families

- **`SWACodeNode`** hierarchy (SWA-Nodes) -- `SWACodeRootNode` (aggregates
  glob-matched packages, resolves package nesting + category ownership),
  `SWACodePackageNode`, `SWACodeClassNode` (builds a comment node + category
  children, owns the Graphviz record-box + UML compartment emission),
  `SWACodeCategoryNode`, `SWACodeMethodNode` (leaf; source/LOC/byte/change metrics,
  all cached), `SWACodeCommentNode` (class comment as a 100%-doc leaf),
  `SWACodeInstVarNode` (markable ivar, keyed `'Class>>#ivar'`),
  `SWACodeMarkSetRootNode` (children = the currently-marked classes; feeds the live
  marks class-diagram). Children lazy; metrics cached per node; **each size metric
  has its own rollup cache** (`rollupLoc`/`rollupBytes`/`rollupCoverage`/
  `rollupDataset`/`rollupMethodCount`/`rollupTopic`) so switching size is a fast
  relayout, never a re-walk. `totalSize` is the single dispatch over `weightMetric`
  / `sizeMetric` / `coverageData`. Coverage/topic/size metrics **resolve up the
  parent chain**, so they need only be set on the root.
- **`SWASpaceTallyNode`** -- one node per reachable heap object; holds the object
  (strong ref until compaction), captured `className`/`selfSize`, rolled-up
  `totalSize`, `edgeLabel` (slot provenance), `otherParents`, diff `isNew` marker,
  and pruning bookkeeping. Carries its own explorer wrappers, bullet-list
  serialization, JSON round-trip, retention-DAG Graphviz, and morph-highlight
  helpers.
- **`SWASamplingTallyNode`** -- a call-tree frame: `selfCount`/`totalCount`
  (microseconds), `childNamed:` find-or-create build, `rollUpTotals`, plus two
  **projections** (`asCodeGroupingRoot` = class/method grouping of the same calls,
  `prunedToKeys:` = mask survivor pruning) that let a call tree be re-rendered as a
  different structure.
- **`SWAChangeNode`** -- one change record (or a time-bucket container); computes
  diff size against the prior version, provenance status (`#current`/`#superseded`/
  `#inHistory`/`#gone`/`#other`), author, and inline-diff sources.

## 4. `SWAView`

`SWAView` (23 ivars) is where nearly every cross-cutting concern lives. Its
responsibilities, by subsystem:

- **structure** -- `rootNode`, `keyIndex` (`crossRefKey -> node`, rebuilt eagerly in
  `setRoot:` so peers can O(1)-look-us-up), `history` (zoom stack).
- **datasets** (the unified overlay layer) -- `datasets`, `addDataset:` (mints a
  unique modeSymbol per metric), `selectDataset:`, `setDataMode:`, `metricForMode:`,
  `metricsByMode`, `applyColorMetricSymbol:`, `intrinsicColorMode`.
- **coloring** -- `colorMode`/`colorMode:`/`colorModeOptions`, `colorForNode:`
  (applies the search-dim overlay last), `intrinsicColorForNode:` (the
  metric/coverage/highlight compositing core), `baseColorForNode:` (subclass hook).
- **cross-ref + coverage provenance** -- `highlightWeights:`,
  `crossReferenceFrom:`, `showCoverageData:weightMode:`, `effectiveWeightOf:`
  (rolls a foreign weight map up the tree), the blue-test tint + green/red coverage
  ramp + filter machinery (`filterToTestKey:`, `filterToCoveredMethodKey:`,
  `coverageProportionsForNode:` for aggregate bars), `provenanceListForSelection`.
- **search** -- `searchFor:`, `rebuildSearchMatches` (matches + all ancestors stay
  bright), `isSearchDimmed:`.
- **marks** -- `markedNodes` (cached), `toggleMark:`, `isNodeMarked:`,
  `markProvenance` (a serializable snapshot of where a mark was made), `viewKind`
  (machine-readable kind Symbol; overridden per view).

Concrete `baseColorForNode:` overrides plus a small set of `viewKind`/`overlayClass`
hooks are essentially all a concrete view *must* supply; everything else is
inherited.

### `SWATreemapMorph` 

Adds the Bruls/Huijsen/van Wijk **squarified layout** (`squarify:scales:into:`,
`worstAspectRatio:...`, `emitRow:...`), **Form-cached static rendering**
(`ensureCachedForm`, `renderStaticLayerOn:at:`, `drawTileContent:in:on:` hook),
deferred-resize stepping (stretch-blit the stale form while dragging, relayout once
settled), zoom in/out with breadcrumb, and `leafKind` (stop *rendering* at a
`#kind` cutoff while the full tree + rollups are still built). Concrete subclasses
supply the palette + the `drawTileContent:` decorations (byte-composition bars,
coverage bars, topic bars, duplication links).

**Key decoupling:** colour change flushes only the cached Form (instant redraw);
size change invalidates the layout and reflows (keeping zoom + selection). This is
the "recolour is instant, resize reflows" behaviour.

### `SWATreemapOverlay` 

A transparent sibling morph over the treemap. Handles hover highlight + canvas-drawn
tooltip (Morphic balloons never worked over these views), click-select /
click-again-zoom / shift-mark, right-click context menu, and the shared Size/Color
menu construction. Draws mark borders (green), secondary selection (red), and
selection (yellow) via the stateless `SWASelectionPainter`.

## 5. `SWAPane`

The single largest class (43 ivars, ~130 methods). Wraps any `SWAView` and supplies
**all** window UI, rebuilt per-view and capability-gated (so the header changes as
you morph one tool into another):

- **header** -- hamburger pane-menu, Back, Browse, Deselect, then overlay-gated
  Data / Tree / Size / Color / Links, then Depth + a live name-search field.
- **body flaps** -- a left **Marks** panel (multi-select list + comment editor +
  provenance) and a bottom **Source** row (Details box + Shout source pane +
  covering-tests/duplicates list), both as collapsible floating-tab flaps with
  draggable `SWASplitter`s.
- **datasets orchestration** -- the file-Load dispatch (`loadJsonFile:` by JSON
  marker), the async **Generate** menu entries (coverage / call tally / sample
  tally / duplication / topic -- each forks or opens a Stop panel), the **Mask**
  combinator (B\A), and peer cross-reference wiring.
- **structure morphing** -- the Tree menu: swap the base structure in place
  (`setStructureMode:` / `morphViewInto:`), keeping both views cached in
  `structureViews`.
- **coverage/tally lifecycle** -- start/collect/abandon invocation tally, the Stop
  window, and (critically) `delete` tears down any live instrumentation so wrappers
  never linger.

## 6. Datasets 

The single most important architectural idea (journal 2026-06-30 onward). A
**`SWADataset`** is a named, retained, image-independent overlay wrapping an analysis
result keyed by `crossRefKey`. Kinds: `#coverage`, `#duplication`, `#spaceTally`,
`#sampleTally`, `#topic`, `#masked`, `#peer`.

A dataset exposes one or more **`SWADatasetMetric`**s, each **axis-bindable** to
`#color`, `#size`, `#links`, or `#decoration`. A metric answers a raw per-key value
(`rawValueForKey:`), rolls it up to containers (`#sum` or `#max`), and maps it to a
`Color` via a swappable `scale` (or a categorical `colorBlock:` for topics). So one
loaded coverage file yields *both* a "By coverage" and a "By call" metric; loading
the same kind twice gives two coexisting, instantly-switchable entries.

Two adapter sources make the layer general:

- **`SWAPeerViewSource`** -- wraps another open view as a `#peer` dataset, reading
  its live `keyIndex` weighted by `totalSize`. This *replaced* dedicated X-ref
  buttons: cross-referencing a live peer is now just a dataset in the Data menu.
- **`SWAMaskSource`** -- set arithmetic (currently `B \ A` = keys touched in B but
  not A) over two operand datasets. The mask **mirrors B's metrics gated to the
  survivor set**, so you can colour the mask by call counts, coverage, bytes, etc.,
  not just a boolean hit. The algebra closes: a mask can be an operand of another
  mask.

**`SWAStructure`** completes the picture: a dataset can also supply *tree
projections* (its primary tree plus derived ones -- e.g. a call tally exposes a
flamegraph call-tree structure *and* a grouped-by-class treemap structure of the
same data). The Tree button morphs the view between them.

Binding is orthogonal to kind: any dataset can **decorate** (colour/size/link an
existing tree) or **structure** (become the tree). This "decorate vs structure"
axis is the conceptual core to keep in mind when evolving the design.

## 7. Instrumentation substrate

`SWAMethodWrapper` is installed *in place of* a `CompiledMethod` in a method dict;
sends dispatch to `run:with:in:`, which does minimal bookkeeping then forwards to
the real method (`realMethod` peels stacked wrappers). Subclasses:
`SWACoverageWrapper` (attributes each fired method to the running test) and
`SWATallyWrapper` (invocation count + optional flamegraph call-tree capture).

The correctness backbone is **`SWACapturingLayer`**, a process-specific
`DynamicVariable` holding a suppression depth. "Capturing" is a COP-style *layer*,
active by default; the instrumentation's own machinery runs inside
`withoutCapturing:` so wrapped methods it touches fall straight through. This is
per-process (not a global flag) precisely because wrapping the *live Morphic UI*
means several processes run wrapped methods concurrently -- a global boolean raced
and crashed the VM. The whole wrapper family is a scar tissue of hard-won VM-crash
lessons (documented exhaustively in the method comments): primitive-188 fallback
corruption, per-method `flushCache` hangs on `'*'`, layered-wrapper stranding,
`doesNotUnderstand:` never being instrumentable, infrastructure classes
(`SWAMethodWrapper`/`SWACapturingLayer` themselves) never being wrappable.

`SWACoverage` is the front end: it selects methods by package (with a hard
`substratePackagePatterns` guard + a user exclusion list), installs/uninstalls in
bulk (`installNoFlush` + one `flushSystemCache`), and runs tests with provenance in
a suppressed-UI window, forked behind a `SWACoverageRunPanel` (Stop) or a fresh
throwaway headless child image (`SWACoverageLogTailer` tails its log). Results land
in `SWACoverageData` (image-independent `Class>>selector`-keyed JSON with covering
tests, invocation counts, eviction flags).

## 8. Space Tally walker

`SWASpaceTally` is a BFS object-graph walker (`walk` is a **template method** with
hooks; the `SWASimSpaceTally` subclass reuses it to walk a *simulated* image via
VMMaker's `StackInterpreterSimulator` + `SimObjectMirror`, deduping on oop instead
of identity). Key invariants:

- **Closed universe:** GC, then snapshot `deepUniverse` = all live objects *before*
  allocating any walker state, so the walker's own scaffolding is never tallyable
  and the BFS is guaranteed finite (no depth/time cap needed; `maxVisits` is
  optional, testing-only).
- **First-reached-parent charging** turns the graph into a spanning tree; extra
  referrers optionally recorded as `otherParents`.
- **Slot enumeration** (`referentsOf:do:`) via `thisContext` mirror primitives
  (proxy-safe), following named ivars / indexed slots / literals / the class pointer
  (Behaviors only), skipping weak slots, and bypassing the universe gate only for a
  collection's backing store (which reallocates).
- **Find Deep** sweeps the universe for unreached objects into a `LostAndFound` bin.
- **Diff** filters a second walk to objects absent from a baseline.

Output: a multi-column `SWASpaceTallyExplorer`, a treemap, a per-class
`SWASpaceTallyClassSummary` (feeds the Code Map's `#spaceTally` dataset), and a
single-pass streaming JSON writer/reader that preserves the `otherParents` graph via
mint-on-first-sight ids.

## 9. Cross-cutting mechanisms worth naming

- **`crossRefKey`** is the lingua franca. Every cross-tool feature (peer datasets,
  masks, marks, coverage provenance) is keyed by it, which is why the tools compose
  at all.
- **`SWAMarkSet`** is a process-wide singleton of cross-view bookmark keys +
  comments + provenance, JSON-persistable. Every open pane observes it; a mark set
  in any view lights up (green) in every view that contains it, and can spawn a live
  class diagram of the marked classes.
- **`SWASelectionPainter`** centralizes all selection/hover/tooltip drawing so the
  treemap overlay, flamegraph, and graph view stay visually consistent.
- **Async generation** is a recurring pattern: heavy work (coverage, duplication,
  topic fit, sample profiling) runs forked at background priority behind a
  `SWACoverageRunPanel` Stop window, streaming results back on the UI process via
  `WorldState addDeferredUIMessage:`.

## 10. Rendering pipeline

```
setRoot: aNode
  -> rebuildKeyIndex, flushMarksCache
computeLayout (lazy, on ensureLayout)
  -> squarify children of currentNode into tiles (node -> Rectangle), respecting leafKind
ensureCachedForm
  -> renderStaticLayerOn: a fresh Form:
       per tile: colorForNode: (intrinsic metric/coverage/highlight, then search-dim)
                 drawTileContent: (bars/links, subclass hook)
                 frame + label
drawOn:
  -> blit cachedForm (or stretch-blit during resize)
overlay drawOn:
  -> hover/selection/mark borders + tooltips + decoration links (canvas-drawn)
```

Colour changes flush only the Form; size/zoom/root changes invalidate the layout.

## 11. Extension points

- **New tool view:** subclass `SWATreemapMorph` (or `SWAView` for a non-treemap),
  override `baseColorForNode:`, `viewKind`, `overlayClass`, and a node family under
  `SWANode`. Wrap it in `SWAPane on:`. The header adapts by capability-gating.
- **New dataset kind:** add a `#kind` case to `SWADataset>>buildMetrics` +
  `defaultBindings` + `defaultScale`, a `SWADataset class` constructor, and a
  `rawValueForKey:` case in `SWADatasetMetric`. Add a Load-dispatch marker + a
  Generate menu entry in `SWAPane` if it should be loadable/generatable.
- **New structure projection:** have the dataset answer `SWAStructure`s from
  `#structures`, each with a `viewClass` + a lazy `rootBlock`.
