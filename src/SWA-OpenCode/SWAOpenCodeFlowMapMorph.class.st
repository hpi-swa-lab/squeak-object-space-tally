"
The conversation as a 2D MAP instead of a strip.

A session is not really a list, it is a sequence of TURNS: you ask something, the agent thinks and works until it needs you again, you ask the next thing. The strip (SWAOpenCodeFlowMorph) renders that as one very long column, which spends the whole width of the window on four lanes and the whole height on what is mostly tool output. A ten-turn session is metres tall and you can never see two turns at once.

Here each turn is a COLUMN. The user messages line up in a header row across the top, left to right, so the top edge of the window is the list of things you actually asked. Everything the agent did in answer -- assistant text, reasoning, tool calls -- hangs beneath its own question, top to bottom. The shape of a column is then the shape of the work that one question cost, and columns are directly comparable side by side.

PIVOT transposes it: questions run down the left edge and each answer runs off to the right. Same data, and worth having as a toggle rather than an argument because which one reads better depends entirely on whether a session is many short turns or few long ones.

Both cell axes are configurable and independent (#xSizeMode / #ySizeMode over the same catalogue as the strip's height, times #zoomX / #zoom). With both on #uniform the cells are squares and the map is pure structure; put duration on one axis and cost on the other and it becomes a scatter of the session's two budgets.
"
Class {
	#name : #SWAOpenCodeFlowMapMorph,
	#superclass : #SWAOpenCodeFlowView,
	#instVars : [
		'turns',
		'pivot',
		'zoomX',
		'xSizeMode',
		'scrollX',
		'contentWidthPx',
		'dragStartX',
		'dragStartScrollX'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> cellExtentFor: aNode [
	"The cell aNode wants, before the grid squares anything off. The two axes are
	INDEPENDENT: same catalogue of size modes, one zoom each."
	^ ((self sizeUnitFor: aNode mode: xSizeMode) * zoomX)
		@ ((self sizeUnitFor: aNode mode: yMode) * zoom)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> cellGap [
	"Vanishes when zoomed far out: at a few pixels per cell the gap would be half
	the picture, and the point of zooming out is a continuous shape, not a grid of
	dots."
	^ (zoom min: zoomX) < 0.6 ifTrue: [0] ifFalse: [2]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> clampScroll [
	super clampScroll.
	scrollX := ((scrollX ifNil: [0]) max: 0)
		min: (((contentWidthPx ifNil: [0]) - self width) max: 0)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> computeLayout [
	"Turns across, answers down -- or transposed under #pivot."
	pivot ifTrue: [^ self computeLayoutPivoted].
	^ self computeLayoutColumns
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> computeLayoutColumns [
	"One COLUMN per turn, left to right in conversation order. The user message sits
	in the header band across the top; everything the agent did in answer stacks
	beneath it.

	The band is ONE height for every turn -- the tallest header -- so the questions
	line up as an actual row. Letting each header take its own height would stagger
	the tops of the columns and destroy the one reading this layout exists for.

	Positions accumulate as FLOATS and only the BOUNDARIES are rounded, as in the
	strip: a Rectangle with fractional coordinates cannot be blitted, and rounding
	each cell's size independently would let a column drift by a pixel per cell."
	| xf gap band top maxY |
	gap := self cellGap.
	band := self headerBand.
	top := self topInset asFloat.
	xf := self sideInset asFloat.
	maxY := top.
	self turns do: [:turn |
		| colW yf hdr left right |
		colW := self spanOf: turn axis: #x.
		left := xf rounded.
		right := ((xf + colW - gap) rounded) max: left + 1.
		hdr := self headerIndexOf: turn.
		hdr ifNotNil: [
			layout at: hdr put: (left @ top rounded
				corner: right @ (((top + band - gap) rounded) max: top rounded + 1))].
		yf := top + band.
		turn do: [:i |
			i = hdr ifFalse: [
				| h t |
				h := (self cellExtentFor: (self items at: i)) y.
				t := yf rounded.
				layout at: i put: (left @ t
					corner: right @ (((yf + h - gap) rounded) max: t + 1)).
				yf := yf + h]].
		maxY := maxY max: yf.
		xf := xf + colW].
	contentWidthPx := xf rounded + self sideInset.
	contentHeight := maxY rounded + self topInset
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> computeLayoutPivoted [
	"The transpose: one ROW per turn, questions down the left edge, each answer
	running off to the right.

	Not a different tool, a different aspect ratio. Columns suit a session of many
	short turns; rows suit a few long ones, where a turn's work is a long horizontal
	trail and stacking them vertically is what lets you compare their lengths."
	| yf gap band left maxX |
	gap := self cellGap.
	band := self headerBand.
	left := self sideInset asFloat.
	yf := self topInset asFloat.
	maxX := left.
	self turns do: [:turn |
		| rowH xf hdr top bottom |
		rowH := self spanOf: turn axis: #y.
		top := yf rounded.
		bottom := ((yf + rowH - gap) rounded) max: top + 1.
		hdr := self headerIndexOf: turn.
		hdr ifNotNil: [
			layout at: hdr put: (left rounded @ top
				corner: (((left + band - gap) rounded) max: left rounded + 1) @ bottom)].
		xf := left + band.
		turn do: [:i |
			i = hdr ifFalse: [
				| w l |
				w := (self cellExtentFor: (self items at: i)) x.
				l := xf rounded.
				layout at: i put: (l @ top
					corner: (((xf + w - gap) rounded) max: l + 1) @ bottom).
				xf := xf + w]].
		maxX := maxX max: xf.
		yf := yf + rowH].
	contentWidthPx := maxX rounded + self sideInset.
	contentHeight := yf rounded + self topInset
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> flushLayout [
	"Turns are derived from #items, so they must die with it."
	turns := nil.
	super flushLayout
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> headerBand [
	"Thickness of the band the user messages occupy -- the tallest header cell in
	column mode, the widest in pivot mode. Zero when the session has no user message
	at all, so a map of pure tool traffic wastes no space on an empty band."
	| best |
	best := 0.0.
	self turns do: [:turn |
		(self headerIndexOf: turn) ifNotNil: [:i |
			| e |
			e := self cellExtentFor: (self items at: i).
			best := best max: (pivot ifTrue: [e x] ifFalse: [e y])]].
	^ best
]

{
	#category : #turns,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> headerIndexOf: aTurn [
	"The item that HEADS this turn -- the user message -- or nil for a leading turn
	that has none. Its cell goes in the header band, not in the body stack."
	^ aTurn detect: [:i | (self laneKeyFor: (self items at: i)) == #user] ifNone: [nil]
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> initialize [
	super initialize.
	pivot := false.
	scrollX := 0.
	"BOTH axes uniform, so the default map is squares and reads as pure structure:
	how many turns, how much work each one took. Any quantity you put on an axis
	from here is a deliberate question, not the default view."
	xSizeMode := #uniform.
	yMode := #uniform.
	"Bigger than the strip's zoom 1. A uniform unit is 18 px, which is a legible row
	in a column but an illegible square in a grid; 3.5 puts a cell at ~63 px, enough
	for a couple of lines of the label."
	zoom := 3.5.
	zoomX := 3.5
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:05'
}
SWAOpenCodeFlowMapMorph >> mapExtent [
	"Size of the whole map in content pixels. Distinct from #contentWidth, which is
	the VIEWPORT width minus the scrollbar gutter -- an inherited name that means
	something else and must not be shadowed."
	^ (contentWidthPx ifNil: [0]) @ (contentHeight ifNil: [0])
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> mouseDown: evt [
	"Arm the horizontal half of the pan as well, then let the inherited state
	machine do the rest."
	dragStartX := evt position x.
	dragStartScrollX := scrollX.
	^ super mouseDown: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> mouseMove: evt [
	"Drag anywhere to pan in BOTH directions. A map is wider than its window far
	more often than it is taller, so a vertical-only pan would leave most of it
	unreachable."
	| d |
	dragMode == #pan ifFalse: [^ super mouseMove: evt].
	d := evt position - (dragStartX @ dragStartY).
	"THRESHOLD: below this the gesture is still a click, measured on the whole
	vector rather than on y alone -- otherwise a purely horizontal drag never
	crosses it and the map refuses to pan sideways."
	(didDrag or: [d r >= self dragThreshold]) ifFalse: [^ self].
	didDrag := true.
	scrollX := dragStartScrollX - d x.
	self clampScroll.
	self scrollTo: dragStartScroll - d y.
	self changed
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> narrow [
	^ self zoomX: 0.77 y: 1.0 at: (self width // 2) @ (self height // 2)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> pivot: aBoolean [
	"Transpose. Scroll goes home because the axis you were scrolled along is now the
	other one, and keeping the numbers would land you somewhere arbitrary."
	pivot := aBoolean.
	scrollX := 0.
	scrollY := 0.
	self flushLayout
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> resetZoom [
	zoom := 3.5.
	zoomX := 3.5.
	scrollX := 0.
	self flushLayout.
	self scrollTo: 0
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:05'
}
SWAOpenCodeFlowMapMorph >> scrollHome [
	scrollX := 0.
	^ super scrollHome
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> scrollOffset [
	"2D: the map is routinely wider than the window, which a strip never is."
	^ (scrollX ifNil: [0]) @ scrollY
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> shorter [
	^ self zoomX: 1.0 y: 0.77 at: (self width // 2) @ (self height // 2)
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> showMenuAt: aPoint [
	| m sub |
	m := MenuMorph new defaultTarget: self.
	m addTitle: 'flow map'.
	m add: (pivot ifTrue: ['<on>'] ifFalse: ['<off>']) , 'pivot (turns down the side)'
		target: self selector: #togglePivot.
	m addLine.
	sub := MenuMorph new defaultTarget: self.
	self sizeModeOptions do: [:p |
		sub add: (xSizeMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
			target: self selector: #xSizeMode: argument: p first].
	m add: 'cell width' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	self sizeModeOptions do: [:p |
		sub add: (yMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
			target: self selector: #yMode: argument: p first].
	m add: 'cell height' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	{{#none. 'Nothing'}. {#label. 'Label'}. {#preview. 'Preview'}. {#full. 'Full text (loads!)'}}
		do: [:p | sub add: (contentMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
				target: self selector: #contentMode: argument: p first].
	m add: 'content' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	self colorModeOptions do: [:p |
		sub add: (colorMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
			target: self selector: #colorMode: argument: p first].
	m add: 'colour' subMenu: sub.
	m addLine.
	m add: 'inspect item (all data)' target: self selector: #inspectSelection.
	m addLine.
	m add: 'wider' target: self selector: #widen.
	m add: 'narrower' target: self selector: #narrow.
	m add: 'taller' target: self selector: #taller.
	m add: 'shorter' target: self selector: #shorter.
	m addLine.
	m add: 'zoom in (both)' target: self selector: #zoomIn.
	m add: 'zoom out (both)' target: self selector: #zoomOut.
	m add: 'zoom to fit (whole map)' target: self selector: #zoomToFit.
	m add: 'reset zoom' target: self selector: #resetZoom.
	m popUpAt: aPoint forHand: self activeHand in: self world
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> sizeModeOptions [
	"One catalogue, offered to BOTH axes -- see #sizeUnitFor:mode:."
	^ {
		{#uniform. 'Uniform (square)'}.
		{#content. 'Content size (log)'}.
		{#loc. 'Lines of content (linear)'}.
		{#bytes. 'Content length (linear)'}.
		{#duration. 'Duration'}.
		{#msgCost. 'Message cost'}.
		{#msgContext. 'Message context'}
	}
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> spanOf: aTurn axis: aSymbol [
	"How wide a turn's COLUMN is (axis #x) or how tall its ROW is (axis #y): the
	largest cell in it along that axis, so a turn of small tool calls stays narrow
	and a turn that read a whole file gets the room it needs.

	Per-turn rather than one width for the whole map: making every column as wide as
	the widest cell anywhere would let a single 300 kB file read set the gauge for a
	session of one-line evaluations."
	| f |
	f := aSymbol == #x
		ifTrue: [[:n | (self cellExtentFor: n) x]]
		ifFalse: [[:n | (self cellExtentFor: n) y]].
	^ aTurn inject: 8.0 into: [:a :i | a max: (f value: (self items at: i))]
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> taller [
	^ self zoomX: 1.0 y: 1.3 at: (self width // 2) @ (self height // 2)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> togglePivot [
	^ self pivot: pivot not
]

{
	#category : #turns,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:02'
}
SWAOpenCodeFlowMapMorph >> turns [
	"The conversation cut into TURNS: an Array of Arrays of item INDICES, each turn
	being one user message and everything that followed it until the next.

	Indices, not nodes, because the layout is an Array parallel to #items and every
	other part of the machinery -- drawing, hover, hit testing -- addresses items by
	index.

	A new turn starts at a user item only when the PREVIOUS item was not one: a
	single user message can arrive as several parts (text plus a pasted file), and
	splitting those into separate turns would invent questions that were never
	asked. Anything before the first user message -- a session that opens with a
	system or assistant part -- forms a leading turn of its own rather than being
	dropped."
	turns ifNotNil: [^ turns].
	turns := OrderedCollection new.
	self items ifEmpty: [^ turns := #()].
	self items doWithIndex: [:n :i |
		| isUser startsTurn |
		isUser := (self laneKeyFor: n) == #user.
		startsTurn := turns isEmpty
			or: [isUser and: [(self laneKeyFor: (self items at: i - 1)) ~~ #user]].
		startsTurn ifTrue: [turns add: OrderedCollection new].
		turns last add: i].
	turns := (turns collect: [:t | t asArray]) asArray.
	^ turns
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> visibleIndicesDo: aBlock [
	"Walk TURN BY TURN, rejecting a whole turn before looking at any of its cells.

	The strip can binary-search because its rectangles are sorted in y. These are
	not -- turn 9 starts at the top of the window again -- so the structure to
	exploit is the turn instead: every cell of a turn shares the same span on the
	CROSS axis (one column's left..right, one row's top..bottom), so one test
	against the turn's first cell decides the lot. A session scrolled to turn 30
	then costs 30 comparisons plus the cells of the turns actually on screen."
	| lay band |
	lay := self ensureLayout.
	band := self visibleContentRect.
	self turns do: [:turn |
		| r |
		r := lay at: turn first.
		(pivot
			ifTrue: [r bottom >= band top and: [r top <= band bottom]]
			ifFalse: [r right >= band left and: [r left <= band right]])
		ifTrue: [
			turn do: [:i |
				((lay at: i) intersects: band) ifTrue: [aBlock value: i]]]]
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> widen [
	^ self zoomX: 1.3 y: 1.0 at: (self width // 2) @ (self height // 2)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:03'
}
SWAOpenCodeFlowMapMorph >> xSizeMode: aSymbol [
	"What decides cell WIDTH -- the same catalogue the strip offers for height.
	Independent of #yMode on purpose: the pair is a 2D reading, and pinning them
	together would throw away the only thing a map can say that a strip cannot."
	xSizeMode := aSymbol.
	self flushLayout
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:05'
}
SWAOpenCodeFlowMapMorph >> zoomBarSpecs [
	"{ label. selector. balloon }. The two axis pairs are on the bar and not only in
	the menu: reshaping the cells is the thing you do constantly while reading a
	map, and a menu round-trip per nudge makes that unusable."
	^ {
		{'-'.    #zoomOut.    'Zoom out (both axes)'}.
		{'+'.    #zoomIn.     'Zoom in (both axes)'}.
		{'<>'.   #widen.      'Wider cells'}.
		{'><'.   #narrow.     'Narrower cells'}.
		{'^v'.   #taller.     'Taller cells'}.
		{'v^'.   #shorter.    'Shorter cells'}.
		{'pvt'.  #togglePivot. 'Pivot: turns down the side instead of across the top'}.
		{'fit'.  #zoomToFit.  'Fit the whole map on screen'}.
		{'top'.  #scrollHome. 'Back to the start'}
	}
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> zoomBy: aFactor at: aLocalY [
	"CTRL-wheel scales BOTH axes together, keeping the point under the pointer put.
	Zooming one axis at a time is available from the menu; doing it on the wheel
	would mean the map changes aspect ratio every time you look closer, which is
	disorienting."
	^ self zoomX: aFactor y: aFactor at: (self width // 2) @ aLocalY
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> zoomToFit [
	"Bring the WHOLE map on screen. Solved by ITERATION, not in closed form: unlike
	the strip, cell sizes here pass through per-turn maxima and the header band
	before they become a total, so the content size is only piecewise linear in the
	zooms. Three passes of 'scale by the ratio that is still wrong' converge to
	within a pixel or two, which is all this needs to be."
	self items isEmpty ifTrue: [^ self].
	3 timesRepeat: [
		| fx fy |
		layout := nil.
		self ensureLayout.
		fx := (self width - (self sideInset * 2)) / ((contentWidthPx - (self sideInset * 2)) max: 1).
		fy := (self height - (self topInset * 2)) / ((contentHeight - (self topInset * 2)) max: 1).
		zoomX := (zoomX * fx) min: 60.0 max: 0.0002.
		zoom := (zoom * fy) min: 60.0 max: 0.0002].
	layout := nil.
	self ensureLayout.
	scrollX := 0.
	scrollY := 0.
	self changed
]

{
	#category : #zoom,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:04'
}
SWAOpenCodeFlowMapMorph >> zoomX: fx y: fy at: aLocalPoint [
	"Scale the two axes independently, KEEPING THE CONTENT UNDER aLocalPoint PUT.
	Anchoring on the corner instead makes the map shoot away under the cursor, which
	is the difference between a usable zoom and an unusable one."
	| ax ay newX newY |
	ax := (scrollX + aLocalPoint x) / ((contentWidthPx ifNil: [1]) max: 1).
	ay := (scrollY + aLocalPoint y) / ((contentHeight ifNil: [1]) max: 1).
	newX := (zoomX * fx) min: 60.0 max: 0.0002.
	newY := (zoom * fy) min: 60.0 max: 0.0002.
	(newX = zoomX and: [newY = zoom]) ifTrue: [^ self].
	zoomX := newX.
	zoom := newY.
	layout := nil.
	self ensureLayout.
	scrollX := ((ax * contentWidthPx) - aLocalPoint x) rounded.
	scrollY := ((ay * contentHeight) - aLocalPoint y) rounded.
	self clampScroll.
	self changed
]
