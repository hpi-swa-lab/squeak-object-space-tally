"
The single reused measurement state for SWAYoungSpaceTally, held as a class-side
singleton (SWAYoungSpaceState default).

Young space is found by MOVE-DETECTION over allObjectsOrNil, which is the only complete
and self-cleaning method (2026-08-21c):
  - `nextObject` from the heap head (nil) walks OLD space only, never reaching young;
    from a fresh young marker it reaches only eden (objects newer than the marker) and
    misses the survivor floor -- positionally biased toward transient closures.
  - `allObjectsOrNil` reaches ALL young, and because its ~21MB array is large it is born
    directly in OLD space: it never enters young space, so it is INVISIBLE to a young-space
    measurement and needs no filtering.
  - A young object MOVES on a scavenge; an old object does not. So: read every object's
    address, garbageCollectMost, read again -- the movers are exactly the live young set
    (survivor floor + eden), complete, with zero old contamination. Move-detection is
    self-cleaning: our own buffers/arrays are old (they do not move) so they can never be
    mistaken for young. No identity filtering is ever needed.

Held here: the reused AlienStub `wrapper`; `hashArrays`, an Array of N per-sample hash
Arrays (young objects' identityHashes for each snapshot); `hashCounts`, the per-snapshot
counts. All allocated large/old in #prepareForSamples: so they never pollute young space.
The address buffers for move-detection are allocated per collect and are large (heap
sized) so they too are born old.
"
Class {
	#name : #SWAYoungSpaceState,
	#superclass : #Object,
	#instVars : [
		'wrapper',
		'beforeAddrs',
		'afterAddrs',
		'fpSlot',
		'fpHash',
		'fpClass',
		'fpSize',
		'fpCount',
		'tblObj',
		'tblMore',
		'sampleBuffers'
	],
	#classInstVars : [
		'Default'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState class >> default [
	"The single reused measurement-state instance. Created once, tenured, reused."
	^ Default ifNil: [Default := self new]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState class >> reset [
	"Drop the singleton and everything it holds, then GC. Hard reset."
	Default := nil.
	Smalltalk garbageCollect.
	^ self
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:54'
}
SWAYoungSpaceState >> addStackRootsInto: rootYoung [
	"Young Contexts reachable from a suspended process stack, plus the young objects those
	Contexts hold. An untenured Context is not found by the old-space scan, so without this
	a process parked in a Delay would look like garbage.

	The ACTIVE process is skipped, and that is the honest limit of the whole method: it is
	the process running this analysis, its stack holds the snapshot array, and marking
	from it would declare the entire young space reachable via our own temporaries. So
	whatever the active process was legitimately holding is missed. Answers the number of
	processes walked."
	| active walked |
	active := Processor activeProcess.
	walked := 0.
	Process allInstances do: [:proc |
		proc == active ifFalse: [
			| ctx |
			ctx := proc suspendedContext.
			ctx ifNotNil: [
				walked := walked + 1.
				[ctx isNil] whileFalse: [
					(self isYoungValue: ctx) ifTrue: [rootYoung add: ctx].
					self youngReferentsOf: ctx do: [:each | rootYoung add: each].
					ctx := ctx sender]]]].
	^ walked
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:46'
}
SWAYoungSpaceState >> addrBuffersFor: heapSize [
	"Ensure the two reused before/after address buffers are big enough for heapSize objects
	(with leeway). Allocated ONCE, large (so born old), reused every sample. NOT the
	allObjectsOrNil array -- these are our own scratch, kept; that array is transient."
	(beforeAddrs isNil or: [beforeAddrs size < heapSize]) ifTrue: [
		| cap | cap := heapSize + 500000.
		beforeAddrs := Array new: cap.
		afterAddrs := Array new: cap.
		Smalltalk garbageCollect].
	^ self
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:59'
}
SWAYoungSpaceState >> basicEmulatedYoungMark [
	"Decide the fate of young space by marking it ourselves, with no GC of any kind.

	The snapshot array holds every young object, so nothing can die while we work and no
	fingerprint is needed to recognise anything afterwards -- the references are simply
	still there. That is the whole advantage over #fateOfYoungSpace, which had to run a
	full GC because the 55 MB snapshot is old garbage that a scavenge cannot reclaim.

	Answers a Dictionary: #young, #reachable (IdentitySet), #rootHeld (young objects named
	directly by a root), #referrers (oldObject -> count of young pointers), #stats.

	Known divergences from the real collector, all recorded rather than papered over:
	the active process's stack is not a root (it is ours), ephemerons are not modelled,
	and the walk is not atomic unless run at high priority."
	| all n boundary young excluded rootYoung referrers marked reachable garbage
	  msScan msMark msTotal stackProcs |
	msTotal := [
		all := SystemNavigation default allObjectsOrNil.
		all ifNil: [^ nil].
		n := all size.
		boundary := self youngBoundaryIn: all.
		self buildYoungTablesFrom: all boundary: boundary.
		young := OrderedCollection new: n - boundary + 2.
		boundary to: n do: [:i | young add: (all at: i)].
		excluded := self ownStructures.
		rootYoung := OrderedCollection new: 20000.
		referrers := OrderedCollection new.
		msScan := [self
			scanOldIn: all
			boundary: boundary
			excluding: excluded
			roots: rootYoung
			referrers: referrers] timeToRun.
		stackProcs := self addStackRootsInto: rootYoung.
		msMark := [marked := self markYoungFrom: rootYoung] timeToRun.
		self releaseYoungTables.
		all := nil] timeToRun.
	reachable := OrderedCollection new: marked size + 1.
	garbage := OrderedCollection new: ((young size - marked size) max: 1).
	young do: [:each |
		(marked includes: each)
			ifTrue: [reachable add: each]
			ifFalse: [garbage add: each]].
	^ Dictionary new
		at: #young put: young;
		at: #reachable put: reachable;
		at: #garbage put: garbage;
		at: #marked put: marked;
		at: #rootHeld put: rootYoung;
		at: #referrers put: referrers;
		at: #stats put: (Dictionary new
			at: #heap put: n;
			at: #young put: young size;
			at: #reachable put: reachable size;
			at: #garbage put: garbage size;
			at: #distinctOldReferrers put: referrers size;
			at: #oldToYoungEdges put: (referrers inject: 0 into: [:acc :r | acc + (r at: 2)]);
			at: #stackProcessesWalked put: stackProcs;
			at: #msScanOldSpace put: msScan;
			at: #msMark put: msMark;
			at: #msTotal put: msTotal;
			yourself);
		yourself
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 12:50'
}
SWAYoungSpaceState >> bufferAt: index [
	"The sample buffer as filled, without clearing it. #sampleBufferAt: clears on access
	because it hands out a buffer to be written."
	^ sampleBuffers ifNotNil: [sampleBuffers at: index]
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:33'
}
SWAYoungSpaceState >> buildTablesForObjects: aCollection [
	"Index aCollection by identityHash so a scan can reject a slot with one array read.
	See #buildYoungTablesFrom:boundary: for why there are two tables."
	"No garbageCollect to tenure these: at 33 MB each they are born in old space anyway,
	and the no-GC view must contain no collection at all -- it was the only one left in
	that path."
	tblObj ifNil: [
		tblObj := Array new: 1 << 22.
		tblMore := Array new: 1 << 22].
	tblObj atAllPut: nil.
	tblMore atAllPut: nil.
	aCollection do: [:o |
		| h |
		h := o identityHash.
		(h >= 0 and: [h < 4194304]) ifTrue: [
			(tblObj at: h + 1) isNil
				ifTrue: [tblObj at: h + 1 put: o]
				ifFalse: [
					(tblMore at: h + 1)
						ifNil: [tblMore at: h + 1 put: (Array with: o)]
						ifNotNil: [:more | tblMore at: h + 1 put: (more copyWith: o)]]]].
	^ self
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:39'
}
SWAYoungSpaceState >> buildYoungTablesFrom: allObjects boundary: boundary [
	"Index the young objects by identityHash so the 36M-slot scan can reject a slot with
	one array read.

	Two tables because identityHash is 22 bits and collides: tblObj holds the first object
	for a hash, tblMore an Array of the rest. The overflow table has to be separate rather
	than a chain stored in tblObj, because a young object may ITSELF be an Array and
	searching it for the value would answer yes for the wrong reason.

	A missed young object would be read as old, and its referents would then look
	unrooted -- garbage. That is the error direction that matters, so the 0.4% of
	colliding hashes is worth a second table."
	| n |
	"No garbageCollect to tenure these -- at 33 MB each they are born old anyway."
	tblObj ifNil: [
		tblObj := Array new: 1 << 22.
		tblMore := Array new: 1 << 22].
	tblObj atAllPut: nil.
	tblMore atAllPut: nil.
	n := allObjects size.
	boundary to: n do: [:i |
		| o h |
		o := allObjects at: i.
		h := o identityHash.
		(h >= 0 and: [h < 4194304]) ifTrue: [
			(tblObj at: h + 1) isNil
				ifTrue: [tblObj at: h + 1 put: o]
				ifFalse: [
					(tblMore at: h + 1)
						ifNil: [tblMore at: h + 1 put: (Array with: o)]
						ifNotNil: [:more | tblMore at: h + 1 put: (more copyWith: o)]]]].
	^ self
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:47'
}
SWAYoungSpaceState >> byteSizeOfClass: aClass size: basicSize object: anObjectOrNil [
	"Bytes the VM charges for an object. One place, because getting it wrong is invisible:
	the totals simply come out low.

	A Context is allocated at its method's FRAME SIZE, not at basicSize -- basicSize
	reports the stack depth actually in use. Measured at highestPriority so nothing else
	could allocate: a Context with basicSize 5 and frameSize 16 costs 184 bytes, which is
	byteSizeOfInstanceOfSize: 16 exactly, while basicSize gives 104. Contexts and closures
	dominate young space, so this was the whole of a 24% shortfall against vmParameterAt: 2.

	anObjectOrNil may be nil when only the recorded class and size survive, in which case
	the correction cannot be applied and the figure is the old low one."
	(anObjectOrNil notNil and: [aClass includesBehavior: Context]) ifTrue: [
		anObjectOrNil method ifNotNil: [:m |
			^ aClass byteSizeOfInstanceOfSize: m frameSize]].
	^ aClass isVariable
		ifTrue: [aClass byteSizeOfInstanceOfSize: basicSize]
		ifFalse: [aClass byteSizeOfInstance]
]

