"
A single, reusable draggable resize handle for SWAPane. One class, configured per instance -- NOT subclassed -- for either axis:

- a VERTICAL bar (horizontal: true) dragged left/right to resize a side column
  (the Marks list, the covering-tests list),
- a HORIZONTAL bar (horizontal: false) dragged up/down to resize a stacked row
  (the Show/source row).

Configure an instance with #horizontal: (drag axis) and #resizeAction: (a one-arg
block sent the signed pixel delta as you drag). The sign convention is the caller's
to decide inside the block: e.g. the left-docked Marks panel grows on a positive
(rightward) delta, while the right-docked covering-tests list grows on a negative
(leftward) delta. It renders a centered two-line grip along its long axis and shows
the appropriate resize cursor on hover.

Instance-creation helpers: SWASplitter vertical / SWASplitter horizontal.
"
Class {
	#name : #SWASplitter,
	#superclass : #Morph,
	#instVars : [
		'dragging',
		'lastPos',
		'horizontal',
		'resizeAction'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter class >> horizontal [
	"A horizontal bar dragged up/down to resize a stacked row."
	^ self new horizontal: false
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter class >> vertical [
	"A vertical bar dragged left/right to resize a side column."
	^ self new horizontal: true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> applyResizingForAxis [
	"Set the handle's rigid/spaceFill resizing + thickness for the current axis:
	a vertical bar is 8px wide and fills height; a horizontal bar is 10px tall and
	fills width."
	horizontal
		ifTrue: [self hResizing: #rigid; vResizing: #spaceFill; width: 8]
		ifFalse: [self hResizing: #spaceFill; vResizing: #rigid; height: 10]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:21'
}
SWASplitter >> drawOn: aCanvas [
	"Fill, then a short centered two-line grip along the LONG axis so it reads as a
	drag handle: vertical lines for a vertical bar, horizontal lines for a horizontal
	bar."
	| cx cy g |
	super drawOn: aCanvas.
	cx := self center x.
	cy := self center y.
	g := 18.
	horizontal
		ifTrue: [aCanvas
			line: (cx - 1 @ (cy - g)) to: (cx - 1 @ (cy + g)) width: 1 color: (Color gray: 0.7);
			line: (cx + 1 @ (cy - g)) to: (cx + 1 @ (cy + g)) width: 1 color: (Color gray: 0.7)]
		ifFalse: [aCanvas
			line: (cx - g @ (cy - 1)) to: (cx + g @ (cy - 1)) width: 1 color: (Color gray: 0.7);
			line: (cx - g @ (cy + 1)) to: (cx + g @ (cy + 1)) width: 1 color: (Color gray: 0.7)]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> handlesMouseOver: evt [
	^ true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> horizontal: aBoolean [
	"true = a VERTICAL bar dragged along the X axis (resize a side column);
	false = a HORIZONTAL bar dragged along the Y axis (resize a stacked row)."
	horizontal := aBoolean.
	self applyResizingForAxis
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> initialize [
	super initialize.
	dragging := false.
	horizontal := true.
	self color: (Color gray: 0.35).
	self applyResizingForAxis
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:21'
}
SWASplitter >> mouseDown: evt [
	"Begin a resize drag along the configured axis."
	dragging := true.
	lastPos := horizontal ifTrue: [evt position x] ifFalse: [evt position y].
	self color: (Color gray: 0.7)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> mouseEnter: evt [
	self color: (Color gray: 0.55).
	[evt hand showTemporaryCursor: self resizeCursor] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> mouseLeave: evt [
	dragging ifFalse: [self color: (Color gray: 0.35)].
	[evt hand showTemporaryCursor: nil] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:21'
}
SWASplitter >> mouseMove: evt [
	"Track the cursor along the drag axis and hand the signed incremental delta to
	the resizeAction block (positive = rightward for a vertical bar, downward for a
	horizontal bar). The block interprets the sign for its target."
	| pos delta |
	dragging ifFalse: [^ self].
	pos := horizontal ifTrue: [evt position x] ifFalse: [evt position y].
	delta := pos - lastPos.
	lastPos := pos.
	delta = 0 ifTrue: [^ self].
	resizeAction ifNotNil: [resizeAction value: delta]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:21'
}
SWASplitter >> mouseUp: evt [
	dragging := false.
	self color: (Color gray: 0.35)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> resizeAction: aOneArgBlock [
	"aOneArgBlock is evaluated with the signed pixel delta on each drag step. The
	block decides how (and in which direction) that delta grows/shrinks the target."
	resizeAction := aOneArgBlock
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:20'
}
SWASplitter >> resizeCursor [
	"The hover cursor for the current drag axis."
	^ horizontal ifTrue: [Cursor resizeLeft] ifFalse: [Cursor resizeTop]
]
