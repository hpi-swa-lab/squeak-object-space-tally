"
In-image counterpart of SWASamplingTally: same flamegraph/treemap/explorer views, but the samples come from MessageTally instead of the external st-spy, so no OS process, no trace file, and frames are always resolvable Smalltalk methods.

MessageTally weights are sample counts; they are scaled to microseconds (samples * pollPeriod) so the shared SWASamplingTallyNode views can format them as durations.
"
Class {
	#name : #SWASamplingTracer,
	#superclass : #Object,
	#instVars : [
		'duration',
		'pollPeriod',
		'tally',
		'rootNode',
		'sampleCount',
		'launchTime',
		'showProgress'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer class >> initialize [
	"Apps-menu entry next to SWASamplingTally's. Idempotent: removes any prior
	entry for this receiver first."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Sampling Tracer (Message Tally)'.
		{self. #open}.
		'Sample this image for 10s with MessageTally and open a flamegraph' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer class >> open [
	"Apps-menu entry point."
	^ self recordSelfFor: 10
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer class >> recordSelfFor: seconds [
	"Non-blocking: sample this image for `seconds` and auto-open the flamegraph."
	^ self recordSelfFor: seconds every: MessageTally defaultPollPeriod
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer class >> recordSelfFor: seconds every: milliseconds [
	^ self new
		duration: seconds;
		pollPeriod: milliseconds;
		recordThenOpen
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer class >> unload [
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> addChildrenOf: aMessageTally to: aNode [
	"#childrenOver: appends a pseudo child carrying the hits that stayed in this
	frame itself, but only when there are real children -- a leaf answers #() and
	its whole tally is self time."
	| kids |
	kids := aMessageTally childrenOver: 0.
	kids isEmpty ifTrue: [
		^ aNode addSelfTime: aMessageTally tally * self microsPerSample].
	kids do: [:each |
		each isPrimitives
			ifTrue: [aNode addSelfTime: each tally * self microsPerSample]
			ifFalse: [self addChildrenOf: each to: (aNode childNamed: (self nameFor: each))]].
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> buildTree [
	"Fold the recorded MessageTally into the SWASamplingTallyNode tree the shared
	flamegraph/treemap render. MessageTally counts samples, the views format
	microseconds, so every weight is scaled by #microsPerSample."
	| root |
	tally ifNil: [^ self error: 'Nothing recorded yet -- send #record first'].
	root := SWASamplingTallyNode new name: 'root'.
	self addChildrenOf: tally to: root.
	root rollUpTotals.
	rootNode := root.
	sampleCount := root totalCount.
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> duration [
	^ duration
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> duration: seconds [
	duration := seconds.
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:33'
}
SWASamplingTracer >> initialize [
	super initialize.
	duration := 10.
	pollPeriod := MessageTally defaultPollPeriod.
	sampleCount := 0.
	showProgress := true.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> launchTime [
	^ launchTime
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> metaInfoString [
	^ 'MessageTally', 
		'   ', (rootNode formatMicros: sampleCount), ' total',
		'   ', (sampleCount // self microsPerSample) printString, ' samples',
		'   ', (1000 // pollPeriod) printString, ' Hz',
		'   ', tally time printString, ' ms elapsed'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> microsPerSample [
	^ pollPeriod * 1000
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> nameFor: aMessageTally [
	"'Class>>selector', the form SWASamplingTallyNode>>methodReference resolves.
	The defining class is used, not the receiver's, so browsing lands on the
	method that actually ran. Block frames merge into their home method."
	| m cls |
	m := aMessageTally method ifNil: [^ 'unknown'].
	cls := m methodClass ifNil: [^ m printString].
	m selector ifNil: [^ cls name asString].
	^ cls name asString, '>>', m selector
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> openExplorer [
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	^ rootNode explore
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> openFlamegraph [
	"Same view as SWASamplingTally, on the MessageTally-derived tree."
	| flame panel window |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	flame := SWASamplingTallyFlamegraphMorph on: rootNode.
	flame metaInfo: self metaInfoString.

	panel := SWAPane on: flame.

	window := panel openInWindow.
	window setLabel: 'Sampling Tracer Flamegraph  ', (rootNode formatMicros: sampleCount).
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #views,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> openTreemap [
	"Same view as SWASamplingTally, on the MessageTally-derived tree."
	| treemap overlay panel window |
	rootNode ifNil: [^ self error: 'No tree yet -- send #record first'].
	treemap := SWASamplingTallyTreemapMorph on: rootNode.
	treemap extent: (Display extent * 0.7) rounded.

	overlay := SWASamplingTallyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := SWAPane on: treemap.

	window := panel openInWindow.
	window setLabel: 'Sampling Tracer Treemap  ', (rootNode formatMicros: sampleCount).
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> pollPeriod [
	^ pollPeriod
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> pollPeriod: milliseconds [
	pollPeriod := milliseconds max: 1.
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:40'
}
SWASamplingTracer >> printOn: aStream [
	super printOn: aStream.
	aStream nextPutAll: '(', duration printString, 's @ ', (1000 // pollPeriod) printString, ' Hz'.
	rootNode ifNil: [aStream nextPutAll: ', not recorded yet']
		ifNotNil: [aStream nextPutAll: ', ', (rootNode formatMicros: sampleCount)].
	aStream nextPut: $).
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:34'
}
SWASamplingTracer >> record [
	"Sample every process of this image for `duration` seconds and fold the result
	into the call tree. BLOCKS the calling process for the whole duration -- use
	#recordThenOpen to keep the UI alive."
	MessageTally runningInstance ifNotNil: [
		^ self error: 'a MessageTally is already running'].
	rootNode := nil.
	launchTime := DateAndTime now.
	tally := MessageTally new.
	tally spyAllEvery: pollPeriod on: [
		showProgress ifTrue: [self waitWithProgress] ifFalse: [self waitQuietly]].
	^ self buildTree
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> recordThenOpen [
	"Non-blocking: sample in a forked process, open the flamegraph when done.
	The sampler runs at timingPriority-1, so the forked process' own priority
	only decides how much the tree building afterwards disturbs the UI."
	[self record.
	WorldState addDeferredUIMessage: [self openFlamegraph]]
		forkAt: Processor userBackgroundPriority.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> rootNode [
	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> sampleCount [
	^ sampleCount
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:33'
}
SWASamplingTracer >> showProgress [
	^ showProgress
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:33'
}
SWASamplingTracer >> showProgress: aBoolean [
	"The bar redraws once a second on the UI process, which this profiler samples
	along with everything else -- switch it off for a clean measurement."
	showProgress := aBoolean.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 11:39'
}
SWASamplingTracer >> tally [
	^ tally
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:33'
}
SWASamplingTracer >> waitQuietly [
	(Delay forSeconds: duration) wait.
	^ self
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:33'
}
SWASamplingTracer >> waitWithProgress [
	"Sit out the sampling window driving the standard SystemProgressMorph at the
	bottom of the World. All morphic mutation (open / value: / close:) is pushed to
	the UI process with WorldState addDeferredUIMessage:, because SystemProgressMorph
	adds and deletes submorphs and leaves ghost labels when poked from here.

	SystemProgressMorph's creation method answers a one-arg BLOCK: `barBlock value:
	aNumber` advances the bar, `SystemProgressMorph close: barBlock` tears the slot
	down. It is kept in a holder so only the UI process ever sends to it."
	| holder deadline lastTick |
	holder := Array with: nil.
	WorldState addDeferredUIMessage: [
		holder at: 1 put:
			(SystemProgressMorph
				position: nil
				label: 'MessageTally: sampling this image at ', (1000 // pollPeriod) printString, ' Hz'
				min: 0
				max: duration)].
	deadline := launchTime + duration seconds.
	lastTick := -1.
	[DateAndTime now < deadline] whileTrue: [
		| elapsed |
		elapsed := (DateAndTime now - launchTime) asSeconds.
		elapsed > lastTick ifTrue: [
			lastTick := elapsed.
			(holder at: 1) ifNotNil: [:barBlock |
				WorldState addDeferredUIMessage: [barBlock value: (elapsed min: duration)]]].
		(Delay forMilliseconds: 250) wait].
	WorldState addDeferredUIMessage: [
		(holder at: 1) ifNotNil: [:barBlock | SystemProgressMorph close: barBlock]].
	^ self
]
