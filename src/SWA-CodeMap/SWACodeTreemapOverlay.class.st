"
Interaction overlay for SWACodeTreemapMorph. Context menu offers browse, and (for method tiles) senders/implementors; no other-parent decorations since code nodes form a strict tree.
"
Class {
	#name : #SWACodeTreemapOverlay,
	#superclass : #AnObsoleteSWATreemapOverlay,
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:17'
}
SWACodeTreemapOverlay >> addMenuItems: menu for: aNode [
	"Code context-menu items: browse the element; for method tiles also offer
	senders/implementors. Plus the top-level Data selector (when datasets are loaded),
	a Links (decoration) submenu, and inspect/explore the node itself."
	| dataMenu decoMenu |
	menu add: 'browse' selector: #browseNode: argument: aNode.
	aNode kind = #method ifTrue: [
		menu add: 'senders' selector: #browseSenders: argument: aNode.
		menu add: 'implementors' selector: #browseImplementors: argument: aNode].
	dataMenu := self dataMenuMorph.
	dataMenu ifNotNil: [menu addLine. menu add: 'Data' subMenu: dataMenu].
	decoMenu := self decorationMenuMorph.
	decoMenu ifNotNil: [menu add: 'Links' subMenu: decoMenu].
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
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:43'
}
SWACodeTreemapOverlay >> colorModeOptions [
	"Color (base-tint) modes for the Code Map. Most are intrinsic (kind, LOC,
	duplication, topic, ...). The two DATA-DRIVEN legacy entries -- test coverage and
	invocation tally -- acquire their data lazily when picked.

	APPENDED after the intrinsics: one entry per COLOR-capable METRIC of every
	retained dataset (SWADatasetMetric). A single coverage file thus contributes
	BOTH 'By coverage [file]' and 'By call [file]' (the latter only when the file
	carries invocation data). Each carries its own minted symbol, so you can load
	coverage twice and switch between all their metrics instantly, no reload."
	| base tm |
	base := #(
		(#codeKind         'By kind (package/class/category/method)')
		(#byteComposition  'By byte composition (doc/string/code bar)')
		(#loc              'By LOC (heat)')
		(#avgloc           'By avg LOC / method')
		(#versions         'By avg versions / method')
		(#recency          'By recency (last changed)')
		(#author           'By author (last changed)')
		(#duplication      'By duplication (Jaccard clone heat)')
		(#topic            'By topic (BTM hue families)')
		(#coverage         'By test coverage (green covered + blue tests)')
		(#tally            'By invocation tally (call-count heat)')
	) asOrderedCollection.
	tm := self treemapMorph.
	(tm respondsTo: #datasets) ifTrue: [
		tm datasets do: [:ds |
			ds metrics do: [:metric |
				metric supportsColor ifTrue: [
					base add: (Array with: metric modeSymbol with: metric menuLabel)]]]].
	^ base
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapOverlay >> dataMenuMorph [
	"Build the top-level Data menu from #dataModeOptions, ticking the active dataset.
	Answers nil when only 'None' is available (no datasets loaded)."
	| opts current menu active |
	opts := self dataModeOptions.
	opts size <= 1 ifTrue: [^ nil].
	active := (treemapMorph respondsTo: #activeDataset)
		ifTrue: [treemapMorph activeDataset] ifFalse: [nil].
	current := active ifNil: [#none] ifNotNil: [active modeSymbol].
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode ifTrue: ['* ', pair second] ifFalse: ['   ', pair second].
		menu add: label selector: #setDataMode: argument: mode].
	^ menu
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapOverlay >> dataModeOptions [
	"{ symbol. label } pairs for the top-level Data selector: 'None' plus one entry per
	RETAINED dataset. Picking one makes it the active data source and applies its
	fitting defaults across the axes (color/size/decoration). Empty of datasets ->
	just 'None'."
	| opts tm |
	opts := OrderedCollection new.
	opts add: (Array with: #none with: 'None (intrinsic)').
	tm := self treemapMorph.
	(tm respondsTo: #datasets) ifTrue: [
		tm datasets do: [:ds |
			opts add: (Array with: ds modeSymbol with: 'Data: ', (ds name ifNil: ['?']))]].
	^ opts asArray
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWACodeTreemapOverlay >> decorationMenuMorph [
	"Build the Links (decoration) menu from #decorationModeOptions, ticking the active
	decoration metric. Answers nil when only 'None' is available (no link datasets)."
	| opts current menu active |
	opts := self decorationModeOptions.
	opts size <= 1 ifTrue: [^ nil].
	active := (treemapMorph respondsTo: #decorationMetric)
		ifTrue: [treemapMorph decorationMetric] ifFalse: [nil].
	current := active ifNil: [#none] ifNotNil: [active modeSymbol].
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode ifTrue: ['* ', pair second] ifFalse: ['   ', pair second].
		menu add: label selector: #setDecorationMode: argument: mode].
	^ menu
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWACodeTreemapOverlay >> decorationModeOptions [
	"{ symbol. label } pairs for the Links (decoration) menu: a 'None' entry plus one
	per LINK-capable metric of every retained dataset (currently duplication clone
	links), tagged with the dataset name. Empty of datasets -> just 'None'."
	| opts tm |
	opts := OrderedCollection new.
	opts add: (Array with: #none with: 'None').
	tm := self treemapMorph.
	(tm respondsTo: #datasets) ifTrue: [
		tm datasets do: [:ds |
			ds metrics do: [:metric |
				metric supportsLinks ifTrue: [
					opts add: (Array with: metric modeSymbol with: 'Links: ', metric menuLabel)]]]].
	^ opts asArray
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:30'
}
SWACodeTreemapOverlay >> drawLinksFor: aMetric on: aCanvas origin: origin restrictedTo: keySetOrNil [
	"Draw the metric's links between rendered method tiles. When keySetOrNil is non-nil
	(a selection subtree), a link is drawn only if AT LEAST ONE endpoint key is in the
	set -- so selecting a package/class/method shows just the links connected to it
	(including those going out to partners elsewhere). nil = no restriction (whole-map
	overview). Each unordered pair drawn once; off-screen partners resolve to their
	nearest visible ancestor.

	Each link gets a dark CASING drawn under the score-colored line so it stays visible
	on any tile color (e.g. orange link over an orange duplication-heat tile). ALL
	casings are drawn first, then ALL colored lines, so where links cross the colors
	stay clean on top of the casings. Both passes go heaviest-last (shared-LOC) so the
	highest-impact links sit on top."
	| links seen aaCanvas |
	links := OrderedCollection new.
	seen := Set new.
	treemapMorph tiles do: [:assoc |
		| node fromR nodeKey |
		node := assoc key.
		fromR := assoc value.
		(node isKindOf: SWACodeMethodNode) ifTrue: [
			nodeKey := node crossRefKey.
			(aMetric linksForKey: nodeKey) do: [:m |
				| score partnerKey pairKey target r sharedLoc partnerNode |
				score := m key.
				partnerKey := m value.
				(treemapMorph link: (nodeKey -> partnerKey) connectsRestriction: keySetOrNil) ifTrue: [
					pairKey := (nodeKey <= partnerKey)
						ifTrue: [nodeKey, '|', partnerKey]
						ifFalse: [partnerKey, '|', nodeKey].
					(seen includes: pairKey) ifFalse: [
						seen add: pairKey.
						sharedLoc := aMetric sharedLocForKey: nodeKey score: score partnerKey: partnerKey.
						partnerNode := treemapMorph nodeForCrossRefKey: partnerKey
							orStubLoc: (aMetric locForKey: partnerKey).
						target := partnerNode.
						r := treemapMorph rectForNode: target.
						[r isNil and: [target notNil and: [target parent notNil]]] whileTrue: [
							target := target parent.
							r := treemapMorph rectForNode: target].
						(r notNil and: [target ~~ node]) ifTrue: [
							links add: { score. fromR center + origin. r center + origin. sharedLoc }]]]]]].
	links := links asSortedCollection: [:a :b | (a at: 4) <= (b at: 4)].
	aaCanvas := self aaCanvasFrom: aCanvas.
	"pass 1: dark casings"
	links do: [:lk | | w |
		w := self dupLineWidthForSharedLoc: (lk at: 4).
		aaCanvas
			line: (lk at: 2)
			to: (lk at: 3)
			width: (self dupCasingWidthFor: w)
			color: self dupLineCasingColor].
	"pass 2: score-colored lines on top"
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:33'
}
SWACodeTreemapOverlay >> drawOn: aCanvas [
	"Standard hover highlight (white border + ancestor borders) follows the mouse via
	super. When a DECORATION metric is active (the Links axis), also draw its links,
	FILTERED to the current selection's subtree:
	  - nothing selected  -> the whole-map overview (no restriction),
	  - a method selected -> only that method's links,
	  - a container (package/class/category) selected -> only links with at least one
	    endpoint among the methods under the selection.
	The CLICK selection always gets its own persistent border (via
	#drawSelectionBorderFor:), independent of hover -- so hovering another tile never
	makes the selection appear to move or vanish (hover draws its own transient border
	via super; selection draws this one). Hovering NEVER changes the selection value.
	The decoration axis is INDEPENDENT of colorMode."
	| origin sel deco restrict |
	super drawOn: aCanvas.
	origin := self position.
	sel := treemapMorph selectedNode.
	"Persistent selection border, always, so hover can't visually steal the selection."
	sel ifNotNil: [self drawSelectionBorderFor: sel on: aCanvas origin: origin].
	deco := (treemapMorph respondsTo: #decorationMetric)
		ifTrue: [treemapMorph decorationMetric] ifFalse: [nil].
	deco ifNil: [^ self].
	deco supportsLinks ifFalse: [^ self].
	sel ifNil: [
		"no selection -> full overview"
		^ self drawLinksFor: deco on: aCanvas origin: origin restrictedTo: nil].
	restrict := treemapMorph leafKeySetUnder: sel.
	self drawLinksFor: deco on: aCanvas origin: origin restrictedTo: restrict
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:30'
}
SWACodeTreemapOverlay >> dupCasingWidthFor: lineWidth [
	"Casing is a couple of pixels wider than the line it backs, so a dark rim shows on
	both sides regardless of the line's own width."
	^ lineWidth + 3
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:30'
}
SWACodeTreemapOverlay >> dupLineCasingColor [
	"The dark 'casing' stroke drawn UNDER every colored link line so links stay visible
	on any tile color (notably orange links over orange duplication-heat tiles). A
	fixed near-black, semi-opaque rim -- the metro-map trick: the colored line keeps
	encoding the score, the casing just guarantees contrast."
	^ Color black alpha: 0.6
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
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapOverlay >> popUpDataMenu [
	"Pop up the top-level Data menu standalone (header 'Data' button)."
	| menu |
	menu := self dataMenuMorph.
	menu ifNotNil: [menu popUpInWorld: self world]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWACodeTreemapOverlay >> popUpDecorationMenu [
	"Pop up the Links (decoration) menu standalone (header 'Links' button)."
	| menu |
	menu := self decorationMenuMorph.
	menu ifNotNil: [menu popUpInWorld: self world]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:16'
}
SWACodeTreemapOverlay >> setDataMode: aSymbol [
	(treemapMorph respondsTo: #setDataMode:)
		ifTrue: [treemapMorph setDataMode: aSymbol]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWACodeTreemapOverlay >> setDecorationMode: aSymbol [
	(treemapMorph respondsTo: #setDecorationMode:)
		ifTrue: [treemapMorph setDecorationMode: aSymbol]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeTreemapOverlay >> sizeModeOptions [
	"Live tile-SIZE (weight) metrics for the Code Map. The two legacy DYNAMIC metrics
	-- invocation count and covering-test count -- come from the single-ivar coverage
	overlay and are only offered when such data is present.

	APPENDED: one entry per SIZE-capable METRIC of every retained dataset, tagged
	with the dataset name (e.g. 'By coverage [squeak-coverage.json]'), so a loaded
	dataset can drive tile AREA as well as tint."
	| opts tm |
	opts := OrderedCollection withAll: #(
		(#methods   'Number of methods')
		(#loc       'Lines of code')
		(#bytes     'Source byte size')).
	tm := self treemapMorph.
	(tm respondsTo: #coverageData) ifTrue: [
		tm coverageData ifNotNil: [
			opts add: #(#invocations 'Execution: call count');
				add: #(#tests 'Execution: covering tests')]].
	(tm respondsTo: #datasets) ifTrue: [
		tm datasets do: [:ds |
			ds metrics do: [:metric |
				metric supportsSize ifTrue: [
					opts add: (Array with: metric modeSymbol with: metric menuLabel)]]]].
	^ opts asArray
]
