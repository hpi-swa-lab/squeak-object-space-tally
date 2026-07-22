# SWA API Reference -- As-Is

![](_navigation.html)


**Convention:**<br> 
`Class>>selector` = instance side <br> 
`Class class>>selector` = class side
{style="padding:10px; background-color:gray;color:white; width:50%"}


---

## Opening the tools (entry points)

```smalltalk
"Code Map"
SWAPane openOnPackageNamed: 'Morphic-Kernel' leafKind: #class.   "or leafKind: nil for methods"
SWAPane openByteCompositionOnPackageNamed: 'Kernel'.
SWAPane openCoverage: 'cov.json' onPackageNamed: 'SqueakXR'.
SWAPane openInvocations: 'cov.json' onPackageNamed: 'SqueakXR'.
SWAPane openTopics: 'topics.json' onPackageNamed: 'Morphic*'.
SWAPane open.   "whole image, classes as leaves; also the Apps-menu command"

"Space Tally"
SWASpaceTally explore.                 "walk + compact + explorer"
SWASpaceTally walk openTreemap.
SWASpaceTally walkDeep openExplorer.    "+ LostAndFound sweep"
SWASpaceTally exploreDiffFrom: aBaselineTally.
SWASimSpaceTally chooseImageAndExplore. "walk an image FILE via the simulator"

"Sampling Tally (external st-spy sampler)"
SWASamplingTally recordSelfFor: 10.                 "non-blocking, opens flamegraph"
(SWASamplingTally onPid: 1234 duration: 10) recordThenOpen.
(SWASamplingTally new parseTraceFile: 'trace.json') openFlamegraph.

"Change Map"
SWAChangeParser openLastDays: 7.
SWAChangeParser openRecover: 'foreign.changes'.   "changes present there, missing here"

"Class Diagram"
SWAClassDiagram openOnPackageNamed: 'JSON'.
SWAClassDiagram openOnMarks.   "live diagram of the marked classes"
```

---

## `SWANode` (SWA-Base) -- the tree contract

Every model node answers these; a view depends only on this protocol.

- `children` / `parent` / `parent:` -- structure (leaves answer `#()`).
- `name` -- short display label (subclassResponsibility).
- `totalSize` -- treemap tile weight (subclassResponsibility).
- `isLeaf`, `depth`, `pathString`, `withAllChildrenDo:` -- derived tree ops.
- `crossRefKey` -- cross-view identity String, or nil. **This is the key that makes
  tools compose.** Classes -> class name; methods -> `'Class>>selector'`.
- `markKey` -- bookmark identity; defaults to `crossRefKey`; packages/categories
  override to their own name.
- `nodeKind` -- machine-readable Symbol (`#class`/`#package`/`#method`/...) recorded
  in mark provenance.

---

## `SWAView` (SWA-Base) -- the abstract view

The hub. Subclass hooks in **bold**.

### Structure / lifecycle
- `setRoot: aNode` -- set root, rebuild `keyIndex`, flush marks (subclasses extend).
- `rootNode`, `selectedNode`, `secondarySelection` / `secondarySelection:`.
- `keyIndex` -- `crossRefKey -> node` map (lazy rebuild); how peers cross-reference.
- `rebuildKeyIndex`, `selectNodeForKey:`, `canZoomOut`.

### Datasets (the overlay layer)
- `addDataset: aSWADataset` -- retain + mint a unique modeSymbol per metric.
- `selectDataset: aSWADatasetOrNil` -- exclusive pick; applies default bindings
  (base version handles the colour axis; Code Map overrides for size/decoration).
- `setDataMode: aSymbol` -- Data-menu entry point (`#none` clears).
- `datasets`, `activeDataset`, `metricForMode: aSymbol`, `metricsByMode`.
- `applyColorMetricSymbol: aSymbolOrNil`, **`intrinsicColorMode`** (default `#class`).

### Coloring
- **`baseColorForNode: aNode`** -- intrinsic tile colour (subclassResponsibility).
- `colorForNode: aNode` -- `intrinsicColorForNode:` then search-dim overlay.
- `intrinsicColorForNode: aNode` -- metric / coverage-provenance / highlight
  compositing core.
- `colorMode` / `colorMode:` / **`colorModeOptions`** -- `{symbol. label}` pairs.

