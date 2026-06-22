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
	#superclass : #SWATreemapMorph,
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:09'
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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:09'
}
SWASpaceTallyTreemapMorph >> drawTileContent: aNode in: screenR on: aCanvas [
	"In bitmap color mode, overlay the actual Form for Form-bits tiles."
	self colorMode == #bitmap ifTrue: [
		self drawBitmapNode: aNode in: screenR on: aCanvas]
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:10'
}
SWASpaceTallyTreemapMorph >> formatWeight: aNumber [
	"SpaceTally weights are byte counts."
	^ SWASpaceTally formatBytes: aNumber
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:57'
}
SWASpaceTallyTreemapMorph >> metaInfoString [
	"Meta line: focused subtree's total bytes + immediate child count.
	(SWANavPanel content protocol.)"
	| focus kids |
	focus := currentNode ifNil: [rootNode].
	focus ifNil: [^ ''].
	kids := focus children ifNil: [#()].
	^ focus name, '   ', (focus formatBytes: focus totalSize),
		'   ', kids size printString, ' children'
]
