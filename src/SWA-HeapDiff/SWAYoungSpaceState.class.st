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
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:05'
}
SWAYoungSpaceState >> collectYoungObjects [
	"Answer an OrderedCollection of the actual live young objects, by move-detection. The
	result holds real young objects (that IS the intended young allocation); the big
	allObjectsOrNil + address buffers are old and invisible to young."
	| result |
	result := OrderedCollection new: 20000.
	self detectYoungInto: result.
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:07'
}
SWAYoungSpaceState >> wrapper [
	wrapper ifNil: [wrapper := AlienStub forOop].
	^ wrapper
]
