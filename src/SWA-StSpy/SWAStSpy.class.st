"
Drives the external `st-spy` profiler and turns its chrome-trace output into a sampled call tree (SWAStSpyNode) viewable in the SWA Explorer and TreeMap.

st-spy is an external py-spy-style sampler for OpenSmalltalk VMs (see /home/jens/lively4/st-spy). It is run under sudo (passwordless NOPASSWD rule on the binary path) and writes a chrome://tracing JSON flamechart: nested B/E (begin/end) events carrying entry/exit timestamps, with consecutive identical stacks coalesced into one span. Frames are therefore weighted by WALL TIME (microseconds), not raw sample counts.

NON-BLOCKING by design. #record launches st-spy detached and returns at once; it does NOT freeze the calling process or the UI while sampling. Use one of:

	""non-blocking, auto-open both views when ready""
	SWAStSpy recordSelfFor: 10.

	""non-blocking, profile another VM, run your own block when ready""
	(SWAStSpy onPid: 12345 duration: 10)
		record;
		whenReadyDo: [:spy | spy openTreemap].

	""explicit non-blocking open""
	(SWAStSpy onPid: 12345 duration: 10) recordThenOpen.

	""synchronous (scripts/headless only -- blocks the caller!)""
	| spy |
	spy := SWAStSpy onPid: 12345 duration: 10.
	spy record; waitForTrace; openExplorer; openTreemap.

	""from an existing trace file, no recording""
	(SWAStSpy new parseTraceFile: '/tmp/opencode/trace.json') openExplorer; openTreemap.

Lifecycle: #record -> (st-spy runs ~duration s) -> #isReady becomes true -> #buildTree parses + folds the flamechart into #rootNode (a SWAStSpyNode). #whenReadyDo: forks a background poller that builds the tree and runs your block via WorldState addDeferredUIMessage:, so view-opening happens safely on the UI process.

Self-profiling note: when pid is this image's own pid, st-spy still briefly pauses the VM per sample, but because it runs detached the image stays responsive.

