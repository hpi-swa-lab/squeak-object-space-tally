"
A squarified treemap of a SWACodeNode tree (Package -> Class -> Category -> Method). Tiles are sized by LOC. Overrides the SpaceTally morph's byte-oriented labels/balloon/coloring with code-oriented ones (LOC counts, color by node kind). Nodes are duck-typed to the treemap protocol.
"
Class {
	#name : #SWACodeTreemapMorph,
	#superclass : #SWATreemapMorph,
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:24'
}
SWACodeTreemapMorph >> colorByRecency: aNode [
	"Recency heat: recently-changed = bright blue, old = gray. Based on days since
	lastChanged (rolled up to max over the subtree)."
	| when days t |
	when := aNode lastChanged.
	when isNil ifTrue: [^ Color gray: 0.5].
	days := (DateAndTime now - when) days.
	"0 days -> t=1 (bright), ~2 years -> t=0 (gray)"
	t := (1.0 - (days / 730.0)) max: 0.0.
	^ Color h: 210 s: 0.65 * t v: 0.55 + (0.3 * t)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:29'
}
SWACodeTreemapMorph >> colorForNode: aNode [
	"Dispatch on the active color mode."
	colorMode == #loc ifTrue: [^ self colorByLoc: aNode].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
	^ self colorByKind: aNode
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 17:27'
}
SWACodeTreemapMorph >> metaInfoString [
	"Per-view meta line for the code treemap. When a node is SELECTED, describe it
	(author / last changed / LOC); otherwise summarise the focused subtree
	(LOC / nodes / distinct authors). (SWANavPanel content protocol.)"
	selectedNode ifNotNil: [:n | ^ self metaInfoStringForNode: n].
	^ self metaInfoStringForSubtree: (currentNode ifNil: [rootNode])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 17:27'
}
SWACodeTreemapMorph >> metaInfoStringForNode: aNode [
	"Meta line for a single SELECTED node: kind, author, last-changed date, LOC."
	| author when whenStr |
	author := aNode lastAuthor ifNil: ['?'].
	when := aNode lastChanged.
	whenStr := when
		ifNil: ['?']
		ifNotNil: [:t | t asDate printString, ' ', (t asTime print24)].
	^ aNode kind asString, ' ', aNode name,
		'   author: ', author,
		'   changed: ', whenStr,
		'   ', aNode loc printString, ' LOC'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 17:27'
}
SWACodeTreemapMorph >> metaInfoStringForSubtree: aNode [
	"Meta line summarising a focused subtree: LOC, node count, distinct authors."
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
		'   ', authors size printString, ' authors'
]
