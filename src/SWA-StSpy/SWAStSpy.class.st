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
		'sampleCount'
	],
	#category : #'SWA-StSpy',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:58'
}
SWAStSpy class >> onPid: anInteger duration: seconds [
	^ self new pid: anInteger; duration: seconds; yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:06'
}
SWAStSpy class >> recordSelfFor: seconds [
	"Convenience, NON-BLOCKING: profile THIS image for `seconds` and auto-open
	both views when the trace is ready. Returns the SWAStSpy immediately (its
	rootNode is nil until recording completes)."
	^ self new duration: seconds; recordThenOpen; yourself
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:28'
}
SWAStSpy >> failed [
	"True if st-spy reported a fatal error (e.g. the target pid does not exist, or
	sudo/permission failed) and will never produce a trace. Guard against false
	positives: the success line 'Samples: N Errors: 0' contains 'Errors', and a
	completed run is never a failure."
	| log |
	self isReady ifTrue: [^ false].
	log := self logContents.
	^ (log includesSubstring: 'Error:')
		or: [log includesSubstring: 'error:']
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:58'
}
SWAStSpy >> initialize [
	super initialize.
	pid := OSProcess thisOSProcess pid.   "default: profile self"
	duration := 10.
	rate := 100.
	sampleCount := 0
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWAStSpy >> openFlamegraph [
	"Open a flamegraph on the call tree (same SWAStSpyNode tree the treemap uses),
	with the same window chrome as the treemap: Back + Browse buttons + breadcrumb
	header and a selection-path line. Single click selects a frame (highlight +
	path); clicking the same frame again zooms in; Back zooms out; Browse opens a
	system browser on the selected Smalltalk method; right-click explores. Returns
	the window."
	| flame breadcrumb selectionPath panel window headerRow backButton browseButton |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	flame := SWAStSpyFlamegraphMorph on: rootNode.

	backButton := SimpleButtonMorph new
		label: 'Back';
		color: (Color gray: 0.3);
		target: flame;
		actionSelector: #zoomOut;
		yourself.
	browseButton := SimpleButtonMorph new
		label: 'Browse';
		color: (Color gray: 0.3);
		target: flame;
		actionSelector: #browseSelected;
		yourself.
	breadcrumb := StringMorph new
		contents: flame breadcrumbString;
		font: Preferences standardSystemFont;
		color: Color white;
		yourself.
	flame breadcrumbMorph: breadcrumb.
	selectionPath := StringMorph new
		contents: '';
		font: Preferences standardSystemFont;
		color: (Color gray: 0.7);
		yourself.
	flame selectionPathMorph: selectionPath.

	headerRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	backButton hResizing: #rigid; vResizing: #rigid.
	browseButton hResizing: #rigid; vResizing: #rigid.
	breadcrumb hResizing: #spaceFill; vResizing: #rigid.
	headerRow addMorph: backButton; addMorph: browseButton; addMorph: breadcrumb.

	panel := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		yourself.
	selectionPath hResizing: #spaceFill; vResizing: #rigid.
	flame hResizing: #spaceFill; vResizing: #spaceFill.
	panel addMorph: headerRow; addMorph: selectionPath; addMorph: flame.

	window := panel openInWindow.
	window setLabel: 'st-spy Flamegraph  ', (rootNode formatMicros: sampleCount),
		'  (pid ', pid printString, ')'.
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:02'
}
SWAStSpy >> openTreemap [
	"Open a squarified treemap of the call tree (tiles sized by wall time),
	reusing the shared SWA treemap window chrome (breadcrumb, back button,
	selection path, hover overlay)."
	| treemap overlay breadcrumb selectionPath panel window headerRow backButton |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	treemap := SWAStSpyTreemapMorph on: rootNode.
	treemap extent: (Display extent * 0.7) rounded.

	backButton := SimpleButtonMorph new
		label: 'Back';
		color: (Color gray: 0.3);
		target: treemap;
		actionSelector: #zoomOut;
		yourself.
	breadcrumb := StringMorph new
		contents: treemap breadcrumbString;
		font: Preferences standardSystemFont;
		color: Color white;
		yourself.
	treemap breadcrumbMorph: breadcrumb.
	selectionPath := StringMorph new
		contents: '';
		font: Preferences standardSystemFont;
		color: (Color gray: 0.7);
		yourself.
	treemap selectionPathMorph: selectionPath.
	headerRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	backButton hResizing: #rigid; vResizing: #rigid.
	breadcrumb hResizing: #spaceFill; vResizing: #rigid.
	headerRow addMorph: backButton; addMorph: breadcrumb.

	overlay := SWAStSpyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		yourself.
	selectionPath hResizing: #spaceFill; vResizing: #rigid.
	treemap hResizing: #spaceFill; vResizing: #spaceFill.
	panel addMorph: headerRow; addMorph: selectionPath; addMorph: treemap.

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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:05'
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:06'
}
SWAStSpy >> recordThenOpen [
	"Non-blocking: start recording and arrange for the Explorer + TreeMap to open
	automatically once the trace is ready. Returns immediately."
	self record.
	self whenReadyDo: [:spy | spy openExplorer. spy openTreemap].
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
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:05'
}
SWAStSpy >> traceFileReady [
	"Backwards-compatible alias for #isReady."
	^ self isReady
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:06'
}
SWAStSpy >> waitForTrace [
	"SYNCHRONOUS: block the calling process until the trace is ready, then build
	the tree. Use only from scripts/headless where blocking is acceptable; from
	the UI prefer #whenReadyDo: / #recordThenOpen. Returns self."
	| deadline |
	deadline := DateAndTime now + (duration + 20) seconds.
	[self isReady or: [DateAndTime now > deadline]]
		whileFalse: [(Delay forMilliseconds: 250) wait].
	self isReady
		ifFalse: [^ self error: 'st-spy produced no trace; see ', self outputFile, '.log'].
	self buildTree.
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:12'
}
SWAStSpy >> whenReadyDo: aBlock [
	"Fork a low-priority background process that waits (without blocking the
	caller or the UI) until the trace is ready, builds the call tree, then
	evaluates aBlock with this SWAStSpy on the UI process. If st-spy fails early
	(bad pid, permission, etc.) or times out, pops up a visible warning instead.
	Returns self immediately."
	| deadline |
	deadline := DateAndTime now + (duration + 20) seconds.
	[[self isReady or: [self failed or: [DateAndTime now > deadline]]]
		whileFalse: [(Delay forMilliseconds: 500) wait].
	self isReady
		ifTrue: [
			self buildTree.
			WorldState addDeferredUIMessage: [aBlock value: self]]
		ifFalse: [
			WorldState addDeferredUIMessage: [
				self inform: 'st-spy did not produce a trace (pid ', pid printString, ').',
					String cr, String cr,
					(self failed
						ifTrue: [self errorText]
						ifFalse: ['Timed out. See ', self outputFile, '.log'])]]]
		forkAt: Processor userBackgroundPriority.
	^ self
]
