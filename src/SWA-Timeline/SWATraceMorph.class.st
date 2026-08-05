"
A FLAME CHART over a SWATraceNode tree: every call drawn as its own box, at its own
moment, for its own duration.

HOW THIS DIFFERS FROM THE TWO NEIGHBOURS IT RESEMBLES

vs SWASamplingTallyFlamegraphMorph -- a flamegraph's x axis is not time, it is
SORTED AGGREGATE WIDTH. Two boxes side by side there mean ""these two methods
together account for this fraction""; here they mean ""this one ran, then that one
did"". A flamegraph cannot show a call happening twice, a gap, or two processes; this
cannot show a total.

vs SWATimelineMorph -- that is a HISTOGRAM of instants, bucketed into fixed-width
columns. It answers ""how much activity around this time"". Its nodes have a
timestamp; ours have a timestamp AND a duration (#eventDurationMicros), which is
what buys the second axis.

LAYOUT
  x     = (start - viewStart) scaled to the width, so it is real elapsed time
  width = duration, same scale
  y     = instrumented call depth within the node's LANE
  lanes = one horizontal band per process, stacked, each with a header

Lanes are not merged, deliberately: the render loop and the UI interleave in real
time, and splicing them onto one depth axis would draw parent/child relationships
that never existed.

SUB-PIXEL SPANS ARE MERGED, NOT DROPPED
At any useful zoom most calls are narrower than a pixel. Drawing them is impossible
and discarding them silently would show an empty stretch where thousands of calls
ran. Runs of adjacent too-narrow siblings therefore collapse into one hatched box
labelled with the count; clicking it zooms into its range, where it opens up. The
number of spans not individually drawn is in #metaInfoString, so the picture never
claims to be complete when it is not.

TIME BASE
Microseconds, via #timeUnitsOf: -> #eventMicros. Everything about range, zoom, drag
and the Back button is inherited from SWATemporalView, which is unit-agnostic
precisely so this view could exist without forking it.
"
Class {
	#name : #SWATraceMorph,
	#superclass : #SWATemporalView,
	#instVars : [
		'frames',
		'rowHeight',
		'laneBands',
		'hiddenCount'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> axisHeight [
	^ 18
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:11'
}
SWATraceMorph >> breadcrumbString [
	"Visible window, what is drawn, and -- crucially -- what is NOT. The hidden count
	is not a footnote: at full zoom-out it is usually most of the trace, and a picture
	of 300 boxes standing for 90000 calls must say so."
	| range zero |
	range := self viewRange ifNil: [^ 'no trace'].
	self ensureLayout.
	zero := self traceZero.
	^ String streamContents: [:s |
		s nextPutAll: (SWATraceNode stringForMicros: (range first - zero) rounded);
			nextPutAll: '  ->  ';
			nextPutAll: (SWATraceNode stringForMicros: (range second - zero) rounded);
			nextPutAll: '   ('; nextPutAll: (SWATraceNode stringForMicros:
				(range second - range first) rounded); nextPutAll: ' wide)'.
		"Count SPANS, not boxes: a merged box is not a call, and reporting
		'417 boxes' next to '5116 merged' invites adding them into a total that is
		233 too big. Say how many of the calls got their own box."
		s nextPutAll: '   '; print: self drawnSpanCount;
			nextPutAll: ' of '; print: self drawnSpanCount + (hiddenCount ifNil: [0]);
			nextPutAll: ' calls drawn'.
		(hiddenCount ifNil: [0]) > 0 ifTrue: [
			s nextPutAll: ', '; print: hiddenCount; nextPutAll: ' merged'].
		s nextPutAll: '   [drag to zoom, click a hatched box to open it]']
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> browseSelected [
	| n key cls sel |
	n := selectedNode ifNil: [^ self].
	key := n crossRefKey ifNil: [^ self].
	(key includesSubstring: '>>') ifFalse: [^ self].
	cls := Smalltalk classNamed: (key copyUpToLast: $>) allButLast.
	cls ifNil: [^ self].
	sel := (key copyAfterLast: $>) asSymbol.
	(cls includesSelector: sel) ifTrue: [ToolSet browse: cls selector: sel]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> colorModeOptions [
	^ { {#method. 'By method (stable hue)'}.
		{#duration. 'By duration (heat)'} }
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:04'
}
SWATraceMorph >> columnAt: x in: cols [
	"The { step. old. young. committed } slot for pixel column x, created empty on first
	touch. Slots are filled in independently -- a column can carry a step time with no
	memory reading (mid-cycle) or a reading with no step (nothing ran) -- so every field
	is nil until something writes it."
	^ (cols at: x + 1) ifNil: [
		| slot |
		slot := Array new: 4.
		cols at: x + 1 put: slot.
		slot]
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:04'
}
SWATraceMorph >> columnSeriesIn: range span: span width: w [
	"Bucket the per-cycle samples into one entry per PIXEL COLUMN:
	{ longest step (micros). live old space. used young space. committed } -- memory in
	bytes. nil where no cycle fell in that column. Answers nil if the run has no samples.

	Everything is a MAXIMUM, never an average. The whole reason to draw these bands is
	the cycle that took 200 ms and the peak that triggered the collection; averaging is
	exactly the operation that hides both, and at zoom-out one column can cover a
	hundred cycles.

	THE TWO QUANTITIES ARE PLACED DIFFERENTLY, and that is the whole subtlety here.

	Memory is an INSTANT: one reading, at the moment it was taken, at that one column.
	It is made continuous afterwards by #holdColumns:, because between two readings the
	committed heap is the last measured figure -- nothing observed it change.

	Step time is an INTERVAL: the cycle ran from t1-duration to t1, and the value belongs
	to every column in between. Stamping it at t1 (the sample's timestamp) and holding it
	forward -- the first version of this -- is wrong twice over: the stretch of x where
	the image was actually frozen shows the PREVIOUS cycle's value, and the spike is then
	carried into the NEXT cycle's stretch. Measured on a 125 ms cycle: the stall covered
	columns 217..362 and the spike was drawn at 363. Everything shifted right by one step.

	Both are MAXIMA per column, never averages. The whole reason to draw these bands is
	the cycle that took 200 ms and the peak that triggered the collection; averaging is
	exactly the operation that hides both, and at zoom-out one column can cover a
	hundred cycles.

	Samples from before this class carried a step time are tolerated (nil step, memory
	only), so a trace collected earlier still draws instead of erroring."
	| samples cols |
	samples := rootNode ifNil: [^ nil] ifNotNil: [:r | r series].
	samples isEmpty ifTrue: [^ nil].
	cols := Array new: w + 1.
	samples do: [:s |
		| step x x0 x1 old young committed slot |
		old := s second - s fourth.		"committed old - free old = live old"
		young := s third.
		committed := s second + s third.
		x := (s first - range first) * w // span.
		(x >= 0 and: [x <= w]) ifTrue: [
			slot := self columnAt: x in: cols.
			slot at: 2 put: ((slot second ifNil: [0]) max: old).
			slot at: 3 put: ((slot third ifNil: [0]) max: young).
			slot at: 4 put: ((slot fourth ifNil: [0]) max: committed)].
		step := s size >= 5 ifTrue: [s fifth] ifFalse: [nil].
		step ifNotNil: [
			x0 := (s first - step - range first) * w // span.
			x1 := x.
			(x1 >= 0 and: [x0 <= w]) ifTrue: [
				(x0 max: 0) to: (x1 min: w) do: [:xi |
					slot := self columnAt: xi in: cols.
					(slot first isNil or: [step > slot first])
						ifTrue: [slot at: 1 put: step]]]]].
	^ cols
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> countUnder: aNode [
	| n |
	n := 0.
	aNode withAllChildrenDo: [:each | n := n + 1].
	^ n - 1
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> depthOf: aNode [
	"Deepest nesting below aNode, 0 for a leaf. Used to size a lane's band."
	| max |
	max := 0.
	aNode children do: [:c | max := max max: (self depthOf: c) + 1].
	^ max
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:33'
}
SWATraceMorph >> drawAxisOn: aCanvas at: anOrigin [
	"Baseline plus round-interval ticks, labelled in time SINCE THE START OF THE
	TRACE. Absolute clock values would be microseconds since 1901 -- true and
	useless. Ticks are aligned to multiples of the step in trace-relative time, so
	they land on round numbers and stay put while zooming."
	| range span w font t y0 step |
	range := self viewRange ifNil: [^ self].
	span := (range second - range first) max: 1.
	w := self width max: 1.
	y0 := self height - self axisHeight.
	font := self labelFont.
	aCanvas
		fillRectangle: ((0 @ y0 extent: w @ 1) translateBy: anOrigin)
		color: (Color gray: 0.35).
	step := self tickStepFor: span.
	"Align ticks in TRACE-RELATIVE time, not absolute. The clock's zero is 1901, so
	aligning to absolute multiples puts the first tick at an arbitrary offset and
	every label reads 19 us / 119 us / 219 us instead of 0 / 100 / 200."
	t := ((range first - self traceZero) / step) ceiling * step.
	[t + self traceZero <= range second] whileTrue: [
		| x |
		x := (t + self traceZero - range first) * w // span.
		aCanvas
			fillRectangle: ((x @ y0 extent: 1 @ 4) translateBy: anOrigin)
			color: (Color gray: 0.5).
		aCanvas
			drawString: (self labelForMicros: t)
			at: ((x + 2) @ (y0 + 4)) + anOrigin
			font: font
			color: (Color gray: 0.65).
		t := t + step]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> drawFrame: aFrame on: aCanvas at: anOrigin [
	"One box: a lane header (depth -1), a merged run (node nil) or a real span."
	| node rect r |
	node := aFrame first.
	rect := aFrame second.
	r := rect translateBy: anOrigin.
	aFrame third = -1 ifTrue: [^ self drawLaneHeader: node in: r on: aCanvas].
	node isNil ifTrue: [^ self drawMerged: aFrame fourth in: r on: aCanvas].
	aCanvas fillRectangle: r color: (self spanColorFor: node).
	rect width > 6 ifTrue: [
		aCanvas frameRectangle: r width: 1 color: (Color black alpha: 0.25)].
	selectedNode == node ifTrue: [
		aCanvas frameRectangle: r width: 2 color: Color white].
	rect width > 24 ifTrue: [
		self drawSpanLabelFor: node in: r on: aCanvas]
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:53'
}
SWATraceMorph >> drawGraphBandsOn: aCanvas at: anOrigin [
	"The two continuous bands above the lanes: step time, then memory. Same x axis as
	the spans, so a GC mark, the cycle that paid for it and the sawtooth that caused it
	line up vertically -- which is the only reason to put them in this window rather
	than in SWA Memory Stats, where the numbers already were."
	| range span w cols h |
	self graphBandsHeight = 0 ifTrue: [^ self].
	range := self viewRange ifNil: [^ self].
	span := (range second - range first) max: 1.
	w := self width max: 1.
	cols := self columnSeriesIn: range span: span width: w.
	cols ifNil: [^ self].
	cols := self holdColumns: cols.
	h := self graphBandHeight.
	self drawStepTimeBand: cols in: (0 @ 0 extent: w @ h) on: aCanvas at: anOrigin.
	self drawMemoryBand: cols in: (0 @ h extent: w @ h) on: aCanvas at: anOrigin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:08'
}
SWATraceMorph >> drawLaneHeader: aLane in: r on: aCanvas [
	"Process name, priority and span count. Per-lane, because 'which process' is the
	one fact a merged view would destroy."
	aCanvas fillRectangle: r color: (Color gray: 0.18).
	aCanvas
		drawString: aLane name , '   ' , (self countUnder: aLane) printString , ' calls'
		at: (r left + 4) @ (r top)
		font: self labelFont
		color: (Color gray: 0.7)
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:05'
}
SWATraceMorph >> drawMemoryBand: cols in: aRect on: aCanvas at: anOrigin [
	"Committed memory per pixel column, stacked: live old space at the bottom, used young
	space on top of it, and the rest of the committed heap as the pale remainder.

	Stacked and not three lines, because the question these bands exist to answer is
	'what did the GC react to', and that is about PROPORTION -- young filling up under a
	flat old space is a scavenge about to happen; old space stepping up is a tenuring
	problem. Young space is a few hundred KB against a few hundred MB of old, so it gets
	a one-pixel floor: at true scale it would be invisible exactly when it matters.

	Scaled to the largest committed heap in view, never to zero, so the band shows the
	SHAPE of the heap and not a full bar that never moves."
	| max h base |
	max := 1.
	cols do: [:c | (c notNil and: [c fourth notNil]) ifTrue: [max := max max: c fourth]].
	h := aRect height - 13.
	base := aRect top + aRect height - 2.
	aCanvas fillRectangle: (aRect translateBy: anOrigin) color: (Color gray: 0.16).
	1 to: cols size do: [:i |
		| c x committedH oldH youngH |
		c := cols at: i.
		(c notNil and: [c fourth notNil]) ifTrue: [
			x := aRect left + i - 1.
			committedH := c fourth * h // max.
			oldH := c second * h // max.
			youngH := (c third * h // max) max: 1.
			aCanvas
				fillRectangle: ((x @ (base - committedH) extent: 1 @ committedH) translateBy: anOrigin)
				color: (GcGraph deepOceanColor alpha: 0.35).
			aCanvas
				fillRectangle: ((x @ (base - oldH) extent: 1 @ oldH) translateBy: anOrigin)
				color: (GcGraph deepOceanColor alpha: 0.75).
			aCanvas
				fillRectangle: ((x @ (base - oldH) extent: 1 @ 1) translateBy: anOrigin)
				color: GcGraph deepOceanColor.
			aCanvas
				fillRectangle: ((x @ (base - oldH - youngH) extent: 1 @ youngH) translateBy: anOrigin)
				color: GcGraph seafoamColor]].
	aCanvas
		drawString: 'memory   committed ', (max / 1048576.0) rounded printString, ' MB',
			'   [old, young, free]'
		at: (aRect left + 3) @ (aRect top + 1) + anOrigin
		font: self labelFont
		color: (Color gray: 0.6)
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> drawMerged: count in: r on: aCanvas [
	"A run of spans too narrow to draw individually, as a dim HATCHED box. The
	hatching matters: a flat box here would read as one long call, which is the exact
	opposite of the truth -- it is many short ones."
	| x |
	aCanvas fillRectangle: r color: (Color gray: 0.28).
	x := r left.
	[x < r right] whileTrue: [
		aCanvas fillRectangle: (x @ r top extent: 1 @ r height) color: (Color gray: 0.42).
		x := x + 3].
	r width > 30 ifTrue: [
		aCanvas
			drawString: count printString , ' calls'
			at: (r left + 3) @ (r top - 1)
			font: self labelFont
			color: (Color gray: 0.75)]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> drawOn: aCanvas [
	"Cached spans, then the live range-drag band on top -- drawn here and not into the
	Form precisely because it changes on every mouse move."
	super drawOn: aCanvas.
	"The scrollbar is drawn HERE, not into the cached Form, because its geometry is in
	global coordinates and because it changes with the scroll position rather than with
	the picture."
	self drawScrollIndicatorOn: aCanvas.
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
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:11'
}
SWATraceMorph >> drawSpanLabelFor: aNode in: r on: aCanvas [
	"Selector only, elided from the FRONT so the tail stays readable -- in a trace the
	class prefix repeats endlessly and the selector is what distinguishes the boxes.
	Clipped to the box so a long name cannot bleed into its neighbour."
	| font label maxChars |
	font := self labelFont.
	label := aNode name copyAfterLast: $>.
	label isEmpty ifTrue: [label := aNode name].
	maxChars := (r width - 6) // (font widthOf: $n) max: 1.
	"Below ~8 characters an elided label is '...:' -- three dots of ellipsis and one
	real character. That is not a shorter label, it is noise that reads as a label.
	Draw nothing instead; the box still has its colour, and hovering still names it."
	maxChars < 8 ifTrue: [^ self].
	label := self elideHead: label to: maxChars.
	(aCanvas copyClipRect: (r insetBy: 2 @ 0))
		drawString: label
		at: (r left + 3) @ (r top + ((r height - font height) // 2))
		font: font
		color: (Color gray: 0.08)
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:53'
}
SWATraceMorph >> drawStepTimeBand: cols in: aRect on: aCanvas at: anOrigin [
	"How long each Morphic cycle took, longest-of-column, as a filled curve.

	STEP TIME UPWARDS, not frame rate downwards. A stall is then a spike, and spikes are
	what the eye finds; as a rate it is a dip towards zero, and a dip towards zero has
	nowhere left to go -- a 40 ms stutter and a 400 ms freeze come out looking nearly the
	same. It is also the same unit as the spans in the lanes below, so a tall column and
	the wide span that caused it read together.

	The scale is anchored at one 60 fps frame (16.7 ms) and grows to the worst cycle in
	view, so a smooth run is a low flat band under the budget line rather than noise
	rescaled to fill the height."
	| max h base ref frame |
	frame := 16667.
	max := frame.
	cols do: [:c | (c notNil and: [c first notNil]) ifTrue: [max := max max: c first]].
	h := aRect height - 13.
	base := aRect top + aRect height - 2.
	aCanvas fillRectangle: (aRect translateBy: anOrigin) color: (Color gray: 0.16).
	ref := base - (frame * h // max).
	aCanvas
		fillRectangle: ((aRect left @ ref extent: aRect width @ 1) translateBy: anOrigin)
		color: (Color gray: 0.3).
	1 to: cols size do: [:i |
		| c bh col x |
		c := cols at: i.
		(c notNil and: [c first notNil]) ifTrue: [
			bh := (c first * h // max) max: 1.
			x := aRect left + i - 1.
			col := c first > (frame * 2) ifTrue: [GcGraph coralColor] ifFalse: [GcGraph deepOceanColor].
			"Area under the curve dimmed, the curve itself solid on top. With every column
			filled (#holdColumns:) a single flat colour is a block, not a graph -- the
			bright top edge is what makes the shape readable."
			aCanvas
				fillRectangle: ((x @ (base - bh) extent: 1 @ bh) translateBy: anOrigin)
				color: (col alpha: 0.3).
			aCanvas
				fillRectangle: ((x @ (base - bh) extent: 1 @ 2) translateBy: anOrigin)
				color: col]].
	aCanvas
		drawString: 'step time   16.7 ms ---   worst ', (SWATraceNode stringForMicros: max)
		at: (aRect left + 3) @ (aRect top + 1) + anOrigin
		font: self labelFont
		color: (Color gray: 0.6)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:11'
}
SWATraceMorph >> drawnSpanCount [
	"Frames that are a real call: not the lane headers (depth -1), not the merged
	runs (node nil)."
	^ (frames ifNil: [^ 0]) count: [:f | f first notNil and: [f third >= 0]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> elideHead: aString to: maxChars [
	"Truncate from the FRONT with a leading ellipsis, so the tail stays visible."
	aString size <= maxChars ifTrue: [^ aString].
	maxChars < 4 ifTrue: [^ ''].
	^ '...', (aString last: maxChars - 3)
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:11'
}
SWATraceMorph >> emitMergedFrom: x1 to: x2 count: n hidden: descendants depth: d top: top [
	"One box standing for n adjacent spans too narrow to draw, plus their whole
	subtrees. node is nil and the count rides in slot 4, which is how #drawFrame:
	knows to hatch it and #mouseDown: knows to zoom rather than select.

	BOTH numbers are counted into hiddenCount: the n merged siblings AND their
	`descendants` children, which are never laid out at all. Counting only the
	siblings under-reported a real XR frame as '854 calls merged' when 4957 of 5299
	calls were not individually drawn -- a caption that made the picture look far
	more complete than it was."
	| w |
	w := self width max: 1.
	hiddenCount := hiddenCount + n + descendants.
	frames add: { nil.
		((x1 max: 0) @ top corner: ((x2 min: w) max: x1 + 1) @ (top + rowHeight - 1)).
		d.
		n + descendants }
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:26'
}
SWATraceMorph >> ensureLayout [
	"Build `frames` -- a flat list of { node. rect. depth. mergedCount } in LOCAL
	coordinates -- one entry per drawable span, plus one per lane header and one per
	merged run of sub-pixel spans.

	Flat and precomputed for the same reason the flamegraph's is: the result goes
	into a cached Form and gets blitted, and hit testing is then a linear scan over
	rectangles rather than a tree walk per mouse move.

	CONTENT COORDINATES: y runs from 0 at the first lane, NOT from my top edge. The
	scroll position and the space the continuous bands take are applied at draw and
	hit-test time (#laneOffset), so scrolling never invalidates this layout -- it only
	invalidates the cached Form.

	Vertical budget: each lane gets a header row plus as many rows as it is deep, and
	ALL lanes are laid out however tall that comes to. Rows are never squeezed, because
	rows a few pixels high produce a picture that looks like data and is not readable;
	what does not fit is reached by scrolling. #contentHeight is the total, which is
	what SWAView's scrollbar measures itself against."
	| range span w y |
	frames ifNotNil: [^ self].
	frames := OrderedCollection new.
	laneBands := OrderedCollection new.
	hiddenCount := 0.
	rootNode ifNil: [^ self].
	range := self viewRange ifNil: [^ self].
	span := (range second - range first) max: 1.
	w := self width max: 1.
	y := 0.
	rootNode children do: [:lane |
		| depth needed |
		depth := self depthOf: lane.
		needed := (depth + 1) * rowHeight + self laneHeaderHeight.
		frames add: { lane.
			(0 @ y extent: w @ self laneHeaderHeight).
			-1.
			0 }.
		laneBands add: { lane. y. y + needed }.
		self
			layoutChildrenOf: lane
			depth: 0
			top: y + self laneHeaderHeight
			rangeStart: range first
			span: span
			width: w.
		y := y + needed + self laneGap].
	contentHeight := y
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> exploreSelected [
	selectedNode ifNotNil: [:n | n explore]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> exportChromeTrace [
	"Write the trace as Chrome Trace Event JSON, loadable in chrome://tracing or
	ui.perfetto.dev by dropping the file on the page."
	| name f |
	rootNode ifNil: [^ self].
	name := UIManager default
		request: 'Write Chrome trace JSON to:'
		initialAnswer: 'squeak-trace.json'.
	(name isNil or: [name isEmpty]) ifTrue: [^ self].
	f := FileStream forceNewFileNamed: name.
	[f nextPutAll: rootNode chromeTraceJson] ensure: [f close].
	self inform: 'Wrote ', name, String cr, 'Open ui.perfetto.dev and drop the file on it.'
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> flushLayout [
	frames := nil.
	laneBands := nil.
	self flushCache
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> frameAt: aLocalPoint [
	"The frame under a local point. Scanned in REVERSE so the deepest box wins:
	frames are emitted parent-before-child, and a child is drawn on the row below its
	parent rather than over it, but merged runs and lane headers can overlap edges."
	| p |
	frames ifNil: [^ nil].
	"Frames are in CONTENT coordinates; the point is in mine. One conversion, the same
	#laneOffset the drawing uses -- hit-testing against a different mapping than the one
	that painted the picture is how a view ends up looking right and feeling wrong."
	p := aLocalPoint - (0 @ self laneOffset).
	frames reverseDo: [:f |
		((f second) containsPoint: p) ifTrue: [^ f]].
	^ nil
]

{
	#category : #steps,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:09'
}
SWATraceMorph >> gcNotesWithin: aNode [
	"The names of the GC marks overlapping aNode's interval, joined, or '' if none.
	The marks live in a lane of their own, so the only way to connect a slow step to the
	collection that caused it is to intersect the two time ranges -- which is exactly
	what you want to know first about a 145 ms cycle."
	| gcLane hits |
	gcLane := rootNode ifNil: [^ ''] ifNotNil: [:r |
		r children detect: [:l | l name = 'GC'] ifNone: [nil]].
	gcLane ifNil: [^ ''].
	hits := gcLane children select: [:m |
		m startMicros < aNode stopMicros and: [m stopMicros > aNode startMicros]].
	hits isEmpty ifTrue: [^ ''].
	^ String streamContents: [:s |
		s nextPutAll: '   incl. '.
		hits do: [:m | s nextPutAll: m name] separatedBy: [s nextPutAll: ' + ']]
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:40'
}
SWATraceMorph >> graphBandHeight [
	"Height of ONE continuous band (fps, memory). Tall enough for a shape to be a shape,
	short enough that two of them do not evict a lane from a small window."
	^ 40
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:40'
}
SWATraceMorph >> graphBandsHeight [
	"Vertical space the continuous bands take off the top, and therefore where the lanes
	start. Zero when the run has no samples -- a trace collected without step boundaries
	(no Morphic running) draws exactly as it did before."
	rootNode ifNil: [^ 0].
	^ rootNode series isEmpty ifTrue: [0] ifFalse: [2 * self graphBandHeight]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceMorph >> handlesMouseMove: evt [
	^ true
]

{
	#category : #bands,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:05'
}
SWATraceMorph >> holdColumns: cols [
	"SAMPLE AND HOLD -- for MEMORY ONLY. Step time is left exactly where
	#columnSeriesIn: painted it.

	The two need opposite treatment, and giving them the same one was the bug. Committed
	memory is sampled at instants, and between two samples it is the last measured
	figure because nothing observed it change: holding is what the value DID, not an
	interpolation. Step time is already painted across the interval its cycle occupied,
	so holding it would smear every cycle over the following one -- exactly the
	one-step shift this pass used to introduce. Where no cycle was running the step
	band is empty, and that gap is the inter-cycle pause: information, not a hole.

	Leading columns are held BACKWARDS from the first reading, so the memory band
	reaches the left edge instead of starting after the first cycle."
	| out lastMem firstIdx first |
	out := Array new: cols size.
	lastMem := nil.
	1 to: cols size do: [:i |
		| c step |
		c := cols at: i.
		(c notNil and: [c second notNil]) ifTrue: [lastMem := c].
		step := c ifNil: [nil] ifNotNil: [:x | x first].
		(step notNil or: [lastMem notNil]) ifTrue: [
			out at: i put: (Array
				with: step
				with: (lastMem ifNil: [nil] ifNotNil: [:m | m second])
				with: (lastMem ifNil: [nil] ifNotNil: [:m | m third])
				with: (lastMem ifNil: [nil] ifNotNil: [:m | m fourth]))]].
	firstIdx := (1 to: out size)
		detect: [:i | (out at: i) notNil and: [(out at: i) second notNil]]
		ifNone: [nil].
	firstIdx ifNil: [^ out].
	first := out at: firstIdx.
	1 to: firstIdx - 1 do: [:i |
		| c |
		c := out at: i.
		out at: i put: (Array
			with: (c ifNil: [nil] ifNotNil: [:x | x first])
			with: first second
			with: first third
			with: first fourth)].
	^ out
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:27'
}
SWATraceMorph >> initialize [
	super initialize.
	rowHeight := 14.
	measure := #time.
	colorMode := #method
]

{
	#category : #steps,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:18'
}
SWATraceMorph >> isStepSpan: aNode [
	"True if aNode is a Morphic cycle -- the span the step-time band measures, and the
	one worth reading in frame terms. Recognised by its cross-ref key: the cycle sits in
	the ordinary process lane among every other call, so there is no lane to ask and no
	flag on the node to keep in sync."
	^ self stepSpanKeys includes: aNode crossRefKey
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> labelFont [
	"Smaller than the flamegraph's: a trace packs many more, much shorter boxes into
	the same width, so legibility per box loses to how many boxes get a label at all.
	Same fallback chain."
	^ (StrikeFont familyName: 'BitstreamVeraSans' size: 8)
		ifNil: [(StrikeFont familyName: 'Atlanta' size: 8)
			ifNil: [TextStyle defaultFont]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceMorph >> labelForMicros: micros [
	^ SWATraceNode stringForMicros: micros rounded
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> laneGap [
	^ 6
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> laneHeaderHeight [
	^ 15
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:36'
}
SWATraceMorph >> laneOf: aNode do: aBlock [
	"Evaluate aBlock with the LANE ROOT above aNode -- the child of the trace root,
	i.e. the process it ran in. Nothing happens if aNode is a lane or the root itself."
	| n |
	n := aNode.
	[n notNil and: [n parent notNil]] whileTrue: [
		n parent parent isNil ifTrue: [^ aBlock value: n].
		n := n parent]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:26'
}
SWATraceMorph >> laneOffset [
	"Where content y = 0 lands in my local coordinates: below the bands, moved up by the
	scroll position. Frames are laid out from 0 so that the layout survives scrolling
	untouched -- one place converts, here."
	^ self graphBandsHeight - (scrollY ifNil: [0])
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> layoutChildrenOf: aNode depth: d top: top rangeStart: t0 span: span width: w [
	"Lay out aNode's children as boxes on the time axis, merging runs of adjacent
	sub-pixel siblings, then recurse into the ones that were drawn individually.

	THE MERGE is the honest part of this method. At any interesting zoom most calls
	are far narrower than a pixel; drawing each is impossible and skipping each is a
	lie, because a stretch where ten thousand short calls ran would render as empty.
	So consecutive children that are each too narrow accumulate into one box carrying
	their COUNT, which is drawn hatched so it cannot be mistaken for a real call.
	A merged run is not recursed into -- its children are narrower still.

	Children are already in start order from reconstruction, so one left-to-right
	pass suffices and no sorting is needed."
	| runStart runEnd runCount runHidden |
	"Depth is bounded by #maxContentHeight, not by my own height: what does not fit on
	screen is now reached by SCROLLING, so the only thing left to guard against is a
	pathologically deep tree turning into a hundred thousand frames nobody will look at."
	top + rowHeight > self maxContentHeight ifTrue: [
		hiddenCount := hiddenCount + (self countUnder: aNode).
		^ self].
	runStart := nil. runEnd := nil. runCount := 0. runHidden := 0.
	aNode children do: [:c |
		| x1 x2 |
		x1 := (c startMicros - t0) * w // span.
		x2 := (c stopMicros - t0) * w // span.
		(x2 < 0 or: [x1 > w])
			ifTrue: ["entirely outside the view -- not hidden, just not now"]
			ifFalse: [
				(x2 - x1 < self minSpanPixels
					and: [c markerKind isNil and: [c hasMarkers not]])
					ifTrue: [
						"too narrow to draw: start or extend the merged run"
						(runStart notNil and: [x1 - runEnd > self minSpanPixels]) ifTrue: [
							self emitMergedFrom: runStart to: runEnd count: runCount
								hidden: runHidden depth: d top: top.
							runStart := nil].
						runStart
							ifNil: [runStart := x1. runEnd := x2. runCount := 1.
								runHidden := self countUnder: c]
							ifNotNil: [runEnd := x2. runCount := runCount + 1.
								runHidden := runHidden + (self countUnder: c)]]
					ifFalse: [
						runStart ifNotNil: [
							self emitMergedFrom: runStart to: runEnd count: runCount
								hidden: runHidden depth: d top: top.
							runStart := nil. runCount := 0. runHidden := 0].
						"A GC marker is an ANNOTATION, not a call: it is never merged away
						and never drawn narrower than #markerMinPixels. A 0.4 ms scavenge
						is sub-pixel at any useful zoom, and a mark you cannot see or
						click is not a mark. The label carries the real number."
						c markerKind ifNotNil: [x2 := x2 max: x1 + self markerMinPixels].
						"...and a step that CONTAINS a marker is never merged away either
						(the test above), and is widened enough to hold it. Otherwise the
						100 ms full GC would be invisible precisely because the cycle that
						paid for it did nothing else and is two pixels wide."
						c hasMarkers ifTrue: [x2 := x2 max: x1 + self markerMinPixels + 2].
						frames add: { c.
							((x1 max: 0) @ top corner: ((x2 min: w) max: x1 + 1) @ (top + rowHeight - 1)).
							d.
							0 }.
						self layoutChildrenOf: c depth: d + 1 top: top + rowHeight
							rangeStart: t0 span: span width: w]]].
	runStart ifNotNil: [
		self emitMergedFrom: runStart to: runEnd count: runCount
			hidden: runHidden depth: d top: top]
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:55'
}
SWATraceMorph >> markerMinPixels [
	"Narrowest box a GC marker is drawn as, whatever its real duration. Wide enough to
	see and to hit with the mouse; narrow enough that nobody mistakes it for a
	millisecond. Real GC pauses are wider than this on their own and are unaffected."
	^ 4
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> maxContentHeight [
	"Ceiling on laid-out content, in pixels. Roughly 400 rows: deep enough that no real
	call stack reaches it, shallow enough that a runaway recursion cannot turn the
	layout into an unbounded amount of work. What is cut off is counted into
	#hiddenCount and reported in the breadcrumb."
	^ rowHeight * 400
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:18'
}
SWATraceMorph >> metaInfoString [
	"Details of the selected span: where it is in the run, how long it took, how much
	of that was its own, and how many instrumented calls it made."
	| n |
	n := selectedNode ifNil: [^ metaInfo ifNil: ['']].
	"A marker is not a call: 'self time' and 'direct calls' would both be 0 and both be
	meaningless. Say instead what is actually known -- and what is not."
	n markerKind ifNotNil: [
		^ String streamContents: [:s |
			s nextPutAll: n name; nextPutAll: '   detected at ';
				nextPutAll: (SWATraceNode stringForMicros: n stopMicros - self traceZero).
			n parent ifNotNil: [:p |
				s nextPutAll: '   at the end of '; nextPutAll: (p name ifNil: ['?'])].
			s nextPutAll: '   [GC: the VM reports only that it happened during this step, not when]']].
	"A STEP is read as a frame, so give it in frame terms: how long it took, what rate
	that is if every frame cost the same, how many 60 fps budgets it ate, and which
	collection (if any) happened inside it. 'took 145.706 ms' alone leaves you doing
	that arithmetic in your head every time."
	(self isStepSpan: n) ifTrue: [
		^ String streamContents: [:s |
			| d |
			d := n durationMicros max: 1.
			s nextPutAll: n name; nextPutAll: '   at ';
				nextPutAll: (SWATraceNode stringForMicros: n startMicros - self traceZero);
				nextPutAll: '   took ';
				nextPutAll: (SWATraceNode stringForMicros: n durationMicros);
				nextPutAll: '   = ';
				nextPutAll: ((1000000.0 / d) printShowingDecimalPlaces: 1);
				nextPutAll: ' fps   ';
				nextPutAll: ((d / 16667.0) printShowingDecimalPlaces: 1);
				nextPutAll: ' x 16.7 ms budget'.
			s nextPutAll: (self gcNotesWithin: n).
			s nextPutAll: '   '; print: n children size; nextPutAll: ' direct calls']].
	^ String streamContents: [:s |
		s nextPutAll: n name; nextPutAll: '   at ';
			nextPutAll: (SWATraceNode stringForMicros: n startMicros - self traceZero);
			nextPutAll: '   took ';
			nextPutAll: (SWATraceNode stringForMicros: n durationMicros);
			nextPutAll: '   self ';
			nextPutAll: (SWATraceNode stringForMicros: n selfMicros);
			nextPutAll: '   '; print: n children size; nextPutAll: ' direct calls'.
		self laneOf: n do: [:lane | s nextPutAll: '   in '; nextPutAll: lane name]]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:28'
}
SWATraceMorph >> minSpanPixels [
	"Narrowest box drawn individually. Below this a span cannot carry a border, let
	alone a label, so it joins a merged run instead."
	^ 3
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:27'
}
SWATraceMorph >> minTimeSpanUnits [
	"1 ms. A trace of a single sub-millisecond call still needs a non-zero axis."
	^ 1000
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:27'
}
SWATraceMorph >> minZoomUnits [
	"20 us across the whole width. Below that the clock's own 1 us granularity is
	visible as quantisation and there is genuinely nothing more to resolve."
	^ 20
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> mouseDown: evt [
	"Left on a span: select it. Left on a MERGED run: zoom into its time range, which
	is the only way to see what is inside it. Left on empty space: start a range drag.
	Shift+left: mark. Right: menu."
	| local f |
	self takeKeyboardFocusFrom: evt.
	local := evt position - self position.
	evt yellowButtonPressed ifTrue: [^ self showMenuAt: evt].
	"The scrollbar gutter first: it overlays the right edge of every lane, and a click
	there means scroll, not select."
	(self handleScrollMouseDown: evt) ifTrue: [^ self].
	dragStart := local. dragNow := nil.
	"Inside the continuous bands there are no frames to hit, but there IS a step under
	the cursor -- the one whose interval covers this x. Selecting it makes the bands
	clickable in the obvious way: point at the spike, read what it cost. Dragging still
	works, because dragStart is left set."
	local y < self graphBandsHeight ifTrue: [
		(self stepSpanAtTime: (self timeAtX: local x)) ifNotNil: [:step |
			^ self selectNode: step]].
	f := self frameAt: local.
	f ifNil: [^ self].
	f third = -1 ifTrue: [^ self].
	f first
		ifNil: [
			"merged run: zoom to the pixels it covers"
			dragStart := nil.
			^ self
				zoomToStart: (self timeAtX: f second left)
				end: (self timeAtX: f second right)]
		ifNotNil: [:node |
			evt shiftPressed ifTrue: [
				self toggleMark: node.
				^ self flushCache].
			self selectNode: node]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> mouseMove: evt [
	(self handleScrollMouseMove: evt) ifTrue: [^ self].
	dragStart ifNil: [^ self].
	dragNow := evt position - self position.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> mouseUp: evt [
	"A drag wider than a few pixels is a range zoom; narrower was a click, already
	handled in #mouseDown:."
	| a b |
	(self handleScrollMouseUp: evt) ifTrue: [^ self].
	(dragStart notNil and: [dragNow notNil and: [(dragNow x - dragStart x) abs > 3]])
		ifTrue: [
			a := self timeAtX: dragStart x.
			b := self timeAtX: dragNow x.
			dragStart := dragNow := nil.
			^ self zoomToStart: a end: b].
	dragStart := dragNow := nil.
	self changed
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> printSelectedSubtree [
	| n |
	n := selectedNode ifNil: [^ self].
	(Workspace new contents: n traceString)
		openLabel: 'Trace -- ', n name
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> printTrace [
	"Open the whole trace as indented text in a workspace. Deliberately the WHOLE
	trace and not the visible window: the point of the text form is to have the part
	the picture had to merge away."
	rootNode ifNil: [^ self].
	(Workspace new contents: rootNode traceString)
		openLabel: 'Trace -- ', (self countUnder: rootNode) printString, ' calls'
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATraceMorph >> renderStaticLayerOn: aCanvas at: anOrigin [
	"Background, spans, then the time axis on top. Rendered once into a cached Form
	and blitted (SWATemporalView>>drawOn:); only the drag band is live."
	self ensureLayout.
	aCanvas fillRectangle: (anOrigin extent: self extent) color: (Color gray: 0.12).
	"Lanes are drawn SCROLLED and CLIPPED to their viewport; the bands above and the
	axis below are painted afterwards, unscrolled, so they always sit on top."
	frames ifNotNil: [
		aCanvas
			clipBy: ((anOrigin x @ (anOrigin y + self graphBandsHeight))
				extent: self width @ self scrollViewportHeight)
			during: [:c |
				| off |
				off := anOrigin + (0 @ self laneOffset).
				frames do: [:f | self drawFrame: f on: c at: off]]].
	self drawGraphBandsOn: aCanvas at: anOrigin.
	self drawAxisOn: aCanvas at: anOrigin
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:26'
}
SWATraceMorph >> scrollChanged [
	"The lanes are blitted from a cached Form, so a new scroll position needs a new
	Form. The LAYOUT is untouched -- frames are in content coordinates and the scroll
	offset is applied at draw and hit-test time -- so this is a repaint, not a relayout."
	cachedForm := nil
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:26'
}
SWATraceMorph >> scrollViewportHeight [
	"What is left for the lanes once the bands have the top and the time axis the bottom."
	^ (self height - self graphBandsHeight - self axisHeight) max: 1
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:26'
}
SWATraceMorph >> scrollViewportTop [
	"The lanes scroll; the continuous bands above them do not. They are the reference
	the lanes are read against, so scrolling them away would be like scrolling away the
	axis -- which also stays put, at the bottom."
	^ self top + self graphBandsHeight
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:31'
}
SWATraceMorph >> selectedSourceString [
	"Show-pane content: the source of the method this span is a call of. A span has no
	source of its own -- it is an event -- so this resolves the cross-ref key back to
	the compiled method."
	| n cls sel key |
	n := selectedNode ifNil: [^ ''].
	key := n crossRefKey ifNil: [^ ''].
	(key includesSubstring: '>>') ifFalse: [^ ''].
	cls := Smalltalk classNamed: (key copyUpToLast: $>) allButLast.
	cls ifNil: [^ ''].
	sel := (key copyAfterLast: $>) asSymbol.
	(cls includesSelector: sel) ifFalse: [^ ''].
	^ (cls >> sel) getSource asString
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATraceMorph >> showMenuAt: evt [
	"Right-click: zoom control, colour meaning, and the two PRINT paths -- the
	indented dump for reading here and the Chrome/Perfetto export for reading
	elsewhere. The export is not a nicety: loading the same trace in an independently
	written viewer is how you check that this one is drawing the truth."
	| menu |
	menu := MenuMorph new defaultTarget: self.
	menu add: 'zoom in' selector: #zoomIn argument: nil.
	menu add: 'zoom out' selector: #zoomOut argument: nil.
	menu add: 'pan left' selector: #panLeft argument: nil.
	menu add: 'pan right' selector: #panRight argument: nil.
	menu add: 'reset zoom' selector: #resetZoom argument: nil.
	menu addLine.
	self colorModeOptions do: [:pair |
		menu
			add: (self colorMode == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #colorMode: argument: pair first].
	menu addLine.
	menu add: 'print trace (text)' selector: #printTrace argument: nil.
	menu add: 'export Chrome/Perfetto JSON...' selector: #exportChromeTrace argument: nil.
	selectedNode ifNotNil: [:n |
		menu addLine.
		menu add: 'print this subtree' selector: #printSelectedSubtree argument: nil.
		menu add: 'browse method' selector: #browseSelected argument: nil.
		menu add: 'explore span' selector: #exploreSelected argument: nil].
	menu popUpEvent: evt in: self world
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:55'
}
SWATraceMorph >> spanColorFor: aNode [
	"Colour a span. Two modes matter here and neither is the inherited heat ramp:

	#method -- deterministic per METHOD, so the same call is the same colour
	everywhere in the trace. That is what makes a repeating pattern visible as a
	pattern, and it is why Chrome and Perfetto do it.

	#duration -- heat by how long THIS call took, for finding the one slow
	invocation among a thousand fast ones of the same method, which the #method
	palette deliberately hides.

	Dataset metric modes still route through SWAView's machinery via super."
	| h |
	"GC markers are not code and are not comparable to the spans around them, so they
	keep ONE fixed colour in every mode -- the same coral/seafoam the SWA Memory Stats
	graph uses for full GCs and tenures, so the two tools read the same way."
	aNode markerKind ifNotNil: [:mk |
		^ mk == #gcFull
			ifTrue: [GcGraph coralColor]
			ifFalse: [GcGraph seafoamColor]].
	colorMode == #duration ifTrue: [
		| max |
		max := (rootNode ifNil: [^ Color gray: 0.5]) durationMicros max: 1.
		^ self intensityColorFor: aNode durationMicros max: max].
	colorMode == #method ifFalse: [^ self baseColorForNode: aNode].
	h := (aNode crossRefKey ifNil: [aNode name]) hash.
	^ Color
		h: h \\ 360
		s: 0.42 + ((h // 360 \\ 25) / 100.0)
		v: 0.78 + ((h // 9000 \\ 18) / 100.0)
]

{
	#category : #steps,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:18'
}
SWATraceMorph >> stepSpanAtTime: t [
	"The Morphic cycle whose interval covers t, or nil -- t may land in the pause
	between two cycles, where nothing was running.

	A walk rather than a scan, because the cycle now lives in the process lane at
	whatever depth the traced call graph puts it. Only branches whose interval contains
	t are entered, so it touches a handful of nodes, and it runs once per click."
	rootNode ifNil: [^ nil].
	^ self stepSpanAtTime: t under: rootNode
]

{
	#category : #steps,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:18'
}
SWATraceMorph >> stepSpanAtTime: t under: aNode [
	"Depth-first search for the cycle covering t, pruned to branches that contain t."
	aNode children ifNil: [^ nil].
	aNode children do: [:c |
		(c startMicros <= t and: [c stopMicros >= t]) ifTrue: [
			(self isStepSpan: c) ifTrue: [^ c].
			(self stepSpanAtTime: t under: c) ifNotNil: [:found | ^ found]]].
	^ nil
]

{
	#category : #steps,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:17'
}
SWATraceMorph >> stepSpanKeys [
	"Cross-ref keys of the spans the step-time band measures -- the Morphic cycle.
	Derived from SWACoverage class>>stepProbeMethods rather than written out, so the
	two cannot drift apart."
	^ SWACoverage stepProbeMethods
		collect: [:m | m methodClass name , '>>' , m selector]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> tickStepFor: spanMicros [
	"A round step giving roughly 8 ticks across the view. 1/2/5 x powers of ten, in
	microseconds, so labels come out as 200 us / 5 ms / 1 s rather than 1.37 ms."
	| target pow |
	target := (spanMicros / 8) max: 1.
	pow := 10 raisedTo: (target log: 10) floor.
	target / pow < 2 ifTrue: [^ pow].
	target / pow < 5 ifTrue: [^ 2 * pow].
	^ 5 * pow
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:32'
}
SWATraceMorph >> timeSpan [
	"Full extent of the trace, taken from the ROOT rather than from #events.

	The inherited version reads the first and last event, which works only because
	the other temporal views deal in instants. A span that STARTS first can END last,
	so the last event's start is not the end of the trace -- taking it would clip the
	longest call in the run, which is invariably the one being looked for."
	| lo hi |
	rootNode ifNil: [^ nil].
	rootNode children isEmpty ifTrue: [^ nil].
	lo := rootNode startMicros.
	hi := rootNode stopMicros.
	"Pad only a DEGENERATE span, not a short one. The inherited rule pads up to
	#minTimeSpanUnits, which is right for a timeline of same-second events but wrong
	here: a 330 us trace would be drawn into the left third of a 1 ms axis, throwing
	away two thirds of the resolution for nothing."
	hi <= lo ifTrue: [hi := lo + self minTimeSpanUnits].
	^ {lo. hi}
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:27'
}
SWATraceMorph >> timeUnitsOf: aNode [
	"Microseconds. The whole reason SWATemporalView has a pluggable time base."
	^ aNode eventMicros
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:29'
}
SWATraceMorph >> traceZero [
	"Absolute clock value that counts as t=0 on the axis: the start of the whole
	trace, NOT of the current zoom, so labels keep their meaning as you zoom in."
	^ rootNode ifNil: [0] ifNotNil: [:r | r startMicros]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceMorph >> viewKind [
	^ #trace
]
