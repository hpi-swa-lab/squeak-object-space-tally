"
Stateless canvas-drawing helpers for selection / hover feedback shared by the SWA visual views (treemap overlay, graph view). All methods are on the class side and take a canvas plus explicit geometry (rectangles in the target morph's coordinate space, already translated by the caller's origin), so they are decoupled from any particular view's model.

Provided:
- frame:on:width:color: -- a single border rectangle.
- selectionFrameOn:rect:  -- the persistent CLICK-selection border (blue, 3px).
- hoverFrameOn:rect:      -- the transient HOVER border (white, 2px).
- ancestorFramesOn:from:rectBlock:origin: -- fading cyan borders up a node's parent chain, using a caller-supplied rect-lookup block.
- tooltipOn:string:at:bounds: -- a small dark name label near a point, clamped inside bounds.

Colors/widths are centralized here so every view's selection feedback stays visually consistent.
"
Class {
	#name : #SWASelectionPainter,
	#superclass : #Object,
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> ancestorFramesOn: aCanvas from: aNode rectBlock: aBlock [
	"Draw fading cyan borders up aNode's parent chain (bright near the node, dimming
	upward), stopping before the synthetic root. aBlock maps a node to its rectangle
	in aCanvas coordinates (or nil if it has none). Shared by treemap + graph hover
	and selection feedback."
	| node alpha r |
	aNode ifNil: [^ self].
	node := aNode parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil]] whileTrue: [
		r := aBlock value: node.
		r ifNotNil: [
			aCanvas frameRectangle: r width: 2 color: (Color cyan alpha: alpha)].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:59'
}
SWASelectionPainter class >> frame: aRect on: aCanvas width: w color: aColor [
	"Draw a single border rectangle. aRect is already in aCanvas coordinates."
	aRect ifNil: [^ self].
	aCanvas frameRectangle: aRect width: w color: aColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> hoverFrameOn: aCanvas rect: aRect [
	"The transient HOVER border: a WHITE 2px frame. aRect is in aCanvas coords."
	self frame: aRect on: aCanvas width: 2 color: Color white
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> selectionColor [
	"The persistent click-selection border color, shared by all views."
	^ Color blue
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> selectionFrameOn: aCanvas rect: aRect [
	"The persistent CLICK-selection border in the default color. aRect is in
	aCanvas coords."
	self selectionFrameOn: aCanvas rect: aRect color: self selectionColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> selectionFrameOn: aCanvas rect: aRect color: aColor [
	"The persistent CLICK-selection border: a distinct 3px frame (deliberately
	thicker than the transient 2px hover border) in aColor. aRect is in aCanvas
	coords. Views choose their own selection color (treemap yellow, graph blue)
	while sharing the width/semantics."
	self frame: aRect on: aCanvas width: 3 color: aColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWASelectionPainter class >> tooltipOn: aCanvas string: aString at: anAnchorPoint bounds: aBounds [
	"Draw a small dark tooltip label (aString) near anAnchorPoint (already in canvas
	coords, typically the cursor + a small offset), clamped to stay inside aBounds
	(the on-screen rectangle of the drawing morph). Canvas-drawn because Morphic's
	balloon never worked over these views. No-op for a nil/empty string."
	| font pad w h boxOrigin |
	(aString isNil or: [aString isEmpty]) ifTrue: [^ self].
	font := TextStyle default fontOfPointSize: 10.
	pad := 4.
	w := (font widthOfString: aString) + (pad * 2).
	h := font height + (pad * 2).
	boxOrigin := anAnchorPoint.
	(boxOrigin x + w) > aBounds right ifTrue: [boxOrigin := (aBounds right - w - 2) @ boxOrigin y].
	(boxOrigin y + h) > aBounds bottom ifTrue: [boxOrigin := boxOrigin x @ (anAnchorPoint y - h - 26)].
	boxOrigin := (boxOrigin x max: aBounds left + 2) @ (boxOrigin y max: aBounds top + 2).
	aCanvas
		frameAndFillRectangle: (boxOrigin extent: w @ h)
		fillColor: (Color black alpha: 0.82)
		borderWidth: 1
		borderColor: (Color gray: 0.6).
	aCanvas
		drawString: aString
		at: (boxOrigin x + pad) @ (boxOrigin y + pad)
		font: font
		color: Color white
]