### Coverage provenance + cross-ref
- `showCoverageData: aData weightMode: (#tests|#invocations)` -- green/blue overlay.
- `activateCoverageProvenanceFrom:` / `deactivateCoverageProvenance`.
- `crossReferenceFrom: aPeerView`, `highlightWeights:`, `effectiveWeightOf:`.
- `filterToTestKey:`, `filterToCoveredMethodKey:`, `updateTestFilterForSelection`.
- `coverageProportionsForNode:` -- aggregate green/red/blue/dim bar counts.
- `provenanceListForSelection`, `provenanceListTitle` -- covering-tests pane feed.

### Search / marks
- `searchFor: aStringOrNil`, `isSearchDimmed: aNode`.
- `markedNodes`, `toggleMark: aNode`, `isNodeMarked: aNode`, `flushMarksCache`.
- **`viewKind`** -- machine-readable kind Symbol (override per view).

---

## `SWATreemapMorph` (SWA-Base) -- squarified engine

- `on: aNode` (class) / `setRoot:` -- create rooted on a node.
- **`baseColorForNode:`**, **`labelFor:inWidth:`**, **`balloonStringFor:`**,
  **`drawTileContent:in:on:`**, **`exploreNode:`**, **`formatWeight:`** -- the
  domain hooks a subclass overrides.
- `leafKind` / `leafKind:` -- stop *rendering* at a `#kind` cutoff (rollups still
  built over the full tree).
- `zoomInto:`, `zoomOut`, `selectTileNode:`, `rectForNode:`, `tileAtLocal:`.
- `ensureLayout`, `flushCache`, `flushCacheKeepingSelection` -- cache/relayout
  control. `layoutProgress:` drives a progress bar during build.
- `overlayMorph` / `overlayMorph:`, **`overlayClass`** (view-policy hook the pane
  uses to wire an overlay when morphing structures).

`SWATreemapOverlay` -- `treemapMorph:`, event handlers, **`addMenuItems:for:`**,
**`colorModeOptions`**, **`sizeModeOptions`**, `sizeMenuMorph`, `colorMenuMorph`,
`showMenuFor:event:`.

---

## `SWAPane` (SWA-Base) -- window chrome

- `SWAPane on: aViewMorph` -- wrap a view (builds header + flaps).
- `SWAPane class>>openPanels` / `openPanes` -- live panes (for peer discovery).
- `view`, `treemap` (the view if it supports `keyIndex`), `refresh`.
- `enclosingWindow`, `enforceMinimumWindowWidth`, `defaultWindowBounds` (class).
- **Data menu:** `popUpDataMenu`, `dataMenuMorph`, `setDataMode:`,
  `maskableDatasets`, `popUpMaskBaseMenu` -> `chooseMaskOverlayFor:` ->
  `buildMaskFrom:overlay:`, `crossReferenceAsDataset:`, `peerPanels`.
- **Load / Generate:** `importData`, `loadJsonFile:` (dispatch by marker),
  `loadCoverageJson:name:`, `loadDuplicationJson:name:`, `loadTopicJson:name:`,
  `loadSpaceTallyJson:name:`; `codeMapGeneratorEntries`, `generateCoverageDataset`,
  `generateCallTallyDataset`, `generateSampleTallyDataset`,
  `generateDuplicationDataset`, `generateTopicDataset`.
- **Tally lifecycle:** `startInvocationTally:`, `collectInvocationTally`,
  `abandonInvocationTally`, `openTallyStopWindow`, `cleanupAllWrappers`.
- **Structure (Tree menu):** `popUpTreeMenu`, `setStructureMode:`,
  `restoreStructure:`, `morphViewInto:`, `structureViews`, `structureDatasets`.
- **Marks flap:** `openMarks`/`collapseMarks`, `newMarksPanel`, save/load,
  `openMarksClassDiagram`. **Source flap:** `openSource`/`collapseSource`.
- Class-side generators: `generateSqueakCoverageJson`, `generateSqueakDuplicationJson`,
  `generateSqueakTopicJson`, `openCodeMapAndLoad:`; mark-show
  `showMarkKey:`, `paneMatchingProvenance:`, `spawnFromProvenance:`.
- Preferences (class): `sampleTallyDuration`, `topicK`, `topicSweeps`.

---

## `SWADataset` / `SWADatasetMetric` / `SWAStructure` (SWA-Base + SWA-MessageTally)

