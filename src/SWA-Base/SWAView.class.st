"
Abstract superclass for SWA tree visualisations (treemap, flamegraph).

Holds the structure (rootNode), navigation chrome link (navPanel), selection
and render cache shared by all views, and -- crucially -- the cross-reference
protocol that links independent views by SWANode>>crossRefKey:

- keyIndex: Dictionary crossRefKey -> node, built in #setRoot:, so peers can
  look us up in O(1).
- highlightWeights: foreign key -> weight map pushed in from another view.
- effectiveWeights: that map rolled up the tree (max of self + descendants) so
  ancestor tiles (class/package) light up when any descendant matched.

Subclasses must implement: setRoot: (call rebuildKeyIndex), children-walking via
the node tree, baseColorForNode:, and the actual rendering. They provide their
own layout-specific ivars.
"
Class {
	#name : #SWAView,
	#superclass : #Morph,
	#instVars : [
		'rootNode',
		'keyIndex',
		'highlightWeights',
		'effectiveWeights',
		'cachedForm',
		'history',
		'navPanel',
		'selectedNode',
		'highlightStyle',
		'coverageKind',
		'coverageData',
		'testKeys',
		'testFilterKeys',
		'coveringTestFilter',
		'secondarySelection',
		'datasets',
		'metricsByMode',
		'sizeMetric',
		'decorationMetric',
		'activeDataset',
		'searchQuery',
		'searchMatchSet'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:54'
}
SWAView >> aboutToStyle: aStyler [
	"Shout styling hook (this morph is the source pane's model). Give the styler the
	selected node's class context so ivars/selectors highlight correctly, then allow
	styling to proceed. The class is taken from #styleClassOrNil when the node
	supplies it (code/treemap nodes), else from #methodReference (flamegraph frames).
	Subclasses may override to suppress styling (e.g. while showing a diff)."
	| cls |
	cls := self styleClassForSelection.
	(cls notNil and: [aStyler respondsTo: #classOrMetaClass:])
		ifTrue: [aStyler classOrMetaClass: cls].
	^ true
]

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAView >> aboutToStyle: aStyler requestor: anObject [
	"2-arg Shout hook the styler actually sends; delegates to the 1-arg
	#aboutToStyle:, mirroring Model>>aboutToStyle:requestor:. A SWAView is the
	source pane's Shout model (see SWAPane>>newSourceMorph), so every view
	needs this."
	^ self aboutToStyle: aStyler
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWAView >> activateCoverageProvenanceFrom: aSWACoverageData [
	"Wire up the test<->method PROVENANCE relation from aSWACoverageData -- WITHOUT the
	legacy green highlight overlay. This gives us the blue test tint (#isTestKey:) and
	the click filters (select a test -> its covered methods; select a covered method ->
	its covering tests), while the BASE tile color still comes from the active dataset
	METRIC. So coverage-as-a-dataset keeps its special provenance behavior.

	Sets #coverageData + #testKeys only; leaves #highlightWeights nil (the metric owns
	color) and does NOT push weights onto the root (size stays intrinsic). Pass the
	same data your active coverage metric wraps."
	aSWACoverageData ifNil: [^ self deactivateCoverageProvenance].
	coverageData := aSWACoverageData.
	testKeys := aSWACoverageData testKeySet , aSWACoverageData testClassNameSet.
	testFilterKeys := nil.
	coveringTestFilter := nil.
	self updateTestFilterForSelection.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> activeDataset [
	"The dataset last picked from the top-level Data selector (or nil). Used to tick
	the Data menu."
	^ activeDataset
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> addDataset: aSWADataset [
	"Retain a named dataset and register ITS METRICS. Each metric gets a UNIQUE minted
	symbol so it becomes its own Color/Size menu entry, tagged with the dataset name --
	and loading the same kind twice yields distinct, coexisting entries you switch
	between with no reload. Answers the dataset. Does NOT change the current color/size
	mode."
	| n base |
	n := (self datasets count: [:d | d kind == aSWADataset kind]) + 1.
	aSWADataset modeSymbol: (aSWADataset kind, '_', n printString) asSymbol.
	base := aSWADataset kind, '_', n printString.
	self datasets addLast: aSWADataset.
	aSWADataset metrics do: [:metric | | sym |
		sym := (base, '_', metric id) asSymbol.
		metric modeSymbol: sym.
		self metricsByMode at: sym put: metric].
	^ aSWADataset
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:57'
}
SWAView >> applyColorMetricSymbol: aSymbolOrNil [
	"Bind the COLOR axis to a minted dataset-metric symbol, or (nil) restore the
	view's intrinsic default color mode. The one axis MOST SWA views support. Views
	without a switchable color mode (e.g. the flamegraph, which colors intrinsically
	per frame) simply can't be a color TARGET -- they no-op here but can still be a
	cross-ref SOURCE (peer) for others."
	(self respondsTo: #colorMode:) ifFalse: [^ self].
	aSymbolOrNil
		ifNotNil: [self colorMode: aSymbolOrNil]
		ifNil: [self colorMode: self intrinsicColorMode]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> baseColorForNode: aNode [
	"Intrinsic fill color for a node, ignoring cross-ref highlight. Subclasses override."
	^ self subclassResponsibility
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:42'
}
SWAView >> bumpKey: aCoverageClass dim: aBoolean [
	"The proportions-Dictionary key for a leaf of the given coverage class
	(#green/#red/#blue), choosing the dimmed variant when aBoolean. nil for #none."
	aCoverageClass == #green ifTrue: [^ aBoolean ifTrue: [#greenDim] ifFalse: [#green]].
	aCoverageClass == #red ifTrue: [^ aBoolean ifTrue: [#redDim] ifFalse: [#red]].
	aCoverageClass == #blue ifTrue: [^ aBoolean ifTrue: [#blueDim] ifFalse: [#blue]].
	^ nil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> clearCrossReference [
	"Remove any active cross-reference highlight."
	self highlightWeights: nil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> clearTestFilters [
	"Drop both the green (test-selected) and blue (method-selected) filters and
	restore the full coverage overlay."
	coveringTestFilter := nil.
	self filterToTestKey: nil
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:04'
}
SWAView >> colorForNode: aNode [
	"Tile color, with the name-SEARCH overlay applied last: compute the intrinsic color
	(metric / coverage / highlight compositing -- see #intrinsicColorForNode:) then, if
	a name-search is running and aNode is neither a match nor an ancestor of one, DIM it
	toward near-black so the matching tiles (and the path down to them) stand out."
	| base |
	base := self intrinsicColorForNode: aNode.
	(self isSearchDimmed: aNode)
		ifTrue: [^ base alphaMixed: 0.16 with: (Color gray: 0.1)].
	^ base
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMenuMorph [
	"Build the Color (instant recolor) menu from #colorModeOptions, ticking the
	current #colorMode. Generic mechanism shared by every SWAView: the context menu
	and the header 'Color' button. Answers nil when the view offers no color options.
	Selecting an item sends #colorMode: to the view."
	| opts current menu |
	opts := self colorModeOptions.
	opts isEmpty ifTrue: [^ nil].
	current := self colorMode.
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode
			ifTrue: ['* ', pair second]
			ifFalse: ['   ', pair second].
		menu add: label selector: #colorMode: argument: mode].
	^ menu
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMode [
	"The active color mode symbol (from #colorModeOptions), or nil if the view has
	no switchable coloring. Subclasses that recolor override this with an ivar."
	^ nil
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMode: aSymbol [
	"Set the active color mode and recolor. Default: no-op (view has no switchable
	coloring). Subclasses override to store the mode and re-render."
	^ self
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorModeOptions [
	"{ colorModeSymbol. menuLabel } pairs offered by the Color menu. Default: none
	(no Color menu). Subclasses that support recoloring override this."
	^ #()
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:39'
}
SWAView >> coverageClassOfNode: aNode [
	"Classify a single (leaf) node under the active provenance overlay, mirroring the
	priority in #colorForNode::
	  #blue  -- an executed test method / TestCase class,
	  #red   -- a method evicted during the run,
	  #green -- a covered method,
	  #none  -- not covered / not relevant.
	Keyed by crossRefKey against the loaded SWACoverageData (node-identity-independent),
	so it works while walking descendants. Used to build the proportional
	green/red/blue bar on aggregate tiles."
	| key |
	key := aNode crossRefKey.
	(self isTestKey: key) ifTrue: [^ #blue].
	coverageData ifNil: [^ #none].
	(coverageData isEvicted: key) ifTrue: [^ #red].
	(coverageData isCovered: key) ifTrue: [^ #green].
	^ #none
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> coverageColorForWeight: aWeight base: baseColor [
	"Coverage ramp. For boolean coverage every matched weight is 1, so all covered
	tiles are solid green and everything unmatched is dimmed by #colorForNode:.
	For invocation tallies, busier methods go from pale to saturated green on a log
	scale (hue 120), so hot paths read darker-green."
	| maxW frac |
	maxW := self highlightMaxWeight.
	(aWeight isNil or: [aWeight <= 0]) ifTrue: [^ Color gray: 0.2].
	maxW <= 1 ifTrue: [^ Color h: 120.0 s: 0.75 v: 0.85].   "boolean: flat green"
	frac := ((aWeight + 1) ln) / ((maxW + 1) ln).
	frac := (frac max: 0.0) min: 1.0.
	"Pale green (low) -> vivid green (hot): raise saturation + drop brightness."
	^ Color h: 120.0 s: (0.35 + (0.55 * frac)) v: (0.95 - (0.2 * frac))
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:47'
}
SWAView >> coverageData [
	"The SWACoverageData behind a provenance overlay (test<->method relation), or
	nil. Lets the meta line show a method's covering tests."
	^ coverageData
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> coverageKind [
	"#boolean or #tally when a coverage overlay is active, else nil."
	^ coverageKind
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:42'
}
SWAView >> coverageProportionsForNode: aNode [
	"For an AGGREGATE (non-leaf) tile under a loaded SWACoverageData overlay, answer
	the leaf-method counts per coverage class, split into BRIGHT (matching the active
	selection filter) and DIM (filtered out), as a Dictionary:
	  #green #greenDim #red #redDim #blue #blueDim #total.
	'total' is ALL leaf descendants, so uncovered methods leave empty (background)
	space in the bar. With no filter active everything is bright (the *Dim entries
	are 0). Answers nil for leaf tiles or when no coverage overlay is active (let
	#colorForNode: paint solid)."
	| counts |
	(coverageData isNil and: [testKeys isNil]) ifTrue: [^ nil].
	aNode children isEmpty ifTrue: [^ nil].
	counts := Dictionary new.
	#(green greenDim red redDim blue blueDim total) do: [:k | counts at: k put: 0].
	self leavesUnder: aNode do: [:leaf | | class dim |
		counts at: #total put: (counts at: #total) + 1.
		class := self coverageClassOfNode: leaf.
		class ~~ #none ifTrue: [
			dim := self isFilteredOut: leaf.
			(self bumpKey: class dim: dim) ifNotNil: [:k | counts at: k put: (counts at: k) + 1]]].
	^ counts
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> coverageValueForNode: aNode [
	"The rolled-up coverage/tally value for aNode (max over its subtree), or nil if
	no overlay is active or nothing in its subtree matched. For a method node this
	is its own value; for a class/package node it is the hottest descendant's."
	(highlightStyle == #coverage and: [effectiveWeights notNil]) ifFalse: [^ nil].
	^ effectiveWeights at: aNode ifAbsent: [nil]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:41'
}
SWAView >> coveringTestFilter [
	"The set of test/TestCase crossRefKeys currently highlighted because a covered
	method is selected (the tests that covered it), or nil for none."
	^ coveringTestFilter
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> crossReferenceFrom: aPeerView [
	"Highlight our tiles that also appear in aPeerView, weighting each by the peer
	node's totalSize (samples / bytes / loc). Pass nil to clear."
	| weights |
	aPeerView ifNil: [^ self highlightWeights: nil].
	weights := Dictionary new.
	aPeerView keyIndex keysAndValuesDo: [:k :node |
		weights at: k put: node totalSize].
	self highlightWeights: weights
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> datasetForDataMode: aSymbol [
	"Resolve a Data-menu symbol to its dataset; #none clears the active dataset."
	aSymbol == #none ifTrue: [^ nil].
	^ self datasets detect: [:d | d modeSymbol == aSymbol] ifNone: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> datasets [
	"The retained, named analysis overlays loaded into this view (SWADataset), in
	load order. Shared across all SWA views so any tool -- Code Map, Space Tally,
	flamegraph -- can host datasets and cross-reference peers uniformly. Lazily
	initialized."
	^ datasets ifNil: [datasets := OrderedCollection new]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWAView >> deactivateCoverageProvenance [
	"Drop the coverage provenance relation (blue tests + click filters). Used when the
	active color leaves a coverage-provenance metric."
	coverageData := nil.
	testKeys := nil.
	testFilterKeys := nil.
	coveringTestFilter := nil.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> effectiveWeightOf: aNode [
	"Memoised rolled-up highlight weight: the max of aNode's own direct match and
	its children's effective weights. Answers nil if nothing in the subtree matched.
	When a test filter is active (a test/TestCase is selected), a method only counts
	as a direct match if it is one of that test's covered methods."
	| key w |
	effectiveWeights at: aNode ifPresent: [:cached | ^ cached ].
	w := nil.
	key := aNode crossRefKey.
	(key notNil
		and: [highlightWeights includesKey: key]
		and: [testFilterKeys isNil or: [testFilterKeys includes: key]])
		ifTrue: [w := highlightWeights at: key].
	aNode children do: [:c | | cw |
		cw := self effectiveWeightOf: c.
		cw ifNotNil: [w := w isNil ifTrue: [cw] ifFalse: [w max: cw]]].
	effectiveWeights at: aNode put: w.
	^ w
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:51'
}
SWAView >> filterToCoveredMethodKey: aMethodKey [
	"Restrict the blue test highlight to just the tests (and their TestCase classes)
	that covered the given application method. Pass nil to remove the filter.
	No-op unless a SWACoverageData provenance overlay is active."
	coverageData ifNil: [^ self].
	coveringTestFilter := aMethodKey
		ifNil: [nil]
		ifNotNil: [:key | coverageData testKeysForMethod: key].
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:51'
}
SWAView >> filterToTestKey: aTestOrClassKey [
	"Restrict the green coverage highlight to just the methods covered by the given
	test method or TestCase class. Pass nil to remove the filter (show all covered
	methods again). No-op unless a SWACoverageData provenance overlay is active."
	coverageData ifNil: [^ self].
	aTestOrClassKey
		ifNil: [testFilterKeys := nil]
		ifNotNil: [:key |
			testFilterKeys := (coverageData methodsForTestOrClass: key) asSet].
	self rebuildEffectiveWeights.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAView >> handlesKeyboard: evt [
	"Accept keystrokes so the Ctrl+F search shortcut works while the map has focus
	(the view grabs keyboard focus on mouseDown -- see #mouseDown: in subclasses /
	#takeKeyboardFocusFrom:)."
	^ true
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> heatColorForWeight: aWeight base: baseColor [
	"Map aWeight onto a log-scaled cold->hot ramp (blue -> red). Log scale spreads
	the long tail of small values."
	| maxW frac |
	maxW := self highlightMaxWeight.
	(aWeight isNil or: [aWeight <= 0 or: [maxW <= 0]])
		ifTrue: [^ Color h: 220.0 s: 0.7 v: 0.85].
	frac := ((aWeight + 1) ln) / ((maxW + 1) ln).
	frac := (frac max: 0.0) min: 1.0.
	^ Color h: (220.0 * (1.0 - frac)) s: 0.85 v: 0.95
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightColorForWeight: aWeight base: baseColor [
	"Dispatch a matched tile's colour on the active highlight style."
	^ self highlightStyle == #coverage
		ifTrue: [self coverageColorForWeight: aWeight base: baseColor]
		ifFalse: [self heatColorForWeight: aWeight base: baseColor]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightMaxWeight [
	"Largest weight in the active cross-reference map (0 if none)."
	highlightWeights ifNil: [^ 0].
	highlightWeights isEmpty ifTrue: [^ 0].
	^ highlightWeights values inject: 0 into: [:mx :w | mx max: w]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightStyle [
	"How a matched tile is coloured: #heat (cross-ref blue->red, default) or
	#coverage (covered green -> uncovered red, for SWACoverage data)."
	^ highlightStyle ifNil: [#heat]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightStyle: aSymbol [
	"#heat or #coverage. Redraws."
	highlightStyle := aSymbol.
	self flushCache.
	self changed
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightWeights [
	"Dictionary crossRefKey -> Number pushed in from a peer view, or nil when no
	cross-reference is active. Drives the cross-ref heat colouring."
	^ highlightWeights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightWeights: aDictionaryOrNil [
	"Set (or clear, with nil) the foreign weight map, roll it up the tree (max of
	self + descendants) so ancestor tiles also light up, and redraw."
	highlightWeights := aDictionaryOrNil.
	self rebuildEffectiveWeights.
	self flushCache.
	self changed
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> intrinsicColorForNode: aNode [
	"Tile color IGNORING the name-search overlay (see #colorForNode:, which dims this
	result for nodes filtered out by an active search). LAYERED-DATASETS: when the
	active color mode is a dataset METRIC, that metric owns the BASE tint. But a
	COVERAGE-provenance metric ALSO keeps the special behavior: executed tests /
	TestCase classes are tinted BLUE, and when a selection filter is active (select a
	test -> its covered methods; select a covered method -> its covering tests)
	non-matching tiles DIM. So we layer blue + filter-dim on top of the metric's color.

	Without a metric active, this falls back to the legacy provenance/highlight
	compositing (blue tests, red eviction, gray aggregate base, cross-ref heat).

	Metric dispatch needs BOTH #metricForMode: and a switchable #colorMode (a view
	without a colorMode -- e.g. the flamegraph -- colors intrinsically and can't be a
	metric color TARGET, so it skips straight to its own baseColorForNode:)."
	| metric base w red |
	((self respondsTo: #metricForMode:) and: [self respondsTo: #colorMode]) ifTrue: [
		metric := self metricForMode: self colorMode].
	metric ifNotNil: [
		"Blue tint for executed test / TestCase tiles (needs provenance wired up)."
		(metric isCoverageProvenance and: [self isTestKey: aNode crossRefKey])
			ifTrue: [^ self testColorForNode: aNode].
		"Base tint from the metric; dim it if an active provenance filter excludes it."
		base := (metric colorForNode: aNode) ifNil: [Color gray: 0.22].
		(metric isCoverageProvenance and: [aNode isLeaf and: [self isFilteredOut: aNode]])
			ifTrue: [^ base alphaMixed: 0.25 with: (Color gray: 0.12)].
		^ base].
	(self isTestKey: aNode crossRefKey) ifTrue: [^ self testColorForNode: aNode].
	(coverageData notNil and: [coverageData isEvicted: aNode crossRefKey]) ifTrue: [
		red := Color h: 0.0 s: 0.8 v: 0.85.
		^ (self isFilteredOut: aNode)
			ifTrue: [red alphaMixed: 0.25 with: (Color gray: 0.12)]
			ifFalse: [red]].
	(coverageData notNil and: [aNode children notEmpty])
		ifTrue: [^ Color gray: 0.25].   "aggregate base under coverage overlay; bar drawn on top"
	highlightWeights ifNil: [^ self baseColorForNode: aNode].
	base := self baseColorForNode: aNode.
	w := effectiveWeights ifNil: [nil] ifNotNil: [effectiveWeights at: aNode ifAbsent: [nil]].
	(w notNil and: [aNode isLeaf and: [self isFilteredOut: aNode]]) ifTrue: [w := nil].
	w ifNil: [^ (base alphaMixed: 0.25 with: (Color gray: 0.12))].
	^ self highlightColorForWeight: w base: base
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> intrinsicColorMode [
	"The view's own default color mode, restored when a dataset color binding is
	cleared. Subclasses override with their native default (#codeKind, #class, ...)."
	^ #class
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:37'
}
SWAView >> isFilteredOut: aNode [
	"True if an active provenance filter excludes aNode (so its tile should dim).
	 - test selected (testFilterKeys): a method not among the selected test's
	   covered methods is out;
	 - covered method selected (coveringTestFilter): only the selected method itself
	   stays bright;
	 - no filter: nothing is filtered out."
	testFilterKeys notNil ifTrue: [
		^ (testFilterKeys includes: aNode crossRefKey) not].
	coveringTestFilter notNil ifTrue: [
		^ aNode crossRefKey ~= (selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey])].
	^ false
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> isSearchDimmed: aNode [
	"True when a name-search is active and aNode is neither a match nor an ancestor of
	a match, so its tile should be dimmed out. Answers false when no search is running
	(the common case), so callers can guard cheaply."
	searchQuery ifNil: [^ false].
	^ (searchMatchSet notNil and: [searchMatchSet includes: aNode]) not
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> isTestKey: aKey [
	"True if aKey identifies an executed test method or TestCase class under the
	active provenance coverage overlay (drives blue tinting)."
	(testKeys isNil or: [aKey isNil]) ifTrue: [^ false].
	^ testKeys includes: aKey
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> keyIndex [
	"Dictionary crossRefKey -> node for this view, built in #setRoot: (lazily on
	first access if missing). Lets other panels cross-reference us in O(1)."
	keyIndex ifNil: [self rebuildKeyIndex].
	^ keyIndex
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAView >> keyStroke: evt [
	"Ctrl+F (Cmd+F on Mac) focuses the header search field; everything else is ignored
	(the map has no other typed input). Ctrl+F may arrive either as the letter $f with
	the control/command modifier set, or -- on some platforms -- as control-code 6."
	| isFindKey |
	isFindKey := (evt keyValue = 6)
		or: [(evt commandKeyPressed or: [evt controlKeyPressed])
			and: [evt keyCharacter asLowercase = $f]].
	isFindKey ifTrue: [
		navPanel ifNotNil: [navPanel focusSearchField: evt].
		^ self].
	^ super keyStroke: evt
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:39'
}
SWAView >> leavesUnder: aNode do: aBlock [
	"Evaluate aBlock with every LEAF node in aNode's subtree (depth-first). A leaf is
	a node with no children (a method node on the code map)."
	aNode children isEmpty
		ifTrue: [aBlock value: aNode]
		ifFalse: [aNode children do: [:c | self leavesUnder: c do: aBlock]]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> metricForMode: aSymbol [
	"The dataset METRIC a minted color/size symbol refers to, or nil if aSymbol is an
	intrinsic mode (#loc, #class, ...)."
	^ self metricsByMode at: aSymbol ifAbsent: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> metricsByMode [
	"Map of minted menu symbol (e.g. #coverage_1_call) -> SWADatasetMetric. One entry
	per metric of every loaded dataset; the symbol-based color/size machinery
	dispatches through this."
	^ metricsByMode ifNil: [metricsByMode := Dictionary new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel [
	^ navPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAView >> navPanel: aSWAPane [
	"The chrome panel that owns my breadcrumb/selection/meta labels + source pane."
	navPanel := aSWAPane
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> popUpColorMenu [
	"Pop up the Color menu standalone (header 'Color' button). No-op if the view
	offers no color options."
	| menu |
	menu := self colorMenuMorph.
	menu ifNotNil: [menu popUpInWorld: self world]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> provenanceListForSelection [
	"For the covering-tests side pane. Returns an Array of associations
	displayLabel -> crossRefKey describing the current selection's provenance under
	a SWACoverageData overlay:
	 - a covered application method -> the tests (and TestCase classes) that cover it;
	 - a test method / TestCase class -> the methods it covers;
	 - otherwise -> empty.
	The key lets the panel navigate the treemap to the clicked entry."
	| key |
	coverageData ifNil: [^ #()].
	selectedNode ifNil: [^ #()].
	key := selectedNode crossRefKey.
	key ifNil: [^ #()].
	(self isTestKey: key) ifTrue: [
		^ (coverageData methodsForTestOrClass: key) asSortedCollection asArray
			collect: [:m | m -> m]].
	(selectedNode kind == #method and: [coverageData isCovered: key]) ifTrue: [
		| tests classes entries |
		tests := coverageData testsForMethod: key.
		classes := coverageData testClassesForMethod: key.
		entries := OrderedCollection new.
		classes asSortedCollection do: [:c | entries add: ('[', c, ']') -> c].
		tests asSortedCollection do: [:t | entries add: ('   ', t) -> t].
		^ entries asArray].
	^ #()
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> provenanceListTitle [
	"A short heading for the covering-tests side pane describing what it lists for
	the current selection."
	| key |
	(coverageData isNil or: [selectedNode isNil]) ifTrue: [^ 'Coverage'].
	key := selectedNode crossRefKey.
	key ifNil: [^ 'Coverage'].
	(self isTestKey: key) ifTrue: [
		^ 'Covers ', (coverageData methodsForTestOrClass: key) size printString, ' methods'].
	(selectedNode kind == #method and: [coverageData isCovered: key]) ifTrue: [
		^ 'Covered by ', (coverageData coveringTestCountFor: key) printString, ' tests'].
	^ 'Coverage'
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rebuildEffectiveWeights [
	"Roll the foreign highlightWeights up the tree so a class/package tile lights
	up when any contained method matched. Each node's effective weight is the MAX
	of its own match and its children's effective weights."
	effectiveWeights := IdentityDictionary new.
	(highlightWeights isNil or: [rootNode isNil]) ifTrue: [^ effectiveWeights].
	self effectiveWeightOf: rootNode.
	^ effectiveWeights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rebuildKeyIndex [
	"(Re)build the crossRefKey -> node index by walking the whole tree. On key
	collisions keep the largest-totalSize node so lookups land on the most
	significant tile/frame."
	keyIndex := Dictionary new.
	rootNode ifNil: [^ keyIndex].
	rootNode withAllChildrenDo: [:n | | k existing |
		k := n crossRefKey.
		k ifNotNil: [
			existing := keyIndex at: k ifAbsent: [nil].
			(existing isNil or: [n totalSize > existing totalSize])
				ifTrue: [keyIndex at: k put: n]]].
	^ keyIndex
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> rebuildSearchMatches [
	"Build the IdentitySet of nodes to keep BRIGHT for the current searchQuery: every
	node whose #name contains the query (case-insensitive), plus all of that node's
	ancestors up to the root, so a container tile stays lit when anything inside it
	matches and the path down to a leaf hit is never dimmed."
	searchMatchSet := IdentitySet new.
	(searchQuery isNil or: [rootNode isNil]) ifTrue: [^ searchMatchSet].
	rootNode withAllChildrenDo: [:n | | nm |
		nm := n name ifNil: [''].
		(nm asLowercase includesSubstring: searchQuery) ifTrue: [
			| a |
			a := n.
			[a notNil and: [(searchMatchSet includes: a) not]] whileTrue: [
				searchMatchSet add: a.
				a := a parent]]].
	^ searchMatchSet
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rootNode [
	^ rootNode
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> searchFor: aStringOrNil [
	"Set the name-search filter. A node MATCHES when aString (case-insensitive) is a
	substring of its #name; matching nodes AND all their ancestors stay bright, every
	other tile dims (see #searchMatches:). Empty/nil clears the filter. Recomputes the
	kept-node set, flushes the render cache and redraws."
	| q |
	q := (aStringOrNil ifNil: ['']) asString withBlanksTrimmed.
	q isEmpty
		ifTrue: [searchQuery := nil. searchMatchSet := nil]
		ifFalse: [searchQuery := q asLowercase. self rebuildSearchMatches].
	self flushCache.
	self changed
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> searchQuery [
	"The active lowercase name-search string, or nil when no search is running."
	^ searchQuery
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWAView >> secondarySelection [
	"A SECONDARY selection node (or nil), distinct from the primary #selectedNode.
	Drawn with a RED border (vs the primary's white). General mechanism: a view can
	use it for any 'compare against' / 'related-to' relationship -- the duplication
	view uses it for the near-duplicate currently being diffed against the primary
	selection."
	^ secondarySelection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWAView >> secondarySelection: aNodeOrNil [
	"Set the secondary selection and refresh chrome so its red border and any
	dependent panes update."
	secondarySelection := aNodeOrNil.
	self refreshChrome
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> selectDataset: aSWADatasetOrNil [
	"Top-level Data pick (exclusive): make aSWADataset the active data source and bind
	the COLOR axis to its fitting default color metric (or restore intrinsic color when
	nil). This base version handles only color -- the axis every SWA view has. Tools
	with size/decoration axes (the Code Map) override to also apply those, calling
	super for the color + activeDataset bookkeeping."
	| colorMetric |
	activeDataset := aSWADatasetOrNil.
	aSWADatasetOrNil isNil ifTrue: [^ self applyColorMetricSymbol: nil].
	colorMetric := aSWADatasetOrNil defaultBindings at: #color ifAbsent: [nil].
	self applyColorMetricSymbol: (colorMetric ifNotNil: [:m | m modeSymbol])
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> selectNodeForKey: aCrossRefKey [
	"Navigate to and select the node with the given crossRefKey (from the covering-
	tests pane). No-op if not found. Zooms out to a node that contains it if it is
	not under the current focus, so the tile becomes visible."
	| node |
	aCrossRefKey ifNil: [^ self].
	node := self keyIndex at: aCrossRefKey ifAbsent: [^ self].
	self selectedNode: node
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> selectedNode [
	"The currently selected node (single-click), or nil."
	^ selectedNode
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> setDataMode: aSymbol [
	"Data-menu entry point: pick the active data source by its symbol (#none clears),
	applying its fitting defaults across the axes."
	self selectDataset: (self datasetForDataMode: aSymbol)
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:40'
}
SWAView >> showCoverage: aCoverage [
	"Overlay a SWACoverage result (its 'Class>>selector' -> value map) using the
	green coverage ramp, with the usual max class-rollup. Pass nil to clear.
	This overlay has no test<->method provenance, so no blue test tinting."
	testKeys := nil. testFilterKeys := nil. coveringTestFilter := nil.
	aCoverage ifNil: [coverageKind := nil. coverageData := nil. ^ self highlightWeights: nil].
	highlightStyle := #coverage.
	coverageData := nil.
	coverageKind := aCoverage kind.
	self highlightWeights: aCoverage resultMap
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:02'
}
SWAView >> showCoverageData: aCoverageData [
	"Overlay a SWACoverageData graded by COVERING-TEST count (the default metric).
	See #showCoverageData:weightMode: for the invocation-count metric."
	^ self showCoverageData: aCoverageData weightMode: #tests
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:22'
}
SWAView >> showCoverageData: aCoverageData weightMode: aWeightMode [
	"Overlay a SWACoverageData: covered application methods are tinted green graded
	by the chosen metric -- #tests (covering-test count) or #invocations (raw call
	count) -- and executed test methods / TestCase classes are tinted BLUE. So the
	overlay VALUES (tint + the coverage-value shown in the header/details) match the
	tile SIZING when the view is coverage-weighted. #invocations silently falls back
	to test count if the data carries no invocation counts. Pass nil data to clear.

	Also pushes the data onto the ROOT NODE (when it understands #coverageData:), so
	the #invocations/#tests SIZE metrics actually have weights to lay out -- without
	this the 'Load' path tinted tiles but every coverage weight rolled up to 0,
	collapsing those size metrics to an empty map."
	| useInvocations |
	testFilterKeys := nil. coveringTestFilter := nil.
	aCoverageData ifNil: [
		coverageData := nil. coverageKind := nil. testKeys := nil.
		(rootNode respondsTo: #coverageData:) ifTrue: [rootNode coverageData: nil].
		^ self highlightWeights: nil].
	coverageData := aCoverageData.
	coverageKind := #tally.   "graded green by the chosen count"
	highlightStyle := #coverage.
	testKeys := aCoverageData testKeySet , aCoverageData testClassNameSet.
	(rootNode respondsTo: #coverageData:) ifTrue: [
		rootNode coverageData: aCoverageData.
		(rootNode respondsTo: #coverageWeightMode:) ifTrue: [
			rootNode coverageWeightMode: aWeightMode]].
	useInvocations := aWeightMode == #invocations and: [aCoverageData hasInvocationData].
	self highlightWeights: (useInvocations
		ifTrue: [aCoverageData invocationMap]
		ifFalse: [aCoverageData resultMap])
]

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:54'
}
SWAView >> styleClassForSelection [
	"The class/metaclass context for Shout styling of the selected node's source,
	or nil. Prefers #styleClassOrNil (code + treemap nodes); falls back to the first
	element of #methodReference (st-spy flamegraph frames)."
	selectedNode ifNil: [^ nil].
	(selectedNode respondsTo: #styleClassOrNil)
		ifTrue: [^ selectedNode styleClassOrNil].
	(selectedNode respondsTo: #methodReference)
		ifTrue: [^ selectedNode methodReference ifNotNil: [:ref | ref first]].
	^ nil
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAView >> takeKeyboardFocusFrom: evt [
	"Grab keyboard focus so the Ctrl+F search shortcut reaches this view. Called from
	subclass #mouseDown: (clicking the map is a natural point to take focus)."
	evt hand newKeyboardFocus: self
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> testColorForNode: aNode [
	"Blue tint for an executed test method or TestCase class tile.
	 - With a test selected (testFilterKeys set): the selected test/class is bright,
	   the others dimmed.
	 - With a covered application method selected (coveringTestFilter set): tests
	   that covered it are bright, the others dimmed.
	 - Otherwise: plain blue."
	| key selectedKey |
	key := aNode crossRefKey.
	coveringTestFilter notNil ifTrue: [
		^ (coveringTestFilter includes: key)
			ifTrue: [Color h: 210.0 s: 0.85 v: 0.95]
			ifFalse: [Color h: 210.0 s: 0.35 v: 0.45]].
	selectedKey := selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey].
	(testFilterKeys notNil and: [key = selectedKey])
		ifTrue: [^ Color h: 210.0 s: 0.85 v: 0.95].
	testFilterKeys notNil ifTrue: [^ Color h: 210.0 s: 0.35 v: 0.45].
	^ Color h: 210.0 s: 0.6 v: 0.85
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> testFilterKeys [
	"The set of method crossRefKeys the green highlight is currently restricted to
	(because a test/TestCase is selected), or nil for 'show all covered methods'."
	^ testFilterKeys
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> updateTestFilterForSelection [
	"Called after the selection changes (no-op without a provenance overlay):
	 - select a test / TestCase -> green-filter to the methods it covers;
	 - select a covered application method -> blue-filter to the tests that
	   covered it (and their TestCase classes);
	 - select anything else -> drop both filters."
	| key |
	coverageData ifNil: [^ self].
	key := selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey].
	(self isTestKey: key) ifTrue: [
		coveringTestFilter := nil.
		^ self filterToTestKey: key].
	(key notNil and: [selectedNode kind == #method and: [coverageData isCovered: key]]) ifTrue: [
		testFilterKeys := nil.
		^ self filterToCoveredMethodKey: key].
	(testFilterKeys notNil or: [coveringTestFilter notNil]) ifTrue: [
		self clearTestFilters]
]
