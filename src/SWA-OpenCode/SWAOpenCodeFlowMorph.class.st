"
The conversation as a 1D STRIP: every part in reading order, top to bottom, one row each. Lanes put user / assistant / reasoning / tool in columns, so who-said-what is a shape before it is a text. Height is the axis that carries a quantity (content size, lines, duration, cost, context).

Its sibling SWAOpenCodeFlowMapMorph lays the same items out in 2D. Everything the two share is in SWAOpenCodeFlowView (data) and SWAChatFlowMorph (machinery); what is left here is purely the strip's geometry.
"
Class {
	#name : #SWAOpenCodeFlowMorph,
	#superclass : #SWAOpenCodeFlowView,
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> computeLayout [
	"The strip: one row per item, stacked downward in reading order.

	y is a FLOAT accumulator and only the BOUNDARIES are rounded: row i runs from
	`y rounded` to `(y + h) rounded`. Rounding each height independently would
	accumulate error over 24000 rows; rounding boundaries cannot drift, and rows
	still tile exactly even when each is a fraction of a pixel tall. A row that
	rounds to zero height is kept -- drawing gives it its one pixel."
	| y gap |
	y := self topInset asFloat.
	gap := self rowGap.
	self items doWithIndex: [:n :i |
		| h topY botY r |
		h := self rowHeightFor: n.
		topY := y rounded.
		botY := (y + h) rounded.
		r := self rowRectFor: n index: i height: botY - topY.
		layout at: i put: (r translateBy: 0 @ topY).
		y := y + h + gap].
	contentHeight := y rounded + self topInset
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> firstIndexAtOrAfter: aY [
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:07'
}
SWAOpenCodeFlowMorph >> hoverIsUseful [
	"Both ends come from the binary search, so this costs O(log n) rather than the
	generic O(visible) count -- which matters here and only here: the whole-project
	strip has 24458 rows and every one of them is on screen when zoomed out."
	| first last |
	self ensureLayout.
	first := self firstIndexAtOrAfter: scrollY.
	last := self firstIndexAtOrAfter: scrollY + self height.
	^ last - first <= 400
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> rowGap [
	"Vanishes when zoomed far out: at one pixel per row the gap would be half the
	picture, and the point of zooming out is a continuous shape, not a dotted line."
	^ zoom < 0.4 ifTrue: [0] ifFalse: [2]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> rowHeightFor: aNode [
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> rowRectFor: aNode index: i height: h [
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> visibleIndicesDo: aBlock [
	"The strip's rectangles are built in increasing y, so they are SORTED by
	construction: binary-search the first one that reaches the top of the viewport
	and walk until one starts below the bottom. That is what makes a repaint cost
	O(visible) instead of O(items) -- otherwise every frame scans all 24000 rows to
	find the thirty that are on screen."
	| lay band i |
	lay := self ensureLayout.
	band := self visibleContentRect.
	i := self firstIndexAtOrAfter: band top.
	[i <= lay size and: [(lay at: i) top <= band bottom]] whileTrue: [
		aBlock value: i.
		i := i + 1]
]

{
	#category : #modes,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> xMode: aSymbol [
	xMode := aSymbol.
	self flushLayout
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> zoomBy: aFactor at: aLocalY [
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:00'
}
SWAOpenCodeFlowMorph >> zoomToFit [
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
