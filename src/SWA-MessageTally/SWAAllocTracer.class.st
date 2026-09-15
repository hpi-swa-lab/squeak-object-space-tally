"
Allocation tracer: an allocation flamegraph for chosen classes.

The survivor diff (SWASurvivorDiff) shows WHICH objects survive a scavenge and WHO holds them (the reference graph). It cannot show WHO CREATED them -- a surviving Vector3 leaf has no call stack. This is the other half: instrument the constructor, and at each allocation fold the FULL live sender chain into a shared call tree keyed by Class>>selector, counting one allocation at the leaf. Roll up and open the existing flamegraph -- so 'which code paths allocate these Vector3s' reads exactly like a time profile, but the weight is allocations, not microseconds.

Aggregated by stack, not per object: a run makes millions of Vector3s but only a handful of distinct allocation stacks, so the tree stays small and nothing is retained (we record the STACK, never the object -- pinning the objects would be the SWAHeapDiff trap).

Instrumentation is the established SWAMethodWrapper path. The single funnel is Vector class>>new (Vector3, Matrix4x4, Quaternion and every Vector subclass route through it via `super new: numElements`), gated by a concrete-class filter so a trace armed for {Vector3. Matrix4x4} ignores the rest. #captureIn: runs inside the capturing layer's #withoutCapturing:, so the stack walk and tree sends here do not re-enter the wrapper.

