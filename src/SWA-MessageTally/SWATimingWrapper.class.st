"
A TIMING tally wrapper: the stopwatch twin of SWATallyWrapper.

Where SWATallyWrapper answers ""how OFTEN was this method called"", this one also
answers ""how LONG did it take"" -- the Smalltalk equivalent of bracketing every
JavaScript function with performance.now(). Each wrapped call is bracketed with
Time utcMicrosecondClock (~0.1 us per read, microsecond resolution) and the
elapsed time is accumulated into two numbers per method:

  totalMicros -- INCLUSIVE (wall) time: everything between entry and return,
                 callees included.
  selfMicros  -- EXCLUSIVE time: inclusive minus the inclusive time of the
                 INSTRUMENTED methods called directly from here. Un-instrumented
                 callees (substrate, other packages) count as self time, exactly
                 like a sampling profiler's self time.

NESTING is tracked with a small PER-PROCESS frame record (see #frameSlots), not
a global -- several Smalltalk processes may be running instrumented code at the
same time and a shared stack would interleave into nonsense. The record holds
three slots: (1) the inclusive time of the direct callees of the frame currently
running, (2) the instrumentation OVERHEAD consumed inside it, (3) the call-tree
node of that frame. Each activation saves the three slots in its own temps,
zeroes them for its callees, and restores them on the way out -- so the ""stack""
is the real Smalltalk stack and nothing has to be allocated per call.

OVERHEAD COMPENSATION: measuring costs time, and that time lands inside the
CALLER's interval, so a caller of many small methods would otherwise appear to
take far longer than it does. Every frame therefore measures its OWN
instrumentation cost (clock reads, frame bookkeeping, call-tree lookup) plus that
of its whole subtree and reports the sum upward in slot 2; the caller subtracts
it. Same idea as the `bias` calibration in Python's profile module, but measured
per call instead of estimated once.

BALANCE is guaranteed by ensure: -- an exception, a non-local return or a process
termination unwinding through a wrapped method still restores the caller's slots,
so one bad call cannot corrupt every later measurement.

CALL TREE: when capture is armed, the wrapper does NOT walk the stack the way
SWATallyWrapper>>captureIn: does. It already knows its caller's node (slot 3), so
the current node is one #childNamed: away -- cheaper AND exact. Nodes are
credited in MICROSECONDS of self time, which makes the resulting flamegraph a
real time flamegraph, directly comparable with the sampling one.

CAVEAT -- this is WALL time, like performance.now(): a frame that is preempted,
waits on a Delay or blocks on I/O is charged for it. And tracing every call is
expensive (order of a microsecond per call on top of the wrapper itself), so a
method that is genuinely a few hundred nanoseconds long is dominated by its own
measurement. For those, trust the sampling tally instead. Eviction is therefore
OFF by default here (evictAt: nil): a self-evicting wrapper would stop measuring
exactly the hot methods you want timed.
"
Class {
	#name : #SWATimingWrapper,
	#superclass : #SWATallyWrapper,
	#instVars : [
		'totalMicros',
		'selfMicros'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'timing frame',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:17'
}
SWATimingWrapper class >> frameSlots [
	"The PER-PROCESS frame record used to attribute time to the right frame, held in
	the active process's environment (the same process-specific slot mechanism
	SWACapturingLayer uses for its suppression depth, so a preempted process cannot
	scribble on another one's bookkeeping).

	Three slots, all belonging to the frame CURRENTLY running in this process:
	  1 -- summed INCLUSIVE time of its direct instrumented callees (us),
	  2 -- summed instrumentation OVERHEAD consumed inside it, subtree included (us),
	  3 -- its call-tree node, or nil when no tree is being captured / at top level.

	Allocated once per process and then reused: one #environmentAt:ifAbsent: (~45 ns)
	per wrapped call, after which the slots are plain Array accesses. Storing three
	separate process variables instead would cost an #environmentAt:put: (~190 ns)
	each, six times per call.

	Slot 3 starting as nil is deliberate: a top-level frame reads nil and attaches
	itself under the CURRENT SWATallyWrapper CallTreeRoot, so a record left over from
	an earlier run can never pin a stale tree."
	| p slots |
	p := Processor activeProcess.
	slots := p environmentAt: self ifAbsent: [nil].
	slots ifNotNil: [^ slots].
	slots := Array with: 0 with: 0 with: nil.
	p environmentAt: self put: slots.
	^ slots
]

{
	#category : #'timing frame',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:17'
}
SWATimingWrapper class >> resetFrames [
	"Drop this process's frame record so a new timing run starts from a clean slate.
	Sent before instrumenting and after collecting. Only THIS process can be cleaned
	(a process environment is not enumerable from outside), which is enough: every
	frame restores its caller's slots in an ensure:, so no other process can be
	holding a half-finished record once its call has returned."
	Processor activeProcess environmentRemoveKey: self ifAbsent: []
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:17'
}
SWATimingWrapper >> onClass: aClass selector: aSelector evictAt: anIntegerOrNil [
	"Tally setup plus the two microsecond accumulators. Pass nil for evictAt (what
	SWACoverage>>instrumentTiming does) so hot methods keep being measured: a wrapper
	that evicts itself stops the stopwatch on precisely the methods worth timing."
	super onClass: aClass selector: aSelector evictAt: anIntegerOrNil.
	totalMicros := 0.
	selfMicros := 0
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:17'
}
SWATimingWrapper >> run: aSelector with: anArray in: aReceiver [
	"THE timing dispatch: the stopwatch version of SWAMethodWrapper>>run:with:in:.
	Bracket the forwarded call with Time utcMicrosecondClock -- performance.now()
	around every function -- and split the elapsed time into inclusive and self time.

	 0. COUNT FIRST (so a timing run is also a plain call tally).
	 1. LAYER CHECK: capturing suppressed in this process (instrumentation's own
	    machinery is running) -> forward untimed. Same guard as the base wrapper.
	 2. EVICT if over the cap -- normally OFF for timing (evictAt nil).
	 3. tA .. t0: entry bookkeeping (frame record + call-tree node lookup), OUTSIDE
	    the measured interval but inside the CALLER's, hence reported as overhead.
	 4. t0 .. t1: the call itself.
	 5. exit: raw = (t1 - t0) - overhead consumed by my subtree; self = raw - the
	    inclusive time of my direct instrumented callees. Credit both accumulators
	    and the call-tree node, then restore the caller's slots and hand it the
	    overhead I cost it, so the caller's own raw comes out clean.

	Clamped at 0 because the clock has microsecond granularity: a method faster than
	a tick can legitimately measure as slightly less than the sum of its parts.

	Everything here sends only to substrate (Time, Array, Process) or to
	SWASamplingTallyNode, which SWACoverage class>>infrastructureClasses excludes
	from instrumentation -- so no send on this path can re-enter a wrapper, and the
	expensive #withoutCapturing: dance the counting tally needs is not required.

	ensure: (~15 ns) is not optional: without it an exception unwinding through a
	wrapped method would leave the caller's slots zeroed and silently poison every
	measurement after it."
	| slots tA t0 t1 tB raw selfT over savedTotal savedOver savedNode parent node result |
	count := count + 1.
	SWACapturingLayer isActive ifFalse: [
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	(evictAt notNil and: [count >= evictAt]) ifTrue: [
		evicted := true.
		SWACapturingLayer withoutCapturing: [self uninstallNoFlush].
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	tA := Time utcMicrosecondClock.
	slots := SWATimingWrapper frameSlots.
	savedTotal := slots at: 1.
	savedOver := slots at: 2.
	savedNode := slots at: 3.
	parent := savedNode ifNil: [SWATallyWrapper callTreeRoot].
	node := parent ifNil: [nil] ifNotNil: [:p | p childNamed: methodNameString].
	slots at: 1 put: 0; at: 2 put: 0; at: 3 put: node.
	t0 := Time utcMicrosecondClock.
	[result := aReceiver withArgs: anArray executeMethod: self realMethod]
		ensure: [
			t1 := Time utcMicrosecondClock.
			raw := t1 - t0 - (slots at: 2).
			raw < 0 ifTrue: [raw := 0].
			selfT := raw - (slots at: 1).
			selfT < 0 ifTrue: [selfT := 0].
			totalMicros := totalMicros + raw.
			selfMicros := selfMicros + selfT.
			node ifNotNil: [node addSelfTime: selfT].
			tB := Time utcMicrosecondClock.
			over := tB - tA - raw.
			over < 0 ifTrue: [over := 0].
			slots at: 1 put: savedTotal + raw;
				at: 2 put: savedOver + over;
				at: 3 put: savedNode].
	^ result
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:18'
}
SWATimingWrapper >> selfMicros [
	"Summed EXCLUSIVE wall time of this method: inclusive time minus the inclusive
	time of the INSTRUMENTED methods it called. Time spent in un-instrumented callees
	(substrate, packages outside the run) is charged here, exactly as a sampling
	profiler charges it -- so widening the instrumented scope moves time out of self
	and into the callees, which is the point."
	^ selfMicros ifNil: [0]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:18'
}
SWATimingWrapper >> totalMicros [
	"Summed INCLUSIVE wall time of every measured call of this method, in
	microseconds, with the instrumentation overhead of the subtree removed. Callees
	included, so a recursive method double-counts its own nested activations here --
	read #selfMicros when that matters."
	^ totalMicros ifNil: [0]
]
