"
GcStatsSurface backed by a Morphic Canvas (the desktop GcGraphMorph path). Draws graph forms and labels at origin + panel-local coordinates.
"
Class {
	#name : #GcStatsCanvasSurface,
	#superclass : #GcStatsSurface,
	#instVars : [
		'canvas',
		'origin',
		'font',
		'labelColor',
		'bgColor',
		'stripWidth',
		'stripRect',
		'stripTopLeft',
		'stripBottomRight'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsCanvasSurface >> canvas: aCanvas origin: aPoint [
	canvas := aCanvas.
	origin := aPoint.
	font := TextStyle defaultFont.
	labelColor := GcGraph slateColor.
	bgColor := GcGraph backgroundColor
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsCanvasSurface >> canvas: aCanvas origin: aPoint width: aWidth [
	canvas := aCanvas.
	origin := aPoint.
	stripWidth := aWidth.
	font := TextStyle defaultFont.
	labelColor := GcGraph slateColor.
	bgColor := GcGraph backgroundColor
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcStatsCanvasSurface >> canvas: aCanvas origin: aPoint width: aWidth font: aFont [
	canvas := aCanvas.
	origin := aPoint.
	stripWidth := aWidth.
	font := aFont ifNil: [TextStyle defaultFont].
	labelColor := GcGraph slateColor.
	bgColor := GcGraph backgroundColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:14'
}
GcStatsCanvasSurface >> drawForm: aForm at: aPoint [
	canvas paintImage: aForm at: (origin isZero ifTrue: [aPoint] ifFalse: [origin + aPoint])
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:14'
}
GcStatsCanvasSurface >> drawLabel: aString at: aPoint [
	canvas
		drawString: aString
		at: (origin isZero ifTrue: [aPoint] ifFalse: [origin + aPoint])
		font: font
		color: labelColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:33'
}
GcStatsCanvasSurface >> fillLabelStripAt: y height: h [
	"Reuse a retained Rectangle + two corner Points, mutated in place, so a per-lane strip fill
	allocates nothing. origin is (0,0) on the compositing path; add it component-wise."
	stripRect ifNil: [
		stripTopLeft := 0@0. stripBottomRight := 0@0.
		stripRect := stripTopLeft corner: stripBottomRight].
	stripTopLeft setX: origin x setY: origin y + y.
	stripBottomRight setX: origin x + self width setY: origin y + y + h.
	stripRect setOrigin: stripTopLeft corner: stripBottomRight.
	canvas fillRectangle: stripRect color: bgColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsCanvasSurface >> labelFont [
	^ font
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsCanvasSurface >> width [
	"Strip fill width -- the widest graph form (set by the panel)."
	^ stripWidth ifNil: [0]
]