{
	#category : #collecting,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:36'
}
SWAYoungSpaceState >> collectYoungObjects [
	"The live AND dead objects standing in young space now, in address order.

	No scavenge: the previous implementation move-detected across a forced
	garbageCollectMost, which drained the transient objects it was asked to show.
	#youngBoundaryIn: needs ~30 address reads instead of two per object, so the snapshot
	is taken and cut before the image can allocate much into it.

	The result includes young GARBAGE -- prim 178 reports what is physically in eden, not
	what is reachable (verified: 20000 deliberately orphaned Semaphores all came back).
	That is the point: the fate of these objects is the question, so the set has to
	contain the objects that are about to die."
	| all n boundary result |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ OrderedCollection new].
	n := all size.
	boundary := self youngBoundaryIn: all.
	result := OrderedCollection new: n - boundary + 2.
	boundary to: n do: [:i | result add: (all at: i)].
	"Erase the snapshot's slots before dropping it. At 55 MB it is born in OLD space, so
	once dropped it is old garbage a scavenge cannot reclaim -- and it still names every
	young object through the remembered set, keeping all of them alive. Measured: dropping
	one took p35 from 9446 to 29678; nilling it first left 9448. Every call used to leave
	one of these behind, which is why the tools were a significant source of the floating
	garbage they reported."
	all atAllPut: nil.
	^ result
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:05'
}
SWAYoungSpaceState >> detectYoungInto: aCollection [
	"The one move-detection primitive. Snapshot allObjectsOrNil (its ~21MB array is born
	OLD, invisible to young), read every object's address into a big buffer, scavenge, read
	again; an object whose address CHANGED is young, and is appended to aCollection. Answers
	the count.

	The address buffers are large so they are born old and never appear in young. The hot
	loops are inlined (whileTrue:/ifTrue:) so no closure/context of ours is created young
	during the measurement. addressField is read-only, one object at a time."
	| all wrap n before after a count o |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ 0].
	n := all size.
	"REUSED before/after buffers -- allocated once, sized to the heap with leeway, never
	the allObjectsOrNil array itself (that is transient and dropped below)."
	self addrBuffersFor: n.
	before := beforeAddrs.
	after := afterAddrs.
	wrap := self wrapper.
	"Read BEFORE addresses (inlined; -1 marks immediates)."
	a := 1.
	[a <= n] whileTrue: [
		o := all at: a.
		before at: a put: (o class isImmediateClass ifTrue: [-1] ifFalse: [wrap oopAt: 1 put: o. wrap addressField]).
		a := a + 1].
	Smalltalk garbageCollectMost.
	"Read AFTER addresses."
	a := 1.
	[a <= n] whileTrue: [
		o := all at: a.
		after at: a put: (o class isImmediateClass ifTrue: [-1] ifFalse: [wrap oopAt: 1 put: o. wrap addressField]).
		a := a + 1].
	"Movers = young. Append them."
	count := 0.
	a := 1.
	[a <= n] whileTrue: [
		((before at: a) ~= (after at: a) and: [(before at: a) ~= -1]) ifTrue: [
			o := all at: a.
			count := count + 1.
			aCollection add: o].
		a := a + 1].
	"Drop the transient allObjectsOrNil array -- never stored."
	all := nil.
	^ count
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:56'
}
SWAYoungSpaceState >> emulatedYoungMark [
	"Run the mark in a forked process, which is what makes the caller's stack visible.

	#addStackRootsInto: has to skip the active process, because that stack holds the
	snapshot and marking from it would call all of young space reachable. Run inline, the
	active process IS the caller -- so on a quiet desktop, where the caller is the only
	thing allocating, every genuinely live young object was reported as garbage. Measured
	before this change: 2557 objects said garbage that a full GC then kept.

	Forking inverts it. The analysis becomes the active process and excludes only itself;
	the caller is suspended and gets walked like any other stack."
	| holder done |
	holder := Array new: 1.
	done := false.
	[holder at: 1 put: self basicEmulatedYoungMark. done := true]
		forkAt: Processor userInterruptPriority.
	[done] whileFalse: [(Delay forMilliseconds: 20) wait].
	^ holder at: 1
]

