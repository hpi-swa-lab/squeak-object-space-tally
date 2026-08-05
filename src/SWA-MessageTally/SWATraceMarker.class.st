"
A stand-in for a method wrapper in a trace lane, for events that no method produced.

A trace lane is a flat log of {producer. start. stop. depth}, and SWATraceNode class>>fromLane: only ever asks the producer for its #crossRefKey. So anything that answers a key can put a span in a trace -- it does not have to be a SWATraceWrapper, and it does not have to correspond to a call. That is the whole trick here.

WHAT USES IT: garbage collection. The VM gives no GC callback, only cumulative counters (Smalltalk vmParameterAt: 7/8/9/10 -- full GC count and total ms, scavenge count and total ms; the same ones the SWA Memory Stats graph polls). So GCs cannot be observed as they happen; they can only be DETECTED AFTER THE FACT by watching those counters move.

The counters are therefore drained at STEP BOUNDARIES (see SWAStepTraceWrapper), and the resulting spans are pinned to the END of the step that has just finished, stacked backwards from its stop time. That placement is honest about what is known and what is not: the DURATION is real (from the VM's own millisecond totals), the POSITION within the step is not -- all we know is that the GC happened somewhere inside that step. Read a GC marker as 'this step lost 4 ms to a full GC', never as 'the GC started at exactly this microsecond'.

Instances are flyweights, shared per label via #markerLabelled:kind: -- a run with 900 scavenges allocates one marker, not 900.
"
Class {
	#name : #SWATraceMarker,
	#superclass : #Object,
	#instVars : [
		'key',
		'markerKind'
	],
	#classVars : [
		'LastFullCount',
		'LastFullMillis',
		'LastScavCount',
		'LastScavMillis',
		'LastTenureCount',
		'Markers'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'gc probe',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker class >> armGcProbe [
	"Snapshot the VM's cumulative GC counters as the baseline for this run. Sent from
	SWATraceWrapper class>>armTrace, which is the only sensible moment: the counters
	run from image startup, so without a baseline the first step boundary would report
	every GC since the image was launched as if it had just happened."
	LastFullCount := Smalltalk vmParameterAt: 7.
	LastFullMillis := Smalltalk vmParameterAt: 8.
	LastScavCount := Smalltalk vmParameterAt: 9.
	LastScavMillis := Smalltalk vmParameterAt: 10.
	LastTenureCount := Smalltalk vmParameterAt: 11
]

{
	#category : #'gc probe',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker class >> disarmGcProbe [
	"Drop the baseline so no marker is emitted until the next #armGcProbe. Sent from
	SWATraceWrapper class>>resetTrace along with the lanes."
	LastFullCount := LastFullMillis := LastScavCount := LastScavMillis := LastTenureCount := nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker class >> markerLabelled: aString kind: aSymbol [
	"The shared marker for this exact label. Flyweight: a run with 900 scavenges in
	batches of 1..9 allocates at most nine markers, not 900 -- and the lane holds the
	producer strongly, so this is the difference between a few objects and a few
	thousand surviving until the next run."
	Markers ifNil: [Markers := Dictionary new].
	^ Markers at: aString ifAbsentPut: [self new setKey: aString kind: aSymbol; yourself]
]

{
	#category : #'gc probe',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:53'
}
SWATraceMarker class >> recordGcMarkersIn: lane endingAt: stopMicros notBefore: startMicros depth: d [
	"Drain the VM's GC counters into marker spans for the step that just ended, and
	rebase for the next one. Answers the number of markers appended.

	Full GCs are laid down first, then scavenges, each stacked BACKWARDS from the step's
	stop time so they never overlap -- see the class comment for why the end of the step
	is the only defensible position. Everything is clamped to startMicros: a span must
	stay inside its parent or SWATraceNode>>checkNesting is right to complain and the
	trace view would draw a child wider than the call that contains it.

	Nothing is appended when nothing collected, which is the overwhelmingly common case
	-- this costs four vmParameterAt: reads per step boundary and no allocation."
	| fc fm sc sm cursor n |
	LastFullCount ifNil: [^ 0].
	fc := Smalltalk vmParameterAt: 7.
	fm := Smalltalk vmParameterAt: 8.
	sc := Smalltalk vmParameterAt: 9.
	sm := Smalltalk vmParameterAt: 10.
	n := 0.
	cursor := stopMicros.
	cursor := self
		recordMarkerIn: lane label: 'GC full' kind: #gcFull
		count: fc - LastFullCount micros: (fm - LastFullMillis) * 1000
		endingAt: cursor notBefore: startMicros depth: d
		ifRecorded: [n := n + 1].
	cursor := self
		recordMarkerIn: lane label: 'GC scavenge' kind: #gcScavenge
		count: sc - LastScavCount micros: (sm - LastScavMillis) * 1000
		endingAt: cursor notBefore: startMicros depth: d
		ifRecorded: [n := n + 1].
	LastFullCount := fc.
	LastFullMillis := fm.
	LastScavCount := sc.
	LastScavMillis := sm.
	^ n
]

{
	#category : #'gc probe',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:57'
}
SWATraceMarker class >> recordMarkerIn: lane label: aLabel kind: aSymbol count: n micros: micros endingAt: stopMicros notBefore: startMicros depth: d ifRecorded: aBlock [
	"Append ONE right-aligned marker span and answer the new cursor -- its start time --
	so the caller can stack the next marker immediately before it. Answers stopMicros
	unchanged, and evaluates nothing, when n <= 0.

	WIDTH. The VM reports GC time in whole MILLISECONDS, so a batch of sub-millisecond
	scavenges legitimately reports 0 ms. A zero-width span cannot be seen or clicked, so
	the floor is one microsecond per collection: enough to exist and be picked up by the
	view's sub-pixel merging, small enough that nobody reads it as a real duration. The
	COUNT is in the label, which is the number to trust at that scale.

	n batched collections become ONE span labelled 'GC scavenge x7' rather than seven
	spans: they did not happen at seven distinguishable moments -- we only know they
	happened somewhere in this step."
	| width t0 label |
	n <= 0 ifTrue: [^ stopMicros].
	width := micros max: n.
	t0 := (stopMicros - width) max: startMicros.
	t0 >= stopMicros ifTrue: [^ stopMicros].
	"The BOX is clamped to the enclosing step, the LABEL is not. A GC triggered by
	another process is detected at the end of a step that may be much shorter than the
	pause itself, and drawing that box at its true width would put a child outside its
	parent. So the drawn width is what fits and the millisecond figure in the name is
	what actually happened -- when the two disagree, believe the name."
	label := aLabel,
		(n = 1 ifTrue: [''] ifFalse: [' x', n printString]),
		(micros >= 1000 ifTrue: [' ', (micros // 1000) printString, 'ms'] ifFalse: ['']).
	SWATraceWrapper
		record: (self markerLabelled: label kind: aSymbol)
		in: lane start: t0 stop: stopMicros depth: d.
	aBlock value.
	^ t0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker >> crossRefKey [
	"The label a rebuilt span carries, e.g. 'GC full' or 'GC scavenge x7'. Deliberately
	contains no '>>': SWATraceMorph>>selectedSourceString and #browseSelected both test
	for that separator before trying to resolve a key to a method, so a marker silently
	has no source and no browse target instead of erroring."
	^ key
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker >> printOn: aStream [
	aStream nextPutAll: 'marker('; nextPutAll: (key ifNil: ['?']); nextPut: $)
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker >> setKey: aString kind: aSymbol [
	key := aString.
	markerKind := aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:52'
}
SWATraceMarker >> traceMarkerKind [
	"#gcFull or #gcScavenge -- what KIND of non-call event this is. SWAMethodWrapper
	answers nil to the same message, which is how SWATraceNode class>>fromLane: tags
	marker nodes without an isKindOf: test in its reconstruction loop."
	^ markerKind
]
