"
Parses Graphviz `dot -Tjson` output into pixel-space geometry for GraphvizMorph.

More robust than the whitespace-tokenized `-Tplain` format: JSON is properly structured and, crucially, carries per-field rectangles for `shape=record` nodes (the `rects` attribute), enabling sub-node (e.g. per-method) click granularity.

Coordinate system: Graphviz JSON positions are in POINTS with a bottom-left origin. `bb` (x0,y0,x1,y1) is the graph bounding box. We scale points to the rendered PNG's pixel extent and flip Y to a top-left origin.

Produces:
- nodeRects: Dictionary nodeName -> whole-node pixel Rectangle.
- fieldRects: OrderedCollection of Associations (nodeName -> Array{ fieldIndex. pixelRect }), top-to-bottom, for record sub-fields. Empty for non-record nodes.

Use: GraphvizJsonParser parse: jsonString pixelExtent: aForm extent.
"
Class {
	#name : #GraphvizJsonParser,
	#superclass : #Object,
	#instVars : [
		'pixelExtent',
		'graphSize',
		'scale',
		'nodeRects',
		'fieldRects'
	],
	#category : #'SWA-Graphviz',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser class >> parse: jsonString pixelExtent: aPoint [
	"Parse jsonString (dot -Tjson output) mapping onto aPoint pixel extent.
	Answer the parser."
	^ self new
		pixelExtent: aPoint;
		parse: jsonString;
		yourself
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:49'
}
GraphvizJsonParser >> addRecordFieldsFor: name rects: rectsString gx0: gx0 gy0: gy0 sx: sx sy: sy [
	"shape=record: one field rect per space-separated 'x0,y0,x1,y1' token."
	(rectsString findTokens: ' ') doWithIndex: [:fieldStr :i | | coords |
		coords := (fieldStr findTokens: ',') collect: [:t | t asNumber].
		coords size = 4 ifTrue: [
			fieldRects add: (name -> {
				i - 1.
				self pixelRectFromX0: (coords at: 1) y0: (coords at: 2)
					x1: (coords at: 3) y1: (coords at: 4)
					gx0: gx0 gy0: gy0 sx: sx sy: sy }) ]]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:16'
}
GraphvizJsonParser >> addTextRowFieldsFor: name object: obj wholeBox: wholeBox gx0: gx0 gy0: gy0 sx: sx sy: sy [
	"HTML-like (<table>) node: no explicit field 'rects'. Derive one field rect per
	text ROW from the exact table geometry Graphviz gives us: the border 'p' polygon
	is the precise cell area, and the 'T' text ops give one baseline per row.

	Method rows have a UNIFORM pitch; the first (class-name) row is taller (bold,
	larger font), so its baseline sits lower in its cell. Using the name<->method
	baseline MIDPOINT as their boundary therefore biased the first method row upward
	(it ate into the name row). Instead we place every INTERIOR boundary a uniform
	half-pitch above the lower row's baseline (pitch = the method baseline spacing),
	which is exact for the equal-height method rows and correct for the name<->method
	boundary too. First/last boundaries are the border polygon edges.
	Field index i matches recordFieldNodes."
	| ldraw pixelBaselines borderTop borderBottom pitch rowTop rowBottom left right |
	ldraw := obj at: '_ldraw_' ifAbsent: [^ self].
	pixelBaselines := (ldraw select: [:op | (op at: 'op' ifAbsent: ['']) = 'T'])
		collect: [:op | self pixelYFor: (((op at: 'pt') at: 2)) gy0: gy0 sy: sy].
	pixelBaselines isEmpty ifTrue: [^ self].
	left := wholeBox left. right := wholeBox right.
	borderTop := wholeBox top. borderBottom := wholeBox bottom.
	(self borderPolygonYRangeOf: ldraw gy0: gy0 sy: sy) ifNotNil: [:range |
		borderTop := range first. borderBottom := range second].
	"Uniform method-row pitch in pixels: the gap between the last two baselines
	(all method rows share it). Falls back to the whole span for single-row tables."
	pitch := pixelBaselines size >= 3
		ifTrue: [(pixelBaselines last) - (pixelBaselines at: pixelBaselines size - 1)]
		ifFalse: [borderBottom - borderTop].
	pixelBaselines doWithIndex: [:py :i |
		"Boundary above row i sits half a method-pitch above THIS row's baseline
		(exact for uniform rows, and unbiased at the taller name row)."
		rowTop := i = 1
			ifTrue: [borderTop]
			ifFalse: [py - (pitch / 2)].
		rowBottom := i = pixelBaselines size
			ifTrue: [borderBottom]
			ifFalse: [(pixelBaselines at: i + 1) - (pitch / 2)].
		fieldRects add: (name -> {
			i - 1.
			(left @ rowTop) corner: (right @ rowBottom) }) ]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:12'
}
GraphvizJsonParser >> borderPolygonYRangeOf: ldrawOps gy0: gy0 sy: sy [
	"For an HTML-table node, the first 'p' (polygon) op in _ldraw_ is the table's
	border rectangle -- the exact cell area. Answer { pixelTop. pixelBottom } from
	its point-Y extent, or nil if there is no polygon."
	| poly ys |
	poly := ldrawOps detect: [:op | (op at: 'op' ifAbsent: ['']) = 'p'] ifNone: [nil].
	poly ifNil: [^ nil].
	ys := (poly at: 'points') collect: [:pt | pt at: 2].
	ys isEmpty ifTrue: [^ nil].
	"Larger point-Y is higher on screen -> smaller pixel-Y (top)."
	^ { self pixelYFor: ys max gy0: gy0 sy: sy.
	    self pixelYFor: ys min gy0: gy0 sy: sy }
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> fieldRects [
	"OrderedCollection of Associations nodeName -> { fieldIndex. pixelRect },
	top-to-bottom, for shape=record sub-fields. Empty when no records."
	^ fieldRects
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> graphSize [
	"Graph bounding-box size in points (Graphviz 'bb' extent)."
	^ graphSize
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> nodeRects [
	"Dictionary nodeName (String) -> whole-node Rectangle in pixel coordinates."
	^ nodeRects
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> parse: jsonString [
	"Parse dot -Tjson output. Populate graphSize, scale, nodeRects and fieldRects.
	All geometry is mapped from Graphviz points (bottom-left origin) to the
	rendered PNG's pixel space (top-left origin, Y flipped)."
	| root bb x0 y0 x1 y1 sx sy |
	nodeRects := Dictionary new.
	fieldRects := OrderedCollection new.
	root := STONJSON fromString: jsonString.
	bb := ((root at: 'bb' ifAbsent: ['0,0,1,1']) findTokens: ',') collect: [:t | t asNumber].
	x0 := bb at: 1. y0 := bb at: 2. x1 := bb at: 3. y1 := bb at: 4.
	graphSize := (x1 - x0) @ (y1 - y0).
	sx := graphSize x = 0 ifTrue: [1] ifFalse: [pixelExtent x / graphSize x].
	sy := graphSize y = 0 ifTrue: [1] ifFalse: [pixelExtent y / graphSize y].
	scale := sx.
	(root at: 'objects' ifAbsent: [#()]) do: [:obj |
		self parseObject: obj x0: x0 y0: y0 sx: sx sy: sy].
	^ self
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:49'
}
GraphvizJsonParser >> parseObject: obj x0: gx0 y0: gy0 sx: sx sy: sy [
	"Record one node's whole-box rectangle in nodeRects, plus one rectangle per
	field in fieldRects (top-to-bottom). shape=record nodes carry explicit field
	'rects'; HTML-like (plaintext <table>) nodes do not, so we derive per-row rects
	from the text baselines in '_ldraw_'."
	| name rectsString wholeBox |
	name := obj at: 'name' ifAbsent: [^ self].
	wholeBox := self wholeBoxFor: obj x0: gx0 y0: gy0 sx: sx sy: sy.
	wholeBox ifNil: [^ self].
	nodeRects at: name put: wholeBox.
	rectsString := obj at: 'rects' ifAbsent: [nil].
	rectsString
		ifNotNil: [self addRecordFieldsFor: name rects: rectsString
			gx0: gx0 gy0: gy0 sx: sx sy: sy]
		ifNil: [self addTextRowFieldsFor: name object: obj wholeBox: wholeBox
			gx0: gx0 gy0: gy0 sx: sx sy: sy]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> pixelExtent: aPoint [
	pixelExtent := aPoint
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> pixelRectFromX0: px0 y0: py0 x1: px1 y1: py1 gx0: gx0 gy0: gy0 sx: sx sy: sy [
	"Map a Graphviz point-space rect (bottom-left origin, relative to graph bb
	origin gx0@gy0) to a pixel Rectangle in the PNG (top-left origin, Y flipped)."
	| left right top bottom |
	left := (px0 - gx0) * sx.
	right := (px1 - gx0) * sx.
	"Flip Y: larger point-y is higher on screen (smaller pixel-y)."
	top := pixelExtent y - ((py1 - gy0) * sy).
	bottom := pixelExtent y - ((py0 - gy0) * sy).
	^ (left @ top) corner: (right @ bottom)
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:12'
}
GraphvizJsonParser >> pixelYFor: aPointY gy0: gy0 sy: sy [
	"Map a Graphviz point-space Y (bottom-left origin, relative to bb origin gy0)
	to a pixel Y (top-left origin, flipped)."
	^ pixelExtent y - ((aPointY - gy0) * sy)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> scale [
	"Points-per-pixel-ish scale factor (kept for parity with the plain parser)."
	^ scale
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:41'
}
GraphvizJsonParser >> wholeBoxFor: obj x0: gx0 y0: gy0 sx: sx sy: sy [
	"The node's whole bounding box as a pixel Rectangle. Prefer 'rects' (records:
	union of fields), else derive from pos + width/height (inches -> points).
	Answer nil if the object carries no usable geometry (e.g. a subgraph)."
	| rectsString pos w h cx cy hw hh |
	rectsString := obj at: 'rects' ifAbsent: [nil].
	rectsString ifNotNil: [ | xs ys |
		xs := OrderedCollection new. ys := OrderedCollection new.
		(rectsString findTokens: ' ') do: [:fieldStr | | c |
			c := (fieldStr findTokens: ',') collect: [:t | t asNumber].
			c size = 4 ifTrue: [
				xs add: (c at: 1); add: (c at: 3).
				ys add: (c at: 2); add: (c at: 4)]].
		xs isEmpty ifTrue: [^ nil].
		^ self pixelRectFromX0: xs min y0: ys min x1: xs max y1: ys max
			gx0: gx0 gy0: gy0 sx: sx sy: sy].
	pos := obj at: 'pos' ifAbsent: [^ nil].
	pos := (pos findTokens: ',') collect: [:t | t asNumber].
	pos size = 2 ifFalse: [^ nil].
	cx := pos at: 1. cy := pos at: 2.
	w := (obj at: 'width' ifAbsent: ['0']) asNumber * 72.
	h := (obj at: 'height' ifAbsent: ['0']) asNumber * 72.
	hw := w / 2. hh := h / 2.
	^ self pixelRectFromX0: cx - hw y0: cy - hh x1: cx + hw y1: cy + hh
		gx0: gx0 gy0: gy0 sx: sx sy: sy
]