Unlike SWATallyWrapper's call tree, the fold keeps EVERY sender frame, not only instrumented ones -- the point is to see the ordinary application code that allocates, which is never wrapped.
"
Class {
	#name : #SWAAllocTracer,
	#superclass : #SWAMethodWrapper,
	#classVars : [
		'AllocClassFilter',
		'AllocHashesByNode',
		'AllocRoot',
		'AllocSurvivalByNode',
		'AllocWatched',
		'Armed',
		'TracedClasses'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:42'
}
SWAAllocTracer class >> allocRoot [
	"The current allocation tree root (for tests/inspection), or nil."
	^ AllocRoot
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> armFor: aCollectionOfClasses [
	"Start tracing allocations of the given classes. Install ONE wrapper on the shared
	funnel Vector class>>new (every Vector subclass -- Vector3, Matrix4x4, Quaternion --
	is instantiated through it), gated by the class filter so only the requested classes
	are folded into the tree. Eviction is disabled (evictAt: nil): the funnel is far
	hotter than the 1000-call default valve, and a trace that evicts on the first frame
	is useless -- so the caller MUST #disarm to stop paying the per-send overhead."
	| funnels |
	self disarm.
	AllocRoot := SWASamplingTallyNode new name: 'allocations'; yourself.
	AllocClassFilter := IdentitySet withAll: aCollectionOfClasses.
	AllocHashesByNode := IdentityDictionary new.
	"Install a wrapper on each funnel the requested classes route through (Array via
	Array class>>new:, Vector subclasses via Vector class>>new). Eviction off: the
	default-off context gate (#isCapturing), not eviction, is what keeps the hot funnel
	cheap -- the wrapper is dormant outside a #captureDuring: region. AllocWatched holds
	the whole collection so #disarm uninstalls them all."
	funnels := self funnelsFor: AllocClassFilter.
	(self hasUniversalFunnel: funnels) ifTrue: [
		Transcript showln: '[SWAAllocTracer] WARNING: tracing through a UNIVERSAL funnel (Behavior>>new). Every allocation in the image pays the wrapper cost while armed -- keep this capture SHORT and be sure to #disarm.'].
	AllocWatched := funnels collect: [:assoc | | w |
		w := self new onClass: assoc key selector: assoc value; yourself.
		w evictAt: nil.
		w install.
		w].
	Armed := true.
	^ AllocWatched
]

{
	#category : #'context gate',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:23'
}
SWAAllocTracer class >> captureDuring: aBlock [
	"Run aBlock with the context gate ON for its dynamic extent in this process, so the
	installed funnel wrappers actually fold allocations WHILE aBlock runs and stay
	dormant everywhere else. Restores the previous value afterwards (nested regions are
	safe). This is the measuring window: keep it tight -- one method call, not a whole
	Morphic cycle -- and never let it span an MCP round-trip, or the reading side gets
	instrumented too."
	| proc prior |
	proc := Processor activeProcess.
	prior := proc environmentAt: self ifAbsent: [false].
	proc environmentAt: self put: true.
	^ aBlock ensure: [proc environmentAt: self put: prior]
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:24'
}
SWAAllocTracer class >> disarm [
	"Stop tracing: uninstall the funnel wrapper and roll up the tree totals. Idempotent.
	Answers the root node (or nil if never armed), ready for #openFlamegraph."
	AllocWatched ifNotNil: [:ws | ws do: [:w | w uninstall]. AllocWatched := nil].
	Armed := false.
	AllocRoot ifNotNil: [:r | r rollUpTotals].
	^ AllocRoot
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 16:53'
}
SWAAllocTracer class >> funnelSelectorFor: aClass [
	"The constructor selector a class is actually allocated through -- the choke point
	to wrap. Indexable classes (Array and subclasses) are built via #new: with a size;
	everything else (Vector subclasses, ExternalStructure subclasses, ...) funnels
	through #new. This is the one piece that can't be derived from the class alone --
	it's allocation-site knowledge -- so it lives in one small table. #funnelsFor: then
	auto-detects the IMPLEMENTOR of this selector, so no per-family branches are needed."
	(aClass == Array or: [aClass inheritsFrom: Array]) ifTrue: [^ #new:].
	^ #new
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:25'
}
SWAAllocTracer class >> funnelsFor: aClassSet [
	"The (metaclass -> constructor selector) funnels to wrap for the requested classes.
	Auto-detected: for each class we ask #funnelSelectorFor: which constructor it routes
	through (#new: for indexable/Array, #new otherwise), then walk to the class that
	actually IMPLEMENTS that selector -- the shared choke point. Vector3, Matrix4x4, ...
	all resolve to Vector class>>new; RlVector3 and other ExternalStructures resolve to
	ExternalStructure class>>new; Array to Array class>>new:. The Set dedups, so a whole
	family installs ONE wrapper. No per-family branches -- new Vector/ExternalStructure
	subclasses just work. A class whose implementor can't be found is skipped (documented,
	not an error).

	CAUTION -- universal funnels: a class with no dedicated allocator inherits the plain
	Behavior>>new, so its implementor resolves to Behavior (or Object class). Wrapping that
	traces EVERY plain #new in the whole image while armed, gated only by the class filter.
	That is intentionally allowed (a broad Code Map working set naturally lands here) but is
	HOT -- use it only for short one-shot captures and always #disarm. #hasUniversalFunnel:
	answers whether a funnel set includes such a choke point; #armFor: warns when it does."
	| funnels |
	funnels := Set new.
	aClassSet do: [:cls | | sel implementor |
		sel := self funnelSelectorFor: cls.
		implementor := cls class whichClassIncludesSelector: sel.
		implementor ifNotNil: [funnels add: implementor -> sel]].
	^ funnels
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> hasUniversalFunnel: aFunnelSet [
	"True if any funnel in the set is a universal allocator -- Behavior>>new or
	Object class>>new -- i.e. a choke point that fires on essentially every allocation in
	the image, not just the classes of interest. Such a set is correct but HOT: only the
	class filter keeps the tree clean, while the per-send wrapper cost is paid image-wide.
	Callers use this to warn and to insist on short, one-shot, #disarm-terminated captures."
	^ aFunnelSet anySatisfy: [:assoc |
		(assoc key == Behavior and: [assoc value == #new])
			or: [assoc key == Object class and: [assoc value == #new]]]
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:38'
}
SWAAllocTracer class >> initialize [
	"Register the Apps-menu entry, grouped with the other SWA tools. Idempotent.

		SWAAllocTracer initialize"
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Alloc Survival (30 steps)'.
		{self. #openMorphicStepsFlamegraph}.
		'Trace where the classes of interest (SWAAllocTracer tracedClasses; Vector3/Matrix4x4 by default, customizable via #traceClass:) are allocated over 30 Morphic cycles; flamegraph coloured red=kept / green=collected' }
]

{
	#category : #'context gate',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:23'
}
SWAAllocTracer class >> isCapturing [
	"True only inside a #captureDuring: region in THIS process. DEFAULT OFF: the hot path
	the wrapper consults answers false for every allocation the rest of the image makes
	(MCP server, Morphic, the render loop), so those pay only this one probe plus the
	primitive-fast forward -- which is what makes wrapping a class as hot as Array
	survivable. Only allocations that happen dynamically inside the profiled block are
	folded. Read straight from the process environment, no #value dispatch, so the guard
	stays as cheap as possible."
	^ (Processor activeProcess environmentAt: self ifAbsent: [false]) == true
]

{
	#category : #survival,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:41'
}
SWAAllocTracer class >> measureSurvival [
	"Scavenge, then work out for every allocation site how many of the objects it made
	are still alive -- its survival fraction, which #SWAAllocFlamegraphMorph colours by.

	Per LEAF: count the recorded hashes that are in the live-survivor set. Then roll the
	{survived. total} pair UP the tree so an inner frame's colour reflects the survival
	of everything allocated beneath it, not just at it. Must run after #disarm (the
	funnel wrapper gone) and with the traced objects' fates already decided -- i.e. the
	caller allocated, we scavenge here, whatever the caller no longer references dies."
	| survivors |
	AllocRoot ifNil: [^ self].
	Smalltalk garbageCollectMost.
	survivors := self survivorHashSetOfTracedClasses.
	AllocSurvivalByNode := IdentityDictionary new.
	"Seed leaves from the recorded hashes."
	AllocHashesByNode keysAndValuesDo: [:node :hashes | | lived |
		lived := hashes count: [:h | survivors includes: h].
		AllocSurvivalByNode at: node put: (Array with: lived with: hashes size)].
	"Roll up: each node's pair is its own plus all descendants'."
	self rollUpSurvivalOf: AllocRoot.
	^ self
]

{
	#category : #viewing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:46'
}
SWAAllocTracer class >> openFlamegraph [
	"Open the allocation flamegraph in the shared SWAPane chrome: each frame is a
	Class>>selector on the allocation stack, its width the number of allocations made
	beneath it, the deepest frames the allocated classes themselves. Click to select,
	again to zoom, Browse to open the allocating method, Show for source. Answers the
	window, or nil if nothing was traced."
	| root flame panel window total rootPair survPct |
	root := AllocRoot ifNil: [^ self inform: 'No allocation trace. Arm one first.'].
	root rollUpTotals.
	total := root totalCount.
	total = 0 ifTrue: [^ self inform: 'Allocation trace is empty (no matching allocations).'].
	"Survival colouring: SWAAllocFlamegraphMorph reads survivalFractionOf:. If survival
	was never measured (AllocSurvivalByNode nil) it falls back to neutral grey, so this
	still opens a usable name-agnostic flamegraph."
	flame := SWAAllocFlamegraphMorph on: root.
	rootPair := AllocSurvivalByNode ifNotNil: [:d | d at: root ifAbsent: [nil]].
	survPct := rootPair ifNil: ['retention n/a']
		ifNotNil: [:p | p second = 0 ifTrue: ['retention n/a']
			ifFalse: [((p first * 100.0 / p second) roundTo: 1) printString, '% retained (', p first printString, '/', p second printString, ' kept)']].
	flame metaInfo: total printString, ' allocations',
		'   ', survPct,
		'   classes: ', ((AllocClassFilter ifNil: [#()]) collect: [:c | c name]) asArray printString,
		'   [RED = kept (bad)   green = collected (good)   grey = stack]'.
	panel := SWAPane on: flame.
	window := panel openInWindow.
	window setLabel: 'Allocation Survival Flamegraph  (', total printString, ' allocs)'.
	window extent: (Display extent * 0.7) rounded.
	window center: Display center.
	^ window
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> openMorphicStepsFlamegraph [
	"Apps-menu action: trace allocations of the classes of interest (#tracedClasses)
	over 30 Morphic cycles and open the allocation flamegraph."
	^ self traceMorphicStepsThenOpen: 30
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:24'
}
SWAAllocTracer class >> recordAllocationOf: aClass from: aContext [
	"Fold one allocation into the shared tree. Walk the FULL sender chain (root..leaf),
	skipping the wrapper's own frames and the constructor funnel itself, then append the
	allocated class as the deepest node so the flamegraph reads 'this call path made N
	<Class>'. One #selfCount at the leaf; #rollUpTotals is deferred to disarm.

	Runs with the capturing layer suppressed (called from #captureIn:), so the
	Collection/Context sends here do not re-enter the wrappers."
	| keys ctx node |
	AllocRoot ifNil: [^ nil].
	keys := OrderedCollection new.
	ctx := aContext.
	[ctx notNil] whileTrue: [ | m cls |
		m := ctx method.
		m ifNotNil: [ | nonMeta |
			cls := m methodClass.
			nonMeta := cls theNonMetaClass.
			"Skip instrumentation frames so the tree shows application code, not the
			tracer: the whole SWAMethodWrapper hierarchy (run:with:in:, captureIn:,
			recordAllocationOf:from:), the capturing layer's DynamicVariable plumbing
			(SWACapturingLayer>>withoutCapturing: -> DynamicVariable>>value:during:), and
			the Vector new funnel itself."
			((nonMeta == SWAMethodWrapper or: [nonMeta inheritsFrom: SWAMethodWrapper])
				or: [(nonMeta == DynamicVariable or: [nonMeta inheritsFrom: DynamicVariable])
				or: [(cls == Vector class and: [m selector == #new])
				or: [(cls == Array class and: [m selector == #new:])
				or: [nonMeta == BlockClosure and: [m selector == #ensure:]]]]])
				ifFalse: [keys addFirst: cls name asString, '>>', m selector]].
		ctx := ctx sender].
	keys addLast: aClass name asString.
	node := AllocRoot.
	keys do: [:k | node := node childNamed: k].
	node bumpSelf.
	"Answer the leaf so the caller can attach the allocated object's identityHash to it
	(for the survival colouring). Returning the node avoids re-walking the stack."
	^ node
]

{
	#category : #recording,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:41'
}
SWAAllocTracer class >> recordHash: aHash forNode: aNode [
	"Remember that an object with this identityHash was allocated at aNode's site, so a
	post-scavenge survivor walk can tell how many of that site's objects lived. Stored
	per leaf node, not per object -- one small integer per allocation, no object retained
	(pinning the objects would be the SWAHeapDiff trap and would also keep them all alive
	across the scavenge we are about to measure)."
	AllocHashesByNode ifNil: [^ self].
	(AllocHashesByNode at: aNode ifAbsentPut: [OrderedCollection new]) add: aHash
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> resetTracedClasses [
	"Drop any explicit pinned set and go back to following the shared Code Map working set
	(see #tracedClasses / #workingSetClasses). Answers the current (now working-set) set."
	TracedClasses := nil.
	^ self tracedClasses
]

{
	#category : #survival,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:41'
}
SWAAllocTracer class >> rollUpSurvivalOf: aNode [
	"Bottom-up: aNode's {survived. total} is its own leaf pair (if any) plus every
	child's rolled-up pair. Answers the pair. Stored in AllocSurvivalByNode so the
	flamegraph reads it without touching SWASamplingTallyNode."
	| lived total own |
	own := AllocSurvivalByNode at: aNode ifAbsent: [nil].
	lived := own ifNil: [0] ifNotNil: [:p | p first].
	total := own ifNil: [0] ifNotNil: [:p | p second].
	aNode children do: [:c | | cp |
		cp := self rollUpSurvivalOf: c.
		lived := lived + cp first.
		total := total + cp second].
	^ AllocSurvivalByNode at: aNode put: (Array with: lived with: total)
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> stopTracingClass: aClass [
	"Remove a class of interest from the traced set. Answers the current set."
	self tracedClasses.
	TracedClasses remove: aClass ifAbsent: [].
	^ self tracedClasses
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> stopTracingPackage: aPackageNameOrGlob [
	"Remove a package glob from the SHARED Code Map working set (removes it from the Code Map
	too -- one source of truth). Idempotent. Clears any explicit pinned class set so tracing
	follows the working set again. Answers #tracedPackages."
	| globs |
	globs := self tracedPackages asOrderedCollection.
	globs remove: aPackageNameOrGlob ifAbsent: [].
	SWAPane codeMapWorkingSet: globs.
	TracedClasses := nil.
	^ self tracedPackages
]

{
	#category : #survival,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:41'
}
SWAAllocTracer class >> survivalFractionOf: aNode [
	"aNode's survived/total in [0,1], or nil if nothing was recorded there (so the view
	can fall back to a neutral colour rather than paint 0% for a frame with no data)."
	| p |
	AllocSurvivalByNode ifNil: [^ nil].
	p := AllocSurvivalByNode at: aNode ifAbsent: [^ nil].
	p second = 0 ifTrue: [^ nil].
	^ p first / p second
]

{
	#category : #survival,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:41'
}
SWAAllocTracer class >> survivorHashSetOfTracedClasses [
	"The identityHashes of every LIVE instance of a traced class, right now. Built after
	the scavenge: a recorded allocation whose hash is in here still exists, i.e. survived.

	Restricted to the traced classes (not the whole heap) on purpose: identityHash is 22
	bits and collides badly across millions of objects, but across a few thousand live
	Vector3/Matrix4x4 a collision is rare, so membership is a reliable survival test at
	this scale. Uses #allInstances per class -- a bounded walk, and the instances are not
	retained past building the hash set."
	| set |
	set := Set new: 4096.
	(AllocClassFilter ifNil: [#()]) do: [:cls |
		cls allInstancesDo: [:o | set add: o identityHash]].
	^ set
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:24'
}
SWAAllocTracer class >> traceBlock: aBlock for: aCollectionOfClasses [
	"THE safe way to trace a hot class (Array): arm, run aBlock with the context gate ON,
	disarm, measure survival -- all in one synchronous call. Only allocations made
	dynamically inside aBlock are folded; nothing outside (the MCP round-trip that reads
	the result, the render loop, Morphic) is instrumented, because the gate is default
	off and closes again before this method returns.

	This is why Array no longer hangs: the wrapper is installed the whole time but only
	AWAKE for the extent of aBlock. Answers self (send #openFlamegraph next)."
	self armFor: aCollectionOfClasses.
	[self captureDuring: [aBlock value]] ensure: [self disarm].
	self measureSurvival.
	^ self
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> traceClass: aClass [
	"Add a class of interest to the traced set (idempotent). Only classes with a known
	allocation funnel are actually caught -- Array (via Array class>>new:) and Vector
	subclasses (via Vector class>>new); see #funnelsFor:. Adding one with no funnel is
	harmless but records nothing for it. Answers the current set."
	self tracedClasses.
	(TracedClasses includes: aClass) ifFalse: [TracedClasses add: aClass].
	^ self tracedClasses
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> traceClasses: aCollection [
	"Replace the traced set outright. Answers the current set."
	TracedClasses := OrderedCollection withAll: aCollection.
	^ self tracedClasses
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:42'
}
SWAAllocTracer class >> traceMorphicStepsThenOpen: aCount [
	"Desktop one-shot: arm, drive aCount Morphic cycles, disarm, open the flamegraph.
	Runs in the UI process (a menu action does), so the cycles are well-defined between
	the loop's own. Answers the window."
	| world |
	world := ActiveWorld ifNil: [World].
	self armFor: self tracedClasses.
	"ensure: the hot funnel wrapper is ALWAYS uninstalled -- a stray wrapper on
	Vector class>>new with eviction disabled would tax every allocation forever."
	[world ifNotNil: [aCount timesRepeat: [world doOneCycleNow]]]
		ensure: [self disarm].
	"Scavenge and score survival AFTER the wrapper is gone, so the measurement walk does
	not itself get traced."
	self measureSurvival.
	^ self openFlamegraph
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> tracePackage: aPackageNameOrGlob [
	"Add a package (name or String>>match: glob) to the SHARED Code Map working set, so both
	the Code Map and this tracer start including it. Idempotent. Clears any explicit pinned
	class set (TracedClasses) so tracing follows the working set again. Answers #tracedPackages."
	| globs |
	globs := self tracedPackages asOrderedCollection.
	(globs includes: aPackageNameOrGlob) ifFalse: [globs add: aPackageNameOrGlob].
	SWAPane codeMapWorkingSet: globs.
	TracedClasses := nil.
	^ self tracedPackages
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:30'
}
SWAAllocTracer class >> traceXRFrames: aCount [
	"XR one-shot: arm, render exactly aCount frames from inside a between-frame action
	(render loop blocked, we drive with doOneCycle), disarm, open the flamegraph. Same
	frame-exact placement the heap diff uses. Answers nil if there is no world."
	^ self traceXRFrames: aCount for: self tracedClasses
]

{
	#category : #controlling,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:30'
}
SWAAllocTracer class >> traceXRFrames: aCount for: aCollectionOfClasses [
	"XR one-shot: from inside a between-frame action (render loop blocked, we drive the
	frames), arm, render aCount frames WITH THE CONTEXT GATE ON, disarm, measure, open.

	The #captureDuring: is essential and is what makes tracing Array here safe: the gate
	is on ONLY in this (world) process for the extent of the rendered frames, so the
	concurrent MCP server and UI process -- different processes, gate off there -- do not
	get their Arrays folded even though the wrapper is installed. Keep aCount small for
	Array: every Array the render path allocates is folded, and the post-frame survivor
	walk is a full Array-instances sweep (~40 ms desktop, more on Quest). Answers nil if
	there is no world."
	| world |
	world := SRWorld current ifNil: [^ nil].
	^ world addDeferredFrameMessage: [
		self armFor: aCollectionOfClasses.
		"ensure: uninstall even if a frame raises."
		[self captureDuring: [aCount timesRepeat: [world doOneCycle]]]
			ensure: [self disarm].
		self measureSurvival.
		self openFlamegraph]
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> tracedClasses [
	"The classes the menu entries trace -- the 'classes of interest'. By DEFAULT this is the
	shared Code Map working set (SWAPane class>>codeMapWorkingSet), expanded to its classes by
	#workingSetClasses: what you are developing in is what you trace, and editing the working
	set (here via #tracePackage:, or in the Code Map, or in Preferences) moves both in lockstep.

	#traceClasses: / #traceClass: pin an explicit set instead, stored in the TracedClasses
	class var, which then overrides the working set until #resetTracedClasses clears it (back
	to following the working set). Only funnel-able classes actually record (see #funnelsFor:).

	Answers a copy as an Array so callers cannot mutate the live set by side effect."
	^ TracedClasses
		ifNil: [self workingSetClasses asArray]
		ifNotNil: [TracedClasses asArray]
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:26'
}
SWAAllocTracer class >> tracedPackages [
	"The package globs currently traced -- literally the shared Code Map working set
	(SWAPane class>>codeMapWorkingSet), split into a list. There is no separate tracer-owned
	package list: the working set IS the source of truth, so this and the Code Map always
	agree. Answers an Array of glob strings, e.g. #('Raylib' 'Morphic' 'SqueakXR' 'SWAGame')."
	^ (SWACodeRootNode globsFrom: SWAPane codeMapWorkingSet) asArray
]

{
	#category : #'context gate',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:24'
}
SWAAllocTracer class >> withGateOff: aBlock [
	"Run aBlock with the context gate forced OFF, restoring it after. Wraps the fold and
	the hash record, which themselves allocate (OrderedCollection, childNamed:, the hash
	bucket) -- without this those allocations would re-enter the wrapper while capturing
	and recurse. The COP #withoutCapturing: analogue, but for our own default-off gate."
	| proc prior |
	proc := Processor activeProcess.
	prior := proc environmentAt: self ifAbsent: [false].
	proc environmentAt: self put: false.
	^ aBlock ensure: [proc environmentAt: self put: prior]
]

{
	#category : #'traced classes',
	#'squeak_changestamp' : 'MCPServer 9/15/2026 17:12'
}
SWAAllocTracer class >> workingSetClasses [
	"The classes to trace, derived live from the shared Code Map working set
	(SWAPane class>>codeMapWorkingSet -- a comma-separated list of String>>match: globs,
	e.g. 'Raylib, SqueakXR, SWAGame'). We reuse the SAME package scope the Code Map shows,
	so 'what I am developing in' is 'what I trace'. Expansion is live: edit the working set
	(here via #tracePackage: or in the Code Map) and the traced set follows.

	Only classes with a known allocation funnel actually record (see #funnelsFor:); the rest
	sit in the filter harmlessly. Answers an Array."
	| globs |
	globs := SWACodeRootNode globsFrom: SWAPane codeMapWorkingSet.
	^ (PackageInfo allPackages
		select: [:p | globs anySatisfy: [:g | g match: p packageName]])
		gather: [:p | p classes]
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> xrMenuAllocOneFrame: aMenu [
	"Trace allocations of the classes of interest (#tracedClasses -- Vector3/Matrix4x4 by
	default, add Array etc. via #traceClass:) over a single rendered frame."

	<xrMenu: #(world profile) label: 'alloc survival 1 frame' priority: 209>
	^ self traceXRFrames: 1
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:37'
}
SWAAllocTracer class >> xrMenuAllocTenFrames: aMenu [
	"Trace allocations of the classes of interest (#tracedClasses) over ten rendered
	frames and open the allocation flamegraph -- which call paths make them, live in the
	render loop. NB: keep the set small/cold for 10 frames -- adding Array here folds
	every array the render path makes across ten frames plus a full survivor sweep."

	<xrMenu: #(world profile) label: 'alloc survival 10 frames' priority: 210>
	^ self traceXRFrames: 10
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:40'
}
SWAAllocTracer >> captureIn: aReceiver [
	"Unused: this wrapper overrides #run:with:in: directly so it can see the RESULT
	object (to record its identityHash for the survival colouring), which #captureIn:,
	running before the forward, cannot. Left as a no-op override for clarity."
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:23'
}
SWAAllocTracer >> run: aSelector with: anArray in: aReceiver [
	"Dispatch for the allocation funnel. Unlike the base template we need the RESULT --
	the freshly built object -- so its identityHash can be recorded against the
	allocation site for the survival colouring. So: fold the stack to a leaf node BEFORE
	forwarding, forward, then stamp the result's hash into that leaf's bucket.

	Same substrate discipline as the base wrapper: count first; if capturing is
	suppressed in this process (our own machinery is running) just forward; do the fold
	and the hash record inside #withoutCapturing: so the Collection/Context sends here
	cannot re-enter a wrapper. aReceiver is the CLASS being instantiated; only classes in
	the filter are recorded (Vector class>>new fires for every Vector subclass)."
	| node result |
	count := count + 1.
	"DEFAULT-OFF CONTEXT GATE (the key to tracing a class as hot as Array): fold ONLY
	when we are dynamically inside a #captureDuring: region in this process. Every other
	allocation in the image -- the MCP server, Morphic, the render loop, and our own fold
	below -- runs with the gate off and takes just this probe plus the fast forward, so
	the wrapper does not tax the whole system. #captureDuring: also turns the gate OFF
	around the fold and the hash record, so those cannot re-enter."
	SWAAllocTracer isCapturing ifFalse: [
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	(AllocClassFilter notNil and: [(AllocClassFilter includes: aReceiver) not])
		ifTrue: [^ aReceiver withArgs: anArray executeMethod: self realMethod].
	node := SWAAllocTracer withGateOff: [
		SWAAllocTracer recordAllocationOf: aReceiver from: thisContext].
	result := aReceiver withArgs: anArray executeMethod: self realMethod.
	node ifNotNil: [
		SWAAllocTracer withGateOff: [
			SWAAllocTracer recordHash: result identityHash forNode: node]].
	^ result
]
