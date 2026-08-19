"
A start/stop GC-statistics recorder for offline analysis, the recorded counterpart to the live GcGraphMorph / GcStatsPanel strips.

Why it exists: the live panels are immediate-mode -- they draw each frame and keep no history, so you cannot pause, zoom or select. This records a run into memory and hands it to SWATraceMorph (via a SWATraceNode root) where the existing zoom/pan/select/scrub machinery already lives, and where a GC recording can later be laid against a real call trace.

No allocation during recording. Every signal is one preallocated Array of SmallIntegers (structure-of-arrays), sized once at #armWithCapacity:. #sampleNow does one integer store per signal into slot `count`, nothing more -- so the act of measuring does not perturb the young space it is measuring. When the buffers fill the recorder stops and sets `truncated`; it does not grow mid-run.

Per sample (all integers, VM units): tMicros, oldSpace (p1, committed old bytes), usedYoung (p2), freeOld (p54, 0 if unavailable), scavCount (p9), fullCount (p7), tenures (p11), survivors (p35), rootTable (p21), stepMicros (duration of the step that took the reading).

`source` names what drives sampling (#morphic on the desktop, #xr from the render loop) and is carried through for provenance only; the recorder itself is source-agnostic -- callers send #sampleNow.

On #stop the arrays are frozen into the same 5-tuple `series` shape SWATraceSeries produces, so SWATraceMorph's memory and step-time bands draw unchanged, plus a synthetic GC lane of scavenge / full-GC marks.
"
Class {
	#name : #SRGCRecorder,
	#superclass : #Object,
	#instVars : [
		'capacity',
		'count',
		'startMicros',
		'lastStepMicros',
		'tMicros',
		'oldSpace',
		'usedYoung',
		'freeOld',
		'scavCount',
		'fullCount',
		'tenures',
		'survivors',
		'rootTable',
		'stepMicros',
		'source',
		'truncated'
	],
	#classVars : [
		'Current'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorder class >> current [
	"The most recent recorder, or nil. One at a time is the model: start, stop, open."
	^ Current
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorder class >> defaultCapacity [
	"Samples to preallocate. At ~60/s a desktop run this holds ~5.5 minutes; the ten
	Arrays cost ~10 * 216000 * 8 bytes ~= 17 MB, allocated once, in old space after the
	first full GC -- deliberately generous so a recording is not silently cut short."
	^ 216000
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:44'
}
SRGCRecorder class >> initialize [
	"Register the Apps-menu entries for the start/stop GC recorder -- the recorded
	counterpart to the live 'SWA GC Stats' panel. Idempotent."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA GC Record start'.
		{self. #startMorphic}.
		'Start recording GC / memory / frame stats into memory for later analysis' }.
	TheWorldMenu registerOpenCommand: {
		'SWA GC Record stop + open'.
		{self. #stopAndOpen}.
		'Stop the GC recording and open it in a zoomable SWA trace pane' }
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder class >> startMorphic [
	"Begin a desktop recording driven once per Morphic cycle. Answers the recorder.
	A prior run is dropped. (#armWithCapacity: full-GCs its buffers into old space
	before the clock starts, so their allocation does not show up in the samples.)"
	Current := self new source: #morphic; yourself.
	Current armWithCapacity: self defaultCapacity.
	(Smalltalk at: #World ifAbsent: [nil]) ifNotNil: [:w |
		w addMorph: (SRGCRecorderStepper new recorder: Current)].
	^ Current
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder class >> startXr [
	"Begin a recording to be driven from the XR render loop: the world calls
	`SRGCRecorder current sampleNow` once per frame (see SRWorld>>sampleGCRecorder).
	No Morphic stepper is added here. Answers the recorder."
	Current := self new source: #xr; yourself.
	Current armWithCapacity: self defaultCapacity.
	^ Current
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder class >> stop [
	"Stop the current recording (the Morphic stepper removes itself next cycle when it
	sees isRecording answer false). Answers the recorder for chaining, or nil."
	^ Current ifNotNil: [:r | r stop. r]
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder class >> stopAndOpen [
	"Stop and open the recording in a SWA pane. Answers the window, or nil."
	self stop ifNotNil: [:r | ^ r openInPane].
	^ nil
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:44'
}
SRGCRecorder class >> xrMenuRecordStart: aMenu [
	<xrMenu: #(world apps) label: 'GC Record start (XR)' priority: 301>
	"Record from the XR render loop -- one sample per presented frame."
	^ self startXr
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:44'
}
SRGCRecorder class >> xrMenuRecordStop: aMenu [
	<xrMenu: #(world apps) label: 'GC Record stop + open' priority: 302>
	^ self stopAndOpen
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder >> armWithCapacity: n [
	"Preallocate one Array per signal, sized for n samples, and start recording. All
	subsequent #sampleNow calls store into these buffers without allocating -- that is
	the whole point: the measurement must not add to the young space it is measuring."
	capacity := n.
	count := 0.
	truncated := false.
	tMicros := Array new: n.
	oldSpace := Array new: n.
	usedYoung := Array new: n.
	freeOld := Array new: n.
	scavCount := Array new: n.
	fullCount := Array new: n.
	tenures := Array new: n.
	survivors := Array new: n.
	rootTable := Array new: n.
	stepMicros := Array new: n.
	"Tenure the buffers into old space before the clock starts, so the ~17 MB
	allocated just above does not read as a scavenge storm in the recorder's own
	first samples. #garbageCollect (a full GC) is what promotes them."
	Smalltalk garbageCollect.
	startMicros := Time utcMicrosecondClock.
	lastStepMicros := startMicros.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> count [
	^ count ifNil: [0]
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:43'
}
SRGCRecorder >> gcLane [
	"A synthetic 'GC' lane whose children are scavenge / full-GC marks, one per sample
	interval in which the VM's counter ticked. Same #gcScavenge / #gcFull kinds the real
	trace uses, so SWATraceMorph colours them identically and a GC recording lines up
	against a later call trace with no translation. Answers nil if nothing collected."
	| lane prevScav prevFull any |
	self count < 2 ifTrue: [^ nil].
	lane := SWATraceNode new
		name: 'GC';
		process: 'GC';
		start: startMicros stop: startMicros + (tMicros at: self count);
		yourself.
	prevScav := scavCount at: 1.
	prevFull := fullCount at: 1.
	any := false.
	2 to: self count do: [:i |
		| t0 t1 dScav dFull |
		t0 := startMicros + (tMicros at: i - 1).
		t1 := startMicros + (tMicros at: i).
		dFull := (fullCount at: i) - prevFull.
		dScav := (scavCount at: i) - prevScav.
		dFull > 0 ifTrue: [
			any := true.
			lane addChildNode: (self
				markerNamed: 'GC full', (dFull = 1 ifTrue: [''] ifFalse: [' x', dFull printString])
				kind: #gcFull start: t0 stop: t1)].
		dScav > 0 ifTrue: [
			any := true.
			lane addChildNode: (self
				markerNamed: 'GC scavenge', (dScav = 1 ifTrue: [''] ifFalse: [' x', dScav printString])
				kind: #gcScavenge start: t0 stop: t1)].
		prevScav := scavCount at: i.
		prevFull := fullCount at: i].
	^ any ifTrue: [lane] ifFalse: [nil]
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:42'
}
SRGCRecorder >> infoString [
	"Header line for the pane: run length, sample count and rate, and the source that
	drove it. The truncated flag matters -- a run that hit the buffer cap stopped early
	and the tail is missing, not idle."
	| durMs |
	durMs := self count < 1 ifTrue: [0] ifFalse: [(tMicros at: self count) / 1000.0].
	^ String streamContents: [:s |
		s print: (durMs roundTo: 1); nextPutAll: ' ms   '.
		s print: self count; nextPutAll: ' samples'.
		durMs > 0 ifTrue: [
			s nextPutAll: '   '; print: ((self count * 1000.0 / durMs) roundTo: 1); nextPutAll: '/s'].
		s nextPutAll: '   source: '; nextPutAll: (source ifNil: [#unknown]) asString.
		self truncated ifTrue: [s nextPutAll: '   (TRUNCATED -- buffer full)']]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> isRecording [
	^ tMicros notNil and: [lastStepMicros notNil]
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:40'
}
SRGCRecorder >> markerNamed: aString kind: aSymbol start: t0 stop: t1 [
	"One marker span. A one-microsecond floor so a sub-millisecond collection still has
	a clickable width, exactly as SWATraceMarker does it."
	^ SWATraceNode new
		name: aString;
		markerKind: aSymbol;
		start: (t1 - t0 < 1 ifTrue: [t1 - 1] ifFalse: [t0]) stop: t1;
		yourself
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorder >> openInPane [
	"Open this recording in the shared SWAPane chrome on a SWATraceMorph, where the
	zoom / pan / select / scrub already live. Answers the window, or nil if the run was
	too short to draw."
	| root chart panel |
	root := self traceRoot ifNil: [^ self inform: 'GC recording: too few samples'].
	chart := SWATraceMorph on: root.
	chart metaInfo: self infoString.
	panel := SWAPane on: chart.
	^ panel
		openInWindowLabeled: 'SWA GC Recording'
		bounds: (((Display extent - (1200 @ 800)) // 2) extent: 1200 @ 800)
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> sampleNow [
	"Take one reading into the preallocated slot `count`+1. Hot path: ten vmParameterAt:
	reads and ten integer stores, no allocation. The step duration is derived from the
	wall clock between successive samples, so a caller that samples once per frame gets
	per-frame step times for free without passing a delta.

	Silently stops recording (marks truncated) when the buffers are full rather than
	growing, because a grow here would allocate in young space mid-measurement -- the
	one thing this class exists to avoid."
	| now i |
	tMicros ifNil: [^ self].
	count >= capacity ifTrue: [truncated := true. ^ self].
	now := Time utcMicrosecondClock.
	i := count + 1.
	tMicros at: i put: now - startMicros.
	oldSpace at: i put: (Smalltalk vmParameterAt: 1).
	usedYoung at: i put: (Smalltalk vmParameterAt: 2).
	freeOld at: i put: ((Smalltalk vmParameterAt: 54) ifNil: [0]).
	scavCount at: i put: (Smalltalk vmParameterAt: 9).
	fullCount at: i put: (Smalltalk vmParameterAt: 7).
	tenures at: i put: (Smalltalk vmParameterAt: 11).
	survivors at: i put: (Smalltalk vmParameterAt: 35).
	rootTable at: i put: (Smalltalk vmParameterAt: 21).
	stepMicros at: i put: now - lastStepMicros.
	lastStepMicros := now.
	count := i.
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:40'
}
SRGCRecorder >> series [
	"The recording as SWATraceSeries-shaped tuples, oldest first:
	#(absoluteMicros oldSpace usedYoung freeOld stepMicros). Absolute micros so the
	series shares the trace root's wall clock and SWATraceMorph's memory / step-time
	bands read it with no change. Built once, on #stop -- not on the hot path."
	| out |
	out := Array new: self count.
	1 to: self count do: [:i |
		out at: i put: (Array
			with: startMicros + (tMicros at: i)
			with: (oldSpace at: i)
			with: (usedYoung at: i)
			with: (freeOld at: i)
			with: (stepMicros at: i))].
	^ out
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> source [
	^ source
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> source: aSymbol [
	source := aSymbol
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> stop [
	"Freeze the buffers. Nothing more is stored; #series and #traceRoot read the first
	`count` slots. The Arrays are kept (not copied down) -- the accessors already honour
	`count`, and a trailing tail of unused slots is cheaper than a copy of a long run."
	lastStepMicros := nil.
]

{
	#category : #materializing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:40'
}
SRGCRecorder >> traceRoot [
	"The recording as a SWATraceNode root ready for SWATraceMorph: the memory / step
	series on the root (drives the two graph bands) plus a synthetic GC lane of marks.
	No call lanes -- this is a GC-only recording -- but the shape is identical to a call
	trace's root, so the same view draws it and a later call trace can be merged in.
	Answers nil if fewer than two samples were taken."
	| root lane |
	self count < 2 ifTrue: [^ nil].
	root := SWATraceNode new
		name: 'GC recording';
		start: startMicros stop: startMicros + (tMicros at: self count);
		yourself.
	(lane := self gcLane) ifNotNil: [root addChildNode: lane].
	root series: self series.
	^ root
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:39'
}
SRGCRecorder >> truncated [
	^ truncated == true
]
