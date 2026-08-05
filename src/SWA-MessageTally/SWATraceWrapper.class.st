"
A TRACING wrapper: the stopwatch of SWATimingWrapper, but it keeps WHEN each call
happened instead of only how long they added up to.

WHY A THIRD WRAPPER
SWATallyWrapper answers ""how often"", SWATimingWrapper answers ""how long in total"".
Both are AGGREGATES -- they fold every invocation of a method into one number and
into one shared call-tree node, which is exactly what makes a flamegraph possible
and a flame CHART impossible. A flame chart needs the individual call, with its own
start and its own end, on a real wall-clock axis. So this wrapper keeps an EVENT
LOG: one record per invocation, appended in a preallocated buffer.

THE RECORD IS A CHROME ""COMPLETE EVENT""
The Chrome Trace Event format (what chrome://tracing and Perfetto ingest) offers
begin/end pairs (ph:""B""/""E"") and the compacted single record with a duration
(ph:""X""). We emit the second: one append per call, written on the way OUT.

  { wrapper. startMicros. stopMicros. depth }

No enter record, no allocation, four stores. The stack is NOT materialised at
capture time; it is implicit in two facts the reconstruction pass relies on:
  1. records are EXIT-ORDERED, so every child is written before its parent, and
  2. each record carries its INSTRUMENTED depth.
Depth is recorded rather than inferred from t0/t1 containment because the clock
has microsecond granularity: many spans share identical timestamps and nesting by
containment is genuinely ambiguous there.

Note that depth is depth in the INSTRUMENTED stack, not in the real one.
Uninstrumented frames collapse away, so two methods can appear adjacent with real
frames between them. That is a projection, and an honest one -- but it is not the
Smalltalk stack.

ONE BUFFER PER PROCESS, WHICH IS THE POINT
The buffer is NOT shared. A shared write index would be a read-modify-write across
processes, and this image preempts across priorities (the XR world process runs at
40, the UI and the MCP server at 60), so the index would be corrupted exactly under
the load worth tracing. Each process instead gets its own lane, held in its own
process environment -- the same per-process slot mechanism SWATimingWrapper uses
for its frame record -- so the bump is a plain slot store that nothing can
interleave with. Lanes become the tid of the exported trace, which is also what
you want to look at: the render loop and the UI are different stories.

Cross-process state is therefore limited to REGISTERING a new lane, which happens
once per process per run and is serialised by TraceMutex.

BOUNDED, STOP-ON-FULL
A lane that fills stops recording and sets its truncated flag; it never wraps.
A ring buffer would be cheaper to justify but leaves orphaned exits whose parents
were overwritten, i.e. a tree that cannot be rebuilt. Truncation is visible in
#traceStatus and must be surfaced in the UI: a silently short trace is a lie.

DURATIONS ARE RAW WALL CLOCK, DELIBERATELY
t0/t1 are the unmodified clock readings around the forwarded send, so they include
our own instrumentation cost and spans nest EXACTLY. The overhead-corrected numbers
still go to totalMicros/selfMicros as in the superclass, so the aggregate views are
unaffected. Chrome does the same: a trace shows what the clock saw.

COST
Everything the superclass does, plus one #laneSlots lookup and four array stores.
See the SWATimingWrapper class comment for what tracing costs in general; this is
strictly more, and there is no eviction, so keep the scope tight and the exercise
short.
"
Class {
	#name : #SWATraceWrapper,
	#superclass : #SWATimingWrapper,
	#classVars : [
		'GcLane',
		'TraceArmed',
		'TraceCapacity',
		'TraceGeneration',
		'TraceLanes',
		'TraceMutex',
		'TraceStartMicros'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceWrapper class >> armTrace [
	"Open a fresh trace log. Bumps the GENERATION, which is how a lane left behind in
	some OTHER process's environment is retired: that process cannot be reached from
	here (a process environment is not enumerable from outside), so it retires its own
	stale lane on its next wrapped call by comparing generations. Without this a
	long-lived process -- the Morphic UI, the XR world -- would keep appending to the
	previous run's orphaned buffer and never appear in this one.

	Sent by SWACoverage>>instrumentTrace BEFORE the wall clock starts."
	TraceMutex ifNil: [TraceMutex := Semaphore forMutualExclusion].
	TraceGeneration := (TraceGeneration ifNil: [0]) + 1.
	TraceLanes := OrderedCollection new.
	TraceStartMicros := Time utcMicrosecondClock.
	StepLane := nil.
	GcLane := nil.
	TraceArmed := true.
	SWATraceMarker armGcProbe.
	SWATraceSeries arm.
	self resetLane
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:05'
}
SWATraceWrapper class >> chunkEvents [
	"Events per chunk. 16384 x 32 bytes = 512 kB, so growth is a 512 kB allocation
	roughly every 16k calls -- small enough not to show up as a spike in the very
	trace being recorded, large enough that the check costs nothing."
	^ 16384
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:05'
}
SWATraceWrapper class >> chunkSlots [
	"Slots per chunk. A multiple of 4 so every chunk fills EXACTLY -- otherwise the
	tail slack has to be tracked per chunk and the reconstruction has to know about it."
	^ self chunkEvents * 4
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceWrapper class >> disarmTrace [
	"Stop appending, but KEEP the lanes: collection reads them afterwards. Sent at the
	start of SWACoverage>>collectTrace, before the wrappers are uninstalled, so that
	the uninstall itself -- thousands of sends -- does not land in the log."
	TraceArmed := false.
	SWATraceSeries disarm
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:37'
}
SWATraceWrapper class >> gcLane [
	"The lane SWATraceMarker writes GC marks into, all at depth 0 so they are top-level
	spans in a lane of their own -- never nested, never merged away, readable at any
	zoom. nil when no trace is armed."
	TraceArmed == true ifFalse: [^ nil].
	^ GcLane ifNil: [GcLane := self syntheticLaneNamed: 'GC']
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:06'
}
SWATraceWrapper class >> laneEventCount: lane [
	"Events recorded in lane. Every chunk but the last is exactly full, which is why
	#chunkSlots is a multiple of 4."
	| chunks |
	chunks := lane at: 1.
	chunks isEmpty ifTrue: [^ 0].
	^ ((chunks size - 1) * (lane at: 1) first size + (lane at: 3)) // 4
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:06'
}
SWATraceWrapper class >> laneEventsDo: aFourArgBlock in: lane [
	"Evaluate aFourArgBlock with wrapper, start, stop and depth for every event in
	lane, in RECORD (exit) order across all chunks. The one place that knows the
	chunked layout, so neither the reconstruction nor the counting has to."
	| chunks last idx |
	chunks := lane at: 1.
	last := chunks size.
	idx := lane at: 3.
	chunks doWithIndex: [:chunk :n |
		| used |
		used := n = last ifTrue: [idx] ifFalse: [chunk size].
		1 to: used by: 4 do: [:i |
			aFourArgBlock
				value: (chunk at: i)
				value: (chunk at: i + 1)
				value: (chunk at: i + 2)
				value: (chunk at: i + 3)]]
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:05'
}
SWATraceWrapper class >> laneSlots [
	"THIS process's trace lane, or nil when no trace is armed. Six slots, all owned by
	one process and therefore safe to bump without any lock:

	  1 -- chunks, an OrderedCollection of flat Arrays (the last one is the current),
	  2 -- the current chunk,
	  3 -- write index within the current chunk,
	  4 -- the owning process, which becomes the tid of the exported trace,
	  5 -- current instrumented call depth in this process,
	  6 -- the TraceGeneration this lane was allocated for.

	CHUNKED, NOT DOUBLED. The log has no size limit, so it must grow, and growing by
	doubling would copy the whole buffer inside a traced call -- a 64 MB allocation
	and memcpy landing in the middle of the frame being measured, which the trace
	would then faithfully report as a slow method. A new fixed-size chunk costs the
	same whether it is the first or the thousandth, and nothing is ever copied.

	The generation compare is the retirement mechanism described in #armTrace: a lane
	from an earlier run is thrown away and reallocated here, in the process that owns
	it, because no other process can reach into its environment.

	One #environmentAt:ifAbsent: (~45 ns) per wrapped call, exactly like
	SWATimingWrapper>>frameSlots, after which everything is a plain Array access.
	Allocation and registration happen once per process per run; only the
	REGISTRATION touches shared state, hence the mutex -- and only there."
	| p lane |
	TraceArmed == true ifFalse: [^ nil].
	p := Processor activeProcess.
	lane := p environmentAt: self ifAbsent: [nil].
	(lane notNil and: [(lane at: 6) == TraceGeneration]) ifTrue: [^ lane].
	lane := Array new: 6.
	lane
		at: 1 put: (OrderedCollection with: (Array new: self chunkSlots));
		at: 3 put: 0;
		at: 4 put: p;
		at: 5 put: 0;
		at: 6 put: TraceGeneration.
	lane at: 2 put: (lane at: 1) first.
	p environmentAt: self put: lane.
	TraceMutex critical: [TraceLanes ifNotNil: [:l | l add: lane]].
	^ lane
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:53'
}
SWATraceWrapper class >> record: aProducer in: lane start: t0 stop: t1 depth: d [
	"Append one Chrome-style COMPLETE event -- {producer. start. stop. depth} -- to a
	process's lane. Four stores into a preallocated flat Array, no allocation in the
	common case, no shared state: the lane belongs to the running process, so the index
	bump cannot be interleaved by a preempting one.

	aProducer is normally the SWATraceWrapper whose call this is, but the log does not
	care -- SWATraceNode class>>fromLane: only ever asks it for #crossRefKey. That is
	what lets SWATraceMarker put GC spans into the same lane without a call behind them.

	UNBOUNDED. There is no event cap and no truncation. What bounds a trace instead is
	per-method EVICTION (SWACoverage>>instrumentTrace installs with evictAt), which
	drops each method out of the log after its first n calls. That is a far better
	bound than a buffer limit: it spends the budget on the repetitive tail of hot
	methods rather than on the whole END of the run -- and the end is usually where you
	were going.

	When the current chunk fills, a new one is added. Never doubled, never copied: see
	SWATraceWrapper class>>laneSlots."
	| buf i |
	buf := lane at: 2.
	i := lane at: 3.
	i >= buf size ifTrue: [
		buf := Array new: self chunkSlots.
		(lane at: 1) addLast: buf.
		lane at: 2 put: buf.
		i := 0].
	buf
		at: i + 1 put: aProducer;
		at: i + 2 put: t0;
		at: i + 3 put: t1;
		at: i + 4 put: d.
	lane at: 3 put: i + 4
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 10:59'
}
SWATraceWrapper class >> resetLane [
	"Drop this process's lane so it is reallocated on the next wrapped call."
	Processor activeProcess environmentRemoveKey: self ifAbsent: []
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:39'
}
SWATraceWrapper class >> resetTrace [
	"Drop the log and every buffer. MUST be sent from the collecting caller's ensure:,
	for the same reason SWATallyWrapper>>resetCallTree must be: each lane strongly
	holds up to TraceCapacity records, each pointing at a wrapper, which points at a
	CompiledMethod -- a full-capacity lane is megabytes, and it would otherwise survive
	until the next run.

	Only THIS process's lane can be unhooked from its environment; the others are
	retired by generation on their next wrapped call, or simply garbage once TraceLanes
	lets go."
	TraceArmed := false.
	TraceLanes := nil.
	TraceStartMicros := nil.
	StepLane := nil.
	GcLane := nil.
	SWATraceMarker disarmGcProbe.
	SWATraceSeries reset.
	self resetLane
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:37'
}
SWATraceWrapper class >> syntheticLaneNamed: aString [
	"A lane that belongs to no process. Same six slots as #laneSlots, except that slot 4
	-- normally the owning Process, which becomes the exported tid -- holds a NAME, and
	slot 6 is not a generation because there is nothing to retire: these are built fresh
	by #armTrace and dropped by #resetTrace.

	Why a lane and not a nesting: a top-level lane is always laid out. Anything hung
	underneath a call is only drawn if every one of its ancestors was wide enough to
	draw, and a 16 ms Morphic cycle is a third of a pixel in a 30 s trace. Step spans
	and GC marks are exactly the things you must be able to see AT FULL ZOOM-OUT, so
	they cannot live under anything.

	NOT per-process, unlike the real lanes, so the depth counter in slot 5 is shared. In
	practice only the UI process runs Morphic cycles and there is no contention; two
	worlds cycling in two processes would interleave the step nesting."
	| lane |
	lane := Array new: 6.
	lane
		at: 1 put: (OrderedCollection with: (Array new: self chunkSlots));
		at: 3 put: 0;
		at: 4 put: aString;
		at: 5 put: 0;
		at: 6 put: TraceGeneration.
	lane at: 2 put: (lane at: 1) first.
	TraceMutex critical: [TraceLanes ifNotNil: [:l | l add: lane]].
	^ lane
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:00'
}
SWATraceWrapper class >> traceLanes [
	"The recorded lanes, one per process that ran instrumented code."
	^ TraceLanes ifNil: [#()]
]

{
	#category : #'trace log',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:00'
}
SWATraceWrapper class >> traceStartMicros [
	"utcMicrosecondClock when the trace was armed -- the zero of the time axis."
	^ TraceStartMicros
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 17:53'
}
SWATraceWrapper >> recordIn: lane start: t0 stop: t1 depth: d [
	"Append one Chrome-style COMPLETE event -- {wrapper. start. stop. depth} -- to this
	process's lane. Four stores into a preallocated flat Array, no allocation in the
	common case, no shared state: the lane belongs to the running process, so the index
	bump cannot be interleaved by a preempting one.

	UNBOUNDED. There is no event cap and no truncation. What bounds a trace instead is
	per-method EVICTION (SWACoverage>>instrumentTrace installs with evictAt), which
	drops each method out of the log after its first n calls. That is a far better
	bound than a buffer limit: it spends the budget on the repetitive tail of hot
	methods rather than on the whole END of the run -- and the end is usually where you
	were going.

	When the current chunk fills, a new one is added. Never doubled, never copied: see
	SWATraceWrapper class>>laneSlots.

	The append itself lives on the class side (#record:in:start:stop:depth:) so that
	producers which are not wrappers -- SWATraceMarker's GC spans -- write the same
	format through the same code, instead of a second copy of it that would rot the
	first time the chunk layout changed. This stays an instance method because
	SWAStepTraceWrapper overrides it to emit its markers just before its own span."
	^ SWATraceWrapper record: self in: lane start: t0 stop: t1 depth: d
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:15'
}
SWATraceWrapper >> run: aSelector with: anArray in: aReceiver [
	"THE tracing dispatch. Deliberately a FORK of SWATimingWrapper>>run:with:in:
	rather than a hook into it: that method is the measured hot path of the timing
	tool, and adding a per-call branch there would make every timing run pay for a
	feature it does not use. Read the two side by side -- everything about the time
	attribution is identical, and only the marked steps are new.

	NEW vs the timing twin:
	  a. #laneSlots -- this process's event log, or nil when no trace is armed, in
	     which case this method degrades exactly into the timing one.
	  b. depth is pushed before the call and popped in the ensure:, so a span always
	     knows where in the instrumented stack it sat, even if the call unwinds.
	  c. one record appended AFTER t1 -- so recording cost lands in the caller's
	     overhead, never inside the measured span.

	The recorded t0/t1 are the RAW clock readings, not the overhead-corrected `raw`
	below. A trace must nest geometrically -- a child's span strictly inside its
	parent's -- and correction would break that. The corrected numbers still feed
	totalMicros/selfMicros, so the aggregate views see the same figures a plain
	timing run would give them."
	| slots lane tA t0 t1 tB raw selfT over savedTotal savedOver savedNode parent node depth result |
	count := count + 1.
	SWACapturingLayer isActive ifFalse: [
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	(evictAt notNil and: [count >= evictAt]) ifTrue: [
		evicted := true.
		SWACapturingLayer withoutCapturing: [self uninstallNoFlush].
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	tA := Time utcMicrosecondClock.
	slots := SWATimingWrapper frameSlots.
	lane := SWATraceWrapper laneSlots.
	savedTotal := slots at: 1.
	savedOver := slots at: 2.
	savedNode := slots at: 3.
	parent := savedNode ifNil: [SWATallyWrapper callTreeRoot].
	node := parent ifNil: [nil] ifNotNil: [:p | p childNamed: methodNameString].
	slots at: 1 put: 0; at: 2 put: 0; at: 3 put: node.
	depth := 0.
	lane ifNotNil: [depth := lane at: 5. lane at: 5 put: depth + 1].
	"An EVICTED method leaves a hole, and the hole is well behaved: it returns above
	without pushing depth, so its callees record at ITS depth and the reconstruction
	hangs them from its PARENT. One level vanishes; nothing is misattributed."
	t0 := Time utcMicrosecondClock.
	[result := aReceiver withArgs: anArray executeMethod: self realMethod]
		ensure: [
			t1 := Time utcMicrosecondClock.
			lane ifNotNil: [
				lane at: 5 put: depth.
				self recordIn: lane start: t0 stop: t1 depth: depth].
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
