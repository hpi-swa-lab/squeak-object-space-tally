"
Abstract scrolling strip that plots a stack of coloured segments per step.

Generalises what GcFullGraph does for the object memory so the same drawing and
auto-ranging logic can serve any set of kilobyte figures. Subclasses implement:

	segments    an Array of Association, amountInKB -> Color, drawn bottom up
	rangeKB     the total the vertical axis has to accommodate
	labelString the text drawn over the strip

The scale is kilobytes per pixel, rounded to a 1-2-5 value, and it only shrinks
once the data drops below half the current range so the graph does not flicker
between two scales.
"
Class {
	#name : #SWAStackedGraph,
	#superclass : #GcGraph,
	#instVars : [
		'scale',
		'lastStep'
	],
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:01'
}
SWAStackedGraph >> minimumInterval [
	"Milliseconds between columns. The strips above us scroll once per morphic
	frame so their fps figure stays honest, but reading /proc and NVML that often
	is pointless: these amounts move on a human timescale, and a slower axis
	buys a much longer history in the same width."
	^250
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> rangeKB [
	"The total the vertical axis must accommodate, in kilobytes. Defaults to the
	sum of the segments, which is right whenever the stack is the whole story."
	^self segments inject: 0 into: [:sum :each | sum + each key]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> rangeString [
	"The full-height value of the strip, for the label."
	^self mbString: self scale * self graph height
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> scale [
	"Kilobytes per pixel currently used by the graph."
	^scale ifNil: [scale := 1]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> segments [
	"Answer an Array of Association, amountInKB -> Color. Drawn from the bottom
	of the strip upwards in the order given."
	^self subclassResponsibility
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:01'
}
SWAStackedGraph >> stepUpdate [
	"Advance at most once per minimumInterval, ignoring the caller's rate.
	The second clause catches the millisecond clock wrapping around, which would
	otherwise freeze the strip for the rest of the session."
	| now |
	now := Time millisecondClockValue.
	(lastStep notNil
		and: [now >= lastStep]
		and: [now - lastStep < self minimumInterval]) ifTrue: [^self].
	lastStep := now.
	self updateGraph
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> update [
	"Standalone refresh, matching GcFullGraph>>update."
	self updateGraph.
	self graph display
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> updateGraph [
	"Shift the strip left by two pixels and draw one new stacked column.
	Segments are clipped at the top of the strip; a non-zero segment is always
	given at least one pixel so small contributions stay visible."
	| rescaled height top |
	rescaled := self updateScale.
	height := self graph height.

	self graph shiftBy: 2.
	self graph
		drawFrom: 0 to: height
		color: (rescaled ifTrue: [self class slateColor] ifFalse: [self class backgroundColor])
		width: 2.

	top := 0.
	self segments do: [:each | | pixels |
		pixels := each key <= 0
			ifTrue: [0]
			ifFalse: [(each key // self scale) max: 1].
		pixels > 0 ifTrue: [
			self graph
				drawFrom: top
				to: (top := (top + pixels) min: height)
				color: each value
				width: 2]]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAStackedGraph >> updateScale [
	"Answer true if the scale had to be changed, which is the cue to repaint the
	background column so the discontinuity is visible. Grows as soon as the data
	no longer fits, shrinks only once it uses less than half the range."
	| needed |
	needed := self niceScaleFor: self rangeKB // (self graph height max: 1) + 1.
	scale = needed ifTrue: [^false].
	(scale notNil and: [needed < scale and: [needed * 2 > scale]])
		ifTrue: [^false].
	scale := needed.
	^true
]
