# SWA Tools -- Gallery

A one-look overview of the SWA tool suite. Each tool visualises a tree of
`SWANode`s through the shared view layer (`SWAView` + `SWAPane`) as a
navigable squarified treemap, flamegraph, or diagram, and any tool can colour
itself by another's data because they all speak the same `crossRefKey`
vocabulary. See [index.md](index.md) for the shared-layer and dataset details, and
the per-tool docs linked below.

## The shared view layer

Not a tool of its own -- the substrate every tool is built on. One tree contract
(`SWANode`: `parent`/`children`, `depth`, `pathString`, `crossRefKey`), one morph
(`SWAView`: selection, cached-Form render, the dataset layer), and one chrome
(`SWAPane`: **Back / Browse / Deselect / Show / Data / Tree / Size / Color /
Links** + breadcrumb + two info lines + the toggleable **Show** row with Details /
source / cross-reference panes). The header is rebuilt per view and
capability-gated, so it changes as you morph one tool into another. Below: the
Code Map in **Show** mode -- the full chrome, breadcrumb, selection highlight, and
the details/source/covering-tests panes are all view-layer features.

![The shared SWAPane chrome in Show mode: header, breadcrumb, info lines, and the details/source/xref panes](gallery-viewlayer.png)

<!-- SCREENSHOT gallery-viewlayer.png (shared chrome + Show row; needs squeakxr-coverage.json alongside)
| w tm panel data leaf |
data := SWACoverageData fromFile: 'squeak-object-space-tally/doc/squeakxr-coverage.json'.
w := SWAPane openCoverage: 'squeak-object-space-tally/doc/squeakxr-coverage.json' onPackageNamed: 'SqueakXR' leafKind: nil.
tm := w allMorphs detect: [:m | m isKindOf: SWACodeTreemapMorph].
panel := w allMorphs detect: [:m | m isKindOf: SWAPane].
leaf := nil.
tm rootNode withAllChildrenDo: [:n |
	(leaf isNil and: [(n isKindOf: SWACodeMethodNode) and: [(data coveringTestCountFor: n crossRefKey) >= 2]])
		ifTrue: [leaf := n]].
tm selectTileNode: leaf.
panel toggleSource.
World displayWorld. (Delay forMilliseconds: 700) wait. World displayWorld. (Delay forMilliseconds: 300) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-viewlayer.png'.
w delete.
-->

## Tools

### Code Map -- static code-structure treemap

The `package -> class -> category -> method` tree, tile area = a size metric (LOC /
bytes / method count / execution counts), tile colour = an orthogonal property
(kind / author / recency / churn / byte-composition). Full doc:
**[SWACodeMap.md](SWACodeMap.md)**.

![Code Map of SqueakXR, sized by LOC, coloured by kind](gallery-codemap.png)

<!-- SCREENSHOT gallery-codemap.png
| w |
w := SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.
World displayWorld. (Delay forMilliseconds: 500) wait. World displayWorld. (Delay forMilliseconds: 200) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-codemap.png'.
w delete.
-->

The Code Map is one tool with several **modes**, reachable live from the Size /
Color / Load buttons (the `open...` methods are just presets):

- **Coverage** -- load a `SWACoverageData` JSON to tint covered methods green,
  tests blue, evicted red; optionally *size* by covering-test count so untested
  code collapses. (`openCoverage:onPackageNamed:` /
  `openInvocations:onPackageNamed:`)
- **Duplication** -- load a `SWADuplicationData` JSON to surface copy-paste
  clusters (`SWA-CodeMap-Duplication`).
- **Call Tally** -- colour/size by a live profiler's per-method sample weight,
  picked as a `#peer` dataset from the **Data** menu (container tiles roll up
  their sampled methods).

### Space Tally -- object-memory treemap

Walks the *live object graph* (BFS from the roots) and tiles it by retained
**bytes**, so you see where the memory goes and who keeps it alive. Full doc:
**[SWASpaceTally.md](SWASpaceTally.md)**.

