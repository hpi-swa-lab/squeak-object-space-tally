"
Abstract squarified-treemap morph. Holds the generic machinery shared by concrete treemaps:

  - squarify layout (squarify:scales:into:, layoutChildrenOf:in:, ...)
  - Form-cached static rendering + hover overlay
  - zoom in/out with breadcrumb + selection-path
  - resize deferring + stepping

Concrete subclasses supply the domain-specific bits by overriding these hooks:
  - colorForNode:        fill color for a tile's node
  - labelFor:inWidth:    short tile label
  - balloonStringFor:    hover balloon text
  - exploreNode:         action on tile activation
  - breadcrumbString     header text

Nodes follow the node protocol: a node must answer #children, #totalSize, #selfSize,
#name, #depth (and optionally #pathString / #edgeLabel / #className for the
default hooks). Subclasses: SWASpaceTallyTreemapMorph (sized by bytes),
SWACodeTreemapMorph (sized by LOC).
"
Class {
	#name : #SWATreemapMorph,
	#superclass : #SWAView,
	#instVars : [
		'currentNode',
		'tiles',
		'layoutValid',
		'minTileForLabel',
		'minRecurseExtent',
		'resizeDeferring',
		'lastResizeTime',
		'breadcrumbMorph',
		'overlayMorph',
		'selectionPathMorph',
		'colorMode',
		'layoutProgress',
		'leafKind'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:09'
}
SWATreemapMorph class >> on: aNode [
	"Create a treemap morph rooted at the given duck-typed node."
	^ self new setRoot: aNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWATreemapMorph >> balloonStringFor: aNode [
	"Hover balloon text. Default: name + weight + path. Subclasses refine."
	^ String streamContents: [:s |
		s nextPutAll: (aNode name ifNil: ['?']); cr.
		s nextPutAll: 'weight: '; nextPutAll: (self formatWeight: (aNode totalSize ifNil: [0])); cr.
		(aNode respondsTo: #pathString) ifTrue: [
			s nextPutAll: 'path:   '; nextPutAll: aNode pathString]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:35'
}
SWATreemapMorph >> baseColorForNode: aNode [
	"Intrinsic fill color for a tile, ignoring any cross-ref highlight.
	Default: gray ramp by depth. Subclasses override this (not #colorForNode:)."
	^ Color gray: (0.4 + ((aNode depth \\ 4) * 0.08))
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> breadcrumbMorph: aMorph [
	breadcrumbMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWATreemapMorph >> breadcrumbString [
	"Breadcrumb of the zoom focus + total weight, with control hints."
	| parts node total |
	parts := OrderedCollection new.
	node := currentNode.
	[node notNil] whileTrue: [
		parts addFirst: (node name ifNil: ['?']).
		node := node parent].
	total := currentNode totalSize ifNil: [0].
	^ (parts inject: '' into: [:s :p | s isEmpty ifTrue: [p] ifFalse: [s , ' / ' , p]])
		, '   '
		, (self formatWeight: total) , ' total'
		, '   [left: zoom in, right: zoom out, shift: explore]'
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:55'
}
SWATreemapMorph >> browseSelected [
	"Open a system browser on the selected node, if it understands #browse.
	Beeps when nothing is selected or it cannot be browsed."
	(selectedNode notNil and: [selectedNode respondsTo: #browse])
		ifTrue: [selectedNode browse]
		ifFalse: [Beeper beep]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> colorMode [
	^ colorMode ifNil: [#class]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> colorMode: aSymbol [
	"Set the color mode and re-render. Supported modes:
	  #class         -- hue from class name hash (default)
	  #children      -- green gradient by number of children
	  #otherParents  -- red gradient by number of other parents (shared refs)
	  #type          -- category-based: Morphic, Collections, Values, Other"

	colorMode := aSymbol.
	self flushCache
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> commitDeferredResize [
	"End the deferred-resize cycle: invalidate layout, drop the stale cached
	 form, and do a full re-render at the current extent."

	resizeDeferring := false.
	layoutValid := false.
	cachedForm := nil.
	self stopStepping.
	self changed
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> computeLayout [
	"Build a nested-treemap tile list rooted at currentNode.
	 Full extent is available for tiles (header is a separate morph)."

	| bounds |
	tiles := OrderedCollection new.
	currentNode ifNil: [^ self].
	bounds := 0 @ 0 extent: self extent.
	(bounds width <= 0 or: [bounds height <= 0]) ifTrue: [^ self].
	self layoutChildrenOf: currentNode in: bounds
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> currentNode [
	^ currentNode
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> drawOn: aCanvas [
	"Blit the cached static layer. Hover is handled by the overlay morph.
	 During interactive resizing, stretch-blit the old cached form."

	| origin form |
	origin := self position.

	"If we are deferring a resize, stretch-blit the stale cached form."
	(resizeDeferring == true and: [cachedForm notNil]) ifTrue: [
		| scaleX scaleY scaled |
		scaleX := self width asFloat / cachedForm width.
		scaleY := self height asFloat / cachedForm height.
		scaled := cachedForm magnify: cachedForm boundingBox by: scaleX @ scaleY smoothing: 1.
		aCanvas
			image: scaled
			at: origin
			sourceRect: scaled boundingBox
			rule: Form over.
		^ self].

	self ensureLayout.
	form := self ensureCachedForm.
	aCanvas
		image: form
		at: origin
		sourceRect: form boundingBox
		rule: Form over
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:09'
}
SWATreemapMorph >> drawTileContent: aNode in: screenR on: aCanvas [
	"Hook: draw extra content inside a tile after its fill, before its frame/label.
	Default is a no-op. Subclasses (e.g. SpaceTally bitmap mode) may override."
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:04'
}
SWATreemapMorph >> emitRow: indexRow areas: areaArray sum: rowSum into: aRectangle nodes: nodeArray [
	"Commit a row of tiles into aRectangle, sliced along its short side.
	 Tiles smaller than 5x5 are skipped entirely.
	 All tile rectangles are truncated to integer pixels to avoid fractional
	 coordinate artifacts (sub-pixel skew in text and borders)."

	| w h horizontal thickness x y r tileRect node area remaining inner |
	w := aRectangle width.
	h := aRectangle height.
	(w <= 0 or: [h <= 0 or: [rowSum <= 0]]) ifTrue: [^ aRectangle].
	horizontal := h <= w.
	thickness := rowSum / (horizontal ifTrue: [h] ifFalse: [w]).
	x := aRectangle left.
	y := aRectangle top.
	horizontal
		ifTrue: [
			r := y.
			indexRow do: [:idx |
				node := nodeArray at: idx.
				area := areaArray at: idx.
				tileRect := Rectangle
					origin: (x @ r) truncated
					corner: ((x + thickness) @ (r + (area / thickness))) truncated.
				r := r + (area / thickness).
				(tileRect width >= 5 and: [tileRect height >= 5]) ifTrue: [
					tiles add: node -> tileRect.
					inner := self innerRectFor: tileRect.
					(inner notNil and: [self shouldLayoutChildrenOf: node])
						ifTrue: [self layoutChildrenOf: node in: inner]]].
			remaining := Rectangle
				origin: ((x + thickness) truncated) @ y
				corner: aRectangle bottomRight]
		ifFalse: [
			r := x.
			indexRow do: [:idx |
				node := nodeArray at: idx.
				area := areaArray at: idx.
				tileRect := Rectangle
					origin: (r @ y) truncated
					corner: ((r + (area / thickness)) @ (y + thickness)) truncated.
				r := r + (area / thickness).
				(tileRect width >= 5 and: [tileRect height >= 5]) ifTrue: [
					tiles add: node -> tileRect.
					inner := self innerRectFor: tileRect.
					(inner notNil and: [self shouldLayoutChildrenOf: node])
						ifTrue: [self layoutChildrenOf: node in: inner]]].
			remaining := Rectangle
				origin: x @ ((y + thickness) truncated)
				corner: aRectangle bottomRight].
	^ remaining
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> ensureCachedForm [
	"Render the static layer (header + tiles + labels) into a Form in local coords.
	 Re-used as a blit on every subsequent draw until the layout invalidates."

	| form canvas |
	cachedForm ifNotNil: [^ cachedForm].
	form := Form extent: self extent depth: Display depth.
	canvas := form getCanvas.
	self renderStaticLayerOn: canvas at: 0 @ 0.
	cachedForm := form.
	^ cachedForm
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> ensureLayout [
	"Recompute the tile list (and drop the cached form) if needed."

	layoutValid ifTrue: [^ self].
	self computeLayout.
	cachedForm := nil.
	layoutValid := true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWATreemapMorph >> exploreNode: aNode [
	"Action when a tile is activated (shift-click). Default: object-explore the
	node. Subclasses override (e.g. browse the live code element)."
	ToolSet explore: aNode
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> extent: aPoint [
	"When resized interactively (e.g. halo drag), defer the expensive layout
	 recomputation. Instead, just stretch-blit the existing cached form until
	 the user stops dragging. Also resize the overlay to match."

	| oldExtent |
	oldExtent := self extent.
	super extent: aPoint.
	oldExtent = aPoint ifTrue: [^ self].

	"Keep overlay in sync"
	overlayMorph ifNotNil: [overlayMorph extent: aPoint].

	"If we have a cached form, defer re-layout: just mark that we are scaling."
	cachedForm ifNotNil: [
		resizeDeferring := true.
		lastResizeTime := Time millisecondClockValue.
		self startStepping.
		^ self].

	"No cached form yet -- fall back to immediate invalidation."
	layoutValid := false
]

{
	#category : #caching,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> flushCache [
	"Drop the cached Form so the next draw rebuilds it."

	cachedForm := nil.
	resizeDeferring := false.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self changed
]

{
	#category : #caching,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:50'
}
SWATreemapMorph >> flushCacheKeepingSelection [
	"Drop the cached Form so the next draw rebuilds it, but KEEP the overlay's hover/
	selection (the white selection border). Use this when only COLORS change (e.g. a
	coverage filter re-tints tiles) -- the layout and tile rectangles are unchanged,
	so the selection is still valid. (#flushCache also clears the hover, which is
	only correct when the LAYOUT changes, i.e. zoom in/out.)"
	cachedForm := nil.
	resizeDeferring := false.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWATreemapMorph >> formatWeight: aNumber [
	"Human-readable form of a tile weight, for breadcrumb/balloon. Default: plain
	number. Subclasses override (bytes for SpaceTally, 'N LOC' for code)."
	^ aNumber printString
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> initialize [
	super initialize.
	self extent: 900 @ 600.
	self color: Color black.
	self borderWidth: 0.
	tiles := OrderedCollection new.
	layoutValid := false.
	minTileForLabel := 400.
	minRecurseExtent := 8.
	resizeDeferring := false.
	lastResizeTime := 0.
	history := OrderedCollection new.
	colorMode := #class
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> innerRectFor: aRectangle [
	"Return the sub-rectangle in which to lay out aRectangle's child tiles, or nil
	 if the tile is too small to bother. Leaves a 1-px gutter on all sides so the
	 parent's border remains visible around its children. Reserves an extra strip
	 at the top for a label if there is room."

	| inset labelStrip available |
	(aRectangle width < minRecurseExtent or: [aRectangle height < minRecurseExtent])
		ifTrue: [^ nil].
	inset := aRectangle insetBy: 1.
	(inset width < minRecurseExtent or: [inset height < minRecurseExtent])
		ifTrue: [^ nil].
	"If the tile is tall enough, reserve a small top strip for the parent label."
	labelStrip := Preferences standardSystemFont height + 2.
	(inset height > (labelStrip + minRecurseExtent))
		ifTrue: [
			available := Rectangle
				origin: inset left @ (inset top + labelStrip)
				corner: inset right @ inset bottom.
			^ available]
		ifFalse: [^ inset]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWATreemapMorph >> labelFor: aNode inWidth: maxPixels [
	"Short tile label. Default: the node name when there is room. Subclasses refine."
	maxPixels < 16 ifTrue: [^ nil].
	^ aNode name ifNil: ['?']
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:32'
}
SWATreemapMorph >> layoutChildrenOf: aNode in: aRectangle [
	"Squarify aNode's children into aRectangle; for each child tile, recurse if
	 it is large enough and has children of its own. Appends to `tiles` in
	 draw order: parent tile, then child tiles inside it."

	| kids total area scales |
	layoutProgress ifNotNil: [:p | p value: aNode].
	(aRectangle width < minRecurseExtent or: [aRectangle height < minRecurseExtent])
		ifTrue: [^ self].
	kids := aNode children ifNil: [^ self].
	kids isEmpty ifTrue: [^ self].
	kids := (kids select: [:k | k totalSize > 0])
		asSortedCollection: [:a :b | a totalSize >= b totalSize].
	kids isEmpty ifTrue: [^ self].
	total := kids inject: 0 into: [:s :k | s + k totalSize].
	total <= 0 ifTrue: [^ self].
	area := aRectangle width * aRectangle height.
	scales := kids collect: [:k | k totalSize * area / total].
	self squarify: kids asArray scales: scales into: aRectangle
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:32'
}
SWATreemapMorph >> layoutProgress: aBlockOrNil [
	"Optional one-arg block invoked once per laid-out parent node during layout,
	for driving a progress bar. nil (default) means no reporting and zero overhead."
	layoutProgress := aBlockOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:03'
}
SWATreemapMorph >> leafKind [
	"The node #kind at which layout stops recursing (nodes of this kind render as
	leaf tiles even though they still have children for metric rollup). nil = no
	cutoff (lay out the full tree)."
	^ leafKind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:03'
}
SWATreemapMorph >> leafKind: aSymbolOrNil [
	"Stop laying out the tree at nodes whose #kind = aSymbolOrNil (they become the
	visible leaves). The underlying tree and all metric roll-ups are unaffected;
	only rendering stops here. Pass nil to lay out the full tree."
	leafKind := aSymbolOrNil.
	layoutValid := false.
	cachedForm := nil.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:53'
}
SWATreemapMorph >> metaInfoString [
	"Per-view meta-info line for the panel. Default none; subclasses override."
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> minTileForLabel [
	^ minTileForLabel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWATreemapMorph >> overlayMorph [
	"The transparent event/menu overlay sitting on top of the tiles."
	^ overlayMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> overlayMorph: aMorph [
	overlayMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> rectForNode: aNode [
	"Return the layout rectangle for aNode, or nil if not found in the current tiles."

	tiles ifNil: [^ nil].
	tiles do: [:assoc |
		assoc key == aNode ifTrue: [^ assoc value]].
	^ nil
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:53'
}
SWATreemapMorph >> refreshChrome [
	"Refresh all chrome labels (breadcrumb, selection, meta) + source pane via the
	nav panel, if one is attached. No-op otherwise (legacy standalone use)."
	navPanel ifNotNil: [:p | p refresh]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:09'
}
SWATreemapMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Paint every tile in draw order into aCanvas. No header, no hover.
	Per-tile overlay content (e.g. SpaceTally's bitmap mode) is delegated to the
	#drawTileContent:in:on: hook, which is a no-op by default."
	| font fontH borderColor |
	font := Preferences standardSystemFont.
	fontH := font height.
	aCanvas fillRectangle: (anOrigin extent: self extent) color: Color black.
	borderColor := Color gray: 0.2.
	tiles do: [:assoc | | node r screenR fill labelStr labelClip |
		node := assoc key. r := assoc value.
		screenR := r translateBy: anOrigin.
		fill := self colorForNode: node.
		aCanvas fillRectangle: screenR color: fill.
		self drawTileContent: node in: screenR on: aCanvas.
		aCanvas frameRectangle: screenR color: borderColor.
		((screenR width * screenR height) >= minTileForLabel
			and: [screenR width >= 40 and: [screenR height >= (fontH + 2)]])
			ifTrue: [
				labelStr := self labelFor: node inWidth: screenR width - 6.
				labelStr ifNotNil: [
					labelClip := screenR insetBy: 2.
					aCanvas clipBy: labelClip during: [:c |
						c drawString: labelStr at: labelClip origin font: font color: Color black]]]]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:53'
}
SWATreemapMorph >> selectTileNode: aNodeOrNil [
	"A tile was single-clicked (selected). Record it and refresh the chrome."
	self selectedNode: aNodeOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWATreemapMorph >> selectedNode: aNodeOrNil [
	"Set the selected node and refresh the chrome (selection line, meta, source).
	Under a provenance coverage overlay, selecting a test method or TestCase class
	filters the green highlight to just that test's covered methods; selecting
	anything else clears the filter."
	selectedNode := aNodeOrNil.
	self updateTestFilterForSelection.
	self refreshChrome
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWATreemapMorph >> selectedSourceString [
	"Source text for the Show pane. Default: the selected node's #sourceString if it
	has one, else empty. (SWAPane content protocol.)"
	(selectedNode notNil and: [selectedNode respondsTo: #sourceString])
		ifTrue: [^ selectedNode sourceString].
	^ ''
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> selectionPathMorph: aMorph [
	selectionPathMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:53'
}
SWATreemapMorph >> selectionPathString [
	"Selection-path string for the panel: full path to the selected node, or empty."
	^ selectedNode
		ifNil: ['']
		ifNotNil: [:n | n pathString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:35'
}
SWATreemapMorph >> setRoot: aNode [
	"Set the root node and invalidate the layout. Rebuilds the cross-ref
	key index eagerly so peer panels can link against us immediately."
	rootNode := aNode.
	currentNode := aNode.
	layoutValid := false.
	self rebuildKeyIndex.
	self changed.
	^ self
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:03'
}
SWATreemapMorph >> shouldLayoutChildrenOf: aNode [
	"True if aNode's children should be laid out as nested tiles. False when a
	leafKind cutoff is set and aNode is at (or below) that level, so the full tree
	is still built for metrics but only rendered down to leafKind."
	aNode children ifNil: [^ false].
	aNode children isEmpty ifTrue: [^ false].
	(leafKind notNil and: [(aNode respondsTo: #kind) and: [aNode kind == leafKind]])
		ifTrue: [^ false].
	^ true
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> squarify: nodeArray scales: areaArray into: aRectangle [
	"Classic Bruls/Huijsen/van Wijk squarified treemap.
	 nodeArray is sorted desc by size. areaArray gives the target pixel area for
	 each node, parallel to nodeArray. We carve aRectangle into rows.
	 Appends Associations node -> Rectangle to the tiles OC."

	| rect row rowSum bestRatio nextRatio shortSide n i nextSum |
	rect := aRectangle.
	row := OrderedCollection new.
	rowSum := 0.
	n := nodeArray size.
	i := 1.
	[i <= n] whileTrue: [
		shortSide := rect width min: rect height.
		shortSide <= 0 ifTrue: [^ self].
		row isEmpty
			ifTrue: [
				"Start a new row with this one element."
				row add: i.
				rowSum := areaArray at: i.
				bestRatio := self worstAspectRatio: row areas: areaArray sum: rowSum side: shortSide.
				i := i + 1]
			ifFalse: [
				nextSum := rowSum + (areaArray at: i).
				nextRatio := self worstAspectRatio: (row copyWith: i) areas: areaArray sum: nextSum side: shortSide.
				nextRatio <= bestRatio
					ifTrue: [
						"Adding this child improves (or holds) the worst aspect ratio."
						row add: i.
						rowSum := nextSum.
						bestRatio := nextRatio.
						i := i + 1]
					ifFalse: [
						"Adding it would make things worse - commit current row and start over."
						rect := self emitRow: row areas: areaArray sum: rowSum into: rect nodes: nodeArray.
						row := OrderedCollection new.
						rowSum := 0]]].
	row isEmpty ifFalse: [
		self emitRow: row areas: areaArray sum: rowSum into: rect nodes: nodeArray]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> step [
	"Check if interactive resizing has settled. Once no resize has happened
	 for 200ms, commit the deferred layout."

	| now elapsed |
	resizeDeferring == true ifFalse: [
		self stopStepping.
		^ self].
	now := Time millisecondClockValue.
	elapsed := now - lastResizeTime.
	"Handle wrap-around of millisecondClockValue"
	elapsed < 0 ifTrue: [elapsed := elapsed + 16r20000000].
	elapsed >= 200 ifTrue: [
		self commitDeferredResize]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> stepTime [
	"Poll at ~20fps while deferring resize."
	^ 50
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> tileAtLocal: aLocalPoint [
	"Return the DEEPEST tile under aLocalPoint, or nil. Because the layout
	 appends children after their parents, the last-matching tile is the
	 deepest one."

	| hit |
	hit := nil.
	tiles do: [:assoc | (assoc value containsPoint: aLocalPoint) ifTrue: [hit := assoc]].
	^ hit
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> tiles [
	"For debugging: returns the cached tile list (Associations node -> Rectangle)."
	^ tiles
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:54'
}
SWATreemapMorph >> updateBreadcrumb [
	"Update the breadcrumb label. Routes through the nav panel when present, else
	falls back to the legacy standalone label morph."
	navPanel
		ifNotNil: [:p | p refresh]
		ifNil: [breadcrumbMorph ifNotNil: [breadcrumbMorph contents: self breadcrumbString]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:08'
}
SWATreemapMorph >> worstAspectRatio: indexRow areas: areaArray sum: rowSum side: shortSide [
	"Return the worst (max) aspect ratio of the rectangles produced by laying out
	 indexRow along a side of length shortSide, where rowSum is the sum of their areas.
	 max(s^2 * rMax / sum^2,  sum^2 / (s^2 * rMin))."

	| rMax rMin s2 sum2 |
	(rowSum <= 0 or: [shortSide <= 0]) ifTrue: [^ Float infinity].
	rMax := 0.
	rMin := Float infinity.
	indexRow do: [:i | | a |
		a := areaArray at: i.
		a > rMax ifTrue: [rMax := a].
		a < rMin ifTrue: [rMin := a]].
	s2 := shortSide * shortSide.
	sum2 := rowSum * rowSum.
	^ ((s2 * rMax) / sum2) max: (sum2 / (s2 * rMin))
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:04'
}
SWATreemapMorph >> zoomInto: aNode [
	"Make aNode the new focus, if it has children we are willing to show. Respects
	the leafKind cutoff: you cannot zoom past a leaf-kind node. Push current view
	onto history."

	(self shouldLayoutChildrenOf: aNode) ifFalse: [^ self].
	history addLast: currentNode.
	currentNode := aNode.
	selectedNode := nil.
	layoutValid := false.
	cachedForm := nil.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self refreshChrome.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:54'
}
SWATreemapMorph >> zoomOut [
	"Go back to the previous view from history, clearing the selection."

	history isEmpty ifTrue: [^ self].
	currentNode := history removeLast.
	selectedNode := nil.
	layoutValid := false.
	cachedForm := nil.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self refreshChrome.
	self changed
]