{
	#category : #fingerprinting,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:25'
}
SWAYoungSpaceState >> ensureFingerprintTables [
	"Allocate the fingerprint tables ONCE, large, so they are born in old space, and reset
	them by clearing contents rather than by reallocating.

	Both rules are paid for: a table created lazily mid-sample is itself young and lands in
	the next walk, and `table := nil` to reset orphans a young 33 MB Array that the next
	walk then enumerates (2026-08-21). fpSlot is the dense identityHash index; the parallel
	arrays hold only SmallIntegers and Classes, never a young object -- storing one would
	pin it and resurrect the garbage whose death we are trying to observe."
	fpSlot ifNil: [
		fpSlot := Array new: 1 << 22.
		fpHash := Array new: 200000.
		fpClass := Array new: 200000.
		fpSize := Array new: 200000.
		Smalltalk garbageCollect].
	fpCount := 0.
	^ self
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:02'
}
SWAYoungSpaceState >> expandExclusions: aCollection [
	"An IdentitySet of aCollection's objects AND their direct slot values, so a collection
	we own does not appear as a retainer through its backing Array. Excluding the
	collection alone is not enough -- a collection is one object but its Array is a
	separate one holding the same references, and that distinction has cost this arc a
	day before (2026-08-21)."
	| set mirror |
	set := self ownStructures.
	mirror := thisContext.
	aCollection do: [:each |
		each ifNotNil: [
			| cls |
			set add: each.
			cls := mirror objectClass: each.
			1 to: cls instSize do: [:k |
				(mirror object: each instVarAt: k) ifNotNil: [:v | set add: v]]]].
	^ set
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:36'
}
SWAYoungSpaceState >> fateAcrossScavenge [
	"Fate of young space at the NEXT SCAVENGE -- the question young space actually poses.
	No full GC.

	This was thought impossible: prim 178's result is 55 MB, born in old space, and once
	dropped it is old garbage that a scavenge cannot reclaim while it still names every
	young object, so everything appeared to survive. The way past it is to erase the
	snapshot's slots before dropping it: the pin comes from the young POINTERS it holds,
	not from the array being old. p35 with a dropped snapshot 29678, with a nilled one
	9448 against a control of 9446.

	The oracle is a WeakArray, nilled by the collector exactly when an object dies, so
	nothing has to be re-identified afterwards and nothing is held that would change the
	answer.

	Answers #survivors, #promoted (alive, tenured out of young by this scavenge),
	#collectedByClass, #stats."
	| all n boundary weak classes sizes mirror survivors promoted collectedByClass
	  collectedBytesByClass sampledBytes collectedBytes promotedBytes survivedBytes
	  p2before p9a p9b p11a p11b p35after youngAfter |
	p2before := Smalltalk vmParameterAt: 2.
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ nil].
	n := all size.
	boundary := self youngBoundaryIn: all.
	n := n - boundary + 1.
	weak := WeakArray new: n.
	classes := Array new: n.
	sizes := Array new: n.
	mirror := thisContext.
	1 to: n do: [:i |
		| o cls |
		o := all at: boundary + i - 1.
		cls := mirror objectClass: o.
		weak at: i put: o.
		classes at: i put: cls.
		sizes at: i put: (self byteSizeOfClass: cls size: (mirror objectSize: o) object: o)].
	all atAllPut: nil.
	all := nil.
	p9a := Smalltalk vmParameterAt: 9.
	p11a := Smalltalk vmParameterAt: 11.
	Smalltalk garbageCollectMost.
	p9b := Smalltalk vmParameterAt: 9.
	p11b := Smalltalk vmParameterAt: 11.
	p35after := Smalltalk vmParameterAt: 35.
	"Young membership AFTER the scavenge, to tell a survivor from one tenured out."
	youngAfter := self collectYoungObjects.
	self buildTablesForObjects: youngAfter.
	survivors := OrderedCollection new: 20000.
	promoted := OrderedCollection new.
	collectedByClass := Dictionary new.
	collectedBytesByClass := Dictionary new.
	sampledBytes := 0. collectedBytes := 0. promotedBytes := 0. survivedBytes := 0.
	1 to: n do: [:i |
		| o cls bytes |
		cls := classes at: i.
		bytes := sizes at: i.
		sampledBytes := sampledBytes + bytes.
		o := weak at: i.
		o
			ifNil: [
				collectedBytes := collectedBytes + bytes.
				collectedByClass at: cls put: (collectedByClass at: cls ifAbsent: [0]) + 1.
				collectedBytesByClass at: cls put: (collectedBytesByClass at: cls ifAbsent: [0]) + bytes]
			ifNotNil: [
				(self isYoungValue: o)
					ifTrue: [survivors add: o. survivedBytes := survivedBytes + bytes]
					ifFalse: [promoted add: o. promotedBytes := promotedBytes + bytes]]].
	self releaseYoungTables.
	^ Dictionary new
		at: #survivors put: survivors;
		at: #promoted put: promoted;
		at: #born put: (youngAfter size - survivors size);
		at: #collectedByClass put: collectedByClass;
		at: #collectedBytesByClass put: collectedBytesByClass;
		at: #stats put: (Dictionary new
			at: #sampled put: n;
			at: #sampledBytes put: sampledBytes;
			at: #survived put: survivors size;
			at: #survivedBytes put: survivedBytes;
			at: #promoted put: promoted size;
			at: #promotedBytes put: promotedBytes;
			at: #collected put: (collectedByClass inject: 0 into: [:a :b | a + b]);
			at: #collectedBytes put: collectedBytes;
			at: #born put: (youngAfter size - survivors size);
			at: #fullGCs put: 0;
			at: #scavenges put: p9b - p9a;
			at: #tenuredObjects put: p11b - p11a;
			at: #vmSurvivorsAfter put: p35after;
			at: #vmYoungBytesBefore put: p2before;
			at: #bytesVsVmPercent put: (p2before > 0
				ifTrue: [sampledBytes * 100 // p2before]
				ifFalse: [0]);
			yourself);
		yourself
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:13'
}
SWAYoungSpaceState >> fateOfYoungSpace [
	"Decide, for every object standing in young space now, whether it is reachable.
	Answers a Dictionary with #survivors and #born (real objects, safe to hold),
	#collectedByClass (class -> count) and #stats.

	A full GC is the decider, not a scavenge, and that is forced by the instrument rather
	than chosen: the allObjectsOrNil array is 55 MB, so it is born in OLD space, and
	nilling it leaves old garbage that a scavenge cannot reclaim but that still pins every
	young object it names through the remembered set -- the floating-garbage mechanism of
	2026-09-18c, here created by the measurement itself. Measured: a snapshot taken and
	immediately nilled took p35 from 756 to 20902. So scavenge fate cannot be observed
	with this sampler at all, while a full GC reclaims the dead array first and answers
	the stronger question, true reachability. Young survivors stay young across a full GC
	(2026-08-14b), which is what lets sample B find them.

	The dead can only be answered with metadata, and not for want of trying: holding an
	object is what stops it dying.

	#tenuredObjects is a guard, not a statistic: a promoted object leaves young space
	alive and is indistinguishable here from a collected one, so #collectedByClass is an
	upper bound whenever it is non-zero."
	| young aCount clashes mirror youngB seen survivors born collectedByClass
	  collectedBytesByClass sampledBytes collectedBytes p7a p7b p11a p11b p35 hashOnly
	  truncated |
	young := self collectYoungObjects.
	aCount := young size.
	clashes := self recordFingerprintsOf: young.
	truncated := aCount > fpCount.
	aCount := fpCount.
	young := nil.
	p7a := Smalltalk vmParameterAt: 7.
	p11a := Smalltalk vmParameterAt: 11.
	Smalltalk garbageCollect.
	p7b := Smalltalk vmParameterAt: 7.
	p11b := Smalltalk vmParameterAt: 11.
	p35 := Smalltalk vmParameterAt: 35.
	youngB := self collectYoungObjects.
	mirror := thisContext.
	seen := ByteArray new: aCount + 1.
	survivors := OrderedCollection new: 20000.
	born := OrderedCollection new: 20000.
	hashOnly := 0.
	1 to: youngB size do: [:i |
		| o j |
		o := youngB at: i.
		(fpSlot at: o identityHash + 1) = 0 ifFalse: [hashOnly := hashOnly + 1].
		j := self fingerprintIndexOf: o mirror: mirror.
		j = 0
			ifTrue: [born add: o]
			ifFalse: [seen at: j put: 1. survivors add: o]].
	collectedByClass := Dictionary new.
	collectedBytesByClass := Dictionary new.
	sampledBytes := 0.
	collectedBytes := 0.
	"Byte totals come from the fingerprint record, not from the objects, so the collected
	half can be sized at all -- by now it does not exist."
	1 to: aCount do: [:j |
		| c bytes |
		c := fpClass at: j.
		bytes := c isVariable
			ifTrue: [c byteSizeOfInstanceOfSize: (fpSize at: j)]
			ifFalse: [c byteSizeOfInstance].
		sampledBytes := sampledBytes + bytes.
		(seen at: j) = 0 ifTrue: [
			collectedBytes := collectedBytes + bytes.
			collectedByClass at: c put: (collectedByClass at: c ifAbsent: [0]) + 1.
			collectedBytesByClass at: c put: (collectedBytesByClass at: c ifAbsent: [0]) + bytes]].
	^ Dictionary new
		at: #survivors put: survivors;
		at: #born put: born;
		at: #collectedByClass put: collectedByClass;
		at: #collectedBytesByClass put: collectedBytesByClass;
		at: #stats put: (Dictionary new
			at: #sampled put: aCount;
			at: #sampledBytes put: sampledBytes;
			at: #survived put: survivors size;
			at: #survivedBytes put: sampledBytes - collectedBytes;
			at: #collected put: aCount - survivors size;
			at: #collectedBytes put: collectedBytes;
			at: #born put: born size;
			at: #fullGCs put: p7b - p7a;
			at: #tenuredObjects put: p11b - p11a;
			at: #vmRetainedP35 put: p35;
			at: #hashClashesWithinSample put: clashes;
			at: #matchedOnHashAlone put: hashOnly;
			at: #rejectedByClassOrSize put: hashOnly - survivors size;
			at: #truncated put: truncated;
			yourself);
		yourself
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:47'
}
SWAYoungSpaceState >> fateOfYoungSpaceExact [
	"Fate of everything standing in young space now, decided by a WeakArray rather than by
	re-identifying objects afterwards.

	A weak slot is nilled by the collector exactly when its object dies, so death is read
	off directly: no fingerprints, no 22-bit hash collisions, and no need to match across
	the pass. Whatever is left in a slot is the object itself.

	That also separates the two ways an object can leave young space, which the previous
	version conflated and got wrong: DIED, or PROMOTED to old space and still alive. A
	full GC here tenures freely -- runs have shown 30882 promotions out of 35035 sampled
	-- and every one of those was being reported as collected.

	Answers #survivors, #promoted (alive, now old), #collectedByClass, #stats."
	| young n weak classes sizes mirror youngAfter survivors promoted
	  collectedByClass collectedBytesByClass sampledBytes collectedBytes promotedBytes
	  survivedBytes p7a p7b p11a p11b p35before p35after p2before p2after p9before p9after |
	"p2 is bytes in use in young space. Read immediately before the snapshot, because the
	snapshot's own result collection is itself allocated young and would inflate it -- and
	again after, so the true figure is bracketed rather than guessed at. Comparing it with
	our own byte total is the check that the boundary cut and the per-object sizing are
	both right."
	p2before := Smalltalk vmParameterAt: 2.
	p9before := Smalltalk vmParameterAt: 9.
	young := self collectYoungObjects.
	p2after := Smalltalk vmParameterAt: 2.
	p9after := Smalltalk vmParameterAt: 9.
	n := young size.
	weak := WeakArray new: n.
	classes := Array new: n.
	sizes := Array new: n.
	mirror := thisContext.
	"Size is taken NOW, while the object still exists: a Context's real cost needs its
	method's frame size, and after the collection there is nothing left to ask."
	1 to: n do: [:i |
		| o |
		o := young at: i.
		weak at: i put: o.
		classes at: i put: (mirror objectClass: o).
		sizes at: i put: (self byteSizeOfClass: (mirror objectClass: o)
			size: (mirror objectSize: o)
			object: o)].
	young := nil.
	p35before := Smalltalk vmParameterAt: 35.
	p7a := Smalltalk vmParameterAt: 7.
	p11a := Smalltalk vmParameterAt: 11.
	Smalltalk garbageCollect.
	p7b := Smalltalk vmParameterAt: 7.
	p11b := Smalltalk vmParameterAt: 11.
	p35after := Smalltalk vmParameterAt: 35.
	"Membership of young space AFTER the collection, to tell a survivor from a promotion."
	youngAfter := self collectYoungObjects.
	self buildTablesForObjects: youngAfter.
	survivors := OrderedCollection new: 20000.
	promoted := OrderedCollection new.
	collectedByClass := Dictionary new.
	collectedBytesByClass := Dictionary new.
	sampledBytes := 0. collectedBytes := 0. promotedBytes := 0. survivedBytes := 0.
	1 to: n do: [:i |
		| o cls bytes |
		cls := classes at: i.
		bytes := sizes at: i.
		sampledBytes := sampledBytes + bytes.
		o := weak at: i.
		o
			ifNil: [
				collectedBytes := collectedBytes + bytes.
				collectedByClass at: cls put: (collectedByClass at: cls ifAbsent: [0]) + 1.
				collectedBytesByClass at: cls put: (collectedBytesByClass at: cls ifAbsent: [0]) + bytes]
			ifNotNil: [
				(self isYoungValue: o)
					ifTrue: [survivors add: o. survivedBytes := survivedBytes + bytes]
					ifFalse: [promoted add: o. promotedBytes := promotedBytes + bytes]]].
	self releaseYoungTables.
	^ Dictionary new
		at: #survivors put: survivors;
		at: #promoted put: promoted;
		at: #born put: (youngAfter size - survivors size);
		at: #collectedByClass put: collectedByClass;
		at: #collectedBytesByClass put: collectedBytesByClass;
		at: #stats put: (Dictionary new
			at: #sampled put: n;
			at: #sampledBytes put: sampledBytes;
			at: #survived put: survivors size;
			at: #survivedBytes put: survivedBytes;
			at: #promoted put: promoted size;
			at: #promotedBytes put: promotedBytes;
			at: #collected put: (collectedByClass inject: 0 into: [:a :b | a + b]);
			at: #collectedBytes put: collectedBytes;
			at: #born put: (youngAfter size - survivors size);
			at: #fullGCs put: p7b - p7a;
			at: #tenuredObjects put: p11b - p11a;
			at: #vmSurvivorsBefore put: p35before;
			at: #vmRetainedAfter put: p35after;
			at: #scavengesDuringCapture put: p9after - p9before;
			at: #vmYoungBytesBefore put: p2before;
			at: #vmYoungBytesAfter put: p2after;
			at: #bytesVsVmPercent put: (p2before > 0
				ifTrue: [sampledBytes * 100 // p2before]
				ifFalse: [0]);
			yourself);
		yourself
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 12:50'
}
SWAYoungSpaceState >> fillSampleBuffer: index [
	"Record the identities of young space into reusable buffer `index`. Answers the count.

	Nothing is allocated except the prim 178 snapshot, which is far too big for eden so it
	goes straight to old space and never appears in a sample; its slots are erased before
	it is dropped so it pins nothing. No class or size arrays: for ages the objects that
	matter are alive and can be asked directly at analysis time."
	| all n boundary buf count |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ 0].
	n := all size.
	boundary := self youngBoundaryIn: all.
	count := (n - boundary + 1) min: self sampleCapacity.
	buf := self sampleBufferAt: index.
	1 to: count do: [:i | buf at: i put: (all at: boundary + i - 1)].
	all atAllPut: nil.
	^ count
]

