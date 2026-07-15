"
Horizontal drag handle between the view and the Show (source/details) row in a SWAPane. Dragging up/down calls panel>>growSourceRowBy: to resize the Show row. Stateless.
"
Class {
	#name : #SWASourceSplitter,
	#superclass : #Morph,
	#instVars : [
		'panel',
		'dragging',
		'lastY'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:16'
}
SWASourceSplitter >> drawOn: aCanvas [
	"Fill, then a short centered grip (two thin lines) so it reads as a drag handle."
	| cx cy w |
	super drawOn: aCanvas.
	cx := self center x.
	cy := self center y.
	w := 18.
	aCanvas
		line: (cx - w @ (cy - 1)) to: (cx + w @ (cy - 1)) width: 1 color: (Color gray: 0.7);
		line: (cx - w @ (cy + 1)) to: (cx + w @ (cy + 1)) width: 1 color: (Color gray: 0.7)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWASourceSplitter >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWASourceSplitter >> handlesMouseOver: evt [
	^ true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:16'
}
SWASourceSplitter >> initialize [
	super initialize.
	dragging := false.
	self
		color: (Color gray: 0.35);
		hResizing: #spaceFill;
		vResizing: #rigid;
		height: 10
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:16'
}
SWASourceSplitter >> mouseDown: evt [
	"Begin a resize drag. Record the offset between the cursor and the handle top so
	movement tracks the cursor absolutely (no drift)."
	dragging := true.
	lastY := evt position y.
	self color: (Color gray: 0.7)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWASourceSplitter >> mouseEnter: evt [
	self color: (Color gray: 0.55).
	[evt hand showTemporaryCursor: Cursor resizeTop] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWASourceSplitter >> mouseLeave: evt [
	dragging ifFalse: [self color: (Color gray: 0.35)].
	[evt hand showTemporaryCursor: nil] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:16'
}
SWASourceSplitter >> mouseMove: evt [
	"Vertical drag: moving UP grows the Show row, DOWN shrinks it. Applied as an
	incremental delta from the last event position so the row tracks the cursor."
	| y delta |
	dragging ifFalse: [^ self].
	y := evt position y.
	delta := lastY - y.   "up = positive = grow"
	lastY := y.
	delta = 0 ifTrue: [^ self].
	panel ifNotNil: [panel growSourceRowBy: delta]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWASourceSplitter >> mouseUp: evt [
	dragging := false.
	self color: (Color gray: 0.35)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:10'
}
SWASourceSplitter >> panel: aNavPanel [
	panel := aNavPanel
]
