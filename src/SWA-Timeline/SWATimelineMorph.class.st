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
		'bars',
		'spans',
		'layoutMode'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:30'
}
SWATimelineMorph >> anyEventAnswers: aMeasure [
	"Does any event have a value for aMeasure? Cached per measure: this decides
	whether a menu entry appears, and the menu is rebuilt on every right-click."
	| known |
	known := self valueOfProperty: #measuresAnswered ifAbsentPut: [Dictionary new].
	^ known at: aMeasure ifAbsentPut: [
		self events anySatisfy: [:n | (n eventValueFor: aMeasure) notNil]]
]

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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> breadcrumbString [
	"The visible time window, how much is in it, and what the height means."
	| range shown |
	range := self viewRange ifNil: [^ 'no timestamped events'].
	"The panel asks for this while rebuilding its chrome, which can happen before
	the first draw -- so make sure the buckets exist rather than reporting 0."
	self ensureLayout.
	self layoutMode == #spans ifTrue: [
		^ String streamContents: [:s |
			s nextPutAll: (TimeStamp fromSeconds: range first truncated) asDate printString;
				nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range first truncated) asTime print24;
				nextPutAll: '  ->  ';
				nextPutAll: (TimeStamp fromSeconds: range second truncated) asDate printString;
				nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range second truncated) asTime print24.
			s nextPutAll: '   '; print: (spans ifNil: [#()]) size; nextPutAll: ' spans'.
			s nextPutAll: '   w: duration   h: '; nextPutAll: self measureLabel.
			s nextPutAll: '   [drag to zoom, right-click for options]']].
	shown := bars ifNil: [#()] ifNotNil: [:b | b].
	^ String streamContents: [:s |
		s nextPutAll: (TimeStamp fromSeconds: range first truncated) asDate printString;
			nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range first truncated) asTime print24;
			nextPutAll: '  ->  ';
			nextPutAll: (TimeStamp fromSeconds: range second truncated) asDate printString;
			nextPutAll: ' '; nextPutAll: (TimeStamp fromSeconds: range second truncated) asTime print24.
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> drawScaleLegendOn: aCanvas at: anOrigin [
	"Without this the bar heights are relative to an invisible maximum, so the plot
	shows shape but no magnitude. Label the top of the scale with the tallest
	bucket's value and what it measures."
	| font |
	self layoutMode == #spans ifTrue: [
		spans isEmptyOrNil ifTrue: [^ self].
		^ aCanvas
			drawString: (self formatSpanValue: self maxSpanValue), '  ', self measureLabel,
				'   (width = duration)'
			at: (4 @ 2) + anOrigin
			font: Preferences standardSystemFont
			color: (Color gray: 0.55)].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:20'
}
SWATimelineMorph >> drawSelectionOn: aCanvas at: anOrigin [
	"Yellow frame around the bucket holding the selection. The selected event itself
	is often a sub-pixel band, so highlighting its bar is what actually reads."
	| bar |
	selectedNode ifNil: [^ self].
	"In span mode the event IS a box, so frame the box itself -- no proxy needed."
	self layoutMode == #spans ifTrue: [
		spans ifNil: [^ self].
		^ (spans detect: [:e | e first == selectedNode] ifNone: [nil]) ifNotNil: [:e |
			aCanvas
				frameRectangle: ((e second expandBy: 1) translateBy: anOrigin)
				width: 1
				color: Color yellow]].
	bar := bars detect: [:b | b third includes: selectedNode] ifNone: [nil].
	bar ifNil: [^ self].
	aCanvas
		frameRectangle: ((bar fifth expandBy: 1) translateBy: anOrigin)
		width: 1
		color: Color yellow
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> drawSpansOn: aCanvas at: anOrigin [
	"Every event as a box standing on the baseline, in time order so a later one
	overlapping an earlier is drawn on top.

	SEMI-TRANSPARENT fill: overlapping events are a real feature of the data, and an
	opaque box would hide the one underneath entirely. Through the wash you can see
	that two things ran at once, which is the point."
	| font |
	font := self labelFont.
	spans do: [:e |
		| r c |
		r := e second.
		c := self colorForNode: e first.
		aCanvas fillRectangle: (r translateBy: anOrigin) color: (c alpha: 0.75).
		(r width >= 2 and: [r height >= 3]) ifTrue: [
			aCanvas
				frameRectangle: (r translateBy: anOrigin)
				width: 1
				color: (c lighter alpha: 0.9)]].
	"Labels last, so a wide box's name is never painted over by the box after it."
	spans do: [:e |
		| r |
		r := e second.
		(r width > 30 and: [r height >= font height]) ifTrue: [
			aCanvas
				drawString: (e first name truncateTo: (r width - 4) // (font widthOf: $m))
				at: ((r left + 2) @ (r top + 1)) + anOrigin
				font: font
				color: (Color gray: 0.95)]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:18'
}
SWATimelineMorph >> ensureBucketLayout [
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:18'
}
SWATimelineMorph >> ensureLayout [
	"Two layouts over the same events -- see #layoutMode."
	self layoutMode == #spans
		ifTrue: [^ self ensureSpanLayout]
		ifFalse: [^ self ensureBucketLayout]
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:28'
}
SWATimelineMorph >> ensureSpanLayout [
	"Build `spans` -- a flat list of { node. rect } -- one box per event on ONE time
	axis: x from its start, WIDTH from its duration, HEIGHT from the measure.

	One axis, not a band per kind. Lanes answer 'who was doing this', which the
	colour already says; splitting the height axis between them costs the chart the
	one thing it is for. With everything on a single baseline the silhouette is the
	session's shape over time and the heights are directly comparable -- a four
	second tool call next to a message that cost three cents.

	Boxes may OVERLAP where events do. That is not a defect to pack around: two
	things running at once is a fact about the session, and the honest way to draw
	it is two boxes in the same place, drawn in time order so the later one is on
	top."
	| range span w plotH t0 maxV |
	spans ifNotNil: [^ self].
	spans := OrderedCollection new.
	range := self viewRange ifNil: [^ self].
	t0 := range first.
	span := (range second - t0) max: 1/1000.
	w := self width max: 1.
	plotH := (self height - self axisHeight) max: 1.
	maxV := self maxSpanValue.
	self events do: [:n |
		| secs dur x1 x2 v h |
		secs := self secondsOf: n.
		(secs notNil and: [secs >= t0 and: [secs <= range second]]) ifTrue: [
			dur := (self durationSecondsOf: n) ifNil: [0].
			x1 := ((secs - t0) / span * w) rounded.
			x2 := (((secs + dur) - t0) / span * w) rounded max: x1 + self minSpanPixels.
			v := self spanValueFor: n.
			"A MINIMUM of one pixel, and never zero: an event we have no value for
			(a user message has no cost) still happened, and a box of no height is
			indistinguishable from a gap in the session."
			h := ((v / maxV) * plotH) rounded max: 1.
			spans add: {n. (x1 @ (plotH - h) corner: x2 @ plotH)}]]
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> flushLayout [
	bars := nil.
	spans := nil.
	"Derived from #measure, so they must die when it changes."
	self removeProperty: #maxSpanValue.
	self removeProperty: #groupSizes.
	super flushLayout
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> formatSpanValue: aNumber [
	"Readable top-of-scale label. #duration arrives in MICROSECONDS and #cost in
	dollars, and printing either raw ('4300000', '0.0187185') tells you nothing at a
	glance."
	self measure == #duration ifTrue: [
		aNumber < 1000 ifTrue: [^ aNumber rounded printString , ' us'].
		aNumber < 1000000 ifTrue: [^ ((aNumber / 1000.0) roundTo: 0.1) printString , ' ms'].
		^ ((aNumber / 1000000.0) roundTo: 0.01) printString , ' s'].
	self measure == #cost ifTrue: [^ '$' , ((aNumber roundTo: 0.0001) printString)].
	^ aNumber rounded printString
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:28'
}
SWATimelineMorph >> groupSizeOf: aNode [
	"How many events share aNode's #eventGroupKey. Counted in ONE pass over the
	events and cached, because a per-event scan would make the layout quadratic."
	| counts |
	aNode eventGroupKey ifNil: [^ 1].
	counts := self valueOfProperty: #groupSizes ifAbsentPut: [
		| d |
		d := Dictionary new.
		self events do: [:n |
			n eventGroupKey ifNotNil: [:k | d at: k put: (d at: k ifAbsent: [0]) + 1]].
		d].
	^ (counts at: aNode eventGroupKey ifAbsent: [1]) max: 1
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
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:19'
}
SWATimelineMorph >> labelFont [
	^ self valueOfProperty: #labelFont ifAbsentPut: [
		[StrikeFont familyName: 'DejaVu Sans Mono' size: 9]
			on: Error do: [:e | Preferences standardSystemFont]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:22'
}
SWATimelineMorph >> labelForSeconds: secs step: aStep [
	"Tick label at the granularity the step implies: below a day show the clock,
	below a month show the date, above that show month and year."
	| ts |
	"TRUNCATED: the axis is now in fractional seconds (see
	SWATemporalView>>secondsOf:), and TimeStamp wants a whole number."
	ts := TimeStamp fromSeconds: secs truncated.
	aStep < 86400 ifTrue: [^ ts asTime print24].
	aStep < 2592000 ifTrue: [^ ts asDate monthIndex printString, '/', ts asDate dayOfMonth printString].
	^ ts asDate monthName copyFrom: 1 to: (3 min: ts asDate monthName size)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:23'
}
SWATimelineMorph >> layoutMode [
	"#buckets -- the histogram: events bucketed into fixed-width columns, height =
	measure. Answers 'how much activity around this time'. Every event is a PEAK.

	#spans -- each event drawn as a box from its start to its end, in a band per
	#eventLaneKey. Answers 'what was happening, and for how long'.

	Defaults to #buckets, and is switched by the CALLER rather than auto-detected.
	Auto-detection on 'do the events have durations' looked right and was wrong: the
	whole-project timeline spans three months of tool calls that each lasted a few
	seconds, so every span is at the minimum width and the result is a field of
	identical ticks -- strictly less informative than the histogram it replaced.
	Whether spans help depends on the ratio of event length to window length, which
	only the opener knows. It stays one menu pick away either way."
	^ layoutMode ifNil: [#buckets]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:31'
}
SWATimelineMorph >> layoutMode: aSymbol [
	layoutMode := aSymbol.
	self flushLayout.
	"The two modes have different measure catalogues (#measureOptions), so a mode
	switch can strand the view on a measure the new mode cannot plot -- #commits
	means nothing without buckets, #duration means nothing as a bucket total. Fall
	back to the first the new mode offers rather than drawing a flat line."
	(self measureOptions anySatisfy: [:p | p first == self measure]) ifFalse: [
		self measureOptions ifNotEmpty: [:opts | self measure: opts first first]]
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
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:30'
}
SWATimelineMorph >> maxSpanValue [
	"Tallest event under the current measure, which sets the vertical scale.

	Over the WHOLE data, not over the visible window: rescaling as you pan would
	make two moments in the same session incomparable, which is the one thing a
	timeline has to get right.

	No floor of 1. A cost is a fraction of a dollar, and clamping the scale to 1
	made every message exactly one pixel tall -- the Cost axis drew a flat line and
	looked like missing data. The only thing that needs guarding is division by
	zero, which is what the epsilon is for."
	^ self valueOfProperty: #maxSpanValue ifAbsentPut: [
		(self events inject: 0 into: [:m :n | m max: (self spanValueFor: n)])
			max: 0.000000001]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:30'
}
SWATimelineMorph >> measureLabel [
	"The label from whichever catalogue is in force -- the span measures are not
	the bucket measures, and the inherited lookup only knows the latter."
	^ (self measureOptions detect: [:p | p first == self measure] ifNone: [nil])
		ifNotNil: [:p | p second]
		ifNil: [super measureLabel]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> measureOptions [
	"In SPAN mode the measure is the HEIGHT of each box, so the catalogue is
	different: duration and cost are the two questions a session raises, and
	#commits -- a count of distinct group keys within a bucket -- has no meaning
	when there are no buckets.

	Offered only where the nodes actually answer them, so a change-set timeline
	never shows a Cost entry that would draw a flat line."
	| opts |
	self layoutMode == #spans ifFalse: [^ super measureOptions].
	opts := OrderedCollection new.
	{{#duration. 'Duration'}.
	 {#cost. 'Cost'}.
	 {#tokens. 'Tokens'}.
	 {#context. 'Context (input+cache)'}.
	 {#loc. 'Content size'}.
	 {#count. 'Uniform'}} do: [:pair |
		(self anyEventAnswers: pair first) ifTrue: [opts add: pair]].
	^ opts asArray
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:19'
}
SWATimelineMorph >> minSpanPixels [
	"Narrowest box a span is drawn as, whatever its real duration -- and the width
	an INSTANT gets, since an event with no recorded end is still something that
	happened and must not vanish. The label and the tooltip carry the real number;
	widening is a drawing decision, not a claim about the data."
	^ 2
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:19'
}
SWATimelineMorph >> mouseDown: evt [
	"Left: select the event under the cursor (and start a possible range drag).
	Shift+left: mark it. Right: context menu (zoom out, measure, colour)."
	| local bar node |
	self takeKeyboardFocusFrom: evt.
	local := evt position - self position.
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt].
	dragStart := local. dragNow := nil.
	self layoutMode == #spans ifTrue: [
		node := self spanAt: local.
		node ifNil: [^ self].
		evt shiftPressed ifTrue: [
			self toggleMark: node.
			^ self flushCache].
		^ self selectNode: node].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:29'
}
SWATimelineMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Background, then the axis, then one stacked bar per bucket."
	| plotH |
	aCanvas fillRectangle: (anOrigin extent: self extent) color: (Color gray: 0.12).
	plotH := (self height - self axisHeight) max: 1.
	self drawAxisOn: aCanvas at: anOrigin plotHeight: plotH.
	self layoutMode == #spans ifTrue: [
		spans ifNil: [^ self].
		self drawSpansOn: aCanvas at: anOrigin.
		self drawScaleLegendOn: aCanvas at: anOrigin.
		^ self drawSelectionOn: aCanvas at: anOrigin].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:20'
}
SWATimelineMorph >> showMenuAt: evt [
	"Right-click menu: zoom control plus the two axes that make this view
	configurable -- what the height MEANS and what the colour means."
	| menu |
	menu := MenuMorph new defaultTarget: self.
	menu add: 'zoom out' selector: #zoomOut argument: nil.
	menu add: 'reset zoom' selector: #resetZoom argument: nil.
	menu addLine.
	{{#spans. 'Spans (start .. end)'}. {#buckets. 'Histogram (bucketed peaks)'}} do: [:pair |
		menu
			add: (self layoutMode == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #layoutMode: argument: pair first].
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
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:19'
}
SWATimelineMorph >> spanAt: aLocalPoint [
	"The span whose box contains the point. Searched LAST-FIRST so that when two
	boxes were forced to overlap (both widened to #minSpanPixels at the same
	instant) the click picks the one drawn on top, which is the one you saw."
	spans ifNil: [^ nil].
	spans reverseDo: [:e |
		(e second containsPoint: aLocalPoint) ifTrue: [^ e first]].
	^ nil
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:28'
}
SWATimelineMorph >> spanValueFor: aNode [
	"What this event's HEIGHT stands for, under the current measure. 0 when the node
	knows nothing about it.

	Per-GROUP measures (cost, tokens -- accounted per message, repeated on each of
	its parts) are divided by the number of events sharing the group, so that a
	message's cost is spread across its parts instead of being drawn once per part
	and multiplying the session's total by five."
	| v |
	v := aNode eventValueFor: self measure.
	v ifNil: [^ 0].
	(aNode eventValueIsPerGroup: self measure)
		ifTrue: [^ v / (self groupSizeOf: aNode)].
	^ v
]

{
	#category : #spans,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:18'
}
SWATimelineMorph >> spansAvailable [
	"Do enough events carry a duration for a span view to be worth offering?

	A THIRD, not one: a session where only the tool calls are timed still reads
	well as spans, but a change set with one accidentally-timed entry does not, and
	silently switching that view to a row of ticks would be a regression."
	| evts timed |
	evts := self events.
	evts isEmpty ifTrue: [^ false].
	timed := evts count: [:n | (self durationSecondsOf: n) notNil].
	^ timed * 3 >= evts size
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