{
	#category : #fingerprinting,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:25'
}
SWAYoungSpaceState >> fingerprintIndexOf: anObject mirror: aContext [
	"Index of anObject in the recorded sample, or 0 if it was not in it. The class and
	basicSize test is what makes this a per-class match rather than a global one: without
	it a hash freed by a dying ByteString and reused by a newborn Array counts as a
	survivor of the wrong class."
	| i |
	i := fpSlot at: anObject identityHash + 1.
	i = 0 ifTrue: [^ 0].
	(fpClass at: i) == (aContext objectClass: anObject) ifFalse: [^ 0].
	(fpSize at: i) = (aContext objectSize: anObject) ifFalse: [^ 0].
	^ i
]

{
	#category : #retainers,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:05'
}
SWAYoungSpaceState >> isHeapSnapshotArray: anObject [
	"True for a leftover allObjectsOrNil result. Prim 178 enumerates in address order and
	the heap begins with nil, false, true, which makes the signature unambiguous at this
	size.

	These dominate any retainer list -- each names every young object, and being 55 MB
	they are old, so a scavenge can never reclaim them. They are artifacts of this tool
	and of every other prim-178 user in the image, and reporting them as retention would
	bury the real answers."
	anObject class == Array ifFalse: [^ false].
	anObject basicSize < 100000 ifTrue: [^ false].
	^ (anObject at: 1) == nil
		and: [(anObject at: 2) == false
		and: [(anObject at: 3) == true]]
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:53'
}
SWAYoungSpaceState >> isYoungValue: aValue [
	"Membership against the tables built by #buildYoungTablesFrom:boundary:. nil and the
	immediates are rejected on the cheap path: a SmallInteger's identityHash is its own
	value and would index out of the table."
	| h more |
	aValue == nil ifTrue: [^ false].
	h := aValue identityHash.
	(h >= 0 and: [h < 4194304]) ifFalse: [^ false].
	(tblObj at: h + 1) == aValue ifTrue: [^ true].
	more := tblMore at: h + 1.
	more ifNil: [^ false].
	1 to: more size do: [:i | (more at: i) == aValue ifTrue: [^ true]].
	^ false
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:54'
}
SWAYoungSpaceState >> markYoungFrom: rootYoung [
	"Transitive closure over young->young edges. Answers the IdentitySet of reachable
	young objects.

	Cheap by comparison with the scan -- tens of thousands of objects, not millions --
	because a young object's referents can only be found among the young, and that set is
	already indexed."
	| marked queue |
	marked := IdentitySet new: 65536.
	queue := OrderedCollection new: 65536.
	rootYoung do: [:each |
		(marked includes: each) ifFalse: [marked add: each. queue addLast: each]].
	[queue isEmpty] whileFalse: [
		| o |
		o := queue removeFirst.
		self youngReferentsOf: o do: [:each |
			(marked includes: each) ifFalse: [marked add: each. queue addLast: each]]].
	^ marked
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 12:49'
}
SWAYoungSpaceState >> maxSamples [
	^ 12
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:53'
}
SWAYoungSpaceState >> ownStructures [
	"The reusable buffers, which are old and therefore appear in the snapshot like any
	other object. Left in, they are roots: the fingerprint and address tables name young
	objects and would keep them alive in the emulated mark, so the tool would report its
	own scratch space as retention."
	| set |
	set := IdentitySet new.
	{ tblObj. tblMore. beforeAddrs. afterAddrs. fpSlot. fpHash. fpClass. fpSize }
		do: [:each | each ifNotNil: [set add: each]].
	^ set
]

