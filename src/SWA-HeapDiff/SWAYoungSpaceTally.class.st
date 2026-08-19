"
A structural treemap of what is in YOUNG SPACE right now -- the cruft the XR scavenge
hunt (journal 2026-08-14b) is chasing. Sibling of the GC Diff (SWAHeapDiff): same
enriched treemap + provenance-by-home-method view, different object set.

WHAT IT MEASURES: young space as it stands, with NO perturbation -- no full GC, no
scavenge, no born-before mask. A GC would drain exactly the transient young objects we
want to see; the mask approach was wrong (it marks everything currently alive as 'old',
so it hides the standing young floor, and its 22-bit identity-hash table collides
heavily at 2.6M objects). Both abandoned.

HOW: SystemNavigation allObjectsOrNil enumerates the heap with new space as a
contiguous TAIL (verified: fresh objects land in the last slots of the array). New
space is a contiguous ADDRESS region, so we read each tail object's raw address
(AlienStub addressField, read-only, one object at a time -- never feeding an oop back)
and walk backward from the end while the address stays in the young band. That tail IS
young space. No GC touches it.

The collected objects become #newObjects, so the inherited #spaceTally,
#addProvenanceBranchUnder: and #openEnrichedTreemapWithProgress all work unchanged: the
treemap shows young-object containment and the Provenance branch names the code
(Class>>selector) behind the surviving closures and Contexts.

survivors: the collected young objects, held only for the analysis window. Drop this
instance (or null survivors) afterward so they are not pinned as an MCP eval result.
"
Class {
	#name : #SWAYoungSpaceTally,
	#superclass : #SWAHeapDiff,
	#instVars : [
		'survivors'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:27'
}
SWAYoungSpaceTally class >> openTreemap [
	"Collect what is in young space now and open the enriched treemap. This is the entry
	point. Does not retain the tally as a caller value (it holds the young objects); the
	window keeps only what it needs."
	^ self new openTreemap
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:29'
}
SWAYoungSpaceTally class >> xrMenuYoungSpaceNow: aMenu [
	"Open a Space Tally treemap of everything in young space right now -- no GC, no
	scavenge, no mask, so nothing transient is drained before we look. Deferred to the
	next frame boundary so the collect and the (heavy) treemap build run with the render
	loop blocked, like the other memory entries. The pragma is only ever scanned by
	SRMenuRegistry, so this method is inert without SqueakXR."

	<xrMenu: #(world profile) label: 'young space now' priority: 215>
	| world |
	world := SRWorld current.
	world ifNil: [^ nil].
	^ world addDeferredFrameMessage: [self new openTreemap]
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:26'
}
SWAYoungSpaceTally >> collect [
	"Collect the objects in young space NOW into `survivors`, with no perturbation:
	no full GC, no scavenge, no born-before mask. allObjectsOrNil enumerates the heap
	with new space as a contiguous TAIL; new space is a contiguous address region, so we
	walk backward from the end while each object's address stays within the young band
	of the last (definitely young) object, and that tail is young space.

	addressField is read-only, one object at a time -- the oop is never fed back to the
	VM. The band half-width (8 MB) comfortably exceeds new space (a few hundred KB here)
	while staying far below the young/old gap, so the boundary is the address
	discontinuity into old space. Approximate within a few objects at the very edge; the
	class composition is exact."
	| all n wrap addrOf youngHi i boundary |
	survivors := OrderedCollection new.
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ self error: 'could not snapshot heap (low memory)'].
	n := all size.
	n = 0 ifTrue: [^ self].
	wrap := AlienStub forOop.
	addrOf := [:o | wrap oopAt: 1 put: o. wrap addressField].
	youngHi := addrOf value: (all at: n).
	i := n.
	boundary := n + 1.
	[i > 0 and: [(addrOf value: (all at: i)) between: youngHi - 8000000 and: youngHi + 8000000]]
		whileTrue: [boundary := i. i := i - 1].
	boundary to: n do: [:j | survivors add: (all at: j)].
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:10'
}
SWAYoungSpaceTally >> diff [
	"Tally the collected survivors by class (proxy-safe via #classOf:), so the inherited
	#report works. No before\/after arrays here -- the survivor set is already computed."
	| counts |
	counts := IdentityDictionary new: 1024.
	survivors do: [:obj | | cls |
		cls := self classOf: obj.
		counts at: cls put: (counts at: cls ifAbsent: [0]) + 1].
	newCount := survivors size.
	countsByClass := counts.
	^ self
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:26'
}
SWAYoungSpaceTally >> initialize [
	super initialize.
	survivors := OrderedCollection new.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:10'
}
SWAYoungSpaceTally >> newObjects [
	"The collected young survivors. Overrides the before\/after diff so all inherited
	enrichment (#spaceTally, #addProvenanceBranchUnder:, #openEnrichedTreemap*) treats
	the survivor set as its object universe."
	^ survivors
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 12:27'
}
SWAYoungSpaceTally >> openTreemap [
	"Collect young space now (if not already) and open the enriched Space Tally treemap
	on it: young-object containment plus a Provenance branch naming the code behind the
	surviving closures and Contexts."
	survivors ifEmpty: [self collect].
	survivors ifEmpty: [^ self inform: 'young space is empty'].
	^ self openEnrichedTreemapWithProgress
]
