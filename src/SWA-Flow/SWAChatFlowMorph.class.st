"
A ZOOMABLE FLOW: a sequence of nodes laid out top to bottom, where height,
horizontal placement, colour and rendered content are each bound to a
SEPARATE mapping. Born as an abstraction of a chat transcript, but it knows
nothing about chat -- it reads plain SWANode protocol, so any ordered node
sequence can be poured through it.

WHY NOT A TREEMAP. A treemap answers 'how big is this relative to that' and
destroys order to do it. A conversation, a log, a trace is a SEQUENCE: the
question is what followed what, and how big that was. Reading order is the
one thing a treemap cannot preserve, so it needs its own view rather than
another colouring of an existing one.

THE FOUR INDEPENDENT AXES (each switchable from the menu):

	yMode        row HEIGHT -- #uniform, #content (proportional to totalSize),
	             #duration. This is the axis that carries magnitude.
	xMode        horizontal placement -- #full, #lane (items sorted into
	             columns by kind, the chat metaphor: one side asks, the other
	             answers), #indent (by tree depth), #metric (bar width
	             proportional to totalSize).
	colorMode    inherited from SWAView, so any bound DATASET METRIC colours
	             this view exactly as it colours a treemap -- plus the
	             intrinsic modes below.
	contentMode  what is drawn INSIDE a row -- #none, #label, #preview
	             (#previewChars characters), #full.

ZOOM IS THE POINT, and it is a zoom of the Y axis only. Far out, every item
is a one-pixel line and the whole session is a single legible shape -- where
the big reads were, where the long silences were. Far in, rows are tall
enough to render their actual text. It is the same view continuously, not a
switch between an overview mode and a detail mode.

Rows are VIRTUALISED: layout is computed once for all items, but only rows
intersecting the visible band are drawn. That is what lets 24000 items scroll
without a cached Form, and it is why this view (unlike the treemap and the
temporal views) does not keep one.
"
Class {
	#name : #SWAChatFlowMorph,
	#superclass : #SWAView,
	#instVars : [
		'items',
		'layout',
		'layoutExtent',
		'zoom',
		'xMode',
		'yMode',
		'colorMode',
		'contentMode',
		'hoverIndex',
		'dragMode',
		'dragStartY',
		'dragStartScroll',
		'didDrag',
		'loadingNode'
	],
	#category : #'SWA-Flow',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> baseColorForNode: aNode [
	"Dataset metrics win when bound to colour (SWAView handles that), so any metric
	that colours a treemap colours this view identically -- cost and token metrics
	included, without this class knowing what a token is."
	colorMode == #size ifTrue: [
		| f |
		f := (aNode totalSize max: 1) ln / (self maxItemSize max: 2) ln.
		^ Color h: 220 - (f * 190) s: 0.55 v: 0.75].
	colorMode == #lane ifTrue: [
		^ Color h: (self laneIndexFor: aNode) * 360 / self laneCount
			s: 0.45 v: 0.7].
	^ self intrinsicKindColorFor: aNode
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:38'
}
SWAChatFlowMorph >> byteSizeFor: aNode [
	| p |
	p := (aNode respondsTo: #payload) ifTrue: [aNode payload] ifFalse: [nil].
	^ (p notNil and: [p respondsTo: #byteSize])
		ifTrue: [p byteSize ifNil: [1]]
		ifFalse: [aNode totalSize max: 1]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> collectLeavesOf: aNode into: aCollection [
	aNode isLeaf
		ifTrue: [aCollection add: aNode]
		ifFalse: [aNode children do: [:c | self collectLeavesOf: c into: aCollection]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:43'
}
SWAChatFlowMorph >> colorMode [
	"SWAView answers nil by default ('the view has no switchable coloring') and
	SWAView>>colorMode: is a no-op. Both MUST be overridden by a view that recolors
	-- without this pair the colour menu set nothing and its checkmark sprang back
	to the old entry."
	^ colorMode ifNil: [colorMode := #kind]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:43'
}
SWAChatFlowMorph >> colorMode: aSymbol [
	"Colour affects only what is painted, never where anything sits, so this is a
	repaint and not a relayout."
	colorMode := aSymbol.
	self changed
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> colorModeOptions [
	^ {
		{#kind. 'Kind / role'}.
		{#lane. 'Lane (position)'}.
		{#size. 'Size'}
	}
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> contentColor [
	^ Color white
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> contentFont [
	^ self valueOfProperty: #contentFont ifAbsentPut: [
		[StrikeFont familyName: 'DejaVu Sans Mono' size: 9]
			on: Error do: [:e | TextStyle defaultFont]]
]

{
	#category : #modes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAChatFlowMorph >> contentMode: aSymbol [
	"Content does not affect layout -- only what is painted inside a row -- so this
	is a repaint, not a relayout."
	contentMode := aSymbol.
	self changed
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> contentTextFor: aNode [
	"#full asks the node for its whole source, which for an opencode part triggers
	the on-demand database fetch -- so it is deliberately NOT the default: scrolling
	in #full mode loads every row you pass. #preview and #label cost nothing."
	contentMode == #label ifTrue: [^ aNode name].
	contentMode == #preview ifTrue: [
		^ (aNode respondsTo: #previewString)
			ifTrue: [aNode previewString: self previewChars]
			ifFalse: [aNode name]].
	contentMode == #full ifTrue: [
		^ (aNode respondsTo: #sourceString)
			ifTrue: [[aNode sourceString] on: Error do: [:e | aNode name]]
			ifFalse: [aNode name]].
	^ aNode name
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAChatFlowMorph >> contentWidth [
	"The scrollbar gutter is reserved ALWAYS, not only when scrollable. Making it
	conditional would mean the layout depends on the content height, which depends
	on the layout -- and would also reflow every row the moment a zoom crossed the
	scrollable threshold."
	^ self width - self scrollBarWidth
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:38'
}
SWAChatFlowMorph >> detailInfoString [
	"One line for the pane's details box. Cost and tokens are the MESSAGE's, and
	are labelled 'msg' for that reason -- they cover every part of that message,
	so reading them as this part's cost would be wrong."
	| n d s |
	n := selectedNode ifNil: [^ ''].
	(n respondsTo: #payload) ifFalse: [^ n name].
	d := n payload.
	(d isKindOf: SWAOpenCodePart) ifFalse: [^ n name].
	s := WriteStream on: String new.
	s nextPutAll: d type asString.
	d tool ifNotNil: [:t | s nextPutAll: ' '; nextPutAll: t asString].
	d status ifNotNil: [:st | s nextPutAll: ' ('; nextPutAll: st asString; nextPut: $)].
	s nextPutAll: '   '; print: d byteSize; nextPutAll: ' bytes'.
	s nextPutAll: ', '; print: d lineCount; nextPutAll: ' lines'.
	d isContentLoaded ifFalse: [s nextPutAll: ' (est.)'].
	d messageData ifNotNil: [:m |
		(m at: 'cost' ifAbsent: [nil]) ifNotNil: [:c |
			s nextPutAll: '   msg cost $'; nextPutAll: (c asFloat printShowingDecimalPlaces: 4)].
		(m at: 'tokens' ifAbsent: [nil]) ifNotNil: [:tk |
			s nextPutAll: '   msg tokens '; print: (tk at: 'total' ifAbsent: [0]);
			  nextPutAll: ' (in '; print: (tk at: 'input' ifAbsent: [0]);
			  nextPutAll: ', out '; print: (tk at: 'output' ifAbsent: [0]);
			  nextPutAll: ', cache rd '; print: ((tk at: 'cache' ifAbsent: [Dictionary new]) at: 'read' ifAbsent: [0]);
			  nextPut: $)].
		(m at: 'modelID' ifAbsent: [nil]) ifNotNil: [:mid |
			s nextPutAll: '   '; nextPutAll: mid]].
	^ s contents
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:01'
}
SWAChatFlowMorph >> dragThreshold [
	^ 4
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> drawContentOf: aNode in: r on: aCanvas [
	"Text appears only when the row is TALL ENOUGH to hold a line. That is the
	whole zoom story: nothing switches modes, the same rows simply become legible
	as they grow, and shrink back to pure shape as they do not."
	| font lineH text lines y maxLines |
	contentMode == #none ifTrue: [^ self].
	font := self contentFont.
	lineH := font height.
	r height < (lineH + 2) ifTrue: [^ self].
	r width < 30 ifTrue: [^ self].
	text := self contentTextFor: aNode.
	text isEmptyOrNil ifTrue: [^ self].
	maxLines := (r height - 4) // lineH.
	lines := self wrap: text toWidth: r width - 8 font: font max: maxLines.
	y := r top + 2.
	lines do: [:ln |
		aCanvas
			drawString: ln
			at: (r left + 4) @ y
			font: font
			color: self contentColor.
		y := y + lineH]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> drawEmptyOn: aCanvas [
	aCanvas
		drawString: 'no items'
		at: self position + (12 @ 12)
		font: self contentFont
		color: (Color gray: 0.6)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:24'
}
SWAChatFlowMorph >> drawOn: aCanvas [
	"VIRTUALISED, and drawn straight to the canvas with no cached Form -- unlike
	the treemap and temporal views, which cache because they must redraw everything
	on every change. Here only the rows intersecting the visible band are touched,
	so a 24000-item flow costs the same as a 30-item one and scrolling stays smooth
	without any cache to invalidate."
	| lay top bottom i |
	aCanvas fillRectangle: self bounds color: self color.
	self ensureZoomBar.
	lay := self ensureLayout.
	lay isEmpty ifTrue: [^ self drawEmptyOn: aCanvas].
	top := scrollY.
	bottom := scrollY + self height.
	"CLIPPED: rows at the top and bottom edge are half outside the morph, and
	#drawString:at:font:color: does not clip -- without this the partial rows paint
	their text over whatever morph happens to sit next to this one."
	aCanvas clipBy: (self bounds insetBy: 0 @ 0) during: [:c |
		i := self firstIndexAtOrAfter: top.
		[i <= lay size and: [(lay at: i) top <= bottom]] whileTrue: [
			| rr |
			rr := (lay at: i) translateBy: self position - (0 @ scrollY).
			"Sub-pixel rows still have to be SEEN. Zoomed far out many rows round to
			zero height; giving each a single pixel is what turns the flow into a
			continuous band rather than a sparse comb of the few that survived."
			rr height < 1 ifTrue: [rr := rr origin corner: rr corner + (0 @ 1)].
			self drawRow: (self items at: i) rect: rr index: i on: c.
			i := i + 1]].
	self drawScrollIndicatorOn: aCanvas
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:11'
}
SWAChatFlowMorph >> drawRow: aNode rect: r index: i on: aCanvas [
	| c |
	c := self colorForNode: aNode.
	aCanvas fillRectangle: (r intersect: self bounds) color: c.
	"Below about four pixels a border is most of the row, and the flow reads as
	stripes of border rather than as content."
	r height >= 4 ifTrue: [
		aCanvas frameRectangle: (r intersect: self bounds)
			width: 1 color: (c darker alpha: 0.6)].
	self drawContentOf: aNode in: r on: aCanvas.
	aNode == selectedNode ifTrue: [
		SWASelectionPainter selectionFrameOn: aCanvas rect: r color: Color yellow].
	(hoverIndex = i and: [aNode ~~ selectedNode]) ifTrue: [
		SWASelectionPainter hoverFrameOn: aCanvas rect: r].
	(self isNodeMarked: aNode) ifTrue: [
		SWASelectionPainter frame: r on: aCanvas width: 2 color: Color green]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:22'
}
SWAChatFlowMorph >> ensureLayout [
	"One Rectangle per item, in view coordinates with y growing downward from 0.
	Computed for ALL items (cheap: arithmetic, no drawing) so that scrolling is a
	lookup rather than a re-layout; only DRAWING is virtualised."
	| y gap |
	"VALIDITY IS CHECKED AGAINST THE EXTENT, not against an invalidation hook.
	Overriding #extent: was NOT enough, and that was the bug: SWAPane resizes its
	view through a LAYOUT POLICY, which sets bounds via #privateBounds: and never
	sends #extent:. The layout then silently kept the old geometry while #drawOn:
	computed the visible band from the new height, so the binary search indexed a
	layout that no longer described the morph and the view drew almost nothing.

	Stamping the layout with the extent it was built for is correct whichever of
	Morphic's several bounds-setting paths is used."
	(layout notNil and: [layoutExtent = self extent]) ifTrue: [^ layout].
	layout := Array new: self items size.
	y := self topInset asFloat.
	gap := self rowGap.
	"y is a FLOAT accumulator and only the BOUNDARIES are rounded: row i runs from
	`y rounded` to `(y + h) rounded`. Rounding each height independently would
	accumulate error over 24000 rows; rounding boundaries cannot drift, and rows
	still tile exactly even when each is a fraction of a pixel tall. A row that
	rounds to zero height is kept -- #drawOn: gives it its one pixel."
	self items doWithIndex: [:n :i |
		| h topY botY r |
		h := self rowHeightFor: n.
		topY := y rounded.
		botY := (y + h) rounded.
		r := self rowRectFor: n index: i height: botY - topY.
		layout at: i put: (r translateBy: 0 @ topY).
		y := y + h + gap].
	contentHeight := y rounded + self topInset.
	layoutExtent := self extent.
	"Re-clamp, inline rather than through #scrollTo: which would recurse back into
	here. A relayout can shrink the scrollable range -- growing the window does
	exactly that -- and an unclamped scrollY then points past the last row, which
	is the OTHER way this view could end up drawing nothing."
	scrollY := (scrollY max: 0) min: ((contentHeight - self height) max: 0).
	^ layout
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:47'
}
SWAChatFlowMorph >> firstIndexAtOrAfter: aY [
	"Binary search for the first row whose bottom reaches aY. The layout is built
	in increasing y, so it is sorted by construction and this is what makes drawing
	genuinely O(visible) rather than O(items) -- otherwise every repaint scans all
	24000 rows to find the thirty that are on screen."
	| lay lo hi mid |
	lay := self ensureLayout.
	lo := 1.
	hi := lay size.
	[lo < hi] whileTrue: [
		mid := lo + hi // 2.
		((lay at: mid) bottom < aY)
			ifTrue: [lo := mid + 1]
			ifFalse: [hi := mid]].
	^ lo
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAChatFlowMorph >> flushLayout [
	"For STRUCTURAL changes (new root, new axis mode). Geometry changes need no
	call: #ensureLayout notices those itself via the extent stamp."
	layout := nil.
	layoutExtent := nil.
	items := nil.
	"These are derived from #items, so they MUST die with it -- a stale maxItemSize
	silently rescales every row against a tree that is no longer there."
	self removeProperty: #maxItemSize.
	self removeProperty: #laneKeys.
	self removeProperty: #maxCost.
	self removeProperty: #maxTokens.
	self removeProperty: #msgCost.
	self removeProperty: #msgTokens.
	self removeProperty: #msgContext.
	self removeProperty: #partsPerMessage.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:03'
}
SWAChatFlowMorph >> handlesMouseMove: evt [
	"Morph's default answers true only while a BUTTON IS DOWN, so hover tracking
	could never have worked no matter what #mouseMove: did -- the message was
	simply not delivered. Panning and thumb-dragging happened to work because those
	do have a button down."
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> handlesMouseOver: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> handlesMouseWheel: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:23'
}
SWAChatFlowMorph >> hoverIsUseful [
	"Only when a row is tall enough for a highlight frame to be visible at all."
	"Gated on the REPAINT COST, not on the zoom number: what makes hover unaffordable
	is how many rows are on screen, and that is what a hover repaint has to redraw.
	Both ends come from the binary search, so this costs O(log n)."
	| first last |
	self ensureLayout.
	first := self firstIndexAtOrAfter: scrollY.
	last := self firstIndexAtOrAfter: scrollY + self height.
	^ last - first <= 400
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> initialize [
	super initialize.
	self extent: 900 @ 700.
	self color: (Color gray: 0.12).
	self borderWidth: 0.
	zoom := 1.0.
	scrollY := 0.
	xMode := #lane.
	yMode := #content.
	contentMode := #preview.
	colorMode := #kind.
	hoverIndex := nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:38'
}
SWAChatFlowMorph >> inspectSelection [
	"Open an inspector on EVERYTHING we know or can get about the selected item.

	Deliberately a Dictionary rather than the node itself: the interesting facts
	are spread across the part, its message (which is where cost and tokens live),
	its session and the raw stored document, and an inspector on the node would
	show only the first of those."
	| n |
	n := selectedNode ifNil: [^ self inform: 'Select an item first.'].
	((n respondsTo: #details) ifTrue: [n details] ifFalse: [n]) inspect
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> intrinsicKindColorFor: aNode [
	"Stable pseudo-colour from the lane key, so kinds keep their colour across
	sessions without a hand-maintained palette. Subclasses override for a designed
	one."
	| k |
	k := self laneKeyFor: aNode.
	k ifNil: [^ Color gray: 0.3].
	^ Color h: (k asString hash \\ 360) s: 0.45 v: 0.7
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAChatFlowMorph >> isDraggingScrollThumb [
	"I track the thumb in my own drag-mode state machine (it also handles panning), not
	in the inherited #scrollThumbDragOffset."
	^ dragMode == #thumb
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> items [
	"The flow, in READING ORDER: leaves only, depth-first, exactly as the tree
	presents them. Containers are skipped -- a message that holds three parts is
	not itself a fourth thing that happened -- but their order is what defines
	the sequence, which is why this is a depth-first walk and not a sort."
	items ifNotNil: [^ items].
	items := OrderedCollection new.
	rootNode ifNil: [^ items].
	self collectLeavesOf: rootNode into: items.
	^ items
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> laneCount [
	^ self laneKeys size max: 1
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> laneIndexFor: aNode [
	^ (self laneKeys indexOf: (self laneKeyFor: aNode) ifAbsent: [1]) - 1
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> laneKeyFor: aNode [
	"What puts an item in a column. A hook: the default groups by #nodeKind, which
	is the only classification every SWANode has. Subclasses (or nodes carrying a
	role) refine it -- see #laneKeyFor: on the opencode side, which uses
	user/assistant/tool and so reproduces an actual chat layout."
	^ aNode nodeKind
]

{
	#category : #lanes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> laneKeys [
	"Distinct lane keys in FIRST-APPEARANCE order, so the columns are ordered by
	the conversation itself (whoever speaks first is leftmost) rather than
	alphabetically. Cached: every row asks during layout."
	^ self valueOfProperty: #laneKeys ifAbsentPut: [
		| seen out |
		seen := Set new.
		out := OrderedCollection new.
		self items do: [:n |
			| k |
			k := self laneKeyFor: n.
			(seen includes: k) ifFalse: [seen add: k. out add: k]].
		out asArray]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:28'
}
SWAChatFlowMorph >> lineCountFor: aNode [
	^ (aNode respondsTo: #contentLineCount)
		ifTrue: [aNode contentLineCount max: 1]
		ifFalse: [1]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> maxItemSize [
	"Largest totalSize among the items, cached in a property because every row asks
	for it during layout."
	^ self valueOfProperty: #maxItemSize ifAbsentPut: [
		self items inject: 1 into: [:a :n | a max: n totalSize]]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:25'
}
SWAChatFlowMorph >> mouseDown: evt [
	"Records intent only -- SELECTION HAPPENS ON MOUSE UP, and only if the gesture
	never became a drag. Selecting on mouse down (as this did) means every attempt
	to pan also selects whatever was under the finger when the pan started."
	| thumb |
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt position].
	"Do not arm a pan under the floating controls."
	(zoomBar notNil and: [zoomBar bounds containsPoint: evt position]) ifTrue: [^ self].
	didDrag := false.
	dragStartY := evt position y.
	dragStartScroll := scrollY.
	(self isScrollable and: [(self scrollBarTrackRect containsPoint: evt position)])
		ifTrue: [
			thumb := self thumbRect.
			(thumb notNil and: [thumb containsPoint: evt position])
				ifTrue: [dragMode := #thumb.
					dragStartScroll := scrollY.
					dragStartY := evt position y - thumb top]
				ifFalse: ["clicked the track: page toward the click"
					dragMode := nil.
					self scrollBy: (evt position y < (thumb ifNil: [self bounds]) top
						ifTrue: [self height negated]
						ifFalse: [self height])].
			^ self changed].
	dragMode := #pan.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> mouseEnter: evt [
	hoverIndex := nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> mouseLeave: evt [
	hoverIndex ifNotNil: [hoverIndex := nil. self changed]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:01'
}
SWAChatFlowMorph >> mouseMove: evt [
	"Drag anywhere to pan -- with no scrollbar to grab, dragging the content is the
	only direct way to move a long flow."
	| dy |
	dragMode == #thumb ifTrue: [
		didDrag := true.
		^ self scrollToThumbTop: evt position y - dragStartY].
	dragMode == #pan ifFalse: [^ self updateHoverAt: evt position].
	dy := evt position y - dragStartY.
	"THRESHOLD: below this the gesture is still a click. Without it every click
	with a pixel of hand-shake panned the view, which is what made this feel like
	it was doing something other than what was asked."
	(didDrag or: [dy abs >= self dragThreshold]) ifFalse: [^ self].
	didDrag := true.
	self scrollTo: dragStartScroll - dy
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:01'
}
SWAChatFlowMorph >> mouseUp: evt [
	| n |
	(dragMode == #pan and: [didDrag not]) ifTrue: [
		n := self nodeAt: evt position.
		n ifNotNil: [
			evt shiftPressed
				ifTrue: [self toggleMark: n]
				ifFalse: [self selectNode: n]]].
	dragMode := nil.
	didDrag := false.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:24'
}
SWAChatFlowMorph >> nodeAt: aGlobalPoint [
	"The zoom bar floats OVER the rows; a click on it must not also select whatever
	row happens to lie beneath."
	| lay p |
	(zoomBar notNil and: [zoomBar bounds containsPoint: aGlobalPoint])
		ifTrue: [^ nil].
	lay := self ensureLayout.
	p := aGlobalPoint - self position + (0 @ scrollY).
	self items doWithIndex: [:n :i |
		((lay at: i) containsPoint: p) ifTrue: [^ n]].
	^ nil
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> previewChars [
	^ 400
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAChatFlowMorph >> requestContentFor: aNode [
	"Fetch a node's content off the UI process, then refresh the Source flap --
	the async pattern the rest of SWA uses (fork at background priority, come back
	through WorldState addDeferredUIMessage:).

	`loadingNode` is both a guard against firing a second fetch for the same
	selection on every repaint, and the check that the answer is still WANTED: by
	the time a slow read returns, the user may have clicked elsewhere, and pushing
	stale text into the pane then would be worse than not answering at all."
	loadingNode == aNode ifTrue: [^ self].
	loadingNode := aNode.
	[[aNode sourceString] on: Error do: [:e | nil].
	 WorldState addDeferredUIMessage: [
		loadingNode == aNode ifTrue: [
			loadingNode := nil.
			selectedNode == aNode ifTrue: [
				navPanel ifNotNil: [navPanel updateSource]]]]]
		forkAt: Processor userBackgroundPriority
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> resetZoom [
	zoom := 1.0.
	self flushLayout.
	self scrollTo: 0
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> rowGap [
	"Vanishes when zoomed far out: at one pixel per row the gap would be half the
	picture, and the point of zooming out is a continuous shape, not a dotted line."
	^ zoom < 0.4 ifTrue: [0] ifFalse: [2]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:22'
}
SWAChatFlowMorph >> rowHeightFor: aNode [
	"The Y axis, scaled by zoom.

	#content is on a LOG scale. Item sizes here span four orders of magnitude (a
	step marker is 75 bytes, a file read is 300000), and a linear mapping would give
	one item the whole window and everything else a sub-pixel sliver -- which is not
	a visualisation, it is a scrollbar. The log keeps the ordering visible while
	still letting a big item read as big."
	"NO PIXEL FLOOR. A `max: 1` here is what stopped this view zooming out: with
	24458 items it pinned the content to at least 24458 pixels, so the whole flow
	could never be brought on screen however far you zoomed.

	Rows may now be a fraction of a pixel tall. #ensureLayout accumulates the exact
	position and rounds only the BOUNDARIES, so sub-pixel rows still land in the
	right place and the pixel floor is applied at DRAW time, where it belongs."
	^ (self rowHeightUnitFor: aNode) * zoom
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:45'
}
SWAChatFlowMorph >> rowHeightUnitFor: aNode [
	"Row height at zoom 1, as a FLOAT and with no pixel floor. Factored out of
	#rowHeightFor: so that height is exactly linear in zoom -- which is what makes
	#zoomToFit solvable in closed form instead of by searching."
	| base f max |
	base := 3.0.
	yMode == #uniform ifTrue: [^ base * 6].
	"LINEAR in lines, deliberately NOT logarithmic. #content compresses four orders
	of magnitude so that everything stays on one screen; this does the opposite --
	a row is exactly as tall as its text needs, so at zoom 1 with content shown the
	flow reads as the document it is. The price is an enormous canvas when a tool
	dumped a whole file, which is what the zoom is for."
	yMode == #loc ifTrue: [
		^ (self lineCountFor: aNode) * self contentFont height + 6].
	"Raw stored length, linear. Differs from #loc wherever lines are long or the
	document carries a lot of JSON scaffolding, and differs from #content by not
	compressing -- the same quantity #content shows, told honestly."
	yMode == #bytes ifTrue: [
		^ ((self byteSizeFor: aNode) / 24.0) max: 1.0].
	yMode == #duration ifTrue: [
		f := (aNode respondsTo: #eventDurationMicros)
			ifTrue: [(aNode eventDurationMicros ifNil: [0]) / 1000.0]
			ifFalse: [0].
		"sqrt of milliseconds: durations span from a 2 ms step marker to a 60 s
		build, and a linear axis would make everything but the slowest invisible.
		No hard cap -- the old `min: 60` flattened everything above 3.6 s into one
		height, which hid exactly the outliers this mode exists to find. Zoom is
		the right answer to a very tall row, not clipping the data."
		^ base + (f sqrt * 1.5)].
	max := self maxItemSize.
	f := (aNode totalSize max: 1) ln / (max max: 2) ln.
	^ base + (f * 90)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:18'
}
SWAChatFlowMorph >> rowRectFor: aNode index: i height: h [
	"The X axis. Answers a rectangle at y = 0; #ensureLayout translates it down.

	#lane is the chat metaphor generalised: items are sorted into columns by
	#laneIndexFor:, so who-said-what is readable as a shape without reading a word."
	| w x lanes li right |
	w := self contentWidth - (self sideInset * 2).
	xMode == #indent ifTrue: [
		x := self sideInset + ((aNode depth min: 8) * 14).
		^ x @ 0 corner: (self contentWidth - self sideInset) @ h].
	xMode == #metric ifTrue: [
		| f |
		f := (aNode totalSize max: 1) ln / (self maxItemSize max: 2) ln.
		^ self sideInset @ 0 corner: (self sideInset + ((w * f) rounded max: 3)) @ h].
	xMode == #lane ifTrue: [
		"INTEGER DIVISION, and each edge derived from a lane BOUNDARY rather than
		from a width added to an origin. `w * li / lanes` answers a Fraction
		whenever the width is not a multiple of the lane count, and a Rectangle
		with Fraction coordinates cannot be blitted -- the view rendered only at
		widths divisible by 4 and was blank at the other three out of four, which
		is why resizing by a pixel turned it on and off.

		Deriving both edges from boundaries also stops rounding accumulating, so
		lanes tile exactly instead of drifting apart by a pixel each."
		lanes := self laneCount.
		li := self laneIndexFor: aNode.
		x := self sideInset + (w * li // lanes).
		right := self sideInset + (w * (li + 1) // lanes) - 6.
		^ x @ 0 corner: (right max: x + 3) @ h].
	^ self sideInset @ 0 corner: (self contentWidth - self sideInset) @ h
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAChatFlowMorph >> selectNode: aNode [
	selectedNode := aNode.
	"Drop any in-flight fetch for the previous selection, so its late arrival
	cannot overwrite the pane with the wrong part's text."
	loadingNode := nil.
	"The pane's Source flap and details box listen for this."
	navPanel ifNotNil: [navPanel updateSource; updateDetails].
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAChatFlowMorph >> selectedSourceString [
	"Full contents of the selection for the pane's Source flap -- for an opencode
	part this is what triggers the on-demand fetch of the tool's whole output."
	| n |
	n := selectedNode ifNil: [^ ''].
	(n respondsTo: #sourceString) ifFalse: [^ ''].
	"NEVER block here. This runs on the UI process from a mouse handler, and for an
	opencode part #sourceString means a SQLite query, a JSON parse and a
	pretty-print of a document that can be hundreds of kilobytes -- which is what
	made clicking around feel like the view had stalled. If the content is not in
	memory, say so and fetch it in the background."
	((n respondsTo: #isContentLoaded) and: [n isContentLoaded not]) ifTrue: [
		self requestContentFor: n.
		^ 'loading ' , n name , ' ...'].
	^ [n sourceString] on: Error do: [:e |
		'could not load: ' , (e messageText ifNil: [e class name])]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:46'
}
SWAChatFlowMorph >> setRoot: aNode [
	"SWAView declares no #setRoot: -- each concrete view sets rootNode itself and
	is responsible for the two caches the base class owns (key index, marks)."
	rootNode := aNode.
	self flushLayout.
	self flushMarksCache.
	self rebuildKeyIndex.
	scrollY := 0.
	^ self
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:50'
}
SWAChatFlowMorph >> showMenuAt: aPoint [
	| m sub |
	m := MenuMorph new defaultTarget: self.
	m addTitle: 'flow'.
	sub := MenuMorph new defaultTarget: self.
	{{#uniform. 'Uniform'}. {#content. 'Content size (log)'}.
	 {#loc. 'Lines of content (linear)'}. {#bytes. 'Content length (linear)'}.
	 {#duration. 'Duration'}. {#msgCost. 'Message cost'}. {#msgContext. 'Message context'}}
		do: [:p | sub add: (yMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
				target: self selector: #yMode: argument: p first].
	m add: 'height (Y)' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	{{#full. 'Full width'}. {#lane. 'Lanes'}. {#indent. 'Indent by depth'}. {#metric. 'Bar = size'}}
		do: [:p | sub add: (xMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
				target: self selector: #xMode: argument: p first].
	m add: 'placement (X)' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	{{#none. 'Nothing'}. {#label. 'Label'}. {#preview. 'Preview'}. {#full. 'Full text (loads!)'}}
		do: [:p | sub add: (contentMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
				target: self selector: #contentMode: argument: p first].
	m add: 'content' subMenu: sub.
	sub := MenuMorph new defaultTarget: self.
	self colorModeOptions do: [:p | sub add: (colorMode == p first ifTrue: ['<on>'] ifFalse: ['<off>']) , p second
				target: self selector: #colorMode: argument: p first].
	m add: 'colour' subMenu: sub.
	m addLine.
	m add: 'inspect item (all data)' target: self selector: #inspectSelection.
	m addLine.
	m add: 'zoom in' target: self selector: #zoomIn.
	m add: 'zoom out' target: self selector: #zoomOut.
	m add: 'zoom to fit (whole flow)' target: self selector: #zoomToFit.
	m add: 'reset zoom' target: self selector: #resetZoom.
	m popUpAt: aPoint forHand: self activeHand in: self world
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> sideInset [
	^ 8
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> topInset [
	^ 6
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:23'
}
SWAChatFlowMorph >> updateHoverAt: aGlobalPoint [
	"Hover was dead code: #handlesMouseOver: answered true and hoverIndex was only
	ever set back to nil, so the highlight could never appear."
	| lay p found |
	"Hover is SUPPRESSED when zoomed far out. Redrawing the fully zoomed-out flow
	costs ~33 ms because every one of 24458 rows is on screen, and at that zoom a
	one-pixel hover frame is invisible anyway -- so tracking it would buy nothing
	and cost a repaint per pixel of mouse travel."
	self hoverIsUseful ifFalse: [
		hoverIndex ifNotNil: [hoverIndex := nil. self changed].
		^ self].
	lay := self ensureLayout.
	p := aGlobalPoint - self position + (0 @ scrollY).
	found := nil.
	(self firstIndexAtOrAfter: scrollY) to: lay size do: [:i |
		| r |
		r := lay at: i.
		r top > (scrollY + self height) ifTrue: [
			found ~= hoverIndex ifTrue: [hoverIndex := found. self changed].
			^ self].
		(r containsPoint: p) ifTrue: [found := i]].
	found ~= hoverIndex ifTrue: [hoverIndex := found. self changed]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:42'
}
SWAChatFlowMorph >> viewKind [
	^ #chatFlow
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAChatFlowMorph >> wheelZoomBy: aFactor at: localY [
	"CTRL-wheel over the flow zooms the row scale, keeping localY put."
	^ self zoomBy: aFactor at: localY
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:43'
}
SWAChatFlowMorph >> wrap: aString toWidth: w font: aFont max: maxLines [
	"Cheap character-count wrapping on a fixed advance, not real text measurement:
	this runs for every visible row on every repaint, and the font is monospaced.
	Newlines in the source are honoured, so a method body keeps its shape."
	| perLine out |
	maxLines < 1 ifTrue: [^ #()].
	perLine := (w // (aFont widthOf: $m)) max: 4.
	out := OrderedCollection new.
	aString lines do: [:srcLine |
		| rest |
		rest := srcLine.
		[rest isEmpty or: [out size >= maxLines]] whileFalse: [
			out add: (rest truncateTo: perLine).
			rest := rest size > perLine
				ifTrue: [rest copyFrom: perLine + 1 to: rest size]
				ifFalse: ['']].
		out size >= maxLines ifTrue: [^ out asArray]].
	^ out asArray
]

{
	#category : #modes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAChatFlowMorph >> xMode: aSymbol [
	xMode := aSymbol.
	self flushLayout
]

{
	#category : #modes,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAChatFlowMorph >> yMode: aSymbol [
	yMode := aSymbol.
	self flushLayout
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:44'
}
SWAChatFlowMorph >> zoom [
	^ zoom
]

{
	#category : #'zoom bar',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:24'
}
SWAChatFlowMorph >> zoomBarSpecs [
	"{ label. selector. balloon }"
	^ {
		{'-'.    #zoomOut.    'Zoom out'}.
		{'+'.    #zoomIn.     'Zoom in'}.
		{'1:1'.  #resetZoom.  'Back to normal zoom'}.
		{'fit'.  #zoomToFit.  'Fit the whole flow on screen'}.
		{'top'.  #scrollHome. 'Back to the start'}
	}
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:23'
}
SWAChatFlowMorph >> zoomBy: aFactor at: aLocalY [
	"Zoom the Y axis, KEEPING THE ITEM UNDER THE POINTER PUT. Zooming about the top
	of the window instead makes the flow shoot away under the cursor and is the
	difference between a usable zoom and an unusable one."
	| anchor newZoom oldHeight |
	oldHeight := contentHeight ifNil: [1].
	anchor := (scrollY + aLocalY) / (oldHeight max: 1).
	"Lower bound is now tiny, not 0.05: rows may be sub-pixel, so 'zoomed out' can
	mean the whole 24000-item flow on one screen."
	newZoom := (zoom * aFactor) min: 40.0 max: 0.00002.
	newZoom = zoom ifTrue: [^ self].
	zoom := newZoom.
	layout := nil.
	self ensureLayout.
	self scrollTo: (anchor * contentHeight) - aLocalY.
	self changed
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAChatFlowMorph >> zoomIn [
	self zoomBy: 1.6 at: self height // 2
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:45'
}
SWAChatFlowMorph >> zoomOut [
	self zoomBy: 0.625 at: self height // 2
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:22'
}
SWAChatFlowMorph >> zoomToFit [
	"Bring the WHOLE flow on screen at once -- the overview end of the zoom.

	Solved in closed form rather than searched: #rowHeightUnitFor: is the height at
	zoom 1 and heights are exactly linear in zoom, so with the inter-row gap zero
	(it is, below zoom 0.4) the content is `zoom * unitTotal + 2 * topInset` and the
	zoom that fits follows directly."
	| unit |
	self items isEmpty ifTrue: [^ self].
	unit := self items inject: 0.0 into: [:a :n | a + (self rowHeightUnitFor: n)].
	unit <= 0 ifTrue: [^ self].
	zoom := ((self height - (self topInset * 2)) / unit) min: 40.0.
	layout := nil.
	self ensureLayout.
	self scrollTo: 0.
	self changed
]
