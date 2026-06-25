"
A squarified treemap of a SWACodeNode tree (Package -> Class -> Category -> Method). Tiles are sized by LOC. Overrides the SpaceTally morph's byte-oriented labels/balloon/coloring with code-oriented ones (LOC counts, color by node kind). Nodes are duck-typed to the treemap protocol.
"
Class {
	#name : #SWACodeTreemapMorph,
	#superclass : #SWATreemapMorph,
	#instVars : [
		'coverageStatus'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:05'
}
SWACodeTreemapMorph >> balloonStringFor: aNode [
	| kids |
	kids := aNode children ifNil: [#()].
	^ String streamContents: [:s |
		s nextPutAll: aNode name asString; cr.
		s nextPutAll: 'kind:  '; nextPutAll: aNode kind asString; cr.
		s nextPutAll: 'LOC:   '; print: aNode loc; cr.
		s nextPutAll: 'comments: '; print: aNode commentLines; cr.
		s nextPutAll: 'kids:  '; print: kids size; cr.
		aNode lastChanged ifNotNil: [:t |
			s nextPutAll: 'changed: '; nextPutAll: t asDate yyyymmdd; cr].
		s nextPutAll: 'path:  '; nextPutAll: aNode pathString]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:36'
}
SWACodeTreemapMorph >> baseColorForNode: aNode [
	"Dispatch on the active color mode."
	colorMode == #loc ifTrue: [^ self colorByLoc: aNode].
	colorMode == #avgloc ifTrue: [^ self colorByAvgLoc: aNode].
	colorMode == #versions ifTrue: [^ self colorByVersions: aNode].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
	^ self colorByKind: aNode
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
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapMorph >> colorByKind: aNode [
	"Color by node kind (package/class/category/method), darkened with depth.
	Static (class-side) methods get a distinct purple."
	| base depth |
	depth := aNode depth.
	base := aNode kind = #package ifTrue: [Color h: 210 s: 0.45 v: 0.8]
		ifFalse: [aNode kind = #class ifTrue: [Color h: 130 s: 0.45 v: 0.78]
		ifFalse: [aNode kind = #category ifTrue: [Color h: 45 s: 0.5 v: 0.82]
		ifFalse: [aNode isStatic
			ifTrue: [Color h: 280 s: 0.4 v: 0.8]
			ifFalse: [Color h: 0 s: 0.0 v: 0.92]]]].
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:06'
}
SWACodeTreemapMorph >> exploreNode: aNode [
	"Browse the live code element behind the tile instead of exploring the node."
	aNode browse
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWACodeTreemapMorph >> formatWeight: aNumber [
	"Code treemap weights are lines of code."
	^ aNumber printString, ' LOC'
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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:05'
}
SWACodeTreemapMorph >> labelFor: aNode inWidth: maxPixels [
	"Short label: node name, plus LOC when there is room."
	| name |
	maxPixels < 16 ifTrue: [^ nil].
	name := aNode name ifNil: ['?'].
	maxPixels < 80 ifTrue: [^ name].
	^ name, '  ', aNode loc printString, ' LOC'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWACodeTreemapMorph >> metaInfoString [
	"Per-view meta line for the code treemap. When a node is SELECTED, describe it
	(author / last changed / LOC); otherwise summarise the focused subtree
	(LOC / nodes / distinct authors). A coverage overlay, if any, is prefixed so
	the user always sees whether coverage data is shown, fresh, or running.
	(SWANavPanel content protocol.)"
	| base |
	base := selectedNode
		ifNotNil: [:n | self metaInfoStringForNode: n]
		ifNil: [self metaInfoStringForSubtree: (currentNode ifNil: [rootNode])].
	(coverageStatus isNil or: [coverageStatus isEmpty]) ifTrue: [^ base].
	^ '[', coverageStatus, ']   ', base
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWACodeTreemapMorph >> metaInfoStringForNode: aNode [
	"Meta line for a single SELECTED node: kind, author, last-changed date, LOC,
	and version churn (total versions over the subtree + average per method). When
	a coverage/tally overlay is active, the node's coverage value is appended."
	| author when whenStr cov |
	author := aNode lastAuthor ifNil: ['?'].
	when := aNode lastChanged.
	whenStr := when
		ifNil: ['?']
		ifNotNil: [:t | t asDate printString, ' ', (t asTime print24)].
	cov := self coverageNoteForNode: aNode.
	^ aNode kind asString, ' ', aNode name,
		'   author: ', author,
		'   changed: ', whenStr,
		'   ', aNode loc printString, ' LOC',
		'   ', aNode changeCount printString, ' versions',
		' (', (aNode avgChangeCount asFloat printShowingDecimalPlaces: 1), '/method)',
		(cov isEmpty ifTrue: [''] ifFalse: ['   >> ', cov])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:46'
}
SWACodeTreemapMorph >> metaInfoStringForSubtree: aNode [
	"Meta line summarising a focused subtree: LOC, node count, distinct authors,
	and version churn (total versions + average per method)."
	| authors nodeCount |
	aNode ifNil: [^ ''].
	authors := Set new.
	nodeCount := 0.
	aNode withAllChildrenDo: [:n |
		nodeCount := nodeCount + 1.
		n lastAuthor ifNotNil: [:a | authors add: a]].
	^ aNode kind asString, ' ', aNode name,
		'   ', aNode loc printString, ' LOC',
		'   ', nodeCount printString, ' nodes',
		'   ', authors size printString, ' authors',
		'   ', aNode changeCount printString, ' versions',
		' (', (aNode avgChangeCount asFloat printShowingDecimalPlaces: 1), '/method)'
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
