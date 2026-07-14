"
A squarified treemap of a SWACodeNode tree (Package -> Class -> Category -> Method). Tiles are sized by LOC. Overrides the SpaceTally morph's byte-oriented labels/balloon/coloring with code-oriented ones (LOC counts, color by node kind). Nodes are duck-typed to the treemap protocol.
"
Class {
	#name : #SWACodeTreemapMorph,
	#superclass : #SWATreemapMorph,
	#instVars : [
		'coverageStatus',
		'dupScores',
		'dupSimilarity',
		'dupMinLoc',
		'dupLoaded',
		'dupDiffFrom'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 13:00'
}
SWACodeTreemapMorph >> aboutToStyle: aStyler [
	"Suppress Shout syntax styling while an inline DIFF is shown (otherwise the
	styler would repaint over TextDiffBuilder's removed/inserted-line colors).
	Otherwise behave exactly like the superclass."
	self dupDiffTarget notNil ifTrue: [^ false].
	^ super aboutToStyle: aStyler
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapMorph >> activeDataset [
	"The dataset last picked from the top-level Data selector (or nil). It set the
	fitting defaults across the axes; individual axes may since have been overridden.
	Used to tick the Data menu."
	^ activeDataset
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:50'
}
SWACodeTreemapMorph >> addDataset: aSWADataset [
	"Retain a named dataset and register ITS METRICS. Each metric (e.g. 'By coverage'
	and 'By call' from one coverage file) gets a UNIQUE minted symbol so it becomes
	its own Color/Size menu entry, tagged with the dataset name -- and loading the
	same kind twice yields distinct, coexisting entries you switch between with no
	reload. Answers the dataset. Does NOT change the current color/size mode."
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:36'
}
SWACodeTreemapMorph >> balloonStringFor: aNode [
	| kids comp |
	kids := aNode children ifNil: [#()].
	^ String streamContents: [:s |
		s nextPutAll: aNode name asString; cr.
		s nextPutAll: 'kind:  '; nextPutAll: aNode kind asString; cr.
		s nextPutAll: 'LOC:   '; print: aNode loc; cr.
		s nextPutAll: 'comments: '; print: aNode commentLines; cr.
		self byteCompositionMode ifTrue: [
			comp := aNode byteComposition.
			s nextPutAll: 'bytes: '; print: (comp first + (comp at: 2) + comp last);
				nextPutAll: '  (doc '; print: comp first;
				nextPutAll: ' / str '; print: (comp at: 2);
				nextPutAll: ' / code '; print: comp last; nextPutAll: ')'; cr].
		s nextPutAll: 'kids:  '; print: kids size; cr.
		aNode lastChanged ifNotNil: [:t |
			s nextPutAll: 'changed: '; nextPutAll: t asDate yyyymmdd; cr].
		s nextPutAll: 'path:  '; nextPutAll: aNode pathString]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:42'
}
SWACodeTreemapMorph >> baseColorForNode: aNode [
	"Dispatch on the active color mode. A minted dataset-metric symbol
	(#coverage_1_coverage, #coverage_1_call, ...) defers to its SWADatasetMetric (the
	layered-datasets layer); when the metric has no value for a node, fall back to a
	neutral base. All the intrinsic modes below are the untouched legacy path."
	(self metricForMode: colorMode) ifNotNil: [:metric |
		^ (metric colorForNode: aNode) ifNil: [Color gray: 0.22]].
	colorMode == #loc ifTrue: [^ self colorByLoc: aNode].
	colorMode == #avgloc ifTrue: [^ self colorByAvgLoc: aNode].
	colorMode == #versions ifTrue: [^ self colorByVersions: aNode].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
	colorMode == #duplication ifTrue: [^ self colorByDuplication: aNode].
	colorMode == #topic ifTrue: [^ self colorByTopic: aNode].
	colorMode == #byteComposition ifTrue: [^ Color gray: 0.18].   "bar drawn on top"
	^ self colorByKind: aNode
]

{
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:14'
}
SWACodeTreemapMorph >> byteCompositionMode [
	"True when the doc/string/code composition bar should be painted on tiles. This
	is purely a COLOR mode (#byteComposition), toggled from the Color context menu
	and INDEPENDENT of the size metric -- so you can size by bytes and still colour
	by author, kind, recency, etc. (and conversely see the composition bar on a
	LOC-sized layout)."
	^ self colorMode == #byteComposition
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:23'
}
SWACodeTreemapMorph >> collectMethodLeavesFrom: aNode into: aCollection [
	"Depth-first collect all SWACodeMethodNode leaves under aNode."
	(aNode isKindOf: SWACodeMethodNode)
		ifTrue: [aCollection add: aNode]
		ifFalse: [aNode children do: [:c | self collectMethodLeavesFrom: c into: aCollection]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:29'
}
SWACodeTreemapMorph >> colorByAuthor: aNode [
	"Color by last author: each author's initials map to a stable hue.
	Unknown author = gray."
	| author hue |
	author := aNode lastAuthor.
	(author isNil or: [author isEmpty]) ifTrue: [^ Color gray: 0.45].
	hue := (author hash \\ 360).
	^ Color h: hue s: 0.5 v: 0.8
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'jl 7/14/2026 16:04'
}
SWACodeTreemapMorph >> colorByAvgLoc: aNode [
	"Average-LOC-per-method heat (most meaningful for class/category nodes): small
	average methods green, large average methods red. Linear over 0..40 LOC/method,
	which spans tidy short methods to long ones. Zero (no methods) = cool green."
	| avg t |
	avg := aNode avgLoc.
	t := (avg / 40.0) min: 1.0.
	"hue 120 (green) down to 0 (red)"
	^ Color h: 120 * (1.0 - t) s: 0.6 v: 0.85
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:58'
}
SWACodeTreemapMorph >> colorByDuplication: aNode [
	"Tile base color in #duplication mode.

	METHOD LEAVES get the solid duplication heat (#dupHeatColorForScore: of their
	own max Jaccard score): dark slate when unique, yellow->red as the best match
	approaches an exact copy.

	AGGREGATE tiles (package / class / category) get a neutral DARK base; the
	proportional 'percent of methods duplicated' bar (#drawDuplicationBar:in:on:) is
	painted on TOP in #drawTileContent:in:on:, so the base only shows through where
	the bar is skipped (e.g. tile too small)."
	(aNode isKindOf: SWACodeMethodNode)
		ifFalse: [^ Color h: 220 s: 0.18 v: 0.22].
	^ self dupHeatColorForScore: (self dupScoreForNode: aNode)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:50'
}
SWACodeTreemapMorph >> colorByKind: aNode [
	"Color by node kind (package/class/category/method/comment), darkened with depth.
	Class comments get a distinct teal (matching the documentation colour of the
	byte-composition bar). Static (class-side) methods get a distinct purple."
	| base depth |
	depth := aNode depth.
	base := aNode kind = #package ifTrue: [Color h: 210 s: 0.45 v: 0.8]
		ifFalse: [aNode kind = #class ifTrue: [Color h: 130 s: 0.45 v: 0.78]
		ifFalse: [aNode kind = #category ifTrue: [Color h: 45 s: 0.5 v: 0.82]
		ifFalse: [aNode kind = #comment ifTrue: [Color h: 190 s: 0.5 v: 0.8]
		ifFalse: [aNode isStatic
			ifTrue: [Color h: 280 s: 0.4 v: 0.8]
			ifFalse: [Color h: 0 s: 0.0 v: 0.92]]]]].
	^ base adjustBrightness: (depth \\ 4) * -0.05
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:24'
}
SWACodeTreemapMorph >> colorByLoc: aNode [
	"LOC heat: green (small) -> red (large), on a log scale to tame outliers."
	| loc t |
	loc := aNode loc.
	t := loc <= 0 ifTrue: [0] ifFalse: [((loc + 1) ln / 6.0) min: 1.0].
	"hue 120 (green) down to 0 (red)"
	^ Color h: 120 * (1.0 - t) s: 0.6 v: 0.85
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:00'
}
SWACodeTreemapMorph >> colorByRecency: aNode [
	"Recency heat with a LOGARITHMIC age scale and a warm->cool gradient.
	Age (days since lastChanged, rolled up to the most-recent leaf over the
	subtree) is mapped to t in [0,1] on a log scale spanning a full day .. ~30 years,
	so both freshly-edited code and 10-20 year old core code spread across the
	gradient:
	  age <= 1 day       -> t = 1 (hottest: red-orange)
	  age >= ~30 years    -> t = 0 (coldest: blue)
	The hue sweeps 10 deg (warm) .. 230 deg (cool) at constant high saturation/value
	so it reads as a clean gradient rather than fading to gray. Unknown = neutral gray."
	| when ageDays t hue |
	when := aNode lastChanged.
	when isNil ifTrue: [^ Color gray: 0.45].
	ageDays := (DateAndTime now - when) asSeconds / 86400.0.
	"Clamp: degenerate timestamps (parsed to ~1901) read as ~35000 days; treat
	anything older than 40 years as the cold end rather than stretching the scale.
	Floor at 1 day so log is well-defined."
	ageDays := (ageDays max: 1.0) min: (40 * 365.0).
	"Log-scale between 1 day (t=1) and ~30 years (t=0)."
	t := 1.0 - (ageDays ln / (30 * 365.0) ln).
	t := (t max: 0.0) min: 1.0.
	"t=1 (recent) -> hue 10 (red-orange); t=0 (old) -> hue 230 (blue)."
	hue := 230.0 - (t * 220.0).
	^ Color h: hue s: 0.75 v: 0.9
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:42'
}
SWACodeTreemapMorph >> colorByTopic: aNode [
	"Tile base color in #topic mode.

	METHOD LEAVES get a solid hue from their dominant topic's hue family; brightness
	encodes the dominant topic's weight (confidence). Methods with no topic (pruned
	from the model, or no data) get a neutral dark gray.

	AGGREGATE tiles (package/class/category) get a neutral DARK base; the topic-
	mixture proportional bar (#drawTopicBar:in:on:) is painted on TOP in
	#drawTileContent:in:on:, so the base only shows through where the bar is skipped."
	| fam hue conf dist dom |
	(aNode isKindOf: SWACodeMethodNode) ifFalse: [^ Color h: 0 s: 0.0 v: 0.2].
	fam := aNode hueFamily.
	fam ifNil: [^ Color gray: 0.22].
	hue := self hueForFamily: fam.
	dist := aNode topicDistribution.
	dom := aNode dominantTopic.
	conf := (dom notNil and: [dist notEmpty])
		ifTrue: [(dist at: dom ifAbsent: [0.5]) min: 1.0]
		ifFalse: [0.5].
	^ Color h: hue s: 0.65 v: (0.55 + (conf * 0.4))
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:41'
}
SWACodeTreemapMorph >> colorByVersions: aNode [
	"Churn heat: average number of recorded method versions per method over this
	subtree (raw totals just track size, so we average). Green (stable, ~1 version)
	-> red (high churn). Linear over 1..8 versions/method. Unknown/zero = cool green."
	| avg t |
	avg := aNode avgChangeCount.
	t := ((avg - 1.0) / 7.0) max: 0.0.
	t := t min: 1.0.
	"hue 120 (green) down to 0 (red)"
	^ Color h: 120 * (1.0 - t) s: 0.6 v: 0.85
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:27'
}
SWACodeTreemapMorph >> colorMode: aSymbol [
	"Code Map color-mode entry point. Most modes just set the base tint (handled by
	super + #baseColorForNode:). The legacy data-driven modes (#coverage/#tally/
	#duplication) acquire/apply lazily. Dataset-metric symbols set the metric tint.

	When the new mode is a coverage-provenance dataset metric, ACTIVATE the test<->method
	provenance relation (blue tests + click filters) from that metric's source; when it
	is anything else, deactivate it. This keeps the special coverage behavior even
	though base color now comes from the metric."
	| metric |
	aSymbol == #duplication ifTrue: [
		dupLoaded == true ifFalse: [self computeDuplicationScores]].
	aSymbol == #coverage ifTrue: [^ self enterCoverageColorMode].
	aSymbol == #tally ifTrue: [^ self enterTallyColorMode].
	super colorMode: aSymbol.
	metric := self metricForMode: aSymbol.
	(metric notNil and: [metric isCoverageProvenance])
		ifTrue: [self activateCoverageProvenanceFrom: metric coverageSource]
		ifFalse: [self deactivateCoverageProvenance].
	self refreshChrome
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:43'
}
SWACodeTreemapMorph >> computeDuplicationScores [
	"Build the per-method duplication cache, showing a progress bar across the
	stages. The naive pairwise scan is O(n^2); we instead use the paper's
	document-fingerprint idea -- an INVERTED SHINGLE INDEX -- to compare only
	CANDIDATE pairs that share at least one k-gram. Two methods with no shared
	shingle have Jaccard 0 (< dupListFloor), so skipping them is EXACT, not
	approximate: results are identical to brute force, ~13x faster on big packages
	(Morphic-Kernel 13s -> ~1s).

	Stages:
	  1. COLLECT  -- method leaves under the focus, minus trivial (< dupMinLoc) ones,
	  2. SHINGLE  -- each eligible method's k-gram set once (O(n)) + build the
	     inverted index shingle -> {method indices},
	  3. COMPARE  -- for each method, gather candidates via the index and Jaccard
	     only those, keeping matches >= dupListFloor sorted best-first.

	Stored per method (keyed by crossRefKey): an Array of score -> partnerNode.
	Coloring uses the first (max) score; the side pane lists them all; link WIDTH
	uses the shared-LOC estimate.

	PROGRESS: bar runs 0..(n + shingleBudget); COMPARE position is shingleBudget + i
	matching the 'Comparing i / n' caption, with a remaining-time ETA.

	This is a FRESH compute, so any previously LOADED data is dropped (#dupLoaded
	false); the offline counterpart that fills the same cache is
	#loadDuplicationData:."
	| sim leaves shingles index floor minLoc n shingleBudget |
	dupLoaded := false.
	sim := self dupSimilarity.
	floor := self dupListFloor.
	minLoc := self dupMinLoc.
	dupScores := Dictionary new.
	"--- Stage 1: collect + filter ---"
	leaves := OrderedCollection new.
	self collectMethodLeavesFrom: currentNode into: leaves.
	leaves := (leaves reject: [:m | m loc < minLoc]) asArray.
	n := leaves size.
	n = 0 ifTrue: [^ self].
	shingleBudget := (n // 20) max: 1.
	'Duplication analysis' displayProgressFrom: 0 to: n + shingleBudget during: [:bar |
		| compareStart |
		"--- Stage 2: shingle + inverted index -> 0..shingleBudget ---"
		bar value: 'Shingling ', n printString, ' methods...'.
		index := Dictionary new.
		shingles := Array new: n.
		1 to: n do: [:i |
			| s |
			s := sim shinglesFor: (leaves at: i) sourceString.
			shingles at: i put: s.
			s do: [:sh | (index at: sh ifAbsentPut: [OrderedCollection new]) add: i].
			(i \\ 16 = 0) ifTrue: [bar value: (i * shingleBudget // n)]].
		"--- Stage 3: candidate compare -> shingleBudget..(shingleBudget + n) ---"
		compareStart := Time millisecondClockValue.
		1 to: n do: [:i |
			| si cands matches |
			si := shingles at: i.
			matches := OrderedCollection new.
			si isEmpty ifFalse: [
				"candidates = other methods sharing >= 1 shingle (via the index)"
				cands := Set new.
				si do: [:sh | (index at: sh) do: [:j | j ~= i ifTrue: [cands add: j]]].
				cands do: [:j |
					| sc |
					sc := (sim jaccardBetween: si and: (shingles at: j)) asFloat.
					sc >= floor ifTrue: [matches add: sc -> (leaves at: j)]]].
			matches := matches asSortedCollection: [:a :b | a key >= b key].
			dupScores at: (leaves at: i) crossRefKey put: matches asArray.
			(i \\ 10 = 0) ifTrue: [
				| elapsed eta |
				elapsed := Time millisecondClockValue - compareStart.
				eta := elapsed * (n - i) / i.
				bar value: 'Comparing ', i printString, ' / ', n printString,
					'   (~', (self dupFormatEtaMillis: eta), ' left)'.
				bar value: shingleBudget + i]].
		bar value: n + shingleBudget]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:12'
}
SWACodeTreemapMorph >> containerDuplicatePairCountFor: aContainerNode metric: aMetric [
	"Count DISTINCT near-duplicate pairs among the method leaves under aContainerNode
	(unordered, de-duplicated). Used for the side-pane title."
	| leaves seen |
	leaves := OrderedCollection new.
	self collectMethodLeavesFrom: aContainerNode into: leaves.
	seen := Set new.
	leaves do: [:m | | fromKey |
		fromKey := m crossRefKey.
		fromKey ifNotNil: [
			(aMetric linksForKey: fromKey) do: [:assoc |
				| partnerKey pairKey |
				partnerKey := assoc value.
				pairKey := (fromKey <= partnerKey)
					ifTrue: [fromKey, '|', partnerKey]
					ifFalse: [partnerKey, '|', fromKey].
				seen add: pairKey]]].
	^ seen size
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:32'
}
SWACodeTreemapMorph >> containerDuplicatesFor: aContainerNode metric: aMetric [
	"Aggregate near-duplicates of every DESCENDANT method under aContainerNode into
	side-pane entries 'NN%  fromMethod <-> partnerMethod'. Unordered pairs de-duplicated;
	best-first; truncated to the top 50 with a '... N more' note.

	Each entry's VALUE is a  fromKey -> partnerKey  Association carrying BOTH endpoints,
	so a click can preview the pair's DIFF without navigating (see #provenanceIndex:).
	The note entry's value is nil (non-clickable)."
	| leaves seen rows limit shown entries |
	leaves := OrderedCollection new.
	self collectMethodLeavesFrom: aContainerNode into: leaves.
	seen := Set new.
	rows := OrderedCollection new.
	leaves do: [:m | | fromKey |
		fromKey := m crossRefKey.
		fromKey ifNotNil: [
			(aMetric linksForKey: fromKey) do: [:assoc |
				| partnerKey score pairKey |
				score := assoc key.
				partnerKey := assoc value.
				pairKey := (fromKey <= partnerKey)
					ifTrue: [fromKey, '|', partnerKey]
					ifFalse: [partnerKey, '|', fromKey].
				(seen includes: pairKey) ifFalse: [
					seen add: pairKey.
					rows add: { score. fromKey. partnerKey }]]]].
	rows := (rows asSortedCollection: [:a :b | (a at: 1) >= (b at: 1)]) asOrderedCollection.
	limit := 50.
	shown := rows size <= limit ifTrue: [rows] ifFalse: [rows first: limit].
	entries := shown collect: [:r |
		(((r at: 1) * 100) rounded printString, '%  ',
			(r at: 2), ' <-> ', (r at: 3)) -> ((r at: 2) -> (r at: 3))].
	rows size > limit ifTrue: [
		entries := entries copyWith:
			(('... ', (rows size - limit) printString, ' more') -> nil)].
	^ entries
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:00'
}
SWACodeTreemapMorph >> coverageMetricLabel [
	"Human label for the active coverage WEIGHT metric, used in the details box and
	header instead of LOC. 'invocations' / 'covering tests' for a provenance overlay
	(per the root's weight mode), 'invocations' for a live tally, else 'coverage'."
	coverageData ifNotNil: [
		(rootNode notNil and: [rootNode coverageWeightMode == #invocations])
			ifTrue: [^ 'invocations'].
		^ 'covering tests'].
	coverageKind == #tally ifTrue: [^ 'invocations'].
	^ 'coverage'
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:24'
}
SWACodeTreemapMorph >> coverageNoteForNode: aNode [
	"A short per-node coverage/tally note for the selected-node meta line, or '' if
	no overlay is active. With a SWACoverageData (provenance) overlay, a test
	method or TestCase class node reports how many methods it covers, while an
	application method node lists its covering tests (PathTools-style). Method nodes
	show their own value; class/package nodes show the rolled-up (max) value over
	their methods."
	| v isLeaf |
	coverageKind ifNil: [^ ''].
	(coverageData notNil and: [self isTestKey: aNode crossRefKey]) ifTrue: [
		^ self testProvenanceNoteForNode: aNode].
	v := self coverageValueForNode: aNode.
	isLeaf := aNode kind == #method.
	"Provenance: covering tests for a selected method."
	(coverageData notNil and: [isLeaf]) ifTrue: [
		^ self coverageProvenanceNoteForNode: aNode].
	coverageKind == #tally ifTrue: [
		v ifNil: [^ isLeaf ifTrue: ['not invoked'] ifFalse: ['no invoked methods']].
		^ isLeaf
			ifTrue: ['invoked ', v printString, 'x']
			ifFalse: ['hottest method: ', v printString, 'x']].
	"#boolean"
	v ifNil: [^ isLeaf ifTrue: ['not covered'] ifFalse: ['no covered methods']].
	^ isLeaf ifTrue: ['covered'] ifFalse: ['has covered methods']
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:24'
}
SWACodeTreemapMorph >> coverageProvenanceNoteForNode: aNode [
	"For a method node under a SWACoverageData overlay: list the covering tests
	and the distinct TestCase classes they belong to (PathTools-style), or
	'not covered'."
	| key count tests classes |
	key := aNode crossRefKey.
	key ifNil: [^ ''].
	count := coverageData coveringTestCountFor: key.
	count = 0 ifTrue: [^ 'not covered'].
	tests := coverageData testsForMethod: key.
	classes := coverageData testClassesForMethod: key.
	^ 'covered by ', count printString, ' test',
		(count = 1 ifTrue: [''] ifFalse: ['s']),
		' in ', classes size printString, ' TestCase',
		(classes size = 1 ifTrue: [''] ifFalse: ['s']),
		' (', ((classes asSortedCollection) inject: '' into: [:a :b |
			a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]), ')',
		': ',
		((tests first: (5 min: tests size)) inject: '' into: [:a :b |
			a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]),
		(tests size > 5 ifTrue: [', ...'] ifFalse: [''])
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWACodeTreemapMorph >> coverageStatus [
	"Short human-readable description of the current coverage overlay, or nil if
	there is none. Shown in the panel's meta-info line so existing vs. fresh vs.
	in-progress coverage is distinguishable."
	^ coverageStatus
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWACodeTreemapMorph >> coverageStatus: aStringOrNil [
	"Set the coverage status line and refresh the chrome/meta line."
	coverageStatus := aStringOrNil.
	navPanel ifNotNil: [navPanel refresh]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapMorph >> datasetForDataMode: aSymbol [
	"Resolve a Data-menu symbol to its dataset; #none clears the active dataset."
	aSymbol == #none ifTrue: [^ nil].
	^ self datasets detect: [:d | d modeSymbol == aSymbol] ifNone: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWACodeTreemapMorph >> datasets [
	"The retained, named analysis overlays loaded into this map (SWADataset), in load
	order. Part of the additive layered-datasets layer -- legacy colorMode overlays
	are unaffected. Lazily initialized."
	^ datasets ifNil: [datasets := OrderedCollection new]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWACodeTreemapMorph >> decorationMetric [
	"The active SWADatasetMetric driving map DECORATIONS (currently duplication clone
	links), or nil for no decorations. Independent of the color and size bindings, so
	you can e.g. color by LOC while still drawing duplication links."
	^ decorationMetric
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWACodeTreemapMorph >> decorationMetric: aMetricOrNil [
	"Bind (or clear) the decoration axis to a link-capable dataset metric, then
	redraw. Instant like a recolor -- decorations are drawn by the overlay, no
	relayout needed."
	decorationMetric := aMetricOrNil.
	self flushCacheKeepingSelection
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWACodeTreemapMorph >> decorationMetricForMode: aSymbol [
	"Resolve a minted decoration-menu symbol to its metric; #none clears; nil for a
	non-decoration symbol."
	aSymbol == #none ifTrue: [^ nil].
	^ self metricForMode: aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWACodeTreemapMorph >> detailInfoString [
	"Multi-line details for the Show-mode details box BESIDE the source (one
	'label: value' per line). EXCLUDES the covered-methods/tests provenance (that
	has its own pane). When a coverage overlay is active, leads with the coverage
	METRIC (invocations / covering tests) and DROPS the LOC line. In
	byte-composition mode, leads with the source byte size and its doc/string/code
	split. In #duplication mode, leads with the Jaccard duplication score and the
	best-matching method. '' when nothing is selected. (SWAPane content
	protocol.)"
	| n when whenStr cov comp |
	n := selectedNode ifNil: [^ ''].
	when := n lastChanged.
	whenStr := when
		ifNil: ['?']
		ifNotNil: [:t | t asDate printString, ' ', (t asTime print24)].
	cov := self coverageValueForNode: n.
	^ String streamContents: [:s |
		s nextPutAll: n kind asString; nextPutAll: ': '; nextPutAll: n name; cr.
		"Duplication score first when in duplication mode."
		colorMode == #duplication ifTrue: [
			| score best |
			score := self dupScoreForNode: n.
			s nextPutAll: 'duplication: '; print: (score * 100) rounded; nextPutAll: '%'; cr.
			best := self dupPartnerForNode: n.
			best ifNotNil: [
				s nextPutAll: 'best match:'; cr;
					nextPutAll: '  '; nextPutAll: best crossRefKey; cr]].
		"Coverage metric first (and instead of LOC) when an overlay is active."
		coverageKind notNil
			ifTrue: [
				s nextPutAll: self coverageMetricLabel; nextPutAll: ': ';
					nextPutAll: (cov ifNil: ['0'] ifNotNil: [:v | v printString]); cr]
			ifFalse: [self byteCompositionMode
				ifTrue: [
					comp := n byteComposition.
					s nextPutAll: 'bytes: '; print: (comp first + (comp at: 2) + comp last); cr.
					s nextPutAll: '  doc: '; print: comp first;
						nextPutAll: '  str: '; print: (comp at: 2);
						nextPutAll: '  code: '; print: comp last; cr.
					s nextPutAll: 'LOC: '; print: n loc; cr]
				ifFalse: [
					s nextPutAll: 'LOC: '; print: n loc; cr]].
		s nextPutAll: 'author: '; nextPutAll: (n lastAuthor ifNil: ['?']); cr.
		s nextPutAll: 'changed: '; nextPutAll: whenStr; cr.
		s nextPutAll: 'versions: '; print: n changeCount;
			nextPutAll: ' ('; nextPutAll: (n avgChangeCount asFloat printShowingDecimalPlaces: 1);
			nextPutAll: '/method)']
]

{
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:35'
}
SWACodeTreemapMorph >> drawByteCompositionBar: aNode in: screenR on: aCanvas [
	"Paint a horizontal proportional bar across the FULL tile width, left to right:
	  TEAL  -- documentation (method-comment) bytes,
	  AMBER -- string-literal bytes,
	  GREEN-GRAY -- the rest (code) bytes.
	Segments sum to 100% of the width (sized by share of source bytes). This is the
	doc/string/code composition shown as sub-elements of a method; when the tile is
	too small to do anything else the bar simply becomes thin, which is the
	'cannot show children' fallback. Aggregate tiles roll the composition up over
	their leaves. To avoid DOUBLE representation, a node whose RENDERED children are
	themselves aggregates draws its bar DESATURATED, so the crisp bars are the
	most-detailed VISIBLE level. Pixel-fill only -- no morphs, no layout change."
	| comp total x drawnSoFar fade mix segs |
	comp := aNode byteComposition.
	total := comp first + (comp at: 2) + comp last.
	total = 0 ifTrue: [^ self].
	fade := self hasRenderedAggregateChildrenUnder: aNode.
	mix := [:c | fade ifTrue: [c alphaMixed: 0.4 with: (Color gray: 0.25)] ifFalse: [c]].
	segs := {
		comp first    -> (mix value: (Color h: 190.0 s: 0.55 v: 0.82)).   "doc: teal"
		(comp at: 2)  -> (mix value: (Color h: 38.0 s: 0.80 v: 0.88)).    "string: amber"
		comp last     -> (mix value: (Color h: 110.0 s: 0.32 v: 0.62)) }. "code: green-gray"
	x := screenR left.
	drawnSoFar := 0.
	segs do: [:assoc | | n segRight |
		n := assoc key.
		n > 0 ifTrue: [
			drawnSoFar := drawnSoFar + n.
			segRight := screenR left + (screenR width * drawnSoFar / total) rounded.
			segRight := segRight min: screenR right.
			aCanvas fillRectangle: (x @ screenR top corner: segRight @ screenR bottom)
				color: assoc value.
			x := segRight]]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:58'
}
SWACodeTreemapMorph >> drawDuplicationBar: aNode in: screenR on: aCanvas [
	"Paint a horizontal proportional bar across the FULL tile width for an AGGREGATE
	node (package / class / category) in #duplication mode:
	  HEAT  -- the share of eligible methods in the subtree that are duplicated,
	           tinted by the AVERAGE clone strength of those methods (yellow->red),
	  DARK  -- the remaining (unique) methods.
	So a class half of whose methods are clones shows a half-width hot bar; a class
	with no duplication stays dark. To avoid DOUBLE representation, a node whose
	RENDERED children are themselves aggregates draws its bar DESATURATED, so the
	crisp bars are the most-detailed VISIBLE level (cf. byte-composition mode)."
	| comp affected total avgScore fade heat affRight |
	comp := self dupCompositionForNode: aNode.
	affected := comp at: 1.
	total := comp at: 2.
	total = 0 ifTrue: [^ self].
	avgScore := affected = 0 ifTrue: [0.0] ifFalse: [(comp at: 3) / affected].
	fade := self hasRenderedAggregateChildrenUnder: aNode.
	"affected segment color: duplication heat at the average score, faded if needed."
	heat := self dupHeatColorForScore: avgScore.
	fade ifTrue: [heat := heat alphaMixed: 0.4 with: (Color gray: 0.22)].
	"dark base for the whole tile (unique remainder shows through)."
	aCanvas fillRectangle: screenR color: (Color h: 220 s: 0.18 v: 0.22).
	affected = 0 ifTrue: [^ self].
	affRight := screenR left + (screenR width * affected / total) rounded.
	affRight := affRight min: screenR right.
	aCanvas fillRectangle: (screenR left @ screenR top corner: affRight @ screenR bottom)
		color: heat
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:43'
}
SWACodeTreemapMorph >> drawTileContent: aNode in: screenR on: aCanvas [
	"Extra per-tile content painted over the fill, before frame/label.

	BYTE-COMPOSITION mode (#byteCompositionMode): paint the doc/string/code
	proportional bar (#drawByteCompositionBar:in:on:) on EVERY tile -- both method
	leaves (their own analysis) and aggregates (rolled up) -- then return. This is
	the new, additive mode and is independent of the coverage overlay.

	DUPLICATION mode (#colorMode == #duplication): on AGGREGATE tiles paint the
	'percent of methods duplicated' proportional bar (#drawDuplicationBar:in:on:);
	method leaves keep their solid heat color, so fall through. Then return.

	TOPIC mode (#colorMode == #topic): on AGGREGATE tiles paint the topic-mixture
	bar (#drawTopicBar:in:on:); method leaves keep their solid hue, so fall through.
	Then return.

	Otherwise, under a loaded COVERAGE overlay, paint a horizontal proportional bar
	across an AGGREGATE tile, left to right:
	  GRAY untouched, GREEN covered, RED evicted, BLUE test.
	The segments sum to 100% of the width (sized by share of leaf-method
	descendants). When a selection FILTER is active, each coloured class is split
	into a bright sub-segment (filter match) and a DIMMED one (filtered out).
	Pixel-fill only -- no extra morphs, no layout change. Leaf tiles fall through to
	#colorForNode:'s solid colour (proportions answers nil).

	To avoid DOUBLE representation, a node whose RENDERED children are also aggregates
	(#hasRenderedAggregateChildrenUnder:) draws its bar DESATURATED, so the
	crisp bars are the most-detailed VISIBLE level."
	| props total gray x segs drawnSoFar fade mix dim |
	self byteCompositionMode ifTrue: [
		^ self drawByteCompositionBar: aNode in: screenR on: aCanvas].
	colorMode == #duplication ifTrue: [
		(aNode isKindOf: SWACodeMethodNode) ifFalse: [
			self drawDuplicationBar: aNode in: screenR on: aCanvas].
		^ self].
	colorMode == #topic ifTrue: [
		(aNode isKindOf: SWACodeMethodNode) ifFalse: [
			self drawTopicBar: aNode in: screenR on: aCanvas].
		^ self].
	props := self coverageProportionsForNode: aNode.
	props ifNil: [^ self].
	total := props at: #total.
	total = 0 ifTrue: [^ self].
	gray := total - ((props at: #green) + (props at: #greenDim)
		+ (props at: #red) + (props at: #redDim)
		+ (props at: #blue) + (props at: #blueDim)).
	fade := self hasRenderedAggregateChildrenUnder: aNode.
	mix := [:c | fade ifTrue: [c alphaMixed: 0.35 with: (Color gray: 0.25)] ifFalse: [c]].
	dim := [:c | c alphaMixed: 0.25 with: (Color gray: 0.12)].
	segs := {
		gray                -> (Color gray: 0.4).
		(props at: #green)    -> (mix value: (Color h: 120.0 s: 0.75 v: 0.85)).
		(props at: #greenDim) -> (mix value: (dim value: (Color h: 120.0 s: 0.75 v: 0.85))).
		(props at: #red)      -> (mix value: (Color h: 0.0 s: 0.8 v: 0.85)).
		(props at: #redDim)   -> (mix value: (dim value: (Color h: 0.0 s: 0.8 v: 0.85))).
		(props at: #blue)     -> (mix value: (Color h: 210.0 s: 0.6 v: 0.85)).
		(props at: #blueDim)  -> (mix value: (dim value: (Color h: 210.0 s: 0.6 v: 0.85))) }.
	x := screenR left.
	drawnSoFar := 0.
	segs do: [:assoc | | n segRight |
		n := assoc key.
		n > 0 ifTrue: [
			drawnSoFar := drawnSoFar + n.
			segRight := screenR left + (screenR width * drawnSoFar / total) rounded.
			segRight := segRight min: screenR right.
			aCanvas fillRectangle: (x @ screenR top corner: segRight @ screenR bottom)
				color: assoc value.
			x := segRight]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:42'
}
SWACodeTreemapMorph >> drawTopicBar: aNode in: screenR on: aCanvas [
	"Paint a horizontal proportional topic-mixture bar across an AGGREGATE tile.
	Each segment is one topic present in the subtree, width proportional to its
	rolled-up weight, colored by that topic's hue family. Segments are drawn in
	descending-weight order so the dominant topic leads. Pixel-fill only."
	| dist total sorted x drawnSoFar |
	dist := aNode topicDistribution.
	dist isEmpty ifTrue: [^ self].
	total := dist values inject: 0.0 into: [:s :v | s + v].
	total <= 0 ifTrue: [^ self].
	sorted := dist associations asSortedCollection: [:a :b | a value >= b value].
	x := screenR left.
	drawnSoFar := 0.0.
	sorted do: [:assoc |
		| topic hue segRight |
		topic := assoc key.
		drawnSoFar := drawnSoFar + assoc value.
		hue := self hueForFamily: (self topicDataOrNil ifNotNil: [:td | td hueFamilyForTopic: topic]).
		segRight := (screenR left + (screenR width * drawnSoFar / total)) rounded min: screenR right.
		hue ifNotNil: [
			aCanvas fillRectangle: (x @ screenR top corner: segRight @ screenR bottom)
				color: (Color h: hue s: 0.6 v: 0.8)].
		x := segRight]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:58'
}
SWACodeTreemapMorph >> dupCompositionForNode: aNode [
	"Roll up duplication over aNode's subtree for the aggregate bar. Returns an
	Array { affectedMethods. totalMethods. summedScore } where:
	 - totalMethods  = eligible (>= dupMinLoc) method leaves under aNode,
	 - affectedMethods = those with at least one near-duplicate (a non-empty match
	   list in the cache),
	 - summedScore   = sum of each affected method's MAX Jaccard score (so the
	   affected segment can be tinted by the AVERAGE clone strength).
	Methods excluded by the accessor LOC floor are simply absent from the cache and
	thus counted in neither total nor affected, which is what we want."
	| affected total summed |
	dupScores isNil ifTrue: [^ { 0. 0. 0.0 }].
	(aNode isKindOf: SWACodeMethodNode) ifTrue: [
		| matches |
		matches := dupScores at: aNode crossRefKey ifAbsent: [^ { 0. 0. 0.0 }].
		"not in cache (filtered out) -> contributes nothing"
		^ matches isEmpty
			ifTrue: [{ 0. 1. 0.0 }]
			ifFalse: [{ 1. 1. matches first key }]].
	affected := 0. total := 0. summed := 0.0.
	aNode children do: [:c |
		| comp |
		comp := self dupCompositionForNode: c.
		affected := affected + (comp at: 1).
		total := total + (comp at: 2).
		summed := summed + (comp at: 3)].
	^ { affected. total. summed }
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:31'
}
SWACodeTreemapMorph >> dupDiffFrom [
	"The FROM method of a duplicate pair being previewed from a CONTAINER's aggregated
	list -- diffed against #dupDiffTarget in the source pane WITHOUT changing the
	primary selection (so the container stays selected and its list survives). nil for
	the normal method-selection diff (which uses #selectedNode as the from side)."
	^ dupDiffFrom
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWACodeTreemapMorph >> dupDiffTarget [
	"The near-duplicate method node the source pane is diffing the selection
	AGAINST. This IS the secondary selection (the red-boxed tile); a nil means a
	plain source view."
	^ self secondarySelection
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWACodeTreemapMorph >> dupDiffTarget: aMethodNodeOrNil [
	"Set the partner method to diff the current selection against (from a click in
	the duplicates side pane). It becomes the SECONDARY SELECTION (red box), and
	refreshing chrome re-pulls #selectedSourceString -> the inline diff Text."
	self secondarySelection: aMethodNodeOrNil
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:36'
}
SWACodeTreemapMorph >> dupFormatEtaMillis: ms [
	"Compact remaining-time string for the progress caption: 'Ns' under a minute,
	'Nm Ns' otherwise. Negative/zero -> a short placeholder."
	| secs mins |
	ms <= 0 ifTrue: [^ '<1s'].
	secs := (ms / 1000.0) rounded.
	secs < 60 ifTrue: [^ secs printString, 's'].
	mins := secs // 60.
	^ mins printString, 'm ', (secs \\ 60) printString, 's'
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:58'
}
SWACodeTreemapMorph >> dupHeatColorForScore: score [
	"The duplication heat ramp shared by leaf tiles and aggregate bars:
	  score < 0.5  -> cool gray-blue (unique-ish), slightly bluer the lower,
	  0.5 .. 1.0   -> yellow -> orange -> red (likely copy; 1.0 = vivid red)."
	| t |
	score < 0.5 ifTrue: [^ Color h: 220 s: 0.25 v: 0.30 + (score * 0.2)].
	t := ((score - 0.5) / 0.5) min: 1.0.
	^ Color h: 60 * (1.0 - t) s: 0.85 v: 0.95
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> dupListFloor [
	"Minimum Jaccard score for a match to be recorded/listed in the duplication
	pane. Below this we don't consider two methods related at all."
	^ 0.5
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> dupMatchesForNode: aNode [
	"Array of  score -> partnerMethodNode  associations (best first) for a method
	leaf, or #() for non-methods / no matches / cache not built."
	dupScores isNil ifTrue: [^ #()].
	(aNode isKindOf: SWACodeMethodNode) ifFalse: [^ #()].
	^ dupScores at: aNode crossRefKey ifAbsent: [#()]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:45'
}
SWACodeTreemapMorph >> dupMinLoc [
	"Minimum non-blank LOC for a method to take part in duplication analysis at all.
	Below this (one-line accessors, trivial forwarders) methods are near-identical
	by nature and only add noise, so we ignore them. 4 keeps real logic, drops the
	'foo ^ foo' / 'foo: x  foo := x' boilerplate."
	^ dupMinLoc ifNil: [4]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:46'
}
SWACodeTreemapMorph >> dupMinLoc: anInteger [
	"Set the accessor-exception LOC floor and recompute if currently in duplication
	mode."
	dupMinLoc := anInteger.
	colorMode == #duplication ifTrue: [
		self computeDuplicationScores.
		self flushCache.
		self refreshChrome]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> dupPartnerForNode: aNode [
	"The best-matching partner method node for a method leaf, or nil."
	| matches |
	dupScores isNil ifTrue: [^ nil].
	(aNode isKindOf: SWACodeMethodNode) ifFalse: [^ nil].
	matches := dupScores at: aNode crossRefKey ifAbsent: [^ nil].
	^ matches isEmpty ifTrue: [nil] ifFalse: [matches first value]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> dupScoreForNode: aNode [
	"Max Jaccard similarity for aNode. Method leaves read the cache (first/best
	match); container nodes roll up to the max score among their descendant methods
	so a class/category lights up when it contains a near-duplicate. Returns 0.0
	when unknown (cache not built or no methods/matches)."
	dupScores isNil ifTrue: [^ 0.0].
	(aNode isKindOf: SWACodeMethodNode) ifTrue: [
		| matches |
		matches := dupScores at: aNode crossRefKey ifAbsent: [^ 0.0].
		^ matches isEmpty ifTrue: [0.0] ifFalse: [matches first key]].
	^ aNode children
		inject: 0.0
		into: [:mx :c | mx max: (self dupScoreForNode: c)]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:46'
}
SWACodeTreemapMorph >> dupSharedLocBetween: nodeA and: nodeB [
	"Estimated number of DUPLICATED lines between two methods: the Jaccard score
	(fraction of shared shingles) times the smaller method's LOC. This is the
	'impact' of the clone -- a 100% match on a 2-line accessor shares ~2 lines; a
	90% match on a 40-line method shares ~36. Link width uses this, so big copied
	methods draw heavy lines and small ones stay thin regardless of percentage."
	| score |
	(nodeA isNil or: [nodeB isNil]) ifTrue: [^ 0].
	score := 0.0.
	(self dupMatchesForNode: nodeA) do: [:m |
		m value crossRefKey = nodeB crossRefKey ifTrue: [score := m key]].
	^ (score * (nodeA loc min: nodeB loc)) rounded
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:23'
}
SWACodeTreemapMorph >> dupSimilarity [
	"The SWACodeSimilarity engine, lazily created. k=4 is a reasonable default
	for Smalltalk; threshold 0 here because we want a score for EVERY method (the
	color gradient does the thresholding visually)."
	^ dupSimilarity ifNil: [dupSimilarity := SWACodeSimilarity new k: 4; threshold: 0.0; yourself]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:23'
}
SWACodeTreemapMorph >> enterCoverageColorMode [
	"Color by SUnit test coverage. If coverage data is already loaded, (re)apply the
	covering-test overlay and recolor. Otherwise ask the nav panel to RUN the shown
	packages' related tests (forked, Stop-able) and overlay the result -- a no-op
	with a status note if there is no panel to drive the run."
	self coverageData
		ifNotNil: [
			colorMode := #coverage.
			self showCoverageData: self coverageData weightMode: #tests.
			self refreshChrome]
		ifNil: [
			navPanel notNil
				ifTrue: [navPanel acquireTestCoverageThenColor]
				ifFalse: [self coverageStatus: 'Coverage: load or run coverage data first']]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:23'
}
SWACodeTreemapMorph >> enterTallyColorMode [
	"Color by invocation COUNT. Uses whatever invocation data is loaded (live Tally
	button, or a file that carries call counts). If the current coverage data has no
	invocation counts, leave the mode unchanged and say so -- live counting is driven
	interactively by the Tally button, not acquired from here."
	(self coverageData notNil and: [self coverageData hasInvocationData])
		ifTrue: [
			colorMode := #tally.
			self showCoverageData: self coverageData weightMode: #invocations.
			self refreshChrome]
		ifFalse: [
			self coverageStatus: 'Tally: no invocation data -- press the Tally button to count, or load a file with call counts']
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:06'
}
SWACodeTreemapMorph >> exploreNode: aNode [
	"Browse the live code element behind the tile instead of exploring the node."
	aNode browse
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:12'
}
SWACodeTreemapMorph >> formatWeight: aNumber [
	"Unit label for the active size metric."
	| m |
	m := self weightMetric.
	m == #bytes ifTrue: [^ aNumber printString, ' bytes'].
	m == #methods ifTrue: [^ aNumber printString, ' methods'].
	m == #invocations ifTrue: [^ aNumber printString, ' calls'].
	m == #tests ifTrue: [^ aNumber printString, ' tests'].
	^ aNumber printString, ' LOC'
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:54'
}
SWACodeTreemapMorph >> hasRenderedAggregateChildrenUnder: aNode [
	"True if aNode's bar DUPLICATES proportional BARS drawn by visible child tiles, so
	it should be faded. A child draws a bar only if it is itself an aggregate (has
	children) AND is rendered as a tile. Method leaves draw a solid color, not a bar,
	so a category sitting directly over methods does NOT duplicate any child bar and
	stays CRISP.

	Fade iff:
	 1. aNode's children are laid out as tiles (#shouldLayoutChildrenOf: aNode), and
	 2. at least one of those rendered children is itself an aggregate (has children).
	Respects leafKind through #shouldLayoutChildrenOf::
	 - #package: package is a leaf -> false -> crisp.
	 - #class:   package lays out class tiles (aggregates) -> faded; class is a leaf -> crisp.
	 - #category:package/class faded; category is a leaf -> crisp.
	 - nil:      package/class faded; category over methods -> children are leaves -> crisp."
	(self shouldLayoutChildrenOf: aNode) ifFalse: [^ false].
	^ aNode children anySatisfy: [:c | c children notEmpty]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:42'
}
SWACodeTreemapMorph >> hueForFamily: familyIndex [
	"Map a 0-based hue family index to a hue angle (degrees). Spread the families
	evenly around the wheel using the topic data's hueFamilyCount when available,
	else 12. familyIndex nil -> nil (neutral tile)."
	| td n |
	familyIndex ifNil: [^ nil].
	td := self topicDataOrNil.
	n := (td notNil and: [td hueFamilyCount > 0]) ifTrue: [td hueFamilyCount] ifFalse: [12].
	^ (familyIndex \\ n) * 360.0 / n
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:05'
}
SWACodeTreemapMorph >> initialize [
	super initialize.
	colorMode := #codeKind
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWACodeTreemapMorph >> intrinsicColorMode [
	"The Code Map's native default color mode."
	^ #codeKind
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:04'
}
SWACodeTreemapMorph >> isDuplicationProvenanceActive [
	"True when a duplication (link-capable) decoration metric is active, so the side
	pane lists near-duplicates and a click there DIFFS rather than navigates."
	^ self decorationMetric notNil and: [self decorationMetric supportsLinks]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:53'
}
SWACodeTreemapMorph >> isTopicProvenanceActive [
	"True when the map is in #topic color mode and topic data is loaded, so the
	side pane lists the selection's topic mixture instead of coverage provenance."
	^ colorMode == #topic and: [self topicDataOrNil notNil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:22'
}
SWACodeTreemapMorph >> leafKeySetUnder: aNode [
	"The Set of method crossRefKeys at or below aNode -- the 'selection subtree' used
	to filter decorations (links) to what connects to the current selection. A method
	leaf answers a singleton of its own key; a container answers all its descendants'
	keys. General across decoration datasets, not duplication-specific."
	| keys leaves |
	keys := Set new.
	leaves := OrderedCollection new.
	self collectMethodLeavesFrom: aNode into: leaves.
	leaves do: [:m | m crossRefKey ifNotNil: [:k | keys add: k]].
	^ keys
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:23'
}
SWACodeTreemapMorph >> link: aKeyPair connectsRestriction: keySetOrNil [
	"Decoration selection-filter rule (testable, canvas-free): a link between the two
	crossRefKeys in aKeyPair (an Association fromKey -> toKey) is shown when there is
	no restriction (nil) OR at least ONE endpoint is in the restriction key set."
	keySetOrNil isNil ifTrue: [^ true].
	^ (keySetOrNil includes: aKeyPair key)
		or: [keySetOrNil includes: aKeyPair value]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:42'
}
SWACodeTreemapMorph >> loadDuplicationData: aSWADuplicationData [
	"Populate the duplication cache (#dupScores) from a previously GENERATED,
	persisted SWADuplicationData instead of running #computeDuplicationScores now.
	This is the offline counterpart, mirroring #showCoverageData: for coverage:
	expensive scans (big packages) are generated once to a file and reloaded here.

	dupScores is  crossRefKey -> Array of (score -> partnerNode). We resolve each
	stored partner crossRefKey to the ACTUAL method node in the current tree (by
	identity, so #rectForNode: finds it and links are drawn). Partners NOT in the
	current tree become a lightweight SWADuplicationPartnerStub: still listed in the
	details side-pane, but never drawn on the map (Jens's call) since they have no
	tile. Pass nil to clear.

	Sets #dupLoaded so entering #duplication colorMode keeps this data instead of
	recomputing."
	| keyIndex allLeaves |
	aSWADuplicationData ifNil: [dupScores := nil. dupLoaded := false. ^ self changed].
	"index every method leaf in the WHOLE tree by crossRefKey for identity resolution
	(rootNode, not currentNode, so partners outside the current zoom still resolve)"
	allLeaves := OrderedCollection new.
	self collectMethodLeavesFrom: rootNode into: allLeaves.
	keyIndex := Dictionary new.
	allLeaves do: [:m | keyIndex at: m crossRefKey put: m].
	dupScores := Dictionary new.
	aSWADuplicationData matchesByKeyDo: [:methodKey :keyMatches |
		dupScores at: methodKey put: (keyMatches collect: [:assoc |
			| partnerKey partnerNode |
			partnerKey := assoc value.
			partnerNode := keyIndex at: partnerKey ifAbsent: [
				SWADuplicationPartnerStub new
					crossRefKey: partnerKey
					loc: (aSWADuplicationData locForKey: partnerKey)].
			assoc key -> partnerNode]) asArray].
	dupLoaded := true.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWACodeTreemapMorph >> metaInfoString [
	"Per-view meta line for the code treemap. When a node is SELECTED, describe it
	(author / last changed / LOC); otherwise summarise the focused subtree
	(LOC / nodes / distinct authors). A coverage overlay, if any, is prefixed so
	the user always sees whether coverage data is shown, fresh, or running.
	(SWAPane content protocol.)"
	| base |
	base := selectedNode
		ifNotNil: [:n | self metaInfoStringForNode: n]
		ifNil: [self metaInfoStringForSubtree: (currentNode ifNil: [rootNode])].
	(coverageStatus isNil or: [coverageStatus isEmpty]) ifTrue: [^ base].
	^ '[', coverageStatus, ']   ', base
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:37'
}
SWACodeTreemapMorph >> metaInfoStringForNode: aNode [
	"Meta line for a single SELECTED node: kind, author, last-changed date, then the
	primary metric -- LOC normally, the COVERAGE metric (invocations / covering
	tests) under an overlay, or the source byte size (with doc/str/code split) in
	byte-composition mode -- and version churn. The coverage note is appended when
	an overlay is active."
	| author when whenStr cov metric comp |
	author := aNode lastAuthor ifNil: ['?'].
	when := aNode lastChanged.
	whenStr := when
		ifNil: ['?']
		ifNotNil: [:t | t asDate printString, ' ', (t asTime print24)].
	metric := coverageKind notNil
		ifTrue: [ | v |
			v := self coverageValueForNode: aNode.
			'   ', (v ifNil: ['0'] ifNotNil: [:x | x printString]), ' ', self coverageMetricLabel]
		ifFalse: [self byteCompositionMode
			ifTrue: [
				comp := aNode byteComposition.
				'   ', (comp first + (comp at: 2) + comp last) printString,
					' bytes (doc ', comp first printString,
					' / str ', (comp at: 2) printString,
					' / code ', comp last printString, ')']
			ifFalse: ['   ', aNode loc printString, ' LOC']].
	cov := self coverageNoteForNode: aNode.
	^ aNode kind asString, ' ', aNode name,
		'   author: ', author,
		'   changed: ', whenStr,
		metric,
		'   ', aNode changeCount printString, ' versions',
		' (', (aNode avgChangeCount asFloat printShowingDecimalPlaces: 1), '/method)',
		(cov isEmpty ifTrue: [''] ifFalse: ['   >> ', cov])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:01'
}
SWACodeTreemapMorph >> metaInfoStringForSubtree: aNode [
	"Meta line summarising a focused subtree: the primary metric (LOC normally, or
	the total COVERAGE weight + covered-method count when an overlay is active --
	LOC is not the point in a coverage view), node count, distinct authors, and
	version churn. The coverage totals are summed from the treemap's own overlay
	values, so they work for both the coverage-weighted openers and the Load/Cover
	buttons (which overlay onto an LOC-built tree)."
	| authors nodeCount covered totalWeight metric |
	aNode ifNil: [^ ''].
	authors := Set new.
	nodeCount := 0.
	covered := 0.
	totalWeight := 0.
	aNode withAllChildrenDo: [:n |
		nodeCount := nodeCount + 1.
		n lastAuthor ifNotNil: [:a | authors add: a].
		(coverageKind notNil and: [n kind == #method]) ifTrue: [
			(self coverageValueForNode: n) ifNotNil: [:v |
				v > 0 ifTrue: [covered := covered + 1. totalWeight := totalWeight + v]]]].
	metric := coverageKind notNil
		ifTrue: ['   ', totalWeight printString,
			' ', self coverageMetricLabel, '   ', covered printString, ' covered methods']
		ifFalse: ['   ', aNode loc printString, ' LOC'].
	^ aNode kind asString, ' ', aNode name,
		metric,
		'   ', nodeCount printString, ' nodes',
		'   ', authors size printString, ' authors',
		'   ', aNode changeCount printString, ' versions',
		' (', (aNode avgChangeCount asFloat printShowingDecimalPlaces: 1), '/method)'
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:50'
}
SWACodeTreemapMorph >> metricForMode: aSymbol [
	"The dataset METRIC a minted color/size symbol refers to, or nil if aSymbol is a
	legacy intrinsic mode (#loc, #duplication, ...)."
	^ self metricsByMode at: aSymbol ifAbsent: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:50'
}
SWACodeTreemapMorph >> metricsByMode [
	"Map of minted menu symbol (e.g. #coverage_1_call) -> SWADatasetMetric. One entry
	per metric of every loaded dataset; the symbol-based color/size machinery
	dispatches through this."
	^ metricsByMode ifNil: [metricsByMode := Dictionary new]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:12'
}
SWACodeTreemapMorph >> nodeForCrossRefKey: aKey orStubLoc: aLoc [
	"The in-tree node for a crossRefKey, or a lightweight SWADuplicationPartnerStub
	(carrying key + loc) when the partner is not on screen -- used by decoration link
	drawing so an off-tree partner still resolves (its link is dropped when no visible
	ancestor exists)."
	^ self keyIndex at: aKey ifAbsent: [
		SWADuplicationPartnerStub new crossRefKey: aKey loc: aLoc]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:24'
}
SWACodeTreemapMorph >> noteColorMode: aSymbol [
	"Record the active color mode WITHOUT re-dispatching its acquire/apply logic.
	Used by acquisition callbacks (e.g. coverage finished running) that have already
	applied the overlay and just need the menu tick to reflect the mode."
	colorMode := aSymbol
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWACodeTreemapMorph >> overlayClass [
	"The event/menu overlay class this view uses -- a view-policy hook so the
	SWAPane can (re)wire an overlay when morphing structures."
	^ SWACodeTreemapOverlay
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:31'
}
SWACodeTreemapMorph >> previewDuplicatePairFrom: fromKey to: toKey [
	"Browse a duplicate pair from a CONTAINER's aggregated list: show the inline diff of
	fromKey vs toKey in the source pane, and red-box the partner tile -- WITHOUT changing
	the primary selection, so the container stays selected and the duplicates list stays
	put (the clicked row just highlights). Resolve keys to nodes via the key index."
	| fromNode toNode |
	fromNode := self keyIndex at: fromKey ifAbsent: [nil].
	toNode := self keyIndex at: toKey ifAbsent: [nil].
	dupDiffFrom := fromNode.
	secondarySelection := toNode.   "partner = red box; no refresh yet"
	self refreshChrome
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:53'
}
SWACodeTreemapMorph >> provenanceListForSelection [
	"Mode-aware side pane. When a DUPLICATION decoration metric is active:
	 - a METHOD selection lists that method's near-duplicates ('NN%  partnerKey');
	 - ANY container selection (package/class/category) aggregates the near-duplicates of
	   ALL descendant methods ('NN%  fromMethod <-> partnerMethod'), best-first, TRUNCATED
	   to the top 50 with a '... N more' note.
	The method-vs-container split is by NODE KIND (SWACodeMethodNode), NOT by crossRefKey
	-- classes DO have a crossRefKey but are still containers whose methods we aggregate.
	Entries are  label -> navigateKey.

	When #topic color mode is active, list the selection's TOPIC MIXTURE instead
	('NN%  topWords', best-first). Otherwise fall back to coverage provenance."
	| metric node |
	self isTopicProvenanceActive ifTrue: [
		node := self selectedNode.
		node ifNil: [^ #()].
		^ self topicProvenanceListFor: node].
	metric := self decorationMetric.
	(metric notNil and: [metric supportsLinks]) ifTrue: [
		node := self selectedNode.
		node ifNil: [^ #()].
		(node isKindOf: SWACodeMethodNode)
			ifTrue: [
				"method selection: its own partners"
				^ (metric linksForKey: node crossRefKey) collect: [:assoc |
					(((assoc key * 100) rounded) printString, '%  ', assoc value) -> assoc value]]
			ifFalse: [^ self containerDuplicatesFor: node metric: metric]].
	^ super provenanceListForSelection
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:53'
}
SWACodeTreemapMorph >> provenanceListTitle [
	"Mode-aware side-pane title. Topic mode active -> the selection's topic label
	or topic-span count. Duplication metric active:
	 - a METHOD selection -> its near-duplicate count;
	 - ANY container (package/class/category) -> total near-duplicate PAIRS under the
	   subtree.
	Split by NODE KIND, not crossRefKey (classes have a key but are containers here)."
	| metric node |
	self isTopicProvenanceActive ifTrue: [
		^ self topicProvenanceTitleFor: self selectedNode].
	metric := self decorationMetric.
	(metric notNil and: [metric supportsLinks]) ifTrue: [
		node := self selectedNode.
		node ifNil: [^ 'Duplicates'].
		(node isKindOf: SWACodeMethodNode)
			ifTrue: [| n |
				n := (metric linksForKey: node crossRefKey) size.
				^ n = 0
					ifTrue: ['No near-duplicates']
					ifFalse: [n printString, ' near-duplicate', (n = 1 ifTrue: [''] ifFalse: ['s'])]]
			ifFalse: [| n |
				n := (self containerDuplicatePairCountFor: node metric: metric).
				^ n = 0
					ifTrue: ['No near-duplicates in subtree']
					ifFalse: [n printString, ' duplicate pair', (n = 1 ifTrue: [''] ifFalse: ['s']), ' in subtree']]].
	^ super provenanceListTitle
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:50'
}
SWACodeTreemapMorph >> removeDataset: aSWADataset [
	"Unload a dataset and all its metrics. If the active color or size mode belonged
	to it, fall back to an intrinsic default."
	self datasets remove: aSWADataset ifAbsent: [].
	(self metricsByMode values select: [:m | m dataset == aSWADataset]) do: [:m |
		m modeSymbol ifNotNil: [:sym |
			self metricsByMode removeKey: sym ifAbsent: [].
			colorMode == sym ifTrue: [self colorMode: #codeKind].
			(sizeMetric notNil and: [sizeMetric == m])
				ifTrue: [self weightMetric: #loc]]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWACodeTreemapMorph >> runInfoString [
	"Line 1 of the panel info area: GENERIC, whole-run info -- the coverage/tally
	overlay status (if any) followed by a summary of the focused subtree (LOC /
	nodes / authors / versions). Independent of the current selection, so it stays
	put while the user clicks around. (SWAPane content protocol.)"
	| base |
	base := self metaInfoStringForSubtree: (currentNode ifNil: [rootNode]).
	(coverageStatus isNil or: [coverageStatus isEmpty]) ifTrue: [^ base].
	^ '[', coverageStatus, ']   ', base
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapMorph >> selectDataset: aSWADatasetOrNil [
	"Top-level Data pick (exclusive): make aSWADataset the active data source and apply
	its FITTING DEFAULTS across every axis at once -- color, size, decoration -- from
	#defaultBindings. Axes not mentioned by the dataset are CLEARED (color -> #codeKind,
	size -> #loc, decoration -> none), so switching data sources gives a clean, fitting
	view. Each axis can still be overridden afterward from its own menu; the override
	persists until the next Data pick. nil clears back to the intrinsic view."
	| bindings |
	activeDataset := aSWADatasetOrNil.
	aSWADatasetOrNil isNil ifTrue: [
		self colorMode: #codeKind.
		self weightMetric: #loc.
		self decorationMetric: nil.
		^ self].
	bindings := aSWADatasetOrNil defaultBindings.
	"color"
	(bindings at: #color ifAbsent: [nil])
		ifNotNil: [:m | self colorMode: m modeSymbol]
		ifNil: [self colorMode: #codeKind].
	"size"
	(bindings at: #size ifAbsent: [nil])
		ifNotNil: [:m | self weightMetric: m modeSymbol]
		ifNil: [self weightMetric: #loc].
	"decoration"
	self decorationMetric: (bindings at: #decoration ifAbsent: [nil])
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:31'
}
SWACodeTreemapMorph >> selectedNode: aNodeOrNil [
	"Selecting a different primary node clears the secondary selection AND the
	container-browse diff-from, so the source pane reverts to plain source until the
	user picks a new partner. Set the ivar directly to avoid a double refresh -- super
	selectedNode: refreshes chrome."
	secondarySelection := nil.
	dupDiffFrom := nil.
	super selectedNode: aNodeOrNil
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:31'
}
SWACodeTreemapMorph >> selectedSourceString [
	"Source text for the Show pane. When a near-duplicate has been picked, show the
	INLINE DIFF between the two methods (styled removed/inserted lines, like the
	versions browser). The FROM side is #dupDiffFrom when browsing a CONTAINER's
	aggregated list (primary selection is the container), else the selected method.
	The partner (#dupDiffTarget) is the secondary selection. Otherwise plain source."
	| from target |
	target := self dupDiffTarget.
	from := dupDiffFrom ifNil: [self selectedNode].
	(target notNil
		and: [from notNil]
		and: [from isKindOf: SWACodeMethodNode]
		and: [target isKindOf: SWACodeMethodNode]) ifTrue: [
			| header diff |
			header := ('" ', from crossRefKey, '  (selected)', String cr,
				'  vs ', target crossRefKey, ' "', String cr, String cr) asText.
			diff := TextDiffBuilder
				buildDisplayPatchFrom: target sourceString
				to: from sourceString.
			^ header, diff].
	^ super selectedSourceString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWACodeTreemapMorph >> selectionInfoString [
	"Line 2 of the panel info area: info about the CURRENTLY SELECTED node only
	(author / last changed / LOC / versions + any coverage value), or '' when
	nothing is selected. (SWAPane content protocol.)"
	^ selectedNode
		ifNil: ['']
		ifNotNil: [:n | self metaInfoStringForNode: n]
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:28'
}
SWACodeTreemapMorph >> selectionIsMethodForDiff [
	"True when the current selection is a METHOD, so a duplicates-pane click should DIFF
	against the picked partner (rather than navigate, which is what a container's
	aggregated list does)."
	^ self selectedNode notNil and: [self selectedNode isKindOf: SWACodeMethodNode]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapMorph >> setDataMode: aSymbol [
	"Data-menu entry point: pick the active data source by its symbol (#none clears),
	applying its fitting defaults across the axes."
	self selectDataset: (self datasetForDataMode: aSymbol)
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWACodeTreemapMorph >> setDecorationMode: aSymbol [
	"Menu entry point for the Links/decoration axis: #none clears, else bind to the
	link-capable metric that symbol names."
	self decorationMetric: (self decorationMetricForMode: aSymbol)
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:24'
}
SWACodeTreemapMorph >> testProvenanceNoteForNode: aNode [
	"For a selected executed test method / TestCase class under a provenance
	overlay: report how many methods it covers (the green-highlighted set)."
	| key methods |
	key := aNode crossRefKey.
	methods := coverageData methodsForTestOrClass: key.
	^ (aNode kind == #method ifTrue: ['test '] ifFalse: ['TestCase ']),
		'covers ', methods size printString, ' method',
		(methods size = 1 ifTrue: [''] ifFalse: ['s']),
		' (shown in green)'
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:42'
}
SWACodeTreemapMorph >> topicDataOrNil [
	"The SWATopicData in effect for this map (inherited from the root node), or nil."
	^ rootNode ifNil: [nil] ifNotNil: [rootNode topicData]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:53'
}
SWACodeTreemapMorph >> topicProvenanceListFor: aNode [
	"The topic-mixture rows for a selection in #topic mode: one entry per topic
	present in the node's (rolled-up) distribution, best-first, as
	  'NN%  w1 w2 w3 ...'  ->  navigateKey.
	The navigate key is the node's own crossRefKey (clicking re-selects it; topics
	aren't separately navigable), so container rows stay inert-but-harmless."
	| td dist total sorted navKey |
	td := self topicDataOrNil.
	td ifNil: [^ #()].
	dist := aNode topicDistribution.
	dist isEmpty ifTrue: [^ #()].
	total := dist values inject: 0.0 into: [:s :v | s + v].
	total <= 0 ifTrue: [^ #()].
	navKey := aNode crossRefKey ifNil: [''].
	sorted := dist associations asSortedCollection: [:a :b | a value >= b value].
	^ (sorted collect: [:assoc |
		| pct label |
		pct := (assoc value / total * 100) rounded.
		label := pct printString, '%  ', (td labelForTopic: assoc key).
		label -> navKey]) asArray
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:53'
}
SWACodeTreemapMorph >> topicProvenanceTitleFor: aNode [
	"Side-pane heading in #topic mode: for a METHOD leaf, its dominant topic label;
	for a CONTAINER, how many topics its subtree spans."
	| dist |
	aNode ifNil: [^ 'Topics'].
	dist := aNode topicDistribution.
	dist isEmpty ifTrue: [^ 'No topic (method pruned or no data)'].
	(aNode isKindOf: SWACodeMethodNode) ifTrue: [
		^ 'Topic: ', (self topicDataOrNil labelForTopic: aNode dominantTopic)].
	^ 'Topic mix (', dist size printString, ' topics in subtree)'
]

{
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeTreemapMorph >> weightMetric [
	"The active size metric symbol (single source of truth for the Size menu tick).
	When a loaded dataset metric drives size, answer ITS minted symbol; otherwise the
	root's intrinsic metric."
	sizeMetric ifNotNil: [^ sizeMetric modeSymbol].
	^ rootNode ifNil: [#loc] ifNotNil: [rootNode weightMetric]
]

{
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeTreemapMorph >> weightMetric: aSymbol [
	"Live-switch the tile SIZE metric (the 'Size' menu). Two families:
	  - INTRINSIC symbols (#loc/#methods/#bytes/#invocations/#tests) go to the root's
	    #setWeightMetric:;
	  - a minted DATASET-METRIC symbol (#coverage_1_call, ...) resolves to its
	    SWADatasetMetric and binds size to it via the root's #setSizeMetric:.
	Either way we flush rollups, relayout, and redraw keeping zoom + selection --
	the relayout counterpart to #colorMode:'s instant recolor."
	| sel metric |
	rootNode ifNil: [^ self].
	sel := selectedNode.
	metric := self metricForMode: aSymbol.
	metric isNil
		ifTrue: [sizeMetric := nil. rootNode setWeightMetric: aSymbol]
		ifFalse: [sizeMetric := metric. rootNode setSizeMetric: metric].
	layoutValid := false.
	self ensureLayout.
	cachedForm := nil.
	selectedNode := sel.
	self refreshChrome.
	self changed
]
