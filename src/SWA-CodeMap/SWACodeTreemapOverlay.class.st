"
Interaction overlay for SWACodeTreemapMorph. Context menu offers browse, and (for method tiles) senders/implementors; no other-parent decorations since code nodes form a strict tree.
"
Class {
	#name : #SWACodeTreemapOverlay,
	#superclass : #SWATreemapOverlay,
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:51'
}
SWACodeTreemapOverlay >> aaCanvasFrom: aCanvas [
	"Return an anti-aliased BalloonCanvas sharing aCanvas's form/origin/clip, so the
	duplication links draw smooth instead of jaggy. Falls back to aCanvas itself if
	it cannot produce one (e.g. a non-FormCanvas, or a <8-bit form where aaLevel is
	a no-op). The returned canvas uses the SAME point convention as aCanvas (origin
	is preserved by asBalloonCanvas), so callers pass the same coordinates."
	(aCanvas respondsTo: #asBalloonCanvas) ifFalse: [^ aCanvas].
	^ [| bc |
		bc := aCanvas asBalloonCanvas.
		bc aaLevel: 4.
		bc] on: Error do: [:e | aCanvas]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> addMenuItems: menu for: aNode [
	"Code context-menu items: browse the element; for method tiles also offer
	senders/implementors. Plus inspect/explore the node itself."
	menu add: 'browse' selector: #browseNode: argument: aNode.
	aNode kind = #method ifTrue: [
		menu add: 'senders' selector: #browseSenders: argument: aNode.
		menu add: 'implementors' selector: #browseImplementors: argument: aNode].
	menu addLine.
	menu add: 'inspect node' selector: #inspectObject: argument: aNode.
	menu add: 'explore node' selector: #exploreObject: argument: aNode
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseImplementors: aMethodNode [
	SystemNavigation default browseAllImplementorsOf: aMethodNode subject selector
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseNode: aNode [
	aNode browse
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseSenders: aMethodNode [
	SystemNavigation default browseAllCallsOn: aMethodNode subject selector
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:23'
}
SWACodeTreemapOverlay >> colorModeOptions [
	^ #(
		(#codeKind         'By kind (package/class/category/method)')
		(#byteComposition  'By byte composition (doc/string/code bar)')
		(#loc              'By LOC (heat)')
		(#avgloc           'By avg LOC / method')
		(#versions         'By avg versions / method')
		(#recency          'By recency (last changed)')
		(#author           'By author (last changed)')
		(#duplication      'By duplication (Jaccard clone heat)')
	)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:51'
}
SWACodeTreemapOverlay >> drawAllDuplicationLinksOn: aCanvas origin: origin [
	"Overview pass: for every rendered method tile, draw a link to each of its
	near-duplicate partners (resolved to the nearest visible ancestor tile if the
	partner itself is collapsed). Each unordered pair is drawn once. COLOR follows
	the Jaccard score (red = strongest %); WIDTH follows the shared-LOC impact
	(heavy = many duplicated lines). Lines are drawn anti-aliased, by ascending
	shared-LOC so the highest-impact links sit on top."
	| links seen aaCanvas |
	links := OrderedCollection new.
	seen := Set new.
	treemapMorph tiles do: [:assoc |
		| node fromR |
		node := assoc key.
		fromR := assoc value.
		(node isKindOf: SWACodeMethodNode) ifTrue: [
			(treemapMorph dupMatchesForNode: node) do: [:m |
				| score partner pairKey target r sharedLoc |
				score := m key.
				partner := m value.
				pairKey := (node crossRefKey <= partner crossRefKey)
					ifTrue: [node crossRefKey, '|', partner crossRefKey]
					ifFalse: [partner crossRefKey, '|', node crossRefKey].
				(seen includes: pairKey) ifFalse: [
					seen add: pairKey.
					sharedLoc := treemapMorph dupSharedLocBetween: node and: partner.
					target := partner.
					r := treemapMorph rectForNode: target.
					[r isNil and: [target notNil and: [target parent notNil]]] whileTrue: [
						target := target parent.
						r := treemapMorph rectForNode: target].
					(r notNil and: [target ~~ node]) ifTrue: [
						links add: { score. fromR center + origin. r center + origin. sharedLoc }]]]]].
	"highest impact last = on top"
	links := links asSortedCollection: [:a :b | (a at: 4) <= (b at: 4)].
	aaCanvas := self aaCanvasFrom: aCanvas.
	links do: [:lk |
		aaCanvas
			line: (lk at: 2)
			to: (lk at: 3)
			width: (self dupLineWidthForSharedLoc: (lk at: 4))
			color: (self dupLineColorForScore: (lk first))].
	aaCanvas == aCanvas ifFalse: [aaCanvas flush]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:51'
}
SWACodeTreemapOverlay >> drawExtraHighlightsFor: selectedNode on: aCanvas origin: origin [
	"In #duplication color mode, draw a line from the selected method tile to each
	of its near-duplicate partner tiles (cf. SpaceTally's other-parent lines). Line
	COLOR is the Jaccard score on a yellow->red ramp (red = strongest %), while line
	WIDTH is the SHARED-LOC impact (heavy = many duplicated lines), so a big copied
	method stands out over a trivial high-% accessor match. Lines are drawn
	anti-aliased. If a partner tile is too small to be rendered, draw to its nearest
	visible ancestor instead."
	| selectedCenter aaCanvas |
	treemapMorph colorMode == #duplication ifFalse: [^ self].
	(selectedNode isKindOf: SWACodeMethodNode) ifFalse: [^ self].
	hoveredTile ifNil: [^ self].
	selectedCenter := (hoveredTile value translateBy: origin) center.
	aaCanvas := self aaCanvasFrom: aCanvas.
	(treemapMorph dupMatchesForNode: selectedNode) do: [:assoc |
		| score partner target r screenR sharedLoc |
		score := assoc key.
		partner := assoc value.
		sharedLoc := treemapMorph dupSharedLocBetween: selectedNode and: partner.
		target := partner.
		r := treemapMorph rectForNode: target.
		[r isNil and: [target notNil and: [target parent notNil]]] whileTrue: [
			target := target parent.
			r := treemapMorph rectForNode: target].
		(r notNil and: [target ~~ selectedNode]) ifTrue: [
			screenR := r translateBy: origin.
			aaCanvas
				line: selectedCenter
				to: screenR center
				width: (self dupLineWidthForSharedLoc: sharedLoc)
				color: (self dupLineColorForScore: score)]].
	aaCanvas == aCanvas ifFalse: [aaCanvas flush]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:42'
}
SWACodeTreemapOverlay >> drawOn: aCanvas [
	"When in #duplication mode with NOTHING selected, draw an OVERVIEW: every
	duplication link across the whole map at once (so the global clone structure is
	visible without clicking). Otherwise defer to the standard behavior (selected
	tile + ancestor borders + per-selection links)."
	(treemapMorph colorMode == #duplication and: [hoveredTile isNil])
		ifTrue: [^ self drawAllDuplicationLinksOn: aCanvas origin: self position].
	super drawOn: aCanvas
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:38'
}
SWACodeTreemapOverlay >> dupLineColorForScore: score [
	"Line color for a duplication link: yellow (weak, 0.5) -> red (exact, 1.0),
	matching the tile heat ramp. Stronger duplicates are redder and more opaque."
	| t hue alpha |
	t := (((score - 0.5) / 0.5) max: 0.0) min: 1.0.
	hue := 60 * (1.0 - t).               "60=yellow .. 0=red"
	alpha := 0.55 + (t * 0.4).            "fainter for weak matches"
	^ (Color h: hue s: 0.9 v: 1.0) alpha: alpha
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:38'
}
SWACodeTreemapOverlay >> dupLineWidthForScore: score [
	"Line width for a duplication link: 1px at the floor (0.5) up to ~5px for an
	exact duplicate (1.0), so the strongest matches read as the thickest lines."
	| t |
	t := (((score - 0.5) / 0.5) max: 0.0) min: 1.0.
	^ (1 + (t * 4)) rounded max: 1
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 11:46'
}
SWACodeTreemapOverlay >> dupLineWidthForSharedLoc: sharedLoc [
	"Line width encodes the IMPACT of a clone -- the number of duplicated lines --
	NOT the percentage. A 1-2 line shared fragment draws thin (1px); a large
	copied method (~30+ shared lines) draws heavy (~8px), on a log scale so the
	range stays readable. This way many near-identical one-liner accessors no longer
	look as important as a genuinely copied 40-line method."
	| t |
	sharedLoc <= 1 ifTrue: [^ 1].
	"log scale: ~1 line -> 1px, ~32+ lines -> ~8px"
	t := (sharedLoc ln / 32 ln) min: 1.0.
	^ (1 + (t * 7)) rounded max: 1
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:12'
}
SWACodeTreemapOverlay >> sizeModeOptions [
	"Live tile-SIZE (weight) metrics for the Code Map. The two DYNAMIC metrics --
	invocation count and covering-test count -- come from a loaded profile/coverage
	data set (st-spy / SUnit coverage), so they are only offered when such data is
	present."
	| opts |
	opts := OrderedCollection withAll: #(
		(#methods   'Number of methods')
		(#loc       'Lines of code')
		(#bytes     'Source byte size')).
	(treemapMorph respondsTo: #coverageData) ifTrue: [
		treemapMorph coverageData ifNotNil: [
			opts add: #(#invocations 'Execution: call count');
				add: #(#tests 'Execution: covering tests')]].
	^ opts asArray
]
