"
A single-Morph squarified treemap visualization for SWASpaceTally trees.

Renders a NESTED squarified treemap inside drawOn: - each child tile is
recursively subdivided by its own children until a tile becomes too
small (minRecurseExtent on either axis) or has no children. A
million-node tree thus stays a single Morph plus a flat OrderedCollection
of laid-out rectangles.

The static rendering (background, rects, borders, labels) is cached into
a Form. drawOn: blits the form and paints the hover highlight on top.
The form is rebuilt only when the layout changes (extent, focus zoom,
root swap).

Usage:

    | t |
    t := SWASpaceTally new walk; compact; yourself.
    (SWASpaceTallyTreemapMorph on: t) openInWorld.

Or:

    SWASpaceTally openTreemap.

Instance variables:
    rootNode         - the SWASpaceTally tree we are visualizing (top of zoom stack)
    currentNode      - which node currently fills the bounds (zoom focus)
    tiles            - OrderedCollection of Associations node -> Rectangle (local
                       coords), in draw order: parents before children. Used by
                       both rendering and hit testing.
    layoutValid      - false when we need to relayout (extent/focus/root changed)
    hoveredTile      - the Association currently under the mouse (or nil)
    minTileForLabel  - pixel-area threshold below which we skip drawing a label
    minRecurseExtent - minimum width AND height (px) a tile must have to be
                       recursed into. Smaller tiles become leaves.
    cachedForm       - the rendered static layer in local coords; nil while invalid

Interaction:
    move mouse      - hover highlight + balloon text (name + bytes)
    left click      - zoom in to the deepest tile under cursor
    right click     - zoom out to parent
    shift+click     - open ObjectExplorer on the node