{
	#category : #addressing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:21'
}
SWAYoungSpaceState >> rawAddressOf: anObject [
	"Physical address of anObject, or -1 for an immediate, which has none.

	Read-only, one object at a time, and the oop is never fed back: storing a stale oop
	from a snapshot and letting the VM follow it segfaulted the image once (2026-08-19)."
	anObject class isImmediateClass ifTrue: [^ -1].
	wrapper ifNil: [wrapper := AlienStub forOop].
	wrapper oopAt: 1 put: anObject.
	^ wrapper addressField
]

{
	#category : #fingerprinting,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:25'
}
SWAYoungSpaceState >> recordFingerprintsOf: youngObjects [
	"Fingerprint a young sample so it can be recognised after a scavenge without holding
	any of it. Holding is what has to be avoided: the sample contains the garbage, and a
	reference to garbage resurrects exactly the death we want to observe.

	The fingerprint is identityHash + class + basicSize. identityHash alone is 22 bits and
	collides; class and basicSize bin it, which is worth 5x (2026-09-17). All three are
	stable under mutation, which this regime requires because the image keeps running
	between the two samples. Read through the thisContext mirror so a proxy cannot
	intercept and run code mid-walk.

	Answers the number of fingerprints that were overwritten by a later object sharing a
	slot -- the ambiguity already present within one sample, and the honest lower bound on
	the join's error."
	| n mirror clashes o h |
	self ensureFingerprintTables.
	fpSlot atAllPut: 0.
	mirror := thisContext.
	n := youngObjects size min: fpHash size.
	clashes := 0.
	1 to: n do: [:i |
		o := youngObjects at: i.
		h := o identityHash.
		fpHash at: i put: h.
		fpClass at: i put: (mirror objectClass: o).
		fpSize at: i put: (mirror objectSize: o).
		(fpSlot at: h + 1) = 0 ifFalse: [clashes := clashes + 1].
		fpSlot at: h + 1 put: i].
	fpCount := n.
	^ clashes
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:59'
}
SWAYoungSpaceState >> releaseYoungTables [
	"Empty the membership tables of object references as soon as the mark is done.

	They are instance variables of a singleton, so anything left in them is reachable
	forever: the first validation run reported that NOTHING in young space died, because
	the tool was holding all of it. Cleared by contents, never by reallocation -- a nilled
	33 MB Array is young garbage the next walk enumerates (2026-08-21)."
	tblObj ifNotNil: [tblObj atAllPut: nil].
	tblMore ifNotNil: [tblMore atAllPut: nil].
	^ self
]

