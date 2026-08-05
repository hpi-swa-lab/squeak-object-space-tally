"
A LINEAR, zoomable time axis over any timestamped SWANode tree (see
SWATemporalView). x is wall-clock, y is the chosen measure.

LINEAR ON PURPOSE, and it costs something. Change history is violently bursty: a
save writes forty records in one second, a commit stamps every one of its changes
with the SAME second, and then nothing happens for four hours. On a linear axis
most of the width is therefore empty and each burst is a thin spike. The
alternatives -- collapsing idle gaps, or spacing events evenly by rank -- buy
density by making x stop meaning time, which is the one thing a timeline is for.
So the gaps stay honest and ZOOM does the work instead: drag out a range to zoom
into it, right-click to zoom back out. Rhythm (nights, weekends, the shape of a
working day) stays readable, and detail is a drag away.

Each bar is a time bucket about four pixels wide; within it every event is a
stacked segment, so a bar's height is 'how much happened then' and its segments
are the individual changes -- hover, click, mark and Show all work on them exactly
as on treemap tiles.
"
Class {
	#name : #SWATimelineMorph,
	#superclass : #SWATemporalView,
	#instVars : [
		'bars'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> axisHeight [
	"Strip at the bottom reserved for date/time tick labels."
	^ 20
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> barAt: aLocalPoint [
	"The bucket whose COLUMN contains x -- tested on x alone, so you can click
	anywhere above a short bar and still hit it."
	bars ifNil: [^ nil].
	^ bars
		detect: [:b | b fifth notNil
			and: [aLocalPoint x >= b fifth left and: [aLocalPoint x <= b fifth right]]]
		ifNone: [nil]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> barWidth [
	"Bucket width in pixels. Four is a compromise: narrow enough that a day of work
	does not merge into one block, wide enough to be clickable."
	^ 4
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWATimelineMorph >> breadcrumbString [
	"The visible time window, how much is in it, and what the height means."
	| range shown |
	range := self viewRange ifNil: [^ 'no timestamped events'].
	"The panel asks for this while rebuilding its chrome, which can happen before
	the first draw -- so make sure the buckets exist rather than reporting 0."
	self ensureLayout.
	shown := bars ifNil: [#()] ifNotNil: [:b | b].
	^ String streamContents: [:s |
		s nextPutAll: (TimeStamp fromSeconds: range first) asDate printString;
			nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range first) asTime print24;
			nextPutAll: '  ->  ';
			nextPutAll: (TimeStamp fromSeconds: range second) asDate printString;
			nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range second) asTime print24.
		s nextPutAll: '   '; print: (shown inject: 0 into: [:a :b | a + b third size]);
			nextPutAll: ' events'.
		s nextPutAll: '   y: '; nextPutAll: self measureLabel.
		s nextPutAll: '   [drag to zoom, right-click for options]']
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> drawAxisOn: aCanvas at: anOrigin plotHeight: plotH [
	"Baseline plus round-interval ticks. Ticks are aligned to multiples of the step
	in absolute time, not to the window edge, so they land on whole hours/days and
	stay put while you pan."
	| range span step w font t |
	range := self viewRange ifNil: [^ self].
	span := (range second - range first) max: 1.
	w := self width max: 1.
	font := Preferences standardSystemFont.
	aCanvas
		fillRectangle: ((0 @ plotH extent: w @ 1) translateBy: anOrigin)
		color: (Color gray: 0.35).
	step := self tickStepFor: span.
	t := (range first / step) ceiling * step.
	[t <= range second] whileTrue: [
		| x |
		x := (((t - range first) / span) * w) rounded.
		aCanvas
			fillRectangle: ((x @ plotH extent: 1 @ 4) translateBy: anOrigin)
			color: (Color gray: 0.5).
		aCanvas
			drawString: (self labelForSeconds: t step: step)
			at: ((x + 2) @ (plotH + 4)) + anOrigin
			font: font
			color: (Color gray: 0.65).
		t := t + step]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> drawBar: aBar on: aCanvas at: anOrigin [
	"One time bucket. Its events are stacked bottom-up in chronological order, each
	segment sized by its share of the measure -- so the bar's height is the bucket
	total and its bands are the individual changes.

	Below ~1px per event the segments stop being distinguishable, so we fill the bar
	once with the aggregate intensity instead: same silhouette, no misleading detail."
	| rect nodes total y |
	rect := aBar fifth ifNil: [^ self].
	nodes := aBar third.
	total := aBar fourth max: 1.
	(rect height < nodes size or: [nodes size > 60]) ifTrue: [
		^ aCanvas
			fillRectangle: (rect translateBy: anOrigin)
			color: (self intensityColorFor: aBar fourth max: self maxBarValue)].
	y := rect bottom.
	nodes do: [:n |
		| share h segRect |
		share := (self valueForNode: n) max: 0.
		h := ((share / total) * rect height) rounded max: 1.
		y := y - h.
		segRect := (rect left @ y extent: rect width @ h) translateBy: anOrigin.
		aCanvas fillRectangle: segRect color: (self colorForNode: n)]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> drawOn: aCanvas [
	"Cached bars, then the live range-drag band on top. The band is drawn here and
	not into the cached Form precisely because it changes on every mouse move."
	super drawOn: aCanvas.
	(dragStart notNil and: [dragNow notNil]) ifTrue: [
		| lo hi |
		lo := (dragStart x min: dragNow x) max: 0.
		hi := (dragStart x max: dragNow x) min: self width.
		hi - lo > 3 ifTrue: [
			aCanvas
				fillRectangle: ((lo @ 0 corner: hi @ (self height - self axisHeight))
					translateBy: self position)
				color: (Color white alpha: 0.18)]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWATimelineMorph >> drawScaleLegendOn: aCanvas at: anOrigin [
	"Without this the bar heights are relative to an invisible maximum, so the plot
	shows shape but no magnitude. Label the top of the scale with the tallest
	bucket's value and what it measures."
	| font |
	bars isEmpty ifTrue: [^ self].
	font := Preferences standardSystemFont.
	aCanvas
		drawString: self maxBarValue printString, '  ', self measureLabel
		at: (4 @ 2) + anOrigin
		font: font
		color: (Color gray: 0.55)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> drawSelectionOn: aCanvas at: anOrigin [
	"Yellow frame around the bucket holding the selection. The selected event itself
	is often a sub-pixel band, so highlighting its bar is what actually reads."
	| bar |
	selectedNode ifNil: [^ self].
	bar := bars detect: [:b | b third includes: selectedNode] ifNone: [nil].
	bar ifNil: [^ self].
	aCanvas
		frameRectangle: ((bar fifth expandBy: 1) translateBy: anOrigin)
		width: 1
		color: Color yellow
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> ensureLayout [
	"Bucket the events in the current view range into fixed-width columns, and give
	each bucket a rectangle scaled to the tallest bucket. Nothing here depends on
	colour, so recolouring never runs it."
	| range nBuckets secsPerBucket plotH maxValue w |
	bars ifNotNil: [^ self].
	bars := OrderedCollection new.
	range := self viewRange ifNil: [^ self].
	w := self width max: 1.
	plotH := (self height - self axisHeight) max: 1.
	nBuckets := (w // self barWidth) max: 1.
	secsPerBucket := ((range second - range first) / nBuckets) max: 1.
	"One pass over the events, dropping them into their bucket."
	1 to: nBuckets do: [:i | bars add: {range first + ((i - 1) * secsPerBucket).
		range first + (i * secsPerBucket). OrderedCollection new. 0. nil}].
	self events do: [:n |
		| secs idx |
		secs := self secondsOf: n.
		(secs >= range first and: [secs <= range second]) ifTrue: [
			idx := (((secs - range first) / secsPerBucket) truncated + 1) min: nBuckets.
			(bars at: idx) third add: n]].
	"Value per bucket, then the tallest one sets the vertical scale."
	maxValue := 1.
	bars do: [:b |
		| v | v := self valueForNodes: b third.
		b at: 4 put: v.
		v > maxValue ifTrue: [maxValue := v]].
	bars := bars reject: [:b | b third isEmpty].
	bars do: [:b |
		| h x |
		h := ((b fourth / maxValue) * plotH) rounded max: 1.
		x := (((b first - range first) / (range second - range first)) * w) rounded.
		b at: 5 put: (x @ (plotH - h) extent: (self barWidth - 1 max: 1) @ h)]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> exploreSelected [
	selectedNode ifNotNil: [:n | ToolSet explore: n]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> flushLayout [
	bars := nil.
	super flushLayout
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> handlesMouseMove: evt [
	^ true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> initialize [
	super initialize.
	timeHistory := OrderedCollection new
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> labelForSeconds: secs step: aStep [
	"Tick label at the granularity the step implies: below a day show the clock,
	below a month show the date, above that show month and year."
	| ts |
	ts := TimeStamp fromSeconds: secs.
	aStep < 86400 ifTrue: [^ ts asTime print24].
	aStep < 2592000 ifTrue: [^ ts asDate monthIndex printString, '/', ts asDate dayOfMonth printString].
	^ ts asDate monthName copyFrom: 1 to: (3 min: ts asDate monthName size)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> maxBarValue [
	bars ifNil: [^ 1].
	^ bars inject: 1 into: [:m :b | m max: b fourth]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> mouseDown: evt [
	"Left: select the event under the cursor (and start a possible range drag).
	Shift+left: mark it. Right: context menu (zoom out, measure, colour)."
	| local bar node |
	self takeKeyboardFocusFrom: evt.
	local := evt position - self position.
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt].
	dragStart := local. dragNow := nil.
	bar := self barAt: local.
	bar ifNil: [^ self].
	node := self nodeInBar: bar at: local.
	node ifNil: [^ self].
	evt shiftPressed ifTrue: [
		self toggleMark: node.
		^ self flushCache].
	self selectNode: node
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> mouseMove: evt [
	"Track a range drag. Only repaint once the drag is wide enough to mean
	something, so a click with a shaky hand does not flicker."
	dragStart ifNil: [^ self].
	dragNow := evt position - self position.
	(dragNow x - dragStart x) abs > 3 ifTrue: [self changed]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> mouseUp: evt [
	"A drag wider than a few pixels is a range zoom; anything narrower was a click,
	already handled in #mouseDown:."
	| a b |
	(dragStart notNil and: [dragNow notNil and: [(dragNow x - dragStart x) abs > 3]])
		ifTrue: [
			a := self secondsAtX: dragStart x.
			b := self secondsAtX: dragNow x.
			dragStart := dragNow := nil.
			^ self zoomToStart: a end: b].
	dragStart := dragNow := nil.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> nodeInBar: aBar at: aLocalPoint [
	"Which stacked segment the click landed on. Walks the same bottom-up stack the
	renderer builds, so hit test and drawing cannot drift apart. Clicks above the
	bar (or on an aggregate-filled bar) answer the bucket's largest event, which is
	the one you almost certainly meant."
	| rect nodes total y |
	rect := aBar fifth ifNil: [^ nil].
	nodes := aBar third.
	nodes isEmpty ifTrue: [^ nil].
	total := aBar fourth max: 1.
	(aLocalPoint y between: rect top and: rect bottom) ifFalse: [
		^ nodes inject: nodes first into: [:best :n |
			(self valueForNode: n) > (self valueForNode: best) ifTrue: [n] ifFalse: [best]]].
	y := rect bottom.
	nodes do: [:n |
		| h |
		h := (((self valueForNode: n) / total) * rect height) rounded max: 1.
		y := y - h.
		aLocalPoint y >= y ifTrue: [^ n]].
	^ nodes last
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:50'
}
SWATimelineMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Background, then the axis, then one stacked bar per bucket."
	| plotH |
	aCanvas fillRectangle: (anOrigin extent: self extent) color: (Color gray: 0.12).
	plotH := (self height - self axisHeight) max: 1.
	self drawAxisOn: aCanvas at: anOrigin plotHeight: plotH.
	bars ifNil: [^ self].
	bars do: [:b | self drawBar: b on: aCanvas at: anOrigin].
	self drawScaleLegendOn: aCanvas at: anOrigin.
	self drawSelectionOn: aCanvas at: anOrigin
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:27'
}
SWATimelineMorph >> secondsAtX: anX [
	"Inverse of the x mapping -- what moment a pixel column stands for. Kept as a
	name because this view genuinely works in seconds; the generic machinery now
	lives in SWATemporalView>>timeAtX:."
	^ self timeAtX: anX
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> showMenuAt: evt [
	"Right-click menu: zoom control plus the two axes that make this view
	configurable -- what the height MEANS and what the colour means."
	| menu |
	menu := MenuMorph new defaultTarget: self.
	menu add: 'zoom out' selector: #zoomOut argument: nil.
	menu add: 'reset zoom' selector: #resetZoom argument: nil.
	menu addLine.
	self measureOptions do: [:pair |
		menu
			add: (self measure == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #measure: argument: pair first].
	menu addLine.
	self colorModeOptions do: [:pair |
		menu
			add: (self colorMode == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #colorMode: argument: pair first].
	selectedNode ifNotNil: [:n |
		menu addLine.
		menu add: 'explore event' selector: #exploreSelected argument: nil].
	menu popUpEvent: evt in: self world
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:37'
}
SWATimelineMorph >> tickStepFor: aSpanSeconds [
	"A round tick interval giving roughly 6-10 labels across the visible span.
	Steps are calendar-meaningful (minute/hour/day/week) rather than powers of ten,
	because '3 days' is readable on a time axis and '262144 seconds' is not."
	| candidates target |
	candidates := #(60 300 900 1800 3600 10800 21600 43200 86400 172800 604800 1209600 2592000 7776000 31536000).
	target := aSpanSeconds / 8.
	candidates do: [:c | c >= target ifTrue: [^ c]].
	^ candidates last
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:36'
}
SWATimelineMorph >> viewKind [
	^ #timeline
]
