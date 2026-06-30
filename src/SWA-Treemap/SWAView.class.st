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
		'secondarySelection'
	],
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:00'
}
SWAView >> colorForNode: aNode [
	"Subclass's #baseColorForNode: with any active highlight on top. A tile lights
	up when it -- or any descendant -- matched; its weight is the MAX matching
	weight in its subtree, so a class tile is as hot as its hottest matching method.
	Non-matching tiles are dimmed. The matched-tile ramp depends on #highlightStyle
	(#heat for cross-ref, #coverage for SWACoverage data).
	Under a provenance overlay, executed tests / TestCase classes are tinted BLUE.
	A method that was EVICTED during the run is tinted RED, taking priority over the
	green coverage ramp. Both red and green leaf tiles DIM when an active selection
	filter excludes them (#isFilteredOut:): selecting a test keeps its covered
	methods bright; selecting a method keeps only that method bright.
	Under a loaded coverage overlay, AGGREGATE (non-leaf) tiles get a neutral GRAY
	base -- the proportional green/red/blue/gray bar (#drawTileContent:in:on:) is
	painted on top, so the base only shows if drawing the bar is skipped."
	| base w red |
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
	"A leaf excluded by the active selection filter dims even if it has a weight."
	(w notNil and: [aNode isLeaf and: [self isFilteredOut: aNode]]) ifTrue: [w := nil].
	w ifNil: [^ (base alphaMixed: 0.25 with: (Color gray: 0.12))].
	^ self highlightColorForWeight: w base: base
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel [
	^ navPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel: aSWANavPanel [
	"The chrome panel that owns my breadcrumb/selection/meta labels + source pane."
	navPanel := aSWANavPanel
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rootNode [
	^ rootNode
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