### `SWADataset`
- Constructors (class): `coverageFrom:named:`, `duplicationFrom:named:`,
  `spaceTallyFrom:named:`, `spaceTallyFromJsonFile:`, `sampleTallyFrom:named:`,
  `topicFrom:named:`, `peerFrom:named:`, `maskFrom:minus:named:`.
- `kind`, `name`, `modeSymbol`, `source`.
- `metrics` (cached, built by `buildMetrics`), `defaultBindings` (axis -> metric),
  `defaultScale`, `preferredColorMetric`.
- `structures` / `structureForKey:` / `providesStructure` / `structureRoot`,
  `maskStructures`, `isMaskOp`, `operands`.

### `SWADatasetMetric`
- `id`, `label`, `menuLabel`, `axes`, `rollup` (`#sum`/`#max`), `scale`, `modeSymbol`.
- `rawValueForKey:` -- per-key raw value (dispatched by `id` onto the source).
- `valueForNode:` -- keyed value or child rollup; `weightForNode:` -- size axis
  (nil -> 0); `colorForNode:` -- scale value or categorical `colorBlock:`.
- `supportsColor` / `supportsSize` / `supportsLinks`, `isCategorical`,
  `isCoverageProvenance`, `coverageSource`.
- Links: `linksForKey:`, `locForKey:`, `sharedLocForKey:score:partnerKey:`.

### `SWAStructure`
- `key:label:view:rootBlock:` (class) -- a named tree projection.
- `buildViewExtent:` -- instantiate the `viewClass` on the (lazy) `root`.

### Composite sources
- `SWAPeerViewSource` -- `peerView:`, `weightForKey:`, `maxWeight`.
- `SWAMaskSource` -- `left:minus:` (class), `recompute`, `coveredMethodKeys`,
  `weightForKey:`, `overlayDataset`, gated accessors (`invocationCountFor:` etc.).

---

## `SWAMarkSet` (SWA-Base) -- global bookmarks

- `SWAMarkSet default` -- process-wide singleton.
- `add:` / `remove:` / `toggle:` / `removeAll:` / `clear`, `includes:`, `keys`.
- `add:from:` / `toggle:from:` -- with a serializable provenance Dictionary.
- `commentAt:` / `commentAt:put:`, `nodeKindAt:`, `keysOfKind:`, `provenanceAt:`.
- `asJsonString` / `loadFromJsonString:` / `saveToFile:` / `loadFromFile:`.
- `notifyPanes` -- refreshes every open `SWAPane` on mutation.

---

## Instrumentation substrate (SWA-Base + SWA-Coverage + SWA-MessageTally)

### `SWAMethodWrapper` + `SWACapturingLayer`
- `SWAMethodWrapper>>onClass:selector:` -- capture the real method (peels stacked
  wrappers), precompute the name, set eviction.
- `install` / `uninstall` (+ `...NoFlush`), `run:with:in:` (the template hot path),
  **`captureIn:`** (subclass hook), `realMethod`, `evictAt:`.
- `SWAMethodWrapper class`: `uninstallAllStrayWrappers`, `flushSystemCache`,
  `guardedDo:` / `whileUnguardedDo:` / `resetGuard`, `defaultEvictAt` (1000).
- `SWACapturingLayer class`: `withoutCapturing:` / `whileCapturing:` / `isActive` /
  `reset` -- the process-specific reentrancy layer.

### `SWACoverage` (runner)
- `methodsForPackages:` / `methodsForAll` -- select (hard substrate guard +
  exclusions), `instrumentTally` / `collectTally` / `collectCallTree` / `uninstall`.
- `runWithProvenance:panel:`, `runWithProvenanceTestCases:panel:`, `evictAt:`,
  `captureCallTree:`.
- Class-side generation: `generatePackages:tests:toFile:`,
  `generateInstrumenting:tests:toFile:forked:`, `runProvenanceForPackages:tests:then:`,
  `testClassesForPackages:`, `testCasesFromSpecs:`, `fromCoverallsFile:`.

### `SWACoverageData` (result model)
- `recordTest:covers:`, `recordInvocationCount:for:`, `markEvicted:`.
- `isCovered:`, `coveringTestCountFor:`, `invocationCountFor:`, `testsForMethod:`,
  `methodsForTest:` / `methodsForTestOrClass:`, `coveredMethodKeys`,
  `testKeySet` / `testClassNameSet`, `isEvicted:`, `hasInvocationData`, `maxInvocation`.
