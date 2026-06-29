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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:03'
}
SWACodeTreemapMorph >> baseColorForNode: aNode [
	"Dispatch on the active color mode."
	colorMode == #loc ifTrue: [^ self colorByLoc: aNode].
	colorMode == #avgloc ifTrue: [^ self colorByAvgLoc: aNode].
	colorMode == #versions ifTrue: [^ self colorByVersions: aNode].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:37'
}
SWACodeTreemapMorph >> detailInfoString [
	"Multi-line details for the Show-mode details box BESIDE the source (one
	'label: value' per line). EXCLUDES the covered-methods/tests provenance (that
	has its own pane). When a coverage overlay is active, leads with the coverage
	METRIC (invocations / covering tests) and DROPS the LOC line. In
	byte-composition mode, leads with the source byte size and its doc/string/code
	split. '' when nothing is selected. (SWANavPanel content protocol.)"
	| n when whenStr cov comp |
	n := selectedNode ifNil: [^ ''].
	when := n lastChanged.
	whenStr := when
		ifNil: ['?']
		ifNotNil: [:t | t asDate printString, ' ', (t asTime print24)].
	cov := self coverageValueForNode: n.
	^ String streamContents: [:s |
		s nextPutAll: n kind asString; nextPutAll: ': '; nextPutAll: n name; cr.
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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:36'
}
SWACodeTreemapMorph >> drawTileContent: aNode in: screenR on: aCanvas [
	"Extra per-tile content painted over the fill, before frame/label.

	BYTE-COMPOSITION mode (#byteCompositionMode): paint the doc/string/code
	proportional bar (#drawByteCompositionBar:in:on:) on EVERY tile -- both method
	leaves (their own analysis) and aggregates (rolled up) -- then return. This is
	the new, additive mode and is independent of the coverage overlay.

	Otherwise, under a loaded COVERAGE overlay, paint a horizontal proportional bar
	across an AGGREGATE tile, left to right:
	  GRAY untouched, GREEN covered, RED evicted, BLUE test.
	The segments sum to 100% of the width (sized by share of leaf-method
	descendants). When a selection FILTER is active, each coloured class is split
	into a bright sub-segment (filter match) and a DIMMED one (filtered out).
	Pixel-fill only -- no extra morphs, no layout change. Leaf tiles fall through to
	#colorForNode:'s solid colour (proportions answers nil).

	To avoid DOUBLE representation, a node whose RENDERED children are also aggregates
	(#hasRenderedAggregateChildrenUnder:) draws its bar DESATURATED, so the crisp
	bars are the most-detailed VISIBLE level."
	| props total gray x segs drawnSoFar fade mix dim |
	self byteCompositionMode ifTrue: [
		^ self drawByteCompositionBar: aNode in: screenR on: aCanvas].
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
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:05'
}
SWACodeTreemapMorph >> initialize [
	super initialize.
	colorMode := #codeKind
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWACodeTreemapMorph >> runInfoString [
	"Line 1 of the panel info area: GENERIC, whole-run info -- the coverage/tally
	overlay status (if any) followed by a summary of the focused subtree (LOC /
	nodes / authors / versions). Independent of the current selection, so it stays
	put while the user clicks around. (SWANavPanel content protocol.)"
	| base |
	base := self metaInfoStringForSubtree: (currentNode ifNil: [rootNode]).
	(coverageStatus isNil or: [coverageStatus isEmpty]) ifTrue: [^ base].
	^ '[', coverageStatus, ']   ', base
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWACodeTreemapMorph >> selectionInfoString [
	"Line 2 of the panel info area: info about the CURRENTLY SELECTED node only
	(author / last changed / LOC / versions + any coverage value), or '' when
	nothing is selected. (SWANavPanel content protocol.)"
	^ selectedNode
		ifNil: ['']
		ifNotNil: [:n | self metaInfoStringForNode: n]
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
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:02'
}
SWACodeTreemapMorph >> weightMetric [
	"The active size metric, read from the root node (single source of truth)."
	^ rootNode ifNil: [#loc] ifNotNil: [rootNode weightMetric]
]

{
	#category : #'byte-composition',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:03'
}
SWACodeTreemapMorph >> weightMetric: aSymbol [
	"Live-switch the tile SIZE metric (the 'Size' context menu). Sets it on the root
	(flushing the metric-dependent roll-ups across the built tree), invalidates the
	layout, and re-lays-out + redraws keeping the current zoom and selection. This
	is the relayout counterpart to #colorMode:'s instant recolor."
	| sel |
	rootNode ifNil: [^ self].
	sel := selectedNode.
	rootNode setWeightMetric: aSymbol.
	layoutValid := false.
	self ensureLayout.
	cachedForm := nil.
	selectedNode := sel.
	self refreshChrome.
	self changed
]