The path to the st-spy binary is in SWAStSpy class>>stSpyBinary.
"
Class {
	#name : #SWAStSpy,
	#superclass : #Object,
	#instVars : [
		'pid',
		'duration',
		'rate',
		'outputFile',
		'rootNode',
		'events',
		'sampleCount',
		'launchTime',
		'showProgress'
	],
	#category : #'SWA-StSpy',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:02'
}
SWAStSpy class >> initialize [
	"Register the Apps-menu entry for st-spy self profiling.
	Idempotent: removes any prior entry for this receiver first."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'st-spy Self Profile'.
		{self. #open}.
		'Sample this image for 10s with st-spy and open a flamegraph' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:58'
}
SWAStSpy class >> onPid: anInteger duration: seconds [
	^ self new pid: anInteger; duration: seconds; yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:44'
}
SWAStSpy class >> open [
	"Apps-menu entry point: profile THIS image for 10 seconds (non-blocking, with
	the morphic progress bar) and auto-open the flamegraph when ready. Mirrors
	`SWAStSpy recordSelfFor: 10`."
	^ self recordSelfFor: 10
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/22/2026 14:03'
}
SWAStSpy class >> recordSelfFor: seconds [
	"Convenience, NON-BLOCKING: profile THIS image for `seconds` at the default
	100 Hz, then auto-open the flamegraph. Returns the SWAStSpy immediately (its
	rootNode is nil until recording completes)."
	^ self recordSelfFor: seconds atRate: 100
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/22/2026 14:03'
}
SWAStSpy class >> recordSelfFor: seconds atRate: hz [
	"Convenience, NON-BLOCKING: profile THIS image for `seconds` at `hz` samples
	per second, then auto-open the flamegraph. Each sample pauses the VM ~0.5 ms,
	so e.g. 500 Hz ~= 25% pause time; the ceiling is ~2000 Hz. Returns the SWAStSpy
	immediately (its rootNode is nil until recording completes)."
	^ self new duration: seconds; rate: hz; recordThenOpen; yourself
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:27'
}
SWAStSpy class >> stSpyBinary [
	"Command used to invoke st-spy. './st-spy' resolves against the VM's working
	directory (/home/jens/lively4/squeak) and matches a passwordless sudo NOPASSWD
	rule for that exact path, so #record can run it without a tty password prompt."
	^ './st-spy'
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:02'
}
SWAStSpy class >> unload [
	"Remove the Apps-menu entry when the package is unloaded."
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:05'
}
SWAStSpy >> buildTree [
	"Parse the (finished) trace file and fold it into the call tree. Assumes
	#isReady. Returns the rootNode."
	self parseTrace.
	^ self buildTreeFromEvents
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:01'
}
SWAStSpy >> buildTreeFromEvents [
	"Fold the flat flamechart B/E event stream into a merged call tree of
	SWAStSpyNode, weighting frames by TIME (microseconds), not raw event counts.

	st-spy emits a chrome flamechart: each 'B' carries the frame's entry ts and
	each matching 'E' its exit ts, and consecutive identical stacks are coalesced
	into one long B..E span. So the meaningful weight is wall-clock time a frame
	was on the stack: total = E.ts - B.ts, and self = total minus the time spent
	in its children.

	We keep three parallel stacks: the live cursor path (nodes), each frame's
	entry ts, and a per-frame accumulator of time already attributed to its
	children. On 'E' we pop, compute this frame's span, credit (span - childTime)
	as self time to the node, and add the full span to the parent's child-time
	accumulator. selfCount/totalCount thus hold microseconds."
	| root cursor nodeStack tsStack childTimeStack |
	root := SWAStSpyNode new name: 'root'.
	cursor := root.
	nodeStack := OrderedCollection new.
	tsStack := OrderedCollection new.
	childTimeStack := OrderedCollection new.
	events do: [:ev |
		(ev at: 'ph') = 'B'
			ifTrue: [ | child |
				child := cursor childNamed: (ev at: 'name').
				(ev at: 'args' ifAbsent: [nil]) ifNotNil: [:args |
					child filename isNil ifTrue: [
						child filename: (args at: 'filename' ifAbsent: [nil])]].
				nodeStack addLast: cursor.
				tsStack addLast: (ev at: 'ts').
				childTimeStack addLast: 0.
				cursor := child]
			ifFalse: [
				tsStack isEmpty ifFalse: [ | entryTs span childTime selfTime |
					entryTs := tsStack removeLast.
					childTime := childTimeStack removeLast.
					span := (ev at: 'ts') - entryTs.
					selfTime := (span - childTime) max: 0.
					cursor addSelfTime: selfTime.
					"attribute our whole span to our parent's child-time bucket"
					childTimeStack isEmpty
						ifFalse: [childTimeStack at: childTimeStack size
									put: (childTimeStack last + span)].
					cursor := nodeStack removeLast]]].
	root rollUpTotals.
	rootNode := root.
	sampleCount := root totalCount.
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> duration [
	^ duration
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> duration: seconds [
	duration := seconds
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:12'
}
SWAStSpy >> errorText [
	"The trimmed st-spy error log, for reporting."
	^ self logContents withBlanksTrimmed
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:29'
}
SWAStSpy >> failed [
	"True if st-spy reported a fatal error (e.g. the target pid does not exist, or
	sudo/permission failed) and will never produce a trace. Guard against false
	positives: the success line 'Samples: N Errors: 0' contains 'Errors', and a
	completed run is never a failure."
	| log |
	self isReady ifTrue: [^ false].
	log := self logContents asLowercase.
	log isEmpty ifFalse: [
		"Any of these in the log mean st-spy launched but bailed out fatally."
		^ (#('error:' 'permission denied' 'a password is required'
			'no such process' 'operation not permitted' 'failed to'
			'panicked') anySatisfy: [:needle | log includesSubstring: needle])].
	"Empty log: st-spy may simply not have started writing yet. Only treat an
	empty log as a failure once enough time has passed that it SHOULD have written
	its startup banner -- otherwise it is just 'not ready yet'."
	^ launchTime notNil
		and: [DateAndTime now > (launchTime + 8 seconds)]
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:29'
}
SWAStSpy >> failureReason [
	"A human-readable explanation for why no trace appeared, for the warning
	dialog. Distinguishes the three observed failure modes: st-spy launched and
	logged an error, st-spy never wrote anything (likely sudo/ptrace never ran),
	or it simply ran out of time while still working."
	| log |
	log := self logContents.
	log withBlanksTrimmed isEmpty ifTrue: [
		^ 'st-spy wrote NOTHING to its log -- it never started.',
			String cr,
			'Likely causes: sudo -n needed a password (no NOPASSWD match for ',
			self class stSpyBinary, '), the VM cwd is not ',
			'/home/jens/lively4/squeak, or a prior st-spy still holds ptrace on pid ',
			pid printString, '.', String cr, String cr,
			'Command was:', String cr, self recordCommand].
	(self failed) ifTrue: [
		^ 'st-spy reported an error:', String cr, String cr, self errorText].
	^ 'Timed out after ', (duration + 20) printString,
		's but st-spy was still running (no completion marker).', String cr, String cr,
		'Log so far:', String cr, self errorText
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:33'
}
SWAStSpy >> initialize [
	super initialize.
	pid := OSProcess thisOSProcess pid.   "default: profile self"
	duration := 10.
	rate := 100.
	sampleCount := 0.
	showProgress := true   "coarse 1s progress ticks (slightly perturbs measurement)"
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:05'
}
SWAStSpy >> isReady [
	"True once st-spy has finished and written the completion marker to its log.
	More reliable than checking file existence, since the file is created early."
	| log |
	log := self outputFile, '.log'.
	(FileDirectory default fileOrDirectoryExists: log) ifFalse: [^ false].
	^ ([(FileStream readOnlyFileNamed: log) contentsOfEntireFile]
		on: Error do: [:e | '']) includesSubstring: 'Wrote chrome trace'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:30'
}
SWAStSpy >> launchTime [
	"When #record last launched st-spy (nil if never launched). Used by #failed to
	avoid treating a momentarily-empty log as a failure before st-spy has had time
	to write its startup banner."
	^ launchTime
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:12'
}
SWAStSpy >> logContents [
	"Current contents of st-spy's stdout/stderr log, or '' if not yet present."
	| log |
	log := self outputFile, '.log'.
	(FileDirectory default fileOrDirectoryExists: log) ifFalse: [^ ''].
	^ [(FileStream readOnlyFileNamed: log) contentsOfEntireFile]
		on: Error do: [:e | '']
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> openExplorer [
	"Open an ObjectExplorer on the call tree, hottest frames first. The
	SWAStSpyNode explorer protocol drives the disclosure/labels."
	| window |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	window := rootNode explore.
	^ window
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:56'
}
SWAStSpy >> openFlamegraph [
	"Open a flamegraph on the call tree (same SWAStSpyNode tree the treemap uses).
	The shared SWANavPanel supplies the window chrome (Back/Browse/Show + breadcrumb
	+ selection-detail line + meta-info line + toggleable source pane). Single click
	selects a frame; clicking it again zooms in; Back zooms out; Browse opens a
	system browser on the selected Smalltalk method; Show toggles the source pane;
	right-click explores. Returns the window."
	| flame panel window |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	flame := SWAStSpyFlamegraphMorph on: rootNode.
	flame metaInfo: 'pid ', pid printString,
		'   ', (rootNode formatMicros: sampleCount), ' total',
		'   ', sampleCount printString, ' samples',
		'   ', rate printString, ' Hz'.

	panel := SWANavPanel on: flame.

	window := panel openInWindow.
	window setLabel: 'st-spy Flamegraph  ', (rootNode formatMicros: sampleCount),
		'  (pid ', pid printString, ')'.
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:57'
}
SWAStSpy >> openTreemap [
	"Open a squarified treemap of the call tree (tiles sized by wall time), using
	the shared SWANavPanel window chrome (Back/Browse/Show + breadcrumb +
	selection-path + meta-info line + hover overlay)."
	| treemap overlay panel window |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	treemap := SWAStSpyTreemapMorph on: rootNode.
	treemap extent: (Display extent * 0.7) rounded.

	overlay := SWAStSpyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := SWANavPanel on: treemap.

	window := panel openInWindow.
	window setLabel: 'st-spy Treemap  ', (rootNode formatMicros: sampleCount), '  (pid ', pid printString, ')'.
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> outputFile [
	"The chrome-trace JSON path st-spy writes to (defaults under /tmp/opencode)."
	^ outputFile ifNil: [outputFile :=
		'/tmp/opencode/stspy-', pid printString, '-',
		(DateAndTime now asUnixTime) printString, '.json']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> outputFile: aPathString [
	outputFile := aPathString
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> parseTrace [
	"Read and JSON-parse the chrome-trace file into `events` (an Array of
	Dictionaries with at least 'ph', 'name', 'ts')."
	| contents |
	contents := (FileStream readOnlyFileNamed: self outputFile) contentsOfEntireFile.
	events := STONJSON fromString: contents.
	^ events
]

{
	#category : #parsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> parseTraceFile: aPathString [
	"Build the tree from an existing chrome-trace file (skip recording)."
	outputFile := aPathString.
	self parseTrace.
	self buildTreeFromEvents.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:58'
}
SWAStSpy >> pid [
	^ pid
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> pid: anInteger [
	pid := anInteger
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:02'
}
SWAStSpy >> printOn: aStream [
	aStream
		nextPutAll: 'SWAStSpy(pid ';
		print: pid;
		nextPutAll: ', ';
		print: duration;
		nextPutAll: 's req'.
	rootNode ifNotNil: [
		aStream nextPutAll: ', '; nextPutAll: (rootNode formatMicros: sampleCount), ' traced'].
	aStream nextPut: $)
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> rate: samplesPerSecond [
	rate := samplesPerSecond
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:29'
}
SWAStSpy >> record [
	"Launch st-spy detached in the background and return IMMEDIATELY -- this does
	NOT block the calling process or the UI. The trace is written asynchronously
	over the next `duration` seconds.

	To act on the result, either:
	  - poll #isReady / call #buildWhenReady from your own logic, or
	  - use #whenReadyDo: to run a block when the trace lands, or
	  - use #recordThenOpen to auto-open the views when ready, or
	  - call #waitForTrace if you really want to block synchronously.
	Returns self."
	outputFile := nil.   "force a fresh timestamped file for this run"
	self outputFile.
	rootNode := nil.
	events := nil.
	launchTime := DateAndTime now.
	PipeableOSProcess command: self recordCommand.
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> recordCommand [
	"The shell command that runs st-spy detached in the background, writing a
	chrome trace to #outputFile and its log alongside. Backgrounded with & so the
	calling image is not blocked while st-spy samples."
	| log |
	log := self outputFile, '.log'.
	^ 'sudo -n ', self class stSpyBinary,
		' record -f chrometrace',
		' -d ', duration printString,
		' -r ', rate printString,
		' -o ', self outputFile,
		' --pid ', pid printString,
		' > ', log, ' 2>&1 &'
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:34'
}
SWAStSpy >> recordThenOpen [
	"Non-blocking: start recording and arrange for the Flamegraph to open
	automatically once the trace is ready. Returns immediately."
	self record.
	self whenReadyDo: [:spy | spy openFlamegraph].
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> rootNode [
	"The SWAStSpyNode call tree (nil until #record / #buildTreeFromEvents)."
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:59'
}
SWAStSpy >> sampleCount [
	"Number of samples folded into the tree (root totalCount)."
	^ sampleCount
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:33'
}
SWAStSpy >> showProgress [
	"Whether #whenReadyDo: emits a coarse 1s progress tick to the Transcript while
	st-spy records. ON by default; this slightly perturbs the measurement (the
	poller wakes once a second and writes), so turn it OFF for the most accurate
	self-profiles."
	^ showProgress ifNil: [showProgress := true]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:34'
}
SWAStSpy >> showProgress: aBoolean [
	"Set whether to emit coarse 1s progress ticks while recording. Default true."
	showProgress := aBoolean
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:05'
}
SWAStSpy >> traceFileReady [
	"Backwards-compatible alias for #isReady."
	^ self isReady
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:30'
}
SWAStSpy >> waitForTrace [
	"SYNCHRONOUS: block the calling process until the trace is ready, then build
	the tree. Use only from scripts/headless where blocking is acceptable; from
	the UI prefer #whenReadyDo: / #recordThenOpen. Returns self."
	| deadline |
	deadline := DateAndTime now + (duration + 20) seconds.
	[self isReady or: [self failed or: [DateAndTime now > deadline]]]
		whileFalse: [(Delay forMilliseconds: 250) wait].
	self isReady
		ifFalse: [^ self error: 'st-spy produced no trace. ', self failureReason].
	self buildTree.
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:37'
}
SWAStSpy >> waitQuietly [
	"Block the current (background) process polling until st-spy is ready, has
	failed, or the deadline passes. No UI. Returns self."
	| deadline |
	deadline := DateAndTime now + (duration + 20) seconds.
	[self isReady or: [self failed or: [DateAndTime now > deadline]]]
		whileFalse: [(Delay forMilliseconds: 250) wait].
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:39'
}
SWAStSpy >> waitWithProgress [
	"Like #waitQuietly, but drive the standard morphic SystemProgressMorph (the bar
	at the bottom of the World) so recording is visible without touching the
	Transcript. All Morphic mutation (open / update value / close) is pushed to the
	UI process via WorldState addDeferredUIMessage:, because SystemProgressMorph
	adds/deletes submorphs and must not be poked from this background process (that
	leaves ghost labels). We poll here once a second and forward progress.

	SystemProgressMorph's creation method returns a one-arg BLOCK (`barBlock`):
	`barBlock value: aNumber` advances the bar, and `SystemProgressMorph close:
	barBlock` tears the slot down. We keep that block in a holder and only ever
	#value: / #close: it from the UI process.

	As noted, the once-a-second wake-up slightly perturbs the measurement -- use
	#showProgress: false for a clean profile. Returns self."
	| deadline holder lastTick |
	deadline := DateAndTime now + (duration + 20) seconds.
	holder := Array with: nil.
	"Open the bar on the UI process; stash the returned bar-block."
	WorldState addDeferredUIMessage: [
		holder at: 1 put:
			(SystemProgressMorph
				position: nil
				label: 'st-spy: profiling pid ', pid printString
				min: 0
				max: duration)].
	lastTick := -1.
	[self isReady or: [self failed or: [DateAndTime now > deadline]]]
		whileFalse: [
			| elapsed barBlock |
			elapsed := (DateAndTime now - launchTime) asSeconds.
			elapsed > lastTick ifTrue: [
				lastTick := elapsed.
				barBlock := holder at: 1.
				barBlock ifNotNil: [
					WorldState addDeferredUIMessage: [
						barBlock value: (elapsed min: duration)]]].
			(Delay forMilliseconds: 250) wait].
	"Close the bar on the UI process."
	WorldState addDeferredUIMessage: [
		(holder at: 1) ifNotNil: [:barBlock |
			SystemProgressMorph close: barBlock]].
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 13:37'
}
SWAStSpy >> whenReadyDo: aBlock [
	"Fork a low-priority background process that waits (without blocking the
	caller or the UI) until the trace is ready, builds the call tree, then
	evaluates aBlock with this SWAStSpy on the UI process. If st-spy fails early
	(bad pid, permission, etc.) or times out, pops up a visible warning instead.
	While recording, shows a morphic SystemProgressMorph (the standard bar at the
	bottom of the World) updated once a second, unless #showProgress is false.
	Returns self immediately."
	[self showProgress
		ifTrue: [self waitWithProgress]
		ifFalse: [self waitQuietly].
	self isReady
		ifTrue: [
			self buildTree.
			WorldState addDeferredUIMessage: [aBlock value: self]]
		ifFalse: [
			WorldState addDeferredUIMessage: [
				self inform: 'st-spy did not produce a trace (pid ', pid printString, ').',
					String cr, String cr, self failureReason]]]
		forkAt: Processor userBackgroundPriority.
	^ self
]