{
	#category : #retainers,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:36'
}
SWAYoungSpaceState >> retainersOf: targetObjects excluding: ourObjects [
	"Every object outside targetObjects that holds a reference into it. Answers an
	OrderedCollection of Array { retainer. OrderedCollection of the targets it holds }.

	This is a direct observation -- a slot either contains that object or it does not --
	which is why it is usable while the emulated MARK built on the same scan is not yet
	trusted. Run after the fate pass, so what it finds is genuinely live rather than the
	floating garbage a scavenge could never reclaim.

	One full-heap slot pass, ~36M reads at 0.13 us. Objects in targetObjects are skipped
	as retainers so the result names what captures the set from OUTSIDE, not its internal
	structure."
	| all n mirror excluded found |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ OrderedCollection new].
	n := all size.
	self buildTablesForObjects: targetObjects.
	excluded := self expandExclusions: ourObjects.
	excluded add: all.
	found := OrderedCollection new.
	mirror := thisContext.
	1 to: n do: [:i |
		| o cls slots v hits |
		o := all at: i.
		((excluded includes: o)
			or: [(self isYoungValue: o) or: [self isHeapSnapshotArray: o]]) ifFalse: [
			cls := mirror objectClass: o.
			hits := nil.
			slots := cls instSize.
			1 to: slots do: [:k |
				v := mirror object: o instVarAt: k.
				(self isYoungValue: v) ifTrue: [
					hits ifNil: [hits := OrderedCollection new].
					hits add: v]].
			cls isCompiledMethodClass
				ifTrue: [
					slots := o numLiterals.
					1 to: slots do: [:k |
						v := o literalAt: k.
						(self isYoungValue: v) ifTrue: [
							hits ifNil: [hits := OrderedCollection new].
							hits add: v]]]
				ifFalse: [
					(cls isPointers and: [cls isWeak not]) ifTrue: [
						slots := mirror objectSize: o.
						1 to: slots do: [:k |
							v := mirror object: o basicAt: k.
							(self isYoungValue: v) ifTrue: [
								hits ifNil: [hits := OrderedCollection new].
								hits add: v]]]].
			hits ifNotNil: [found add: (Array with: o with: hits)]]].
	"Same reason as #collectYoungObjects: the snapshot must not be left holding young
	pointers, or it pins everything it named until the next full GC."
	all atAllPut: nil.
	all := nil.
	self releaseYoungTables.
	^ found
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 12:49'
}
SWAYoungSpaceState >> sampleBufferAt: index [
	"A reusable WeakArray for sample `index`, allocated ONCE at a size big enough to be
	born in old space and never reallocated.

	Allocating one per sample was the bug: a WeakArray of a few thousand slots is small
	enough to be born YOUNG, so it appeared in the next sample and dominated it -- '4
	objects, 1.1 MB' was the tool's own buffers, not the program's. That is the rule
	2026-08-21 already wrote down and I ignored.

	Cleared by contents on reuse, never by reallocation, for the same reason."
	| buf |
	sampleBuffers ifNil: [sampleBuffers := Array new: self maxSamples].
	buf := sampleBuffers at: index.
	buf ifNil: [
		buf := WeakArray new: self sampleCapacity.
		sampleBuffers at: index put: buf].
	buf atAllPut: nil.
	^ buf
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 12:49'
}
SWAYoungSpaceState >> sampleCapacity [
	"Slots per sample buffer. 250000 is both well above the largest young population seen
	here (~90k) and large enough that the buffer is born in old space."
	^ 250000
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:54'
}
SWAYoungSpaceState >> scanOldIn: allObjects boundary: boundary excluding: excludedSet roots: rootYoung referrers: referrers [
	"Find every old->young pointer -- the remembered set, computed rather than asked for,
	since the VM exposes only its SIZE (p21).

	This is the expensive phase and the only one that is: ~36M slot reads, measured at
	0.13 us each. Jens's 'skip old objects that point only into old space' cannot help,
	because deciding that requires reading their slots anyway.

	The loop is written flat rather than over #youngReferentsOf:do: because a closure per
	object is 2.6M closures, and the point of the exercise is not to allocate our way
	through it."
	| mirror |
	mirror := thisContext.
	1 to: boundary - 1 do: [:i |
		| o cls n v hits |
		o := allObjects at: i.
		(excludedSet includes: o) ifFalse: [
			cls := mirror objectClass: o.
			hits := 0.
			n := cls instSize.
			1 to: n do: [:k |
				v := mirror object: o instVarAt: k.
				(self isYoungValue: v) ifTrue: [rootYoung add: v. hits := hits + 1]].
			cls isCompiledMethodClass
				ifTrue: [
					n := o numLiterals.
					1 to: n do: [:k |
						v := o literalAt: k.
						(self isYoungValue: v) ifTrue: [rootYoung add: v. hits := hits + 1]]]
				ifFalse: [
					(cls isPointers and: [cls isWeak not]) ifTrue: [
						n := mirror objectSize: o.
						1 to: n do: [:k |
							v := mirror object: o basicAt: k.
							(self isYoungValue: v) ifTrue: [rootYoung add: v. hits := hits + 1]]]].
			hits > 0 ifTrue: [referrers add: (Array with: o with: hits)]]].
	^ self
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:38'
}
SWAYoungSpaceState >> scavengeFate [
	"#fateAcrossScavenge at highestPriority, which is a precondition and not a tuning
	choice: the sampling loop holds the snapshot, so any involuntary scavenge during it
	finds all of young space pinned, the survivor set overflows the tenure threshold, and
	the VM bulk-promotes. Measured at normal priority: 52249 of 64461 objects tenured out
	of young space by the act of looking at them. At highestPriority nothing else
	allocates and the figure was 0."
	| holder done |
	holder := Array new: 1.
	done := false.
	[holder at: 1 put: self fateAcrossScavenge. done := true]
		forkAt: Processor highestPriority.
	[done] whileFalse: [(Delay forMilliseconds: 10) wait].
	^ holder at: 1
]

