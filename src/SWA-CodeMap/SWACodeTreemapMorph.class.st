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
		'dupDiffTarget'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:06'
}
SWACodeTreemapMorph >> aboutToStyle: aStyler [
	"Suppress Shout syntax styling while an inline DIFF is shown (otherwise the
	styler would repaint over TextDiffBuilder's removed/inserted-line colors).
	Otherwise behave exactly like the superclass."
	dupDiffTarget notNil ifTrue: [^ false].
	^ super aboutToStyle: aStyler
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:23'
}
SWACodeTreemapMorph >> baseColorForNode: aNode [
	"Dispatch on the active color mode."
	colorMode == #loc ifTrue: [^ self colorByLoc: aNode].
	colorMode == #avgloc ifTrue: [^ self colorByAvgLoc: aNode].
	colorMode == #versions ifTrue: [^ self colorByVersions: aNode].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
	colorMode == #duplication ifTrue: [^ self colorByDuplication: aNode].
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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:34'
}
SWACodeTreemapMorph >> colorMode: aSymbol [
	"Override to (re)compute the Jaccard duplication scores when entering
	#duplication mode, before the superclass triggers a re-render. Also refresh the
	nav-panel chrome so the details box and the side pane immediately reflect the
	new mode for the current selection (super only flushes the tile cache)."
	aSymbol == #duplication ifTrue: [self computeDuplicationScores].
	super colorMode: aSymbol.
	self refreshChrome
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:45'
}
SWACodeTreemapMorph >> computeDuplicationScores [
	"Build the per-method duplication cache. For every NON-TRIVIAL method leaf in
	the map (>= dupMinLoc non-blank lines -- this excludes one-liner accessors,
	which are near-identical by nature and would otherwise dominate the picture) we
	store, keyed by crossRefKey, an Array of  score -> partnerNode  associations for
	every OTHER eligible method whose Jaccard similarity is >= dupListFloor, sorted
	by descending score (first = best match). Coloring uses the first (max) score;
	the side pane lists them all; link WIDTH uses the shared-LOC estimate (see
	dupSharedLocBetween:and:), not the raw ratio. Shingles are computed once per
	eligible method (O(n)); the pairwise pass is O(n^2)."
	| sim leaves shingles floor minLoc |
	sim := self dupSimilarity.
	floor := self dupListFloor.
	minLoc := self dupMinLoc.
	leaves := OrderedCollection new.
	self collectMethodLeavesFrom: currentNode into: leaves.
	"Accessor exception: drop trivial methods before we even compare."
	leaves := leaves reject: [:n | n loc < minLoc].
	leaves := leaves asArray.
	dupScores := Dictionary new.
	shingles := leaves collect: [:n | sim shinglesFor: n sourceString].
	1 to: leaves size do: [:i |
		| si matches |
		si := shingles at: i.
		matches := OrderedCollection new.
		si isEmpty ifFalse: [
			1 to: leaves size do: [:j |
				i = j ifFalse: [
					| sc |
					sc := (sim jaccardBetween: si and: (shingles at: j)) asFloat.
					sc >= floor ifTrue: [matches add: sc -> (leaves at: j)]]]].
		matches := matches asSortedCollection: [:a :b | a key >= b key].
		dupScores at: (leaves at: i) crossRefKey put: matches asArray]
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:34'
}
SWACodeTreemapMorph >> detailInfoString [
	"Multi-line details for the Show-mode details box BESIDE the source (one
	'label: value' per line). EXCLUDES the covered-methods/tests provenance (that
	has its own pane). When a coverage overlay is active, leads with the coverage
	METRIC (invocations / covering tests) and DROPS the LOC line. In
	byte-composition mode, leads with the source byte size and its doc/string/code
	split. In #duplication mode, leads with the Jaccard duplication score and the
	best-matching method. '' when nothing is selected. (SWANavPanel content
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:59'
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:05'
}
SWACodeTreemapMorph >> dupDiffTarget [
	"The near-duplicate method node the source pane is currently diffing the
	selection AGAINST, or nil for a plain source view."
	^ dupDiffTarget
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:05'
}
SWACodeTreemapMorph >> dupDiffTarget: aMethodNodeOrNil [
	"Set the partner method to diff the current selection against (from a click in
	the duplicates side pane) and refresh the source pane so it shows the inline
	diff. Refreshing chrome re-pulls #selectedSourceString, which now returns the
	diff Text."
	dupDiffTarget := aMethodNodeOrNil.
	self refreshChrome
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
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> provenanceListForSelection [
	"Mode-aware side pane. In #duplication mode the corner pane lists the selected
	method's near-duplicates as  'NN%  Class>>selector' -> crossRefKey  (clickable
	to navigate). In every other mode fall back to the coverage provenance."
	colorMode == #duplication ifTrue: [
		| node |
		node := self selectedNode.
		(node isNil or: [(node isKindOf: SWACodeMethodNode) not]) ifTrue: [^ #()].
		^ (self dupMatchesForNode: node) collect: [:assoc |
			| pct partner |
			pct := (assoc key * 100) rounded.
			partner := assoc value.
			(pct printString, '%  ', partner crossRefKey) -> partner crossRefKey]].
	^ super provenanceListForSelection
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:33'
}
SWACodeTreemapMorph >> provenanceListTitle [
	"Mode-aware title for the side pane."
	colorMode == #duplication ifTrue: [
		| node n |
		node := self selectedNode.
		(node isNil or: [(node isKindOf: SWACodeMethodNode) not])
			ifTrue: [^ 'Duplicates'].
		n := (self dupMatchesForNode: node) size.
		^ n = 0
			ifTrue: ['No near-duplicates']
			ifFalse: [n printString, ' near-duplicate', (n = 1 ifTrue: [''] ifFalse: ['s'])]].
	^ super provenanceListTitle
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
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:06'
}
SWACodeTreemapMorph >> selectedNode: aNodeOrNil [
	"Selecting a different node clears any active duplication diff target, so the
	source pane reverts to plain source until the user picks a new partner from the
	duplicates pane."
	dupDiffTarget := nil.
	super selectedNode: aNodeOrNil
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:06'
}
SWACodeTreemapMorph >> selectedSourceString [
	"Source text for the Show pane. In #duplication mode, when a near-duplicate has
	been picked in the side pane (#dupDiffTarget), show the INLINE DIFF between the
	selected method and that partner -- the same styled removed/inserted-line view
	the versions browser uses (via TextDiffBuilder). A 2-line header names the two
	methods. Otherwise fall back to the plain selected-method source."
	| sel |
	sel := self selectedNode.
	(dupDiffTarget notNil
		and: [sel notNil]
		and: [sel isKindOf: SWACodeMethodNode]
		and: [dupDiffTarget isKindOf: SWACodeMethodNode]) ifTrue: [
			| header diff |
			header := ('" ', sel crossRefKey, '  (selected)', String cr,
				'  vs ', dupDiffTarget crossRefKey, ' "', String cr, String cr) asText.
			diff := TextDiffBuilder
				buildDisplayPatchFrom: dupDiffTarget sourceString
				to: sel sourceString.
			^ header, diff].
	^ super selectedSourceString
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
