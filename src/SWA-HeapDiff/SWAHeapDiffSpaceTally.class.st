"
A SWASpaceTally whose closed universe IS a given collection of objects (the
SWAHeapDiff's new objects), not the whole heap.

The parent's #captureUniverse snapshots the entire live heap into deepUniverse
(a ~2.7M-entry IdentityDictionary -- slow, and the thing that OOM-crashed the
image when done twice). Here #captureUniverse instead loads deepUniverse with
only the diff objects. Because SWASpaceTally>>isTallyable: rejects anything not
in deepUniverse, the BFS then never follows a reference OUT of the diff into a
pre-existing shared object -- so the walk stays confined to the diff, is bounded
by the diff size, and needs no full-heap snapshot at all.

Use SWAHeapDiff>>spaceTally, which seeds the diff objects as roots and here as
the universe.
"
Class {
	#name : #SWAHeapDiffSpaceTally,
	#superclass : #SWASpaceTally,
	#instVars : [
		'diffObjects'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:37'
}
SWAHeapDiffSpaceTally >> captureUniverse [
	"Override: the closed universe is the diff objects, not the whole heap. No
	allObjectsOrNil, no full-heap IdentityDictionary. isTallyable: then rejects
	everything outside the diff, so the walk never leaves it."

	deepUniverse := IdentityDictionary new: diffObjects size * 4 // 3 + 16.
	diffObjects do: [:each | deepUniverse at: each put: nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:37'
}
SWAHeapDiffSpaceTally >> diffObjects: aCollection [
	"The objects that ARE the universe: the diff's new objects."

	diffObjects := aCollection
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:40'
}
SWAHeapDiffSpaceTally >> referencedDiffObjects [
	"Pre-pass: the set of diff objects that ARE referenced by some OTHER diff
	object. Scans every diff object's referents (same slot reader the BFS uses)
	and records any referent that is itself in the diff universe. Whatever is
	left out is a root -- a new object no other new object points at.

	Runs after #captureUniverse, so deepUniverse holds the diff and `mirror` is
	set up. Self-references are ignored (an object is not its own parent)."

	| referenced |
	referenced := IdentitySet new: diffObjects size * 4 // 3 + 16.
	diffObjects do: [:obj |
		self referentsOf: obj do: [:referent :slotKind :slotIndex |
			(referent ~~ obj and: [deepUniverse includesKey: referent])
				ifTrue: [referenced add: referent]]].
	^ referenced
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:41'
}
SWAHeapDiffSpaceTally >> seedRoots [
	"Seed only the TRUE roots: diff objects no other diff object references.
	The pre-pass finds the referenced ones; the rest become roots, so the BFS
	then attributes every referenced diff object to its real in-diff parent and
	the treemap shows containment instead of thousands of flat siblings.

	The remaining diff objects are still all reachable: each is referenced by
	some diff object, and every diff object is reachable from a root (worst case
	a pure cycle with no external root -- then nothing is a root and we fall back
	to seeding all, so a cyclic diff still gets walked)."

	| referenced trueRoots |
	referenced := self referencedDiffObjects.
	trueRoots := roots reject: [:each | | obj |
		obj := (each isKindOf: Association) ifTrue: [each value] ifFalse: [each].
		referenced includes: obj].
	trueRoots isEmpty ifFalse: [roots := trueRoots].
	super seedRoots
]
