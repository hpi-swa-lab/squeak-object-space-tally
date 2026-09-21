"
GcGraph whose FPS bars are scaled so maxFps maps to the full graph height, instead of the stock 1 fps = 1 pixel (which saturates any graph shorter than the frame rate). Only the plotted bar is scaled; the label still prints the true fps. Used by SRGCStats so its short (50px) FPS strip shows a meaningful curve up to maxFps rather than a solid block.
"
Class {
	#name : #SRGCFpsGraph,
	#superclass : #GcGraph,
	#instVars : [
		'emaFps',
		'lastScavengeMs',
		'lastScavengeCount',
		'emaFramesPerScavenge',
		'framesSinceScavenge',
		'intervalFrames',
		'intervalMillis',
		'intervalMaxMillis',
		'intervalBytes',
		'lastAllocBytes',
		'discountBytes',
		'emaKBPerFrame',
		'sampleMillis',
		'sampleFlags',
		'sampleCount',
		'frameScavengeCount',
		'lastMorphicCycle',
		'lastColumnCount',
		'secondMinMillis',
		'secondMaxMillis',
		'secondAccumMillis',
		'lastSecondMin',
		'lastSecondMax'
	],
	#classVars : [
		'FrameDisplayMode'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:53'
}
SRGCFpsGraph class >> ceilingFloorFps [
	"Frame rate at which a bar first fills the lane height.

	15, not 30: at a 30 fps floor a frame that is already dropping sits at full height,
	so every further drop has to rescale the lane -- and the picture you most need to
	read is then the one that will not hold still. At 15 the 16-33 ms range you
	normally live in occupies the lower half, and a drop to 50 or 60 ms is visible
	without the scale moving at all."

	^ 15.
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> cycleFrameDisplayMode [

	| modes next |
	modes := self frameDisplayModes.
	next := (modes indexOf: self frameDisplayMode ifAbsent: [1]) \\ modes size + 1.
	self frameDisplayMode: (modes at: next).
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph class >> emaAlpha [
	"Smoothing factor for the label's exponential moving average of fps.
	~0.1 is about a 10-frame time constant: stable to read, still tracks changes."

	^ 0.1
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> frameDisplayMode [
	"#perFrame draws one column per rendered frame, buffered and blitted in bulk at
	paint time; #max and #mean fold the interval into a single column."

	^ FrameDisplayMode ifNil: [FrameDisplayMode := #max]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> frameDisplayMode: aSymbol [

	FrameDisplayMode := aSymbol.
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> frameDisplayModeLabel [

	^ 'FPS bars: ' , self frameDisplayMode
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> frameDisplayModes [

	^ #(#perFrame #max #mean)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:36'
}
SRGCFpsGraph class >> maxFps [
	"Full graph height corresponds to this frame rate."

	^ 120
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:53'
}
SRGCFpsGraph class >> maxFrameMs [
	"Frame time that fills the lane height, derived from #ceilingFloorFps so the two
	cannot drift apart. It is a FLOOR for the auto ceiling, not a clip -- see
	GcGraph>>ceilingFloor."

	^ (1000 / self ceilingFloorFps) rounded.
]

{
	#category : #colors,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph class >> morphicColor [
	"A frame the Morphic UI process ran in. Morphic hands back only between XR frames,
	so its cost lands wholly inside one frame and shows as a single tall bar."

	^ Color r: 0.85 g: 0.65 b: 0.1
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:47'
}
SRGCFpsGraph class >> sampleCapacity [
	"Frames buffered between paints. At 90 fps and a 10 fps paint rate about nine are
	used; the rest is headroom for a host that stalls."

	^ 128
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph class >> scavengeColor [
	"Coral fills the portion of a frame's bar taken by that frame's scavenge time, so
	the young-space GC hitch is visible inside the frame-time bar."
	^ self coralColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph class >> scavengeTimeColor [
	"Darker coral for the portion of a scavenge-frame bar that was the actual scavenge
	time, drawn over the coral whole-bar."
	^ self coralColor muchDarker
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> barColorForFlags: flags [
	"Scavenge wins over Morphic: its cost is measurable from p10, Morphic's is not."

	(flags bitAnd: 1) = 0 ifFalse: [^ self class scavengeColor].
	(flags bitAnd: 2) = 0 ifFalse: [^ self class morphicColor].
	^ self class deepOceanColor
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:53'
}
SRGCFpsGraph >> ceilingFloor [
	"A 15 fps floor, so a frame that has already dropped to 30 fps is only half height
	and you can watch it drop FURTHER without the scale moving. Above the floor the
	ceiling moves instead of clipping."

	^ self class maxFrameMs.
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:42'
}
SRGCFpsGraph >> discountBytes: anInteger [
	"What the panel's own composite and upload allocated. It falls between two frames
	and would otherwise be charged to one of them -- 156 KB a paint against a 16 KB
	Morphic frame is not a rounding error."

	discountBytes := (discountBytes ifNil: [0]) + anInteger.
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:06'
}
SRGCFpsGraph >> drawBufferedFrames [
	"One column per rendered frame, blitted in bulk at paint time. The lane then scrolls
	at frame rate while the host still paints at its own, slower rate."

	| height |
	height := self graph height.
	1 to: sampleCount do: [:i | | scaled ms |
		ms := sampleMillis at: i.
		scaled := (ms * height / self ceiling) rounded min: height.
		self pushColumn: ms flags: (sampleFlags at: i).
		self graph
			addValue: scaled
			color: (self barColorForFlags: (sampleFlags at: i))
			bgColor: self class backgroundColor].
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:07'
}
SRGCFpsGraph >> drawRingColumnAt: x value: ms flags: flagByte height: h [
	"Repaint one frame's column after a rescale, in its own scavenge/Morphic colour.

	The scavenge sub-portion of an aggregated bar is NOT restored -- only the frame
	time and the flags are kept, and the flags already put the whole bar in the
	scavenge colour. A rescale therefore loses the darker inner band until the next
	scavenge frame, which is a fair price for not keeping a third ring."

	| bar |
	bar := (ms * h / self ceiling) rounded min: h.
	bar <= 0 ifTrue: [^ self].
	graph form
		fill: ((x + 1) @ (h - bar) corner: (x + 2) @ h)
		rule: Form over
		fillColor: (self barColorForFlags: flagByte).
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph >> drawScavengePortion: pixels [
	"Fill the bottom `pixels` of the newest bar (the rightmost 1px column, as drawn by
	FormGraph>>addValue:color:bgColor:) with the darker scavenge colour."

	| form w h |
	form := self graph form.
	w := form width.
	h := form height.
	form
		fill: ((w - 1 @ (h - pixels)) corner: (w @ h))
		rule: Form over
		fillColor: self class scavengeTimeColor
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> fps [
	"The label reads this: the smoothed (EMA) fps, rounded. The graph uses rawFps."

	^ (emaFps ifNil: [self rawFps]) rounded
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/16/2026 12:55'
}
SRGCFpsGraph >> framesPerScavenge [
	"nil until a scavenge has been seen, so the label can leave the field out rather
	than print an infinity."
	^ emaFramesPerScavenge
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> initialize [

	super initialize.
	sampleMillis := Array new: self class sampleCapacity withAll: 0.
	sampleFlags := ByteArray new: self class sampleCapacity.
	sampleCount := 0.
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> intervalFlags [

	| flags |
	flags := 0.
	1 to: sampleCount do: [:i | flags := flags bitOr: (sampleFlags at: i)].
	^ flags
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> intervalFrameMillis [
	"The height of an aggregated bar. #max shows the worst frame of the interval, which
	is what a hitch lane is for; #mean is the honest average and hides it."

	self intervalFrames > 0 ifFalse: [^ deltaTime ifNil: [0]].
	^ self class frameDisplayMode == #mean
		ifTrue: [intervalMillis / intervalFrames]
		ifFalse: [intervalMaxMillis]
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:37'
}
SRGCFpsGraph >> intervalFrames [
	^ intervalFrames ifNil: [0].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:42'
}
SRGCFpsGraph >> kiloBytesPerFrame [
	^ emaKBPerFrame.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:06'
}
SRGCFpsGraph >> labelString [
	"As GcGraph>>labelString, plus the frame time and the two scavenge rates. The ms is
	derived from the same EMA as fps (1000/fps) so the two read consistently and neither
	jitters. The cumulative scavenge count is not repeated here -- the young lane prints it."

	| s ms perSecond perScavenge |
	s := self labelStreamReset.
	s nextPutAll: 'fps '; print: self fps.
	(emaFps notNil and: [emaFps > 0]) ifTrue: [
		ms := 1000 / emaFps.
		s nextPutAll: '  '. self tenthsPrint: ms on: s. s nextPutAll: 'ms'].
	(lastSecondMin notNil and: [lastSecondMax notNil]) ifTrue: [
		s nextPutAll: '  '. self tenthsPrint: lastSecondMin on: s.
		s nextPutAll: '-'. self tenthsPrint: lastSecondMax on: s.
		s nextPutAll: 'ms'].
	"Only when it has moved: on the floor the scale is the one it has always been, and
	a reader who never sees this has learned nothing wrong."
	self ceiling > self ceilingFloor ifTrue: [
		s nextPutAll: '  full '; print: self ceiling; nextPutAll: 'ms'].
	perSecond := self scavengesPerSecond.
	perScavenge := self framesPerScavenge.
	perSecond ifNotNil: [
		s nextPutAll: '  scav '. self tenthsPrint: perSecond on: s. s nextPutAll: '/s'].
	perScavenge ifNotNil: [
		s nextPutAll: ' every '. self tenthsPrint: perScavenge on: s. s nextPutAll: 'f'].
	emaKBPerFrame ifNotNil: [
		s nextPutAll: '  '. self tenthsPrint: emaKBPerFrame on: s. s nextPutAll: 'KB/f'].
	s nextPutAll: '  fullGC '; print: (Smalltalk vmParameterAt: 7).
	^ s contents
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:54'
}
SRGCFpsGraph >> lastColumnCount [
	"Columns drawn by the most recent update. The panel stretches the other lanes to
	match, so every lane keeps one x axis."

	^ lastColumnCount ifNil: [1]
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> morphicCycleTime [
	"WorldState stamps this at the end of every Morphic cycle, so a change between two
	XR frames means Morphic ran in that gap. Reading it costs nothing and needs no hook."

	^ World ifNotNil: [:w | w worldState lastCycleTime]
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:06'
}
SRGCFpsGraph >> noteFrameMillis: ms [
	"Called once per real frame by a host that draws less often than it renders.
	Arithmetic into instance variables only: a host whose frames cost 16 KB cannot
	afford an instrument that allocates. #updateGraph consumes and resets this."

	| bytes |
	intervalFrames := (intervalFrames ifNil: [0]) + 1.
	intervalMillis := (intervalMillis ifNil: [0]) + ms.
	intervalMaxMillis := (intervalMaxMillis ifNil: [0]) max: ms.
	bytes := Smalltalk vmParameterAt: 34.
	lastAllocBytes ifNotNil: [
		intervalBytes := (intervalBytes ifNil: [0]) + (bytes - lastAllocBytes)].
	lastAllocBytes := bytes.
	self noteCeilingValue: ms.
	self noteSecondExtremes: ms.
	self recordSample: ms.
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 19:04'
}
SRGCFpsGraph >> noteSecondExtremes: ms [
	"Best and worst frame of the last second. A mean of 60 fps is reached both by sixty
	16 ms frames and by a mix of 11 ms and 25 ms ones, and only the second judders.
	The window is a second of rendered frames, summed from the deltas rather than read
	off the clock, so this costs nothing per frame."

	secondMinMillis := secondMinMillis ifNil: [ms] ifNotNil: [secondMinMillis min: ms].
	secondMaxMillis := (secondMaxMillis ifNil: [0]) max: ms.
	secondAccumMillis := (secondAccumMillis ifNil: [0]) + ms.
	secondAccumMillis < 1000 ifTrue: [^ self].
	lastSecondMin := secondMinMillis.
	lastSecondMax := secondMaxMillis.
	secondMinMillis := nil.
	secondMaxMillis := nil.
	secondAccumMillis := 0.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:37'
}
SRGCFpsGraph >> rawFps [
	"Mean over the interval when the host measured frames it did not draw, otherwise
	this step's own delta."

	self intervalFrames > 0 ifFalse: [^ super fps].
	intervalMillis <= 0 ifTrue: [^ self class maxFps].
	^ (1000.0 * intervalFrames / intervalMillis) min: self class maxFps
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> recordSample: ms [
	"Two pre-allocated arrays and no sends that allocate: this runs on every rendered
	frame. When the buffer fills, fold into the last slot rather than drop, so a host
	that stops painting degrades to the max instead of losing the hitch."

	| flags scavenges cycle |
	flags := 0.
	scavenges := Smalltalk vmParameterAt: 9.
	(frameScavengeCount notNil and: [scavenges > frameScavengeCount])
		ifTrue: [flags := flags bitOr: 1].
	frameScavengeCount := scavenges.
	cycle := self morphicCycleTime.
	(cycle notNil and: [cycle ~= lastMorphicCycle])
		ifTrue: [flags := flags bitOr: 2].
	lastMorphicCycle := cycle.

	sampleCount < sampleMillis size
		ifTrue: [
			sampleCount := sampleCount + 1.
			sampleMillis at: sampleCount put: ms.
			sampleFlags at: sampleCount put: flags]
		ifFalse: [
			sampleMillis at: sampleCount put: ((sampleMillis at: sampleCount) max: ms).
			sampleFlags at: sampleCount put: ((sampleFlags at: sampleCount) bitOr: flags)].
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> resetInterval [
	intervalFrames := 0.
	intervalMillis := 0.
	intervalMaxMillis := 0.
	intervalBytes := 0.
	self resetSamples.
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:48'
}
SRGCFpsGraph >> resetSamples [

	sampleCount := 0.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/16/2026 12:55'
}
SRGCFpsGraph >> scavengesPerSecond [
	"Frames/second over frames/scavenge, both EMAs, so this agrees with the printed
	fps and with #framesPerScavenge instead of being a third independent measurement."
	(emaFramesPerScavenge notNil and: [emaFramesPerScavenge > 0 and: [emaFps notNil]]) ifFalse: [^ nil].
	^ emaFps / emaFramesPerScavenge
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:42'
}
SRGCFpsGraph >> updateAllocationOver: frames [
	"The discount is the PREVIOUS paint's cost: this runs inside the current paint,
	before that paint has finished allocating."

	| net sample alpha |
	self intervalFrames > 0 ifFalse: [^ self].
	net := ((intervalBytes ifNil: [0]) - (discountBytes ifNil: [0])) max: 0.
	discountBytes := 0.
	sample := net / frames / 1024.0.
	alpha := self class emaAlpha.
	emaKBPerFrame := emaKBPerFrame
		ifNil: [sample]
		ifNotNil: [emaKBPerFrame * (1 - alpha) + (sample * alpha)].
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:06'
}
SRGCFpsGraph >> updateGraph [
	"Bar = this frame's time in ms (scaled so maxFrameMs fills the height). The bottom
	darker portion of the bar is the frame's scavenge time, so you see how much of the
	frame the young-space GC ate. Scavenge *frames* are shown in the FPS bar itself, so
	no background colouring here."

	| fps alpha frameMs scaled scavengeMs scavMs scavScaled height scavenges scavenged scavDelta frames |
	frames := self intervalFrames max: 1.
	framesSinceScavenge := (framesSinceScavenge ifNil: [0]) + frames.
	fps := self rawFps.
	"Fold this frame's instantaneous fps into the label's EMA (the label reads fps)."
	alpha := self class emaAlpha.
	emaFps := emaFps
		ifNil: [fps]
		ifNotNil: [emaFps * (1 - alpha) + (fps * alpha)].

	height := self graph height.
	frameMs := self intervalFrameMillis.
	"Note and rescale BEFORE drawing, so a spike is scaled by a ceiling that already
	contains it. #noteCeilingValue: is sent again here for the benefit of a host that
	paints without calling #noteFrameMillis: -- the value is a max, so noting it twice
	is free."
	self noteCeilingValue: frameMs.
	self updateCeiling ifTrue: [self repaintColumns].
	scaled := (frameMs * height / self ceiling) rounded min: height.

	"p9 = scavenge count, p10 = cumulative scavenge ms. The count reliably marks a
	razor frame; the ms delta sizes the coloured portion (a razor shows at least 1px
	even when its time rounds below a pixel)."
	scavenges := Smalltalk vmParameterAt: 9.
	scavengeMs := Smalltalk vmParameterAt: 10.
	scavenged := lastScavengeCount notNil and: [scavenges > lastScavengeCount].
	scavMs := lastScavengeMs ifNil: [0] ifNotNil: [scavengeMs - lastScavengeMs].

	"Frames per scavenge as an EMA -- the rates the label prints are both derived from
	it, so frames/scavenge and scavenges/s can never disagree. Sampled once per scavenge
	rather than once per frame, which is the cadence #scavengeEmaAlpha is chosen for; a
	per-frame EMA of a signal that is 0 on most frames swings by the whole gap length.
	A frame can carry more than one scavenge, so this is a count delta, not #scavenged."
	scavDelta := lastScavengeCount ifNil: [0] ifNotNil: [scavenges - lastScavengeCount].
	scavDelta > 0 ifTrue: [ | a sample |
		a := self class scavengeEmaAlpha.
		sample := framesSinceScavenge / scavDelta.
		emaFramesPerScavenge := emaFramesPerScavenge
			ifNil: [sample]
			ifNotNil: [emaFramesPerScavenge * (1 - a) + (sample * a)].
		framesSinceScavenge := 0].

	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	lastColumnCount := self class frameDisplayMode == #perFrame
		ifTrue: [sampleCount max: 1]
		ifFalse: [1].
	self class frameDisplayMode == #perFrame
		ifTrue: [self drawBufferedFrames]
		ifFalse: [ | flags |
			flags := (scavenged ifTrue: [1] ifFalse: [0]) bitOr: self intervalFlags.
			self pushColumn: frameMs flags: flags.
			self graph
				addValue: scaled
				color: (self barColorForFlags: flags)
				bgColor: self class backgroundColor.

			"Overlay the actual scavenge-time portion at the bottom in a darker coral (at
			least 1px, since a single scavenge is often sub-ms)."
			scavenged ifTrue: [
				scavScaled := ((scavMs * height / self ceiling) rounded min: scaled) max: 1.
				self drawScavengePortion: scavScaled]].
	self updateAllocationOver: frames.
	self resetInterval
]