![Space Tally of the live image, tiles sized by retained bytes](gallery-spacetally.png)

<!-- SCREENSHOT gallery-spacetally.png (whole-image walk; a few seconds)
| w |
w := SWASpaceTally openTreemap.
World displayWorld. (Delay forMilliseconds: 1500) wait. World displayWorld. (Delay forMilliseconds: 500) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-spacetally.png'.
w delete.
-->

### St-Spy -- sampling profiler flamegraph

Drives the external **st-spy** sampler over a running image and presents the
wall-clock call tree as a flamegraph (also treemap / explorer). Shows *where time
goes*. Stub doc: **[SWAMessageTally.md](SWAMessageTally.md)**.

![St-Spy flamegraph of a profiled run](gallery-stspy.png)

<!-- SCREENSHOT gallery-stspy.png (reuses an existing chrome-trace file rather than live recording)
| spy w |
spy := SWAStSpy new.
spy pid: 18463.
spy parseTraceFile: '18463-2026-06-19T13:45:32+02:00.json'.
w := spy openFlamegraph.
World displayWorld. (Delay forMilliseconds: 1200) wait. World displayWorld. (Delay forMilliseconds: 400) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-stspy.png'.
w delete.
-->

`SWAStSpy open` records THIS image for 10 s and opens the flamegraph. Live
recording needs the `./st-spy` binary in the VM's working directory.

### Change Map -- `.changes`-file time treemap

A time-bucketed treemap over the `.changes` file
(`year -> month -> week -> day -> save -> package -> class -> change`), tile weight
= diff-line count. Selecting a change shows an inline diff. Documented in the
journal: [2026-07-09](../../journal/2026-07-09-swachangeparser-change-treemap-and-recovery.md).

![Change Map: the last 14 days of the .changes file, bucketed by time](gallery-changemap.png)

<!-- SCREENSHOT gallery-changemap.png
| w |
w := SWAChangeParser openLastDays: 14.
World displayWorld. (Delay forMilliseconds: 1500) wait. World displayWorld. (Delay forMilliseconds: 500) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-changemap.png'.
w delete.
-->

### Class Diagram -- inheritance diagram

A UML-style class diagram on the SWA view layer (`SWAClassDiagram`): record
boxes + inheritance edges laid out via Graphviz, external superclasses as
lightgray placeholders, click a class/method to drive nav-panel selection.
Documented in the journal:
[2026-07-13](../../journal/2026-07-13-classdiagram-graphviz-json-and-graph-view.md).

![Class Diagram of the JSON package: inheritance edges to external superclasses](gallery-classdiagram.png)

<!-- SCREENSHOT gallery-classdiagram.png (small package: the diagram is only legible on small packages)
| w |
w := SWAClassDiagram openOnPackageNamed: 'JSON'.
World displayWorld. (Delay forMilliseconds: 800) wait. World displayWorld. (Delay forMilliseconds: 300) wait.
PNGReadWriter putForm: w imageForm onFileNamed: 'squeak-object-space-tally/doc/gallery-classdiagram.png'.
w delete.
-->

## Not tools

- **Graphviz viewer** (`SWA-Tools`: `GraphvizMorph` / `GraphvizPane` /
  `GraphvizJsonParser` / `GraphvizPlainParser`) -- an implementation detail behind
  the Class Diagram, not a user-facing tool.
- **`SWA-SpaceTally-Sim`** -- a simulation/parity harness for the Space Tally.

## Housekeeping done while writing this

Naming and scope cleanups applied during the documentation pass:

- Renamed `SWACodeGraphMorph` -> `SWAClassDiagram`.
- Renamed `SWANavPanel` -> `SWAPane`.
- Removed the **containment graph** mode of the class diagram (the old
  `openContainmentOnPackageNamed:` / `#containment` mode) -- it only rendered
  acceptably on tiny packages and is superseded by the treemap Code Map.

Still open: consider whether `SWAView` wants a clearer name alongside `SWAPane`.
