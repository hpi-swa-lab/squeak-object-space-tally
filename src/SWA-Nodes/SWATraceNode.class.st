"
One SPAN in a call trace: a single invocation, with its own start, its own end and
its own place in the tree -- as opposed to SWASamplingTallyNode, which is an
AGGREGATE of every invocation of a method and therefore has no position in time.

That difference is the whole reason this class exists. A flamegraph node answers
""this method cost 40 ms across 900 calls""; a trace node answers ""THIS call ran from
12.431 ms to 12.478 ms, inside that one"". The first is a distribution, the second is
a story.

SHAPE
  name        printable label, 'Class>>selector' for a call, the process name for a
              lane root
  key         cross-ref key ('Class>>selector'), nil for lane roots, so clicking a
              span can select the method in the Code Map
  startMicros absolute utcMicrosecondClock at entry
  stopMicros  absolute utcMicrosecondClock at exit
  process     the Process this span ran in -- the tid of the exported trace
  truncated   lane roots only: this process filled its buffer and stopped early

There are two kinds of node in one class, and deliberately so: a LANE ROOT (key nil,
children = the top-level spans of one process) and a SPAN. Splitting them into two
classes would buy nothing -- the views only ever ask for a label, an interval and
children -- and would cost every consumer a type test.

TIME IS RAW WALL CLOCK
startMicros/stopMicros are the unmodified clock readings taken around the call,
instrumentation overhead included, which is what makes the tree nest exactly: a
child's interval is strictly inside its parent's. The overhead-CORRECTED figures
live in the timing maps of the same SWACoverage; do not mix the two in one number.