- `asJsonString` / `writeToFile:` / `loadFromJson:` / `fromFile:` (class).

### `SWATallyWrapper class` (call-tree capture)
- `beginCallTreeFor:`, `recordStackFrom:leaf:`, `finishCallTree`, `resetCallTree`.

---

## `SWACodeNode` family (SWA-Nodes)

- `SWACodeRootNode>>addPackages:` / `removePackages:` -- glob-based selection.
- `SWACodeNode>>totalSize` -- dispatch over `weightMetric`/`sizeMetric`/coverage.
- Metrics: `loc`, `commentLines`, `byteComposition`, `byteWeight`, `changeCount`,
  `avgLoc`, `avgChangeCount`, `methodCount`, `lastAuthor`, `lastChanged`, `source`,
  `sourceString`, `styleClassOrNil`.
- Size binding: `weightMetric:` / `setWeightMetric:`, `sizeMetric:` / `setSizeMetric:`,
  `coverageData:` / `coverageWeightMode:`, `topicData:`, `flushSizeRollups`.
- Openers: `openTreemapLeafKind:`, `openClassTreemap`, `openClassDiagram`, `browse`.
- Graphviz: `classDiagramGraphColorMode:showState:showMethods:`,
  `SWACodeClassNode>>recordLabelColorMode:maxLoc:showState:showMethods:`,
  `recordFieldNodesShowState:showMethods:` (click-map alignment).
- `SWACodeMethodNode class>>classifyBytes:` -- the doc/string/code lexer;
  `byteAnalysisCache` -- weak cache keyed on `CompiledMethod`.

---

## `SWASpaceTally` (SWA-SpaceTally)

- Class: `walk`, `walkDeep`, `walkRoots:`, `explore`, `exploreDeep`, `openTreemap`,
  `generateToFile:` / `generateToFile:compact:`, `loadFromFile:`,
  `tallyInstancesOf:` / `exploreInstancesOf:`, `exploreDiffFrom:`,
  `diffIgnorePatterns` / `addDiffIgnore:`, `formatBytes:`.
- Instance: `roots:`, `maxVisits:`, `trackOtherParents:`, `findDeep:`,
  `ignoreSet:` / `ignoreClasses:`, `walk`, `compact` / `compact:`, `diffFrom:`,
  `writeToFile:`, `classSummary`, `openTreemap`, `openExplorer`,
  `openExplorerSelecting:`, `rootNode`, `totalSize`, `limitWarning`.
- Walk template hooks (for `SWASimSpaceTally`): `checkWalkPreconditions`,
  `captureUniverse`, `newSeenOfSize:`, `seedSeenWithWalkerState`, `makeRootNode`,
  `seedRoots`, `expandNode:`, `findLostObjects`, `defaultRootsForWalk`.
- `SWASpaceTallyNode` -- `rollUp`, `compact:`, `copyFilteredBy:` (diff),
  `asJsonString`, `asBulletListString`, `openParentsGraph`, `openExplorerSelecting:`.
- `SWASpaceTallyClassSummary` -- `fromTree:`, `systemWide`, `fromAnyJsonFile:`,
  `bytesForKey:` / `totalBytesForKey:`, `maxSelf` / `maxTotal`, `writeToFile:`.
- `SWASpaceTallyJsonWriter class>>writeTree:to:` / `stringFor:`;
  `SWASpaceTallyJsonReader class>>readFrom:` / `readJsonObject:`.

---

## `SWASamplingTally` (SWA-MessageTally)

- Class: `recordSelfFor:` / `recordSelfFor:atRate:`, `onPid:duration:`, `open`,
  `stSpyBinary`.
- Instance: `record` (non-blocking detached launch), `recordThenOpen`,
  `whenReadyDo:`, `waitForTrace` / `waitQuietly` / `waitWithProgress`,
  `parseTraceFile:`, `buildTree`, `isReady` / `failed` / `failureReason`,
  `rootNode`, `openFlamegraph` / `openTreemap` / `openExplorer`.
- `SWASamplingTallyNode` -- `childNamed:`, `rollUpTotals`, `methodReference`,
  `crossRefKey`, `browse`, `asCodeGroupingRoot`, `prunedToKeys:` (projections).
- `SWASampleTallyData class>>fromSamplingTree:` -- flatten to `crossRefKey ->
  selfCount` (feeds the `#sampleTally` dataset).

---

