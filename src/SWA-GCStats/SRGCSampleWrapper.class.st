"
A frame hook, not a profiler capture. Wraps SRFrame>>process and, after the real
frame runs, asks the current SRGCRecorder to take one GC sample. This keeps the GC
recording concern out of the frame path itself: SRFrame>>process no longer mentions
it, and the sampling appears only while a recording installs this wrapper.

Unlike the tally/timing wrappers it does NOT gate on SWACapturingLayer -- that layer
marks a profiling session, which is not active during ordinary XR frames, and this
must sample every presented frame. It also disables eviction (evictAt := nil): a
per-frame hook is expected to be hot and must not uninstall itself.

Driven by SRGCRecorder class>>startXr (install) and >>stop (uninstall).
"
Class {
	#name : #SRGCSampleWrapper,
	#superclass : #SWAMethodWrapper,
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 10:49'
}
SRGCSampleWrapper class >> installOn [
	"Wrap SRFrame>>process with a fresh sampler, unless one is already installed.
	Idempotent so a second startXr (or a startXr after a crash left one installed)
	does not stack wrappers. evictAt nil: a per-frame hook must never self-evict."
	(SRFrame >> #process) class == self ifTrue: [^ self].
	^ (self new onClass: SRFrame selector: #process; evictAt: nil; yourself) install
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 10:50'
}
SRGCSampleWrapper class >> uninstallFrom [
	"Restore the real SRFrame>>process if one of my wrappers is installed. Idempotent:
	a no-op when nothing is wrapped, so a stop without a prior start is harmless."
	| installed |
	installed := SRFrame >> #process.
	(installed class == self) ifTrue: [installed uninstall]
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 10:49'
}
SRGCSampleWrapper >> run: aSelector with: anArray in: aReceiver [
	"Run the real frame, then sample the GC recorder. Sampling AFTER the frame is the
	point Jens's old comment made: the frame is presented and its temporaries are dead,
	so the reading reflects the boundary. The sample is guarded (SRGCRecorder is nil
	before any recording) and shielded: a failure in the recorder must never take the
	render loop down, so it is swallowed here rather than unwinding through the frame.

	No SWACapturingLayer check -- that layer marks a profiling session and is not active
	during ordinary frames; this hook must fire every frame regardless."
	| result |
	count := count + 1.
	result := aReceiver withArgs: anArray executeMethod: self realMethod.
	[SRGCRecorder current ifNotNil: [:r | r sampleFromXrFrame]]
		on: Error do: [:e | ].
	^ result
]
