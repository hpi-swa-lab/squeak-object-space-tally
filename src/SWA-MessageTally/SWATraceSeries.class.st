"
The continuous half of a trace: one sample of the VM's memory counters per Morphic cycle, on the same clock as the spans.

Spans answer 'what ran'. They cannot answer 'why did it collect' -- for that you need the sawtooth, and the sawtooth is a curve, not an event. So SWAStepTraceWrapper takes a reading at every step boundary it already visits (four vmParameterAt: reads and one four-element Array per cycle, which at 60 fps is nothing) and SWATraceMorph draws it as two bands above the lanes, on the trace's own time axis.

Each sample is #(micros oldSpaceBytes usedYoungBytes freeOldBytes) -- vmParameterAt: 1, 2 and 54, the same numbers the SWA Memory Stats graph shows. Frame rate is NOT sampled: it is the reciprocal of the gap between consecutive samples, which is the real frame interval and costs nothing to store.

Lifecycle follows the lanes exactly: #arm from SWATraceWrapper class>>armTrace, #disarm when the trace is disarmed (stop sampling, keep the data -- the reconstruction still has to read it), #reset from #resetTrace once SWATraceNode class>>fromLanes: has handed the samples to the trace root.
"
Class {
	#name : #SWATraceSeries,
	#superclass : #Object,
	#classVars : [
		'Samples'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #lifecycle,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:38'
}
SWATraceSeries class >> arm [
	"Start collecting. Sent from SWATraceWrapper class>>armTrace."
	Samples := OrderedCollection new
]

{
	#category : #lifecycle,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:38'
}
SWATraceSeries class >> disarm [
	"Stop sampling but KEEP what was collected: the reconstruction still has to read it.
	Nothing to do -- #sampleAt: is only ever reached from an armed step wrapper, and the
	wrappers are gone by the time this matters. Kept as a named moment so the lifecycle
	reads the same as the lanes'."
	^ self
]

{
	#category : #lifecycle,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceSeries class >> reset [
	"Drop the samples. Sent from SWATraceWrapper class>>resetTrace, i.e. AFTER
	SWATraceNode class>>fromLanes: has handed them to the trace root."
	Samples := nil
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceSeries class >> sampleAt: micros [
	"Take one reading, stamped with the end of the step that asked for it.

	#(micros oldSpace usedYoung freeOldSpace), all in BYTES as the VM reports them --
	scaling is the view's business, and a divide per cycle is a divide the measured
	system pays for. Parameter 54 is Spur-only and answers nil elsewhere; 0 then, which
	simply makes free old space invisible rather than breaking the band."
	Samples ifNil: [^ self].
	Samples add: (Array
		with: micros
		with: (Smalltalk vmParameterAt: 1)
		with: (Smalltalk vmParameterAt: 2)
		with: ((Smalltalk vmParameterAt: 54) ifNil: [0]))
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:52'
}
SWATraceSeries class >> sampleAt: micros duration: durationMicros [
	"Take one reading, stamped with the end of the step that asked for it and carrying
	how long that step took.

	#(micros oldSpace usedYoung freeOldSpace stepMicros). The three memory figures are
	in BYTES exactly as the VM reports them -- scaling is the view's business, and a
	divide per cycle is a divide the measured system pays for. Parameter 54 is Spur-only
	and answers nil elsewhere; 0 then, which makes free old space invisible rather than
	breaking the band.

	STEP TIME, not frame rate. The duration is measured, the rate would be derived, and
	the derived one is the worse picture: a stalled cycle is a SPIKE in step time and a
	dip towards zero in fps -- and a dip towards zero has nowhere to go, so a 40 ms
	stutter and a 400 ms freeze look nearly the same. Milliseconds are also what the
	spans underneath are measured in, so the band and the lanes read in one unit."
	Samples ifNil: [^ self].
	Samples add: (Array
		with: micros
		with: (Smalltalk vmParameterAt: 1)
		with: (Smalltalk vmParameterAt: 2)
		with: ((Smalltalk vmParameterAt: 54) ifNil: [0]))
		, (Array with: durationMicros)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceSeries class >> samples [
	"The readings so far, oldest first, as an Array of Arrays. Empty if nothing was
	collected -- callers draw nothing rather than special-casing nil."
	^ Samples ifNil: [#()] ifNotNil: [:s | s asArray]
]
