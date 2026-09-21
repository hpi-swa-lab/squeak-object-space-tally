"
GcGraph generates and updates a Form with timing and gc information.
It displays it directly.

to install it: insert ""GcGraph update."" into WorldState>>interCyclePause: milliSecs

then start it with: GcGraph enable
"
Class {
	#name : #GcGraph,
	#superclass : #Object,
	#instVars : [
		'lastTime',
		'lastGcCount',
		'lastTenurCount',
		'graph',
		'deltaTime',
		'labelStream',
		'ceiling',
		'ceilingWindowMax',
		'ceilingHoldCount',
		'valueRing',
		'flagRing',
		'ringHead',
		'ringCount'
	],
	#classVars : [
		'CoralColor',
		'DeepOceanColor',
		'Default',
		'PaleOceanColor',
		'SeafoamColor',
		'ShallowOceanColor',
		'SlateColor',
		'SurvivorColor',
		'ZoomMarkColor'
	],
	#classInstVars : [
		'seafoam',
		'coral',
		'deepOcean',
		'slate',
		'zoomMark',
		'paleOcean',
		'shallowOcean',
		'survivor'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph class >> backgroundColor [
	"Background of the graph forms, and of the morph wherever the forms have
	not been painted yet."
	^ Color white
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:14'
}
GcGraph class >> coralColor [
	"Marker for a full GC. The one warm colour in the palette, muted so it
	stands out without shouting."
	^ coral ifNil: [coral := Color r: 0.87 g: 0.55 b: 0.47]
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:14'
}
GcGraph class >> deepOceanColor [
	"Live old space, and the frame time bars: the deep water at the bottom."
	^ deepOcean ifNil: [deepOcean := Color r: 0.16 g: 0.36 b: 0.47]
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 17:38'
}
GcGraph class >> default [
	^Default
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:17'
}
GcGraph class >> disable [
	Default := nil
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:17'
}
GcGraph class >> enable [
	Default := self new.
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:10'
}
GcGraph class >> fpsCeilingCap [
	"Highest fps reading allowed to raise the lane's ceiling.

	#maxFps clamps a reading at 1000, which its own comment calls implausible -- it
	exists to stop a near-zero paint delta spiking the graph. Such a reading must not
	be allowed to set the SCALE either, or one bad delta flattens the lane for as long
	as #ceilingHoldPaints. Above any real display rate, below the clamp."

	^ 240.
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:09'
}
GcGraph class >> fpsCeilingFloor [
	"Frame rate that fills the plain fps lane's height. 100 keeps a 72 Hz headset near
	the top and 60 Hz at three fifths, which is the range worth resolving."

	^ 100.
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 12:00'
}
GcGraph class >> maxFps [
	"Ceiling for a reported fps reading. A frame interval below ~1ms (stepping as fast
	as possible, or timer jitter) would otherwise report an implausible fps and spike
	the graph and the EMA. 1000 fps is well above any real render rate."
	^ 1000
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 11/9/2005 22:44'
}
GcGraph class >> new [
	^super new
		initialize
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:15'
}
GcGraph class >> paleOceanColor [
	"The pale tint used for the window frame."
	^ paleOcean ifNil: [paleOcean := Color r: 0.855 g: 0.925 b: 0.945]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:13'
}
GcGraph class >> scavengeEmaAlpha [
	"Smoothing factor for the exponential moving averages sampled once per scavenge.
	One scavenge is seconds apart on an idle image, so a 10-scavenge time constant was
	most of a minute before the number settled. ~0.3 is about 3 scavenges."
	^ 0.3
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:14'
}
GcGraph class >> seafoamColor [
	"Used young space, and the marker for a tenure."
	^ seafoam ifNil: [seafoam := Color r: 0.35 g: 0.72 b: 0.66]
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:15'
}
GcGraph class >> shallowOceanColor [
	"Free old space: shallow water above the live objects."
	^ shallowOcean ifNil: [shallowOcean := Color r: 0.62 g: 0.80 b: 0.855]
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:15'
}
GcGraph class >> slateColor [
	"Labels, and the marker column for a change of scale."
	^ slate ifNil: [slate := Color r: 0.24 g: 0.32 b: 0.38]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:15'
}
GcGraph class >> survivorColor [
	"Deeper seafoam for the survivor baseline -- the young-space bytes still live right
	after the last scavenge, i.e. the floor the sawtooth drops to."
	^ survivor ifNil: [survivor := self seafoamColor muchDarker]
]

