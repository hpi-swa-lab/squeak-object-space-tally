"
Vertical drag handle between the source pane and the covering-tests/duplicates list in a SWAPane Show row. Dragging calls panel>>growCoveringTestsPaneBy: to resize the list column. Counterpart to SWASourceSplitter.
"
Class {
	#name : #SWAListSplitter,
	#superclass : #Morph,
	#instVars : [
		'panel',
		'dragging',
		'lastX'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> drawOn: aCanvas [
	"Fill, then a short centered vertical grip (two thin lines) so it reads as a drag
	handle."
	| cx cy h |
	super drawOn: aCanvas.
	cx := self center x.
	cy := self center y.
	h := 18.
	aCanvas
		line: (cx - 1 @ (cy - h)) to: (cx - 1 @ (cy + h)) width: 1 color: (Color gray: 0.7);
		line: (cx + 1 @ (cy - h)) to: (cx + 1 @ (cy + h)) width: 1 color: (Color gray: 0.7)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> handlesMouseOver: evt [
	^ true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> initialize [
	super initialize.
	dragging := false.
	self
		color: (Color gray: 0.35);
		hResizing: #rigid;
		vResizing: #spaceFill;
		width: 8
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> mouseDown: evt [
	"Begin a horizontal resize drag."
	dragging := true.
	lastX := evt position x.
	self color: (Color gray: 0.7)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> mouseEnter: evt [
	self color: (Color gray: 0.55).
	[evt hand showTemporaryCursor: Cursor resizeLeft] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> mouseLeave: evt [
	dragging ifFalse: [self color: (Color gray: 0.35)].
	[evt hand showTemporaryCursor: nil] on: Error do: [:e | ]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> mouseMove: evt [
	"Horizontal drag: moving LEFT widens the list, RIGHT shrinks it. Applied as an
	incremental delta from the last event position so the list tracks the cursor."
	| x delta |
	dragging ifFalse: [^ self].
	x := evt position x.
	delta := lastX - x.   "left = positive = grow the list"
	lastX := x.
	delta = 0 ifTrue: [^ self].
	panel ifNotNil: [panel growCoveringTestsPaneBy: delta]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> mouseUp: evt [
	dragging := false.
	self color: (Color gray: 0.35)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAListSplitter >> panel: aNavPanel [
	panel := aNavPanel
]