{
	#category : #series,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:51'
}
SWAYoungSpaceState >> takeWeakSample [
	"One snapshot of young space that holds NOTHING strongly. Answers
	{ weakArray. classes. byteSizes. scavengeCount. millisecondClock. youngBytes }.

	A WeakArray preserves identity without keeping anything alive, which is what makes a
	series possible at all: samples can be compared object by object later, with no
	fingerprints and no risk that holding sample 1 changes the answer for sample 2. The
	class and size are recorded now because a dead object cannot be asked later.

	The parallel arrays are large enough to be born in old space, so the sample does not
	appear in the next one."
	| all n boundary weak classes sizes mirror |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ nil].
	n := all size.
	boundary := self youngBoundaryIn: all.
	n := n - boundary + 1.
	weak := WeakArray new: n.
	classes := Array new: n.
	sizes := Array new: n.
	mirror := thisContext.
	1 to: n do: [:i |
		| o cls |
		o := all at: boundary + i - 1.
		cls := mirror objectClass: o.
		weak at: i put: o.
		classes at: i put: cls.
		sizes at: i put: (self byteSizeOfClass: cls size: (mirror objectSize: o) object: o)].
	all atAllPut: nil.
	all := nil.
	^ {
		weak. classes. sizes.
		Smalltalk vmParameterAt: 9.
		Time millisecondClockValue.
		Smalltalk vmParameterAt: 2 }
]

{
	#category : #verification,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:58'
}
SWAYoungSpaceState >> validateEmulatedMark [
	"Run the emulated mark, then let a real full GC decide, and compare object for object.

	The oracle is a WeakArray, not a fingerprint join. A weak slot is nilled by the
	collector precisely when its object dies, which is the question being asked, and it
	needs no way to re-identify anything afterwards. The fingerprint version of this check
	was unusable: it matched across the six seconds the scan takes, so objects allocated
	in that window collided with recorded hashes and were counted as resurrected -- it
	reported 8443 such, 73% of them Contexts and closures, the classes where hash is the
	only discriminator.

	#saidGarbageButLived is the error that matters: it means the mark missed a root.
	#saidLiveButGone is expected and is not simply error -- the mark uses SCAVENGE roots,
	so an object held only by a dead old object is live to it and dead to a full GC. That
	difference IS the floating garbage."
	| r young marked weak verdict n tp fn fp tn p11a p11b |
	r := self emulatedYoungMark.
	r ifNil: [^ 'allObjectsOrNil failed'].
	young := r at: #young.
	marked := r at: #marked.
	n := young size.
	weak := WeakArray new: n.
	verdict := ByteArray new: n.
	1 to: n do: [:i |
		| o |
		o := young at: i.
		weak at: i put: o.
		(marked includes: o) ifTrue: [verdict at: i put: 1]].
	r := nil. young := nil. marked := nil.
	p11a := Smalltalk vmParameterAt: 11.
	Smalltalk garbageCollect.
	Smalltalk garbageCollect.
	p11b := Smalltalk vmParameterAt: 11.
	tp := fn := fp := tn := 0.
	1 to: n do: [:i |
		| lived said |
		lived := (weak at: i) notNil.
		said := (verdict at: i) = 1.
		said
			ifTrue: [lived ifTrue: [tp := tp + 1] ifFalse: [fp := fp + 1]]
			ifFalse: [lived ifTrue: [fn := fn + 1] ifFalse: [tn := tn + 1]]].
	^ Dictionary new
		at: #sampled put: n;
		at: #saidLiveAndLived put: tp;
		at: #saidGarbageButLived put: fn;
		at: #saidLiveButGone put: fp;
		at: #saidGarbageAndDied put: tn;
		at: #tenuredObjects put: p11b - p11a;
		yourself
]

