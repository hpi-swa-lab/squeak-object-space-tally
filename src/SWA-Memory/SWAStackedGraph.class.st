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
		'lastStep',
		'reading',
		'sampling'
	],
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAStackedGraph >> minimumInterval [
	"Milliseconds between readings, not between columns. Columns advance once per
	morphic step like every other strip; only the probe is throttled, because
	reading /proc and NVML per frame would cost more than the figures move."
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
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:33'
}
SWAStackedGraph >> reading [
	"The most recent reading. Every column between samples repaints this one, and
	segments, rangeKB and labelString all read it, so one draw costs one probe.

	Answers nil until the first background sample lands; every #segments treats
	that as an empty stack, so the strip just starts out blank. Deliberately does
	not probe on demand: the point of sampling in another process is that no draw
	ever waits for a /proc read."
	^reading
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:34'
}
SWAStackedGraph >> sampleIfDue [
	"Take a fresh reading at most once per minimumInterval. The second clause
	catches the millisecond clock wrapping around, which would otherwise freeze
	the reading for the rest of the session.

	The reading is taken in a background process at userBackgroundPriority, below
	the UI, so the morphic step never waits for a scan of /proc. Squeak processes
	are green threads, so this does not make the reads free; it makes them
	preemptible between individual files, which is what removes the stall.

	Publishing the result needs no lock: takeReading builds a complete object and
	a single assignment makes it visible, and green threads cannot interleave
	mid-assignment, so a drawing step sees either the old reading or the new one.

	The in-flight guard matters more than the clock. If a probe ever runs longer
	than minimumInterval, samplers must not pile up behind each other."
	| now |
	sampling == true ifTrue: [^self].
	now := Time millisecondClockValue.
	(lastStep notNil
		and: [now >= lastStep]
		and: [now - lastStep < self minimumInterval]) ifTrue: [^self].
	lastStep := now.
	sampling := true.
	[[reading := self takeReading] ensure: [sampling := false]]
		forkAt: Processor userBackgroundPriority
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
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAStackedGraph >> stepUpdate [
	"Advance one column per caller step, so every strip in the morph shares one
	time axis and a vertical line means the same instant in all of them. Reading
	the source is throttled separately; between samples the last value is
	repainted, which is what keeps the shared axis affordable."
	self sampleIfDue.
	self updateGraph
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:53'
}
SWAStackedGraph >> takeReading [
	"Answer a fresh reading from this strip's data source, or nil when the source
	is unavailable. Called at most once per minimumInterval."
	^self subclassResponsibility
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