"
Class {
	#name : #SWASpaceTallyTreemapMorph,
	#superclass : #Morph,
	#instVars : [
		'rootNode',
		'currentNode',
		'tiles',
		'layoutValid',
		'minTileForLabel',
		'cachedForm',
		'minRecurseExtent',
		'resizeDeferring',
		'lastResizeTime',
		'breadcrumbMorph',
		'overlayMorph',
		'history',
		'selectionPathMorph',
		'colorMode'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:15'
}
SWASpaceTallyTreemapMorph class >> on: aSWASpaceTally [
	"Create a treemap morph on a SWASpaceTally tree (typically post #walk #compact)."

	^ self new setRoot: aSWASpaceTally
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:58'
}
SWASpaceTallyTreemapMorph >> balloonStringFor: aNode [
	| total selfStr kids |
	total := SWASpaceTally formatBytes: (aNode totalSize ifNil: [0]).
	selfStr := SWASpaceTally formatBytes: (aNode selfSize ifNil: [0]).
	kids := aNode children ifNil: [#()].
	^ String streamContents: [:s |
		s nextPutAll: aNode name asString; cr.
		s nextPutAll: 'total: '; nextPutAll: total; cr.
		s nextPutAll: 'self:  '; nextPutAll: selfStr; cr.
		s nextPutAll: 'kids:  '; print: kids size; cr.
		aNode edgeLabel ifNotNil: [:e |
			s nextPutAll: 'edge:  '; nextPutAll: e asString; cr].
		s nextPutAll: 'path:  '; nextPutAll: aNode pathString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:27'
}
SWASpaceTallyTreemapMorph >> breadcrumbMorph: aMorph [
	breadcrumbMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:59'
}
SWASpaceTallyTreemapMorph >> breadcrumbString [
	"Breadcrumb of zoom focus + total size."

	| parts node total |
	parts := OrderedCollection new.
	node := currentNode.
	[node notNil] whileTrue: [
		parts addFirst: (node name ifNil: ['?']).
		node := node parent].
	total := currentNode totalSize ifNil: [0].
	^ (parts inject: '' into: [:s :p | s isEmpty ifTrue: [p] ifFalse: [s , ' / ' , p]])
		, '   '
		, (SWASpaceTally formatBytes: total) , ' total'
		, '   [left: zoom in, right: zoom out, shift: explore]'
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorByChildren: aNode [
	"Green gradient: more children = brighter green. Leaf nodes are dark."

	| count t |
	count := aNode children size.
	count = 0 ifTrue: [^ Color gray: 0.25].
	t := (count log: 10) / 4.0 min: 1.0.  "log scale, 10000 children = max"
	^ Color h: 120 s: 0.6 v: (0.3 + (t * 0.6))
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorByClass: aNode [
	"Deterministic hue based on className hash; varying saturation/brightness by depth."

	| hue sym sat bright |
	sym := aNode className ifNil: [#Object].
	hue := (sym hash \\ 360) asFloat.
	sat := 0.45 + ((aNode depth \\ 5) * 0.06).
	bright := 0.85 - ((aNode depth \\ 5) * 0.04).
	^ Color h: hue s: sat v: bright
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorByOtherParents: aNode [
	"Red gradient: more other parents = brighter red. Unique objects are blue-gray."

	| refs t |
	refs := aNode otherParents ifNil: [#()].
	refs size = 0 ifTrue: [^ Color h: 220 s: 0.15 v: 0.5].
	t := (refs size log: 10) / 3.0 min: 1.0.  "log scale, 1000 refs = max"
	^ Color h: 0 s: (0.4 + (t * 0.5)) v: (0.5 + (t * 0.4))
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorByType: aNode [
	"Color by type category:
	  Morphic (Morph subclasses) = blue
	  Collections = green
	  Values (Number, String, Symbol, Boolean, Point, Rectangle) = orange
	  Other = gray"

	| cn cls depth sat bright |
	cn := aNode className ifNil: [''].
	cls := Smalltalk at: cn asSymbol ifAbsent: [nil].
	depth := aNode depth.
	sat := 0.5 + ((depth \\ 4) * 0.05).
	bright := 0.75 - ((depth \\ 4) * 0.04).

	"Morphic"
	(cls notNil and: [cls includesBehavior: Morph])
		ifTrue: [^ Color h: 220 s: sat v: bright].

	"Collections"
	(cls notNil and: [cls includesBehavior: Collection])
		ifTrue: [^ Color h: 140 s: sat v: bright].

	"Value objects"
	(cls notNil and: [
		(cls includesBehavior: Number) or: [
		(cls includesBehavior: String) or: [
		(cls includesBehavior: Boolean) or: [
		(cls includesBehavior: Point) or: [
		cls includesBehavior: Rectangle]]]]])
		ifTrue: [^ Color h: 30 s: sat v: bright].

	"Other"
	^ Color h: 0 s: 0.05 v: (0.45 + ((depth \\ 4) * 0.05))
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:20'
}
SWASpaceTallyTreemapMorph >> colorForNode: aNode [
	"Dispatch to the active color strategy."

	self colorMode == #children ifTrue: [^ self colorByChildren: aNode].
	self colorMode == #otherParents ifTrue: [^ self colorByOtherParents: aNode].
	self colorMode == #type ifTrue: [^ self colorByType: aNode].
	self colorMode == #bitmap ifTrue: [
		"Non-Form tiles get a dim gray so actual images stand out."
		^ Color gray: 0.18].
	^ self colorByClass: aNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorMode [
	^ colorMode ifNil: [#class]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:52'
}
SWASpaceTallyTreemapMorph >> colorMode: aSymbol [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:57'
}
SWASpaceTallyTreemapMorph >> commitDeferredResize [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:26'
}
SWASpaceTallyTreemapMorph >> computeLayout [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:15'
}
SWASpaceTallyTreemapMorph >> currentNode [
	^ currentNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:30'
}
SWASpaceTallyTreemapMorph >> drawBitmapNode: aNode in: screenR on: aCanvas [
	"If aNode is the 'bits' slot of a Form, scale the parent Form to the
	tile WIDTH (preserving aspect ratio) and blit it top-aligned, clipped
	to the tile. If the scaled image is shorter than the tile the lower
	part keeps the fill color; if taller it is cut off at the bottom.
	Returns true if it drew an image, false otherwise."

	| parent form scale scaled |
	aNode edgeLabel = 'bits' ifFalse: [^ false].
	parent := aNode parent.
	parent ifNil: [^ false].
	form := parent object.
	(form isKindOf: Form) ifFalse: [^ false].
	(form width > 0 and: [form height > 0]) ifFalse: [^ false].
	(screenR width < 2 or: [screenR height < 2]) ifTrue: [^ false].

	"Uniform scale based on width only -- no horizontal distortion."
	scale := screenR width asFloat / form width.
	scaled := [form magnify: form boundingBox by: scale @ scale smoothing: 1]
		ifError: [:e | ^ false].

	"Blit top-aligned, clipped to the tile so it never overflows."
	aCanvas clipBy: screenR during: [:c |
		c
			image: scaled
			at: screenR origin
			sourceRect: scaled boundingBox
			rule: Form over].
	^ true
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:26'
}
SWASpaceTallyTreemapMorph >> drawOn: aCanvas [
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:19'
}
SWASpaceTallyTreemapMorph >> emitRow: indexRow areas: areaArray sum: rowSum into: aRectangle nodes: nodeArray [
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
					(inner notNil and: [node children notNil and: [node children notEmpty]])
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
					(inner notNil and: [node children notNil and: [node children notEmpty]])
						ifTrue: [self layoutChildrenOf: node in: inner]]].
			remaining := Rectangle
				origin: x @ ((y + thickness) truncated)
				corner: aRectangle bottomRight].
	^ remaining
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 18:58'
}
SWASpaceTallyTreemapMorph >> ensureCachedForm [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 18:58'
}
SWASpaceTallyTreemapMorph >> ensureLayout [
	"Recompute the tile list (and drop the cached form) if needed."

	layoutValid ifTrue: [^ self].
	self computeLayout.
	cachedForm := nil.
	layoutValid := true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:17'
}
SWASpaceTallyTreemapMorph >> exploreNode: aNode [
	"Open an ObjectExplorer rooted at aNode (uses SWASpaceTally's own explorer hook)."

	ToolSet explore: aNode
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:57'
}
SWASpaceTallyTreemapMorph >> extent: aPoint [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:57'
}
SWASpaceTallyTreemapMorph >> flushCache [
	"Drop the cached Form so the next draw rebuilds it."

	cachedForm := nil.
	resizeDeferring := false.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self changed
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:51'
}
SWASpaceTallyTreemapMorph >> initialize [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:31'
}
SWASpaceTallyTreemapMorph >> innerRectFor: aRectangle [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:59'
}
SWASpaceTallyTreemapMorph >> labelFor: aNode inWidth: maxPixels [
	"Build a short label: 'edgeLabel: className  bytes'. Caller already gated on
	 tile area; we still trim the label and skip the byte suffix when very narrow."

	| edge name bytes core |
	maxPixels < 16 ifTrue: [^ nil].
	edge := aNode edgeLabel.
	name := aNode className
		ifNil: [aNode name ifNil: ['?']]
		ifNotNil: [:c | c asString].
	core := edge
		ifNil: [name]
		ifNotNil: [edge asString , ': ' , name].
	bytes := SWASpaceTally formatBytes: (aNode totalSize ifNil: [0]).
	maxPixels < 80 ifTrue: [^ core].
	^ core , '  ' , bytes
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:31'
}
SWASpaceTallyTreemapMorph >> layoutChildrenOf: aNode in: aRectangle [
	"Squarify aNode's children into aRectangle; for each child tile, recurse if
	 it is large enough and has children of its own. Appends to `tiles` in
	 draw order: parent tile, then child tiles inside it."

	| kids total area scales |
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:26'
}
SWASpaceTallyTreemapMorph >> minTileForLabel [
	^ minTileForLabel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:27'
}
SWASpaceTallyTreemapMorph >> overlayMorph: aMorph [
	overlayMorph := aMorph
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:30'
}
SWASpaceTallyTreemapMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Paint every tile in draw order into aCanvas. No header, no hover."

	| font fontH borderColor bitmapMode |
	font := Preferences standardSystemFont.
	fontH := font height.
	bitmapMode := self colorMode == #bitmap.
	aCanvas fillRectangle: (anOrigin extent: self extent) color: Color black.
	borderColor := Color gray: 0.2.
	tiles do: [:assoc | | node r screenR fill labelStr labelClip |
		node := assoc key. r := assoc value.
		screenR := r translateBy: anOrigin.
		"Always fill with the mode color first."
		fill := self colorForNode: node.
		aCanvas fillRectangle: screenR color: fill.
		"In bitmap mode, overlay the actual Form (width-scaled, clipped)."
		bitmapMode ifTrue: [
			self drawBitmapNode: node in: screenR on: aCanvas].
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:15'
}
SWASpaceTallyTreemapMorph >> rootNode [
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 12:04'
}
SWASpaceTallyTreemapMorph >> selectionPathMorph: aMorph [
	selectionPathMorph := aMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:27'
}
SWASpaceTallyTreemapMorph >> setRoot: aSWASpaceTally [
	rootNode := aSWASpaceTally.
	currentNode := aSWASpaceTally.
	layoutValid := false.
	self changed.
	^ self
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:15'
}
SWASpaceTallyTreemapMorph >> squarify: nodeArray scales: areaArray into: aRectangle [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 18:49'
}
SWASpaceTallyTreemapMorph >> step [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 18:49'
}
SWASpaceTallyTreemapMorph >> stepTime [
	"Poll at ~20fps while deferring resize."
	^ 50
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:32'
}
SWASpaceTallyTreemapMorph >> tileAtLocal: aLocalPoint [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:18'
}
SWASpaceTallyTreemapMorph >> tiles [
	"For debugging: returns the cached tile list (Associations node -> Rectangle)."
	^ tiles
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:27'
}
SWASpaceTallyTreemapMorph >> updateBreadcrumb [
	breadcrumbMorph ifNotNil: [
		breadcrumbMorph contents: self breadcrumbString]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 12:04'
}
SWASpaceTallyTreemapMorph >> updateSelectionPath: aNodeOrNil [
	"Update the selection path label to show the full path to aNodeOrNil."

	selectionPathMorph ifNil: [^ self].
	aNodeOrNil
		ifNil: [selectionPathMorph contents: '']
		ifNotNil: [selectionPathMorph contents: aNodeOrNil pathString]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:15'
}
SWASpaceTallyTreemapMorph >> worstAspectRatio: indexRow areas: areaArray sum: rowSum side: shortSide [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:39'
}
SWASpaceTallyTreemapMorph >> zoomInto: aNode [
	"Make aNode the new focus, if it has children. Push current view onto history."

	| kids |
	kids := aNode children.
	(kids isNil or: [kids isEmpty]) ifTrue: [^ self].
	history addLast: currentNode.
	currentNode := aNode.
	layoutValid := false.
	cachedForm := nil.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self updateBreadcrumb.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:39'
}
SWASpaceTallyTreemapMorph >> zoomOut [
	"Go back to the previous view from history."

	history isEmpty ifTrue: [^ self].
	currentNode := history removeLast.
	layoutValid := false.
	cachedForm := nil.
	overlayMorph ifNotNil: [overlayMorph clearHover].
	self updateBreadcrumb.
	self changed
]
