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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:52'
}
SWACodeTreemapOverlay >> drawExtraHighlightsFor: hoveredNode on: aCanvas origin: origin [
	"No-op: duplication clone links are NOT drawn from this hover hook (which fires
	with the hovered node). They are drawn selection-driven from #drawOn: via
	#drawSelectionDuplicationLinksOn:origin:, so hovering never changes them."
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:56'
}
SWACodeTreemapOverlay >> drawOn: aCanvas [
	"Standard hover highlight (white border + ancestor borders) follows the mouse via
	super. In #duplication mode we additionally draw a PERSISTENT selection border
	and the clone links from the CLICK-SELECTION, independent of hover:
	  - a method is selected -> persistent white/ancestor border + lines to its
	    near-duplicates (these survive the mouse leaving the canvas),
	  - nothing selected      -> the whole-map OVERVIEW of all duplication links.
	Hovering never changes the selection or which links are shown."
	| origin sel |
	super drawOn: aCanvas.
	treemapMorph colorMode == #duplication ifFalse: [^ self].
	origin := self position.
	sel := treemapMorph selectedNode.
	(sel isKindOf: SWACodeMethodNode)
		ifTrue: [
			self drawSelectionBorderFor: sel on: aCanvas origin: origin.
			self drawSelectionDuplicationLinksOn: aCanvas origin: origin]
		ifFalse: [self drawAllDuplicationLinksOn: aCanvas origin: origin]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:56'
}
SWACodeTreemapOverlay >> drawSelectionBorderFor: aNode on: aCanvas origin: origin [
	"Draw the white selected-tile border + fading cyan ancestor borders for aNode
	(the CLICK selection), so the selection stays visible even after the mouse
	leaves the canvas and #hoveredTile is cleared. Mirrors the base #drawOn: border
	logic but sourced from the persistent selection rather than hover."
	| selRect node alpha r parentColor screenR |
	aNode ifNil: [^ self].
	selRect := treemapMorph rectForNode: aNode.
	selRect ifNil: [^ self].
	aCanvas frameRectangle: (selRect translateBy: origin) width: 2 color: Color white.
	node := aNode parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil]] whileTrue: [
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			parentColor := Color cyan alpha: alpha.
			screenR := r translateBy: origin.
			aCanvas frameRectangle: screenR width: 2 color: parentColor].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:52'
}
SWACodeTreemapOverlay >> drawSelectionDuplicationLinksOn: aCanvas origin: origin [
	"Draw lines from the CLICK-SELECTED method tile to each of its near-duplicate
	partner tiles. Driven by the treemap's #selectedNode, NOT by hover. Line COLOR
	is the Jaccard score (yellow->red); WIDTH is the SHARED-LOC impact. Drawn
	anti-aliased; partners with no visible tile resolve to their nearest visible
	ancestor."
	| sel selRect selectedCenter aaCanvas |
	sel := treemapMorph selectedNode.
	(sel isKindOf: SWACodeMethodNode) ifFalse: [^ self].
	selRect := treemapMorph rectForNode: sel.
	selRect ifNil: [^ self].
	selectedCenter := (selRect translateBy: origin) center.
	aaCanvas := self aaCanvasFrom: aCanvas.
	(treemapMorph dupMatchesForNode: sel) do: [:assoc |
		| score partner target r screenR sharedLoc |
		score := assoc key.
		partner := assoc value.
		sharedLoc := treemapMorph dupSharedLocBetween: sel and: partner.
		target := partner.
		r := treemapMorph rectForNode: target.
		[r isNil and: [target notNil and: [target parent notNil]]] whileTrue: [
			target := target parent.
			r := treemapMorph rectForNode: target].
		(r notNil and: [target ~~ sel]) ifTrue: [
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
