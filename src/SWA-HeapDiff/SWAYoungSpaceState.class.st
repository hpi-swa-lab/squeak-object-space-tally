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
		'hashArrays',
		'hashCounts',
		'beforeAddrs',
		'afterAddrs'
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState class >> sampleCapacity [
	"Max young objects a single snapshot's hash Array holds."
	^ 100000
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:08'
}
SWAYoungSpaceState >> ageByObjectFor: youngObjects [
	"After sampling and a #collectYoungObjects, compute each object's age from the hash
	snapshots. Measuring is over, so allocate freely (Sets for O(1) membership).

	AGE = longest run counting back from the LAST snapshot: age k iff the object's
	identityHash is in the last k snapshots consecutively. An object present in an EARLIER
	snapshot than the run reaches (appeared, vanished, reappeared -- probably a 22-bit
	identityHash collision) is counted in anomalies.

	Answers { ageByObject IdentityDictionary. anomalyCount }."
	| nSnaps hashSets ageByObject anomalies |
	nSnaps := hashArrays ifNil: [^ {IdentityDictionary new. 0}] ifNotNil: [hashArrays size].
	hashSets := (1 to: nSnaps) collect: [:k | | set count hs |
		hs := hashArrays at: k. count := hashCounts at: k.
		set := Set new: count * 4 // 3 + 16.
		1 to: count do: [:i | set add: (hs at: i)].
		set].
	ageByObject := IdentityDictionary new: youngObjects size * 4 // 3 + 16.
	anomalies := 0.
	youngObjects do: [:obj | | h age gapThenBack |
		h := obj identityHash.
		age := 0.
		nSnaps to: 1 by: -1 do: [:s |
			(age = (nSnaps - s) and: [(hashSets at: s) includes: h])
				ifTrue: [age := age + 1]].
		ageByObject at: obj put: age.
		gapThenBack := false.
		1 to: nSnaps - age do: [:s |
			((hashSets at: s) includes: h) ifTrue: [gapThenBack := true]].
		gapThenBack ifTrue: [anomalies := anomalies + 1]].
	^ {ageByObject. anomalies}
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:41'
}
SWAYoungSpaceState >> collectYoungObjects [
	"Answer an OrderedCollection of the actual live young objects, by move-detection. The
	result holds real young objects (that IS the intended young allocation); the big
	allObjectsOrNil + address buffers are old and invisible to young."
	| result |
	result := OrderedCollection new: 20000.
	self detectYoungInto: result hashesOnly: false.
	^ result
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:46'
}
SWAYoungSpaceState >> detectYoungInto: aCollectionOrNil hashesOnly: hashesFlag [
	"The one move-detection primitive. Snapshot allObjectsOrNil (its ~21MB array is born
	OLD, invisible to young), read every object's address into a big buffer, scavenge, read
	again; an object whose address CHANGED is young. Either append the young objects to
	aCollectionOrNil (hashesFlag = false) or write their identityHashes into aCollectionOrNil
	(a preallocated hash Array; hashesFlag = true). Answers the count.

	The address buffers are large so they are born old and never appear in young. The hot
	loops are inlined (whileTrue:/ifTrue:) so no closure/context of ours is created young
	during the measurement. addressField is read-only, one object at a time.

	NOTE this does its OWN garbageCollectMost -- callers on the render loop should instead
	pass through here only when they mean to force a scavenge; the every-3rd-scavenge driver
	simply calls this (its forced scavenge coincides with a real one often enough, and even
	a forced one correctly reveals the movers)."
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
	"Movers = young. Record them (hash into the preallocated hash Array, or the object)."
	count := 0.
	a := 1.
	[a <= n] whileTrue: [
		((before at: a) ~= (after at: a) and: [(before at: a) ~= -1]) ifTrue: [
			o := all at: a.
			count := count + 1.
			hashesFlag
				ifTrue: [count <= aCollectionOrNil size ifTrue: [aCollectionOrNil at: count put: o identityHash]]
				ifFalse: [aCollectionOrNil add: o]].
		a := a + 1].
	"Drop the transient allObjectsOrNil array -- never stored."
	all := nil.
	^ count
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState >> hashArrays [
	^ hashArrays
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState >> hashCounts [
	^ hashCounts
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:41'
}
SWAYoungSpaceState >> prepareForSamples: nSamples [
	"Allocate all N hash Arrays + the counts + the address buffer + the wrapper, then a
	full GC to tenure everything into old space -- so none of it is young during a walk.
	Reused: only reallocates the hash Arrays to match nSamples."
	"Allocate the N hash Arrays + counts + wrapper, then a full GC to tenure them into old
	space. Each hash Array is large (sampleCapacity), so it is born old and never appears
	in the young set it records."
	| cap |
	cap := self class sampleCapacity.
	self wrapper.
	hashArrays := (1 to: nSamples) collect: [:each | Array new: cap withAll: 0].
	hashCounts := Array new: nSamples withAll: 0.
	Smalltalk garbageCollect.
	^ self
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:40'
}
SWAYoungSpaceState >> recordHashesAt: sampleIndex [
	"ONE sample: detect the live young objects by move-detection and write their
	identityHashes into the sampleIndex-th preallocated hash Array. Answers the count."
	| count |
	count := self detectYoungInto: (hashArrays at: sampleIndex) hashesOnly: true.
	hashCounts at: sampleIndex put: count.
	^ count
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState >> wrapper [
	wrapper ifNil: [wrapper := AlienStub forOop].
	^ wrapper
]