{
	#category : #verification,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:53'
}
SWAYoungSpaceState >> validateWeakOracle [
	"Check the one mechanism the whole fate measurement rests on: that a weak slot is
	nilled by a SCAVENGE exactly when its object dies, and never otherwise.

	A strong array cannot substitute for this -- holding an object prevents the death you
	are trying to observe -- so if weak references are unreliable here, per-object fate is
	not measurable at all and the tool should be deleted rather than believed.

	Answers a Dictionary. liveButNilled must be 0: that is the direction that makes a live
	object look dead. deadNotNilled must be 0 immediately, which also establishes that
	nilling happens IN the scavenge rather than in a later finalization pass, so reading
	straight afterwards is sound.

	Covers plain objects only. Weak objects and ephemerons inside a real sample have their
	own rules and are not exercised here; the cross-check that does cover the real
	population is #survived against the VM's own p35, which agrees within a few objects."
	| n weak strong liveButNilled deadNotNilled deadNotNilledLater |
	n := 20000.
	Smalltalk garbageCollect.
	weak := WeakArray new: n * 2.
	strong := Array new: n.
	1 to: n do: [:i |
		| o |
		o := Array new: 3.
		strong at: i put: o.
		weak at: i put: o].
	1 to: n do: [:i | weak at: n + i put: (Array new: 3)].
	Smalltalk garbageCollectMost.
	liveButNilled := 0.
	1 to: n do: [:i | (weak at: i) isNil ifTrue: [liveButNilled := liveButNilled + 1]].
	deadNotNilled := 0.
	n + 1 to: n * 2 do: [:i | (weak at: i) ifNotNil: [deadNotNilled := deadNotNilled + 1]].
	(Delay forMilliseconds: 300) wait.
	deadNotNilledLater := 0.
	n + 1 to: n * 2 do: [:i | (weak at: i) ifNotNil: [deadNotNilledLater := deadNotNilledLater + 1]].
	strong := nil.
	^ Dictionary new
		at: #sampleSize put: n;
		at: #liveButNilled put: liveButNilled;
		at: #deadNotNilled put: deadNotNilled;
		at: #deadNotNilledAfterDelay put: deadNotNilledLater;
		at: #trustworthy put: (liveButNilled = 0 and: [deadNotNilled = 0]);
		yourself
]

{
	#category : #verification,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:23'
}
SWAYoungSpaceState >> verifyBoundary [
	"Check the boundary cut against move-detection: a scavenge relocates every live young
	object and leaves old space put, and the snapshot array pins the dead young objects
	for the duration (verified: holding it across a scavenge kept 20000 orphaned
	Semaphores alive), so EVERY object at or after the boundary must move and none before
	it may.

	Only a window around the boundary is read. Reading all 6.9M addresses takes 2.5 s, and
	the ~50 involuntary scavenges that fire in that time relocate and tenure the objects
	being tracked -- the first version of this check reported 16890 spurious non-movers
	purely from its own runtime.

	Answers a report; perfect agreement is aboveMoved = young and belowMoved = 0."
	| all n boundary from before after aboveMoved belowMoved |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ 'allObjectsOrNil failed'].
	n := all size.
	boundary := self youngBoundaryIn: all.
	from := (boundary - 5000) max: 1.
	self addrBuffersFor: n.
	before := beforeAddrs.
	after := afterAddrs.
	from to: n do: [:i | before at: i put: (self rawAddressOf: (all at: i))].
	Smalltalk garbageCollectMost.
	from to: n do: [:i | after at: i put: (self rawAddressOf: (all at: i))].
	aboveMoved := 0.
	belowMoved := 0.
	from to: n do: [:i |
		(before at: i) ~= (after at: i) ifTrue: [
			i >= boundary
				ifTrue: [aboveMoved := aboveMoved + 1]
				ifFalse: [belowMoved := belowMoved + 1]]].
	all := nil.
	^ {
		'heap' -> n.
		'young' -> (n - boundary + 1).
		'aboveMoved' -> aboveMoved.
		'belowScanned' -> (boundary - from).
		'belowMoved' -> belowMoved }
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState >> wrapper [
	wrapper ifNil: [wrapper := AlienStub forOop].
	^ wrapper
]

{
	#category : #addressing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:21'
}
SWAYoungSpaceState >> youngBoundaryIn: allObjects [
	"Index of the first young object in an allObjectsOrNil snapshot; allObjects size + 1
	when young space is empty.

	Prim 178 enumerates region by region, ascending within a region, old space first and
	new space last, so the whole array is ascending except for ONE large descent at the
	old/young edge. Measured here: old space 272 MB rising to 2014 MB, new space 265 MB
	-- new space sits BELOW old space, which is why a fixed address threshold (2026-08-19)
	could not work and why the DISCONTINUITY is the only reliable cut.

	That shape is a rotated sorted array, so the edge is found by exponential search back
	from the end plus a binary search: ~30 address reads rather than one per object. The
	window is far wider than the few hundred KB of new space and far narrower than the
	1.7 GB gap to old space, so the handful of sub-MB descents inside young space (the
	survivor/eden split) cannot be mistaken for it."
	| n window k lo hi anchor |
	n := allObjects size.
	n = 0 ifTrue: [^ 1].
	anchor := self rawAddressOf: (allObjects at: n).
	anchor < 0 ifTrue: [^ n + 1].
	window := 32 * 1048576.
	k := 1.
	[k < n and: [((self rawAddressOf: (allObjects at: n - k)) - anchor) abs < window]]
		whileTrue: [k := k * 2].
	k >= n ifTrue: [^ 1].
	lo := n - k max: 1.
	hi := n - (k // 2).
	[lo + 1 < hi] whileTrue: [
		| mid |
		mid := lo + hi // 2.
		((self rawAddressOf: (allObjects at: mid)) - anchor) abs < window
			ifTrue: [hi := mid]
			ifFalse: [lo := mid]].
	^ hi
]

{
	#category : #marking,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:53'
}
SWAYoungSpaceState >> youngReferentsOf: anObject do: aBlock [
	"Evaluate aBlock with each young object anObject points at, the way the collector
	would. Slots are read through the thisContext mirror so a proxy cannot intercept and
	run code in the middle of the walk.

	CompiledMethods are handled separately: their format is not #isPointers, so the
	generic indexable path would read bytecode as if it were pointers and miss the
	literals -- which is exactly where a freshly compiled method holds young objects.

	A weak class's INDEXABLE slots are skipped, since an object reachable only from there
	is collected. Its named slots are strong and are followed. Ephemerons are not modelled."
	| mirror cls n v |
	mirror := thisContext.
	cls := mirror objectClass: anObject.
	n := cls instSize.
	1 to: n do: [:k |
		v := mirror object: anObject instVarAt: k.
		(self isYoungValue: v) ifTrue: [aBlock value: v]].
	cls isCompiledMethodClass ifTrue: [
		n := anObject numLiterals.
		1 to: n do: [:k |
			v := anObject literalAt: k.
			(self isYoungValue: v) ifTrue: [aBlock value: v]].
		^ self].
	(cls isPointers and: [cls isWeak not]) ifTrue: [
		n := mirror objectSize: anObject.
		1 to: n do: [:k |
			v := mirror object: anObject basicAt: k.
			(self isYoungValue: v) ifTrue: [aBlock value: v]]].
	^ self
]