WEIGHT
#totalSize answers the duration, so the generic treemap/flamegraph machinery can
weight these nodes without knowing what they are. But note that a trace view must
NOT lay out by totalSize -- that is what a flamegraph does. It lays out by
startMicros, which is the point.
"
Class {
	#name : #SWATraceNode,
	#superclass : #SWANode,
	#instVars : [
		'name',
		'key',
		'startMicros',
		'stopMicros',
		'process'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:06'
}
SWATraceNode class >> attachRemaining: pending to: laneRoot [
	"Hang everything still waiting for a parent under the lane root, in start order.

	Usually only depth 0 is left and this is just 'attach the top-level spans'. But it
	must handle leftovers at ANY depth, because a span can outlive the log: the trace
	is collected between frames, so a call that was still on the stack when recording
	stopped has children in the log and no parent record of its own. Keeping only
	depth 0 would silently discard everything captured under such a call.

	Orphans are therefore promoted to the lane's top level, in start order. They lose
	their real parent, which is information the log genuinely does not contain, but
	they are not invented and they are not thrown away.

	Promotion cannot create overlapping siblings. An orphan is an orphan precisely
	because none of its ancestors was recorded, so the top-level call it sits in never
	finished -- and any top-level span that DID get recorded finished before that call
	began."
	| all |
	all := OrderedCollection new.
	pending do: [:level | all addAll: level].
	all := all asSortedCollection: [:a :b | a startMicros <= b startMicros].
	all do: [:n | laneRoot addChildNode: n]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:06'
}
SWATraceNode class >> fromLane: lane [
	"Rebuild ONE process's spans from its chunked, exit-ordered event log. Answer a
	lane-root node, or nil if the lane recorded nothing.

	THE ALGORITHM, and why it is a single linear pass.
	Records are written on the way OUT of each call, so:
	  * every child is written BEFORE its parent, and
	  * when a record at depth d is read, every pending record at depth d+1 is one of
	    ITS children -- because any other parent at depth d would itself have exited
	    first, and would have taken those children with it.
	So all that is needed is one pending list per depth: adopt everything waiting at
	d+1, clear it, then park yourself at d. What is left at depth 0 at the end are the
	lane's top-level spans.

	Nesting is taken from the RECORDED depth, not inferred from t0/t1 containment. The
	clock ticks in microseconds and plenty of calls are faster than that, so sibling
	and parent intervals are routinely identical and containment cannot tell them
	apart.

	EVICTED METHODS leave holes, and the holes are well behaved. An evicted call
	returns before pushing depth, so its callees record at the evicted method's OWN
	depth and are adopted here by its PARENT. One level of the tree vanishes; nothing
	is attached to the wrong ancestor and nothing is dropped. That is the whole reason
	eviction is an acceptable bound and a buffer cap was not.

	Two passes over the log, not one: the first only finds the maximum depth so the
	pending lists can be allocated once. Reading a chunked log twice is cheap and
	growing an Array inside the loop is not."
	| pending root maxDepth n |
	n := SWATraceWrapper laneEventCount: lane.
	n = 0 ifTrue: [^ nil].
	maxDepth := 0.
	SWATraceWrapper
		laneEventsDo: [:w :t0 :t1 :d | maxDepth := maxDepth max: d]
		in: lane.
	pending := (1 to: maxDepth + 2) collect: [:each | OrderedCollection new].
	SWATraceWrapper
		laneEventsDo: [:wrapper :t0 :t1 :d |
			| node kids |
			node := self new
				name: wrapper crossRefKey;
				crossRefKey: wrapper crossRefKey;
				start: t0 stop: t1;
				yourself.
			kids := pending at: d + 2.
			kids isEmpty ifFalse: [
				kids do: [:k | node addChildNode: k].
				pending at: d + 2 put: OrderedCollection new].
			(pending at: d + 1) add: node]
		in: lane.
	root := self new
		name: (self laneNameFor: (lane at: 4));
		process: (lane at: 4);
		yourself.
	self attachRemaining: pending to: root.
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode class >> fromLanes: aCollectionOfLanes [
	"Rebuild the whole trace: one lane root per process that ran instrumented code,
	under a single trace root. Answer nil if nothing was recorded at all.

	Lanes are sorted by first event, so the process that started earliest draws at the
	top -- stable across runs, unlike registration order, which depends on which
	process happened to be scheduled first.

	Deliberately NOT merged into one tree: the render loop and the UI are different
	stacks that interleave in real time, and splicing them into one depth axis would
	invent parent/child relationships that never existed. They are separate tids, and
	a trace view draws them as separate lanes."
	| roots root |
	roots := aCollectionOfLanes
		inject: OrderedCollection new
		into: [:acc :lane |
			(self fromLane: lane) ifNotNil: [:r | acc add: r].
			acc].
	roots isEmpty ifTrue: [^ nil].
	roots := roots asSortedCollection: [:a :b | a startMicros <= b startMicros].
	root := self new name: 'trace'; yourself.
	roots do: [:r | root addChildNode: r].
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:09'
}
SWATraceNode class >> laneNameFor: aProcess [
	"Label for a lane. The PRIORITY is part of it, not decoration: in this image the
	XR world runs at 40 while the UI and the MCP server run at 60, and 'this lane was
	preempted by that one' is usually the first thing a trace is being read to find
	out. An unnamed process falls back to its hash, which at least stays stable within
	a run."
	| n |
	n := [aProcess name] on: Error do: [:e | nil].
	n ifNil: [n := 'Process ', aProcess hash printString].
	^ n , ' [prio ' , aProcess priority printString , ']'
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceNode class >> printMicros: micros on: aStream [
	"Human-scaled duration: us below a millisecond, ms below a second, else s.
	On the class side so views can format an axis without inventing a node."
	micros < 1000 ifTrue: [^ aStream print: micros; nextPutAll: ' us'].
	micros < 1000000 ifTrue: [
		^ aStream nextPutAll: ((micros / 1000.0) printShowingDecimalPlaces: 3); nextPutAll: ' ms'].
	aStream nextPutAll: ((micros / 1000000.0) printShowingDecimalPlaces: 3); nextPutAll: ' s'
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceNode class >> stringForMicros: micros [
	^ String streamContents: [:s | self printMicros: micros on: s]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> addChildNode: aNode [
	children ifNil: [children := OrderedCollection new].
	children add: aNode.
	aNode parent: self.
	^ aNode
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:08'
}
SWATraceNode >> checkNesting [
	"Answer a collection of strings describing every place the tree VIOLATES the two
	invariants a trace must satisfy, or an empty collection if it is sound:

	  1. CONTAINMENT -- a child's interval lies inside its parent's. This is why
	     SWATraceWrapper records raw, uncorrected clock readings; overhead-corrected
	     times would break it.
	  2. ORDER -- siblings do not overlap and appear in start order. Within one
	     process they cannot overlap, so a violation here means the reconstruction
	     attached a span to the wrong parent, not that the world is strange.

	Cheap, and worth running on any trace before believing a picture drawn from it."
	| problems |
	problems := OrderedCollection new.
	self withAllChildrenDo: [:n |
		| prev |
		prev := nil.
		n children do: [:c |
			(c startMicros >= n startMicros and: [c stopMicros <= n stopMicros])
				ifFalse: [problems add: 'not contained: ', c name, ' in ', n name].
			(prev notNil and: [c startMicros < prev stopMicros])
				ifTrue: [problems add: 'overlapping siblings: ', prev name, ' / ', c name].
			prev := c]].
	^ problems
]

{
	#category : #exporting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:06'
}
SWATraceNode >> chromeEventsInto: aCollection tid: tid relativeTo: zero [
	"Recursive worker for #chromeTraceJson. A LANE ROOT emits no span of its own --
	it is not a call, it is a thread -- but it does emit a thread_name metadata event
	and hands its own index down as the tid. The trace root emits nothing at all."
	| myTid |
	myTid := tid.
	self parent isNil
		ifTrue: [
			"trace root: each child lane becomes a tid"
			self children doWithIndex: [:lane :i |
				lane chromeEventsInto: aCollection tid: i relativeTo: zero].
			^ self].
	self crossRefKey
		ifNil: [
			aCollection add: (String streamContents: [:s |
				s nextPutAll: '{"ph":"M","name":"thread_name","pid":1,"tid":';
					print: myTid;
					nextPutAll: ',"args":{"name":'.
				self jsonString: self name on: s.
				s nextPutAll: '}}'])]
		ifNotNil: [:k |
			aCollection add: (String streamContents: [:s |
				s nextPutAll: '{"ph":"X","pid":1,"tid":';
					print: myTid;
					nextPutAll: ',"name":'.
				self jsonString: k on: s.
				s nextPutAll: ',"ts":';
					print: self startMicros - zero;
					nextPutAll: ',"dur":';
					print: self durationMicros;
					nextPutAll: '}'])].
	self children do: [:c | c chromeEventsInto: aCollection tid: myTid relativeTo: zero]
]

{
	#category : #exporting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:05'
}
SWATraceNode >> chromeTraceJson [
	"The subtree as Chrome Trace Event Format JSON -- the array-of-events form, which
	both chrome://tracing and Perfetto load directly.

	Every span becomes a COMPLETE event (ph:'X') with ts and dur in microseconds,
	which is exactly the shape SWATraceWrapper already records, so this is close to a
	memory dump. The alternative encoding, begin/end pairs (ph:'B'/'E'), would double
	the size and force the consumer to rebuild the stack it can simply be handed.

	Timestamps are relative to the start of this subtree: absolute Squeak clock values
	are microseconds since 1901 and would push the trace millennia past anything the
	viewers will draw.

	Lanes map to tid, so a process is a thread row -- which is what a process is, from
	the viewer's point of view. pid is fixed at 1: one image, one process.

	This is not decoration. Loading the same trace in an external, independently
	written viewer is the check that our own layout is telling the truth."
	| zero events |
	zero := self startMicros.
	events := OrderedCollection new.
	self chromeEventsInto: events tid: 0 relativeTo: zero.
	^ String streamContents: [:s |
		s nextPutAll: '{"displayTimeUnit":"ms","traceEvents":['; cr.
		events
			do: [:e | s nextPutAll: e]
			separatedBy: [s nextPutAll: ','; cr].
		s cr; nextPutAll: ']}']
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> crossRefKey [
	"'Class>>selector' for a span, nil for a lane root -- a process is not a code
	entity and must not select anything in the Code Map."
	^ key
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> crossRefKey: aStringOrNil [
	key := aStringOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> durationMicros [
	"How long this call took, wall clock, our own overhead included."
	^ self stopMicros - self startMicros
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> eventDurationMicros [
	^ self durationMicros
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> eventMicros [
	^ self startMicros
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> eventTimeStamp [
	"Entry time as a DateAndTime, so a trace can also be dropped into the existing
	second-resolution temporal views. Lossy by construction -- those views truncate
	with #asSeconds, which collapses a whole short run into one bucket. Use
	#eventMicros for anything that cares."
	^ DateAndTime fromSeconds: self startMicros // 1000000
]

{
	#category : #exporting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:06'
}
SWATraceNode >> jsonString: aString on: aStream [
	"A JSON string literal. NOT #printString, which is a SMALLTALK literal -- single
	quotes, doubled-quote escaping -- and produces invalid JSON that the viewer
	rejects with a parse error a long way from here."
	aStream nextPut: $".
	aString do: [:c |
		c = $" ifTrue: [aStream nextPutAll: '\"'] ifFalse: [
		c = $\ ifTrue: [aStream nextPutAll: '\\'] ifFalse: [
		c value < 32
			ifTrue: [aStream nextPutAll: '\u'; nextPutAll: ((c value printStringBase: 16) padded: #left to: 4 with: $0)]
			ifFalse: [aStream nextPut: c]]]].
	aStream nextPut: $"
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> name [
	^ name ifNil: ['?']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> name: aString [
	name := aString
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> nodeKind [
	^ key isNil ifTrue: [#traceLane] ifFalse: [#traceSpan]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:30'
}
SWATraceNode >> printMicros: micros on: aStream [
	"Human-scaled duration. The work is on the CLASS side so views can format an axis
	without inventing a node to ask."
	^ self class printMicros: micros on: aStream
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> printOn: aStream [
	aStream nextPutAll: self name; nextPutAll: ' ('.
	self printMicros: self durationMicros on: aStream.
	aStream nextPut: $)
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 13:09'
}
SWATraceNode >> printTraceOn: aStream relativeTo: zeroMicros [
	"Recursive worker for #traceString. Children are already in start order (the
	reconstruction preserves it), so no sorting here -- if this ever prints out of
	order, the bug is in SWATraceNode class>>fromLane:, not here."
	| indent |
	indent := self depth.
	aStream
		nextPutAll: ((self startMicros - zeroMicros) printPaddedWith: $  to: 9);
		nextPutAll: '  '.
	self printMicros: self durationMicros on: aStream.
	aStream
		nextPutAll: ' (self ';
		nextPutAll: self selfMicros printString;
		nextPutAll: ' us)  '.
	indent timesRepeat: [aStream nextPutAll: '  '].
	aStream nextPutAll: self name; cr.
	self children do: [:c | c printTraceOn: aStream relativeTo: zeroMicros]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> process [
	"The Process this span ran in -- inherited from my lane root if I am a span."
	^ process ifNil: [parent ifNotNil: [:p | p process]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:04'
}
SWATraceNode >> process: aProcess [
	process := aProcess
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> selfMicros [
	"Duration minus everything my instrumented children took -- the part of this call
	that is genuinely mine. Computed, not stored: the tree already knows it, and a
	stored copy would drift the moment the tree is pruned or filtered.

	Note that only INSTRUMENTED children are subtracted, so self time here silently
	includes every call into an unwatched package."
	^ self durationMicros - (self children inject: 0 into: [:s :c | s + c durationMicros])
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> selfSize [
	^ self selfMicros max: 0
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:07'
}
SWATraceNode >> shapeOfSelectors [
	"My subtree as nested Arrays of bare selector Symbols -- #(#top (#a (#leaf))) --
	so a captured trace can be compared against a shape written down beforehand
	instead of against its own output. Structure only: no times, so the comparison
	is deterministic."
	| sel |
	sel := (self name copyAfterLast: $>) asSymbol.
	^ (Array with: sel) , (self children collect: [:c | c shapeOfSelectors])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> start: t0 stop: t1 [
	startMicros := t0.
	stopMicros := t1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> startMicros [
	"Absolute utcMicrosecondClock at entry. A lane root derives it from its children."
	startMicros ifNotNil: [^ startMicros].
	self children isEmpty ifTrue: [^ 0].
	^ startMicros := self children inject: self children first startMicros into: [:m :c |
		m min: c startMicros]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> stopMicros [
	"Absolute utcMicrosecondClock at exit. A lane root derives it from its children."
	stopMicros ifNotNil: [^ stopMicros].
	self children isEmpty ifTrue: [^ self startMicros].
	^ stopMicros := self children inject: self children first stopMicros into: [:m :c |
		m max: c stopMicros]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWATraceNode >> totalSize [
	"Generic treemap/flamegraph weight = duration. Clamped to at least 1 so a
	sub-microsecond call does not vanish from a weight-driven view (it is still
	culled by minimum pixel width in the trace view, which is a layout decision, not
	a data one)."
	^ self durationMicros max: 1
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:05'
}
SWATraceNode >> traceString [
	"The whole subtree as indented text -- the cheapest honest check that capture and
	reconstruction agree, and the thing to read before trusting any drawing.

	Columns: offset from the start of the trace, duration, self time, then the call
	indented by depth. Offsets are relative so the numbers are readable; the absolute
	clock is in #startMicros if you need it."
	^ String streamContents: [:s | self printTraceOn: s relativeTo: self startMicros]
]