{
	#category : #'default instance',
	#'squeak_changestamp' : 'jl 10/25/2005 19:22'
}
GcGraph class >> update [
	self default ifNotNil: [ self default update].
]

{
	#category : #palette,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:57'
}
GcGraph class >> windowColor [
	"Border and title bar of the window. Only the frame is tinted; the graphs
	themselves keep a white background."
	^ self paleOceanColor
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:15'
}
GcGraph class >> zoomMarkColor [
	"The red marker drawn in the zoomed-in old lane's newest column when its floor rebases
	(a lane movement), so the shift is visible as a vertical line."
	^ zoomMark ifNil: [zoomMark := Color r: 0.9 g: 0.15 b: 0.15]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:09'
}
GcGraph >> backgroundColorForFlags: flagByte [
	"Full GC wins over tenure: it is the rarer and more expensive event."

	(flagByte bitAnd: 1) ~= 0 ifTrue: [^ self class coralColor].
	(flagByte bitAnd: 2) ~= 0 ifTrue: [^ self class seafoamColor].
	^ self class backgroundColor.
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> ceiling [
	"The value that currently fills the lane height."

	^ ceiling ifNil: [ceiling := self ceilingFloor].
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:09'
}
GcGraph >> ceilingFloor [
	"The lowest value that may fill the lane height, or nil for a lane that does not
	use the auto ceiling at all.

	It is a FLOOR and not a fixed scale: a quiet lane keeps the scale a reader has
	learned, so a good frame stays a short bar, while a lane that exceeds it rescales
	rather than clipping.

	The value here serves GcGraph's OWN lane, which plots fps. The memory and stacked
	branches scale against something real -- eden, committed memory, the strip total --
	never call #ceiling, and so never see this."

	^ self class fpsCeilingFloor.
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> ceilingHoldPaints [
	"How many paints a lower peak must persist for before the ceiling comes back down.
	The panel paints ~10 times a second, so this is a couple of seconds."

	^ 20.
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> committedSpace [
	"All memory the object memory currently occupies, in kilobytes:
	live old space + free old space + used young space."
	^self oldSpace + self usedYoungSpace
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:09'
}
GcGraph >> drawRingColumnAt: x value: fps flags: flagByte height: h [
	"Repaint one column of the fps lane at the current ceiling, background mark
	included. Subclasses that use the ring override this for their own colouring."

	| bar |
	graph form
		fill: (x @ 0 corner: (x + 2) @ h)
		rule: Form over
		fillColor: (self backgroundColorForFlags: flagByte).
	bar := (fps * h / self ceiling) rounded min: h.
	bar <= 0 ifTrue: [^ self].
	graph form
		fill: ((x + 1) @ (h - bar) corner: (x + 2) @ h)
		rule: Form over
		fillColor: self class deepOceanColor.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 7/14/2006 10:37'
}
GcGraph >> extent: aPoint [
	graph width: aPoint x height: aPoint y
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 7/14/2006 10:28'
}
GcGraph >> form [
	^graph form
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 12:00'
}
GcGraph >> fps [
	"Frames per second from the last frame interval (deltaTime is Float milliseconds).
	Guard a zero/near-zero delta, and clamp to a sane ceiling so a single sub-microsecond
	interval cannot spike the graph/EMA."
	^(deltaTime isNil or: [deltaTime <= 0.05])
		ifTrue: [self class maxFps]
		ifFalse: [(1000.0 / deltaTime) min: self class maxFps]
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> freeSpace [
	"Free space inside the committed old space, in kilobytes.
	Spur only; answer 0 on VMs that do not report it."
	^((Smalltalk vmParameterAt: 54) ifNil: [0]) // 1024
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'jl 10/28/2005 16:03'
}
GcGraph >> graph [
	^graph ifNil: [graph := FormGraph new]
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'jl 11/9/2005 22:45'
}
GcGraph >> initialize [
	graph := FormGraph new.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 13:14'
}
GcGraph >> labelStreamReset [
	"A WriteStream retained for the lifetime of the graph, rewound each frame, so building the
	label allocates neither a WriteStream nor a closure/context (as String streamContents: did).
	The label text itself (#contents) is the one unavoidable allocation -- it is drawn."
	labelStream
		ifNil: [labelStream := WriteStream on: (String new: 128)]
		ifNotNil: [labelStream resetToStart].
	^ labelStream
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:10'
}
GcGraph >> labelString [
	| s |
	s := self labelStreamReset.
	s nextPutAll: 'fps '; print: self fps rounded.
	self ceiling > self ceilingFloor ifTrue: [
		s nextPutAll: '\'; print: self ceiling].
	s nextPutAll: '  fullGC '; print: (Smalltalk vmParameterAt: 7);
	  nextPutAll: '  scavenge '; print: (Smalltalk vmParameterAt: 9);
	  nextPutAll: '  rootTable '; print: self rootTableSize.
	^ s contents
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:59'
}
GcGraph >> lastTime [
	"Microsecond timestamp of the last frame (see updateTimeWith:)."
	^lastTime ifNil: [ lastTime := Time utcMicrosecondClock - 1000]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:33'
}
GcGraph >> mbPrint: kb on: aStream [
	"Streaming form of #mbString: -- write the compact kB/MB amount straight onto aStream,
	no intermediate String (the old #mbString: allocated two with #, )."
	kb < 1024
		ifTrue: [aStream print: kb; nextPut: $k]
		ifFalse: [ | tenths |
			"One decimal via integer math -- printShowingDecimalPlaces: allocates a
			WriteStream/String/Fractions each call; this streams SmallIntegers only."
			tenths := kb * 10 // 1024.
			aStream print: tenths // 10; nextPut: $.; print: tenths \\ 10; nextPut: $M]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:42'
}
GcGraph >> mbString: kb [
	"Print a kilobyte amount compactly."
	kb < 1024 ifTrue: [^kb printString, 'k'].
	^(kb / 1024.0 printShowingDecimalPlaces: 1), 'M'
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:31'
}
GcGraph >> midLabelFraction [
	"Where the mid-label sits, as a fraction of the form height from the TOP. Only used
	when #midLabelString is non-nil."
	^ 0.5
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:31'
}
GcGraph >> midLabelString [
	"An optional second label drawn INSIDE the graph area (see #midLabelFraction), for
	graphs that pack more than one lane and want a divider caption between them. nil = none."
	^ nil
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:33'
}
GcGraph >> msPrint: aFloat on: aStream [
	"Two-decimal millisecond value streamed via integer math (no printShowingDecimalPlaces:,
	which allocates a WriteStream/String/Fractions per call). Pads the fractional part to 2."
	| hundredths frac |
	hundredths := (aFloat * 100) rounded.
	frac := hundredths \\ 100.
	aStream print: hundredths // 100; nextPut: $..
	frac < 10 ifTrue: [aStream nextPut: $0].
	aStream print: frac
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:05'
}
GcGraph >> niceCeilingFor: aValue [
	"Round aValue up to the next 1-2-5 x 10^n value, never below #ceilingFloor.

	Absolute 1-2-5 steps rather than multiples of the floor, so a frame-time lane reads
	33, 50, 100, 200, 500 ms and not 66, 165, 330 -- the ceiling is a number the reader
	has to hold in their head to interpret bar heights.

	Stepping in recognisable multiples is the whole point. A ceiling that tracked the
	peak exactly would rescale on nearly every paint, and a lane whose scale moves
	continuously cannot be read at all -- you can no longer tell a taller bar from a
	smaller scale."

	| floor magnitude |
	floor := self ceilingFloor ifNil: [^ aValue].
	aValue <= floor ifTrue: [^ floor].
	magnitude := 10 raisedTo: (aValue log: 10) floor.
	#(1 2 5 10) do: [:mantissa |
		mantissa * magnitude >= aValue ifTrue: [^ (mantissa * magnitude) max: floor]].
	^ (10 * magnitude) max: floor.
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:58'
}
GcGraph >> niceScaleFor: kbPerPixel [
	"Round kbPerPixel up to the next 1-2-5 x 10^n value, so that the scale
	changes in recognizable steps instead of on every allocation."
	| magnitude |
	kbPerPixel <= 1 ifTrue: [^1].
	magnitude := 10 raisedTo: (kbPerPixel log: 10) floor.
	#(1 2 5 10) do: [:mantissa |
		mantissa * magnitude >= kbPerPixel ifTrue: [^mantissa * magnitude]].
	^10 * magnitude
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> noteCeilingValue: aValue [
	"Fold one reading into the window the ceiling is chosen from. Called once per
	sample, which for a per-frame lane is once per frame, so this must stay arithmetic
	into an instance variable."

	ceilingWindowMax := (ceilingWindowMax ifNil: [0]) max: aValue.
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> oldSpace [
	"Total committed old space, in kilobytes. Includes the free old space."
	^(Smalltalk vmParameterAt: 1) // 1024
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> pushColumn: aValue flags: flagByte [
	"Remember one drawn column's VALUE, so a rescale can redraw it. Same circular
	buffer as SRGCMemGraph>>pushUsed:, for the same reason: a fixed Array sized to the
	number of 2px columns the lane shows, written through a cursor, so steady state is
	two slot stores and no allocation. The instrument must not itself allocate young
	garbage on a path that measures young garbage.

	Without this the lane keeps PIXELS and not values, and a rescale leaves the old
	columns drawn at the old scale -- two scales in one picture, which is worse than
	the clipping it fixes."

	| cap |
	cap := (graph width // 2) max: 1.
	(ringHead isNil or: [(valueRing isKindOf: Array) not] or: [valueRing size ~= cap])
		ifTrue: [
			valueRing := Array new: cap withAll: 0.
			flagRing := ByteArray new: cap.
			ringHead := 1.
			ringCount := 0].
	valueRing at: ringHead put: aValue.
	flagRing at: ringHead put: (flagByte bitAnd: 255).
	ringHead := ringHead \\ cap + 1.
	ringCount < cap ifTrue: [ringCount := ringCount + 1].
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:16'
}
GcGraph >> release [
	super release.
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> repaintColumns [
	"Redraw every remembered column at the current ceiling, oldest left, newest right.

	Runs only on a rescale, which #updateCeiling makes rare. FormGraph maps value v to
	form row (height - v), hence the arithmetic; the columns are drawn straight into
	the retained Form rather than through #addValue:, which only ever touches the
	rightmost column."

	| h w x idx cap |
	h := graph height.
	w := graph width.
	graph form
		fill: (0 @ 0 corner: w @ h)
		rule: Form over
		fillColor: self class backgroundColor.
	(valueRing isNil or: [ringCount isNil or: [ringCount = 0]]) ifTrue: [^ self].
	cap := valueRing size.
	x := 2.
	idx := (ringHead - 2) \\ cap + 1.
	ringCount timesRepeat: [
		self
			drawRingColumnAt: w - x
			value: (valueRing at: idx)
			flags: (flagRing at: idx)
			height: h.
		x := x + 2.
		x > w ifTrue: [^ self].
		idx := (idx - 2) \\ cap + 1].
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'jl 11/8/2005 23:40'
}
GcGraph >> rootTableSize [
	^Smalltalk vmParameterAt: 21
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
GcGraph >> stepUpdate [
	"Advance the strip by one column. Factored out so a morph holding several
	different strips can drive them all uniformly. The fps strip needs the clock
	sampled first; strips that plot absolute amounts do not."
	self updateTime.
	self updateGraph
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 18:53'
}
GcGraph >> stretchToColumns: aCount [
	"This strip drew one column for an interval in which the fps strip drew aCount.
	Repeat it so every lane shares one x axis."

	(aCount - 1) timesRepeat: [self graph repeatLastColumn].
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 13:12'
}
GcGraph >> tenthsPrint: aNumber on: aStream [
	"One decimal via integer math -- printShowingDecimalPlaces: allocates a
	WriteStream/String/Fractions per call; this streams SmallIntegers only."
	| tenths |
	tenths := (aNumber * 10) rounded.
	aStream print: tenths // 10; nextPut: $.; print: tenths \\ 10.
]

{
	#category : #update,
	#'squeak_changestamp' : 'jl 7/14/2006 10:56'
}
GcGraph >> update [
	
	self updateTime.
	self updateGraph.
	graph form display.
	self updateText.

]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:04'
}
GcGraph >> updateCeiling [
	"Choose the ceiling for the columns about to be drawn. Answers whether it changed.

	ASYMMETRIC ON PURPOSE. It rises IMMEDIATELY, before this paint draws, so a spike
	is scaled by a ceiling that already contains it and is never the flat-topped bar
	that made this whole lane unreadable. It falls only after #ceilingHoldPaints of
	lower peaks, so one hitch does not permanently flatten the lane and a run of
	hitches does not make the scale oscillate.

	Send once per paint, before drawing."

	| want |
	self ceilingFloor ifNil: [^ false].
	ceilingWindowMax ifNil: [^ false].
	ceilingWindowMax > self ceiling ifTrue: [
		ceiling := self niceCeilingFor: ceilingWindowMax.
		ceilingWindowMax := 0.
		ceilingHoldCount := 0.
		^ true].
	ceilingHoldCount := (ceilingHoldCount ifNil: [0]) + 1.
	ceilingHoldCount < self ceilingHoldPaints ifTrue: [^ false].
	want := self niceCeilingFor: ceilingWindowMax.
	ceilingWindowMax := 0.
	ceilingHoldCount := 0.
	want = self ceiling ifTrue: [^ false].
	ceiling := want.
	^ true.
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:10'
}
GcGraph >> updateGraph [
	"One column of frame rate, with the column's background marking a full GC (coral)
	or a tenure (seafoam) since the last paint.

	SCALED, not plotted raw. This used to pass fps straight to #addValue:, which reads
	its argument as PIXELS -- so on a 30 px lane every rate above 30 fps was clipped to
	full height and the lane showed a solid block across the whole range anyone cares
	about."

	| gcCount fps tenurCount height scaled flags |
	gcCount := Smalltalk vmParameterAt: 7.
	tenurCount := Smalltalk vmParameterAt: 11.
	fps := self fps.
	flags := 0.
	lastGcCount = gcCount
		ifTrue: [
			lastTenurCount = tenurCount
				ifFalse: [flags := 2. lastTenurCount := tenurCount]]
		ifFalse: [
			flags := 1.
			lastTenurCount := tenurCount.
			lastGcCount := gcCount].

	height := self graph height.
	self noteCeilingValue: (fps min: self class fpsCeilingCap).
	self updateCeiling ifTrue: [self repaintColumns].
	scaled := (fps * height / self ceiling) rounded min: height.
	self pushColumn: fps flags: flags.
	self graph
		addValue: scaled
		color: self class deepOceanColor
		bgColor: (self backgroundColorForFlags: flags).
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:43'
}
GcGraph >> updateText [
	(self labelString, '        ') displayAt: graph position + (0 @ graph height)
			

]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:58'
}
GcGraph >> updateTime [
	"Measure the frame delta from the wall clock -- correct when the owner steps this
	graph once per real frame (e.g. the desktop morph stepping every Morphic cycle)."
	self updateTimeWith: nil
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:59'
}
GcGraph >> updateTimeWith: aDeltaMsOrNil [
	"Set this frame's delta. If the caller has an authoritative frame delta (the XR
	render loop passes SRFrame's deltaTime), use it; otherwise measure the wall-clock
	interval since the last step (the desktop morph, stepped once per Morphic cycle)."
	| nowMicros |
	nowMicros := Time utcMicrosecondClock.
	"deltaTime is milliseconds (Float). Measure at microsecond resolution so frames
	faster than 1ms (stepping as fast as possible) are timed accurately instead of
	rounding to 0/1ms and producing bogus 1000 fps spikes."
	deltaTime := aDeltaMsOrNil
		ifNil: [(nowMicros - self lastTime) / 1000.0]
		ifNotNil: [aDeltaMsOrNil].
	lastTime := nowMicros
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> usedOldSpace [
	"Live (allocated) old space, in kilobytes."
	^self oldSpace - self freeSpace
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> usedYoungSpace [
	"Bytes in use in young space (eden + survivor spaces), in kilobytes.
	On Spur vmParameterAt: 2 is a size, not the end address it was on V3."
	^(Smalltalk vmParameterAt: 2) // 1024
]

{
	#category : #'vm statistics',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:41'
}
GcGraph >> youngSpace [
	"Capacity of eden, in kilobytes. Falls back to the used amount if the VM
	does not report the eden size (parameter 44 is Cog-only)."
	^((Smalltalk vmParameterAt: 44) ifNil: [Smalltalk vmParameterAt: 2]) // 1024
]