## `SWACodeTreemapMorph` (SWA-CodeMap) -- concrete Code Map

Adds on top of `SWATreemapMorph`:
- Colour modes: `colorByKind:`, `colorByLoc:`, `colorByAvgLoc:`, `colorByVersions:`,
  `colorByRecency:`, `colorByAuthor:`, `colorByDuplication:`, `colorByTopic:`,
  byte-composition (`drawByteCompositionBar:in:on:`), topic (`drawTopicBar:in:on:`).
- Coverage: `showCoverageData:weightMode:`, `coverageStatus:`, `enterCoverageColorMode`,
  `enterTallyColorMode`, `coverageMetricLabel`.
- Duplication: `computeDuplicationScores`, `loadDuplicationData:`, `dupMatchesForNode:`,
  `dupScoreForNode:`, `previewDuplicatePairFrom:to:`, `dupDiffTarget:`,
  `provenanceListForSelection` (mode-aware: dup / topic / coverage).
- Topic: `activeTopicData`, `focusTopic:`, `allTopicsList`, `topicProvenanceListFor:`.
- Datasets: `addDataset:`, `selectDataset:` (all axes), `decorationMetric:`,
  `weightMetric:` (intrinsic or dataset-metric), `leafKeySetUnder:`,
  `link:connectsRestriction:`, `overlayClass`.

`SWACodeSimilarity` (SWA-Duplication) -- `shinglesFor:`, `jaccardBetween:and:`,
`duplicatesInPackage:`. `SWADuplicationData` -- `buildFromMethodNodes:...`,
`matchesForKey:`, JSON I/O, class-side `generatePackages:toFile:`.

`SWABitermTopicModel` (SWA-TopicModel) -- `onMethodNodes:`, `onAllMethods`,
`onPackageNamed:`, `k:`, `buildAndRun:`, class-side background/whole-image generators;
`SWATopicData` -- `dominantTopicFor:`, `hueFamilyForTopic:`, `colorForKey:`,
`labelForTopic:`, LLM labeling (`labelTopicsWithLlmEndpoint:model:progress:untilStopped:`).

---

## `SWAChangeParser` (SWA-ChangeMap)

- Class: `openLastDays:` / `openLastDays:onFile:`, `openFrom:to:onFile:`,
  `openRecover:` / `openRecover:against:`, `openInteractiveDiffChangeMap`, `onFile:`.
- Instance: `treeForLastDays:`, `buildTreeTailBytes:rootLabel:`,
  `buildRecoveryTree` / `buildRecoveryTreeAgainst:`, `openTreemapForRoot:`.
- `SWAChangeNode` -- `statusSymbol`, `diffLines`, `diffFromSource`/`diffToSource`,
  `hasDiffBaseline`, `isMissingFromImage`, `dominantAuthor`, `crossRefKey`.

---

## `SWAClassDiagram` (SWA-ClassDiagram)

- Class: `on:`, `openOn:label:`, `openOnPackageNamed:`, `openOnMarks` /
  `openOnMarkSet:`.
- `rootNode:`, `leafKind:` (`#class`/`#state`/`#method`/`#selected`),
  `colorMode:` (`#kind`/`#loc`), `rebuildGraph` / `rebuildGraphKeepView:`,
  `graphNodeClicked:` / `graphFieldClicked:`, `syncToMarkSet:` / `update:` (live).

`GraphvizMorph` (SWA-Graphviz) -- `setDot:`, `onNodeClick:` / `onFieldClick:` /
`onMenuRequest:`, `rectForNode:` / `rectForNode:field:`, `selectionRect:`;
`GraphvizPane` -- scroll/zoom wrapper; `GraphvizJsonParser`/`GraphvizPlainParser` --
`dot -Tjson`/`-Tplain` -> pixel geometry.

---

## Widgets (SWA-Widgets)

- `SWASplitter vertical` / `horizontal`, `resizeAction:` -- draggable resize handle.
- `SWASearchFieldMorph>>panel:` -- header live-search field.
- `SWASelectionPainter class` -- `selectionFrameOn:rect:color:`, `hoverFrameOn:rect:`,
  `ancestorFramesOn:from:rectBlock:`, `tooltipOn:string:at:bounds:`,
  `frame:on:width:color:` -- all stateless canvas drawing.
- `SWAMarksListMorph` -- multi-select list that rewrites Ctrl+click for the Marks panel.
