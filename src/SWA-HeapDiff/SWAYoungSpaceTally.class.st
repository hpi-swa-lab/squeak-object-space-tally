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
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:08'
}
SWAYoungSpaceTally class >> reset [
	"Nil every class-pool variable -- a hard reset that drops all cached buffers, age
	tables, wrappers and bookkeeping so nothing from a previous design or run is left
	lying around (the source of the stray 32MB tiles). The next collect rebuilds only what
	it needs. Run a full GC after to actually reclaim the orphaned arrays."
	"Drop the reused measurement state singleton (which holds every buffer and array) and
	GC. One root, one reset."
	SWAYoungSpaceState reset.
	^ self
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:05'
}
SWAYoungSpaceTally class >> sampleOnce [
	"Take ONE young-space sample by move-detection and answer a quick report: how long it
	took, how many young objects, and the class histogram. For manual inspection -- no
	ages, no treemap, no held state.

	Move-detection: snapshot allObjectsOrNil (born old, invisible to young), read every
	address, garbageCollectMost, read again; the movers are young. Reuses the state's
	before/after buffers. Drops everything."
	| state young ms hist |
	state := SWAYoungSpaceState default.
	young := OrderedCollection new.
	ms := [state detectYoungInto: young] timeToRun.
	hist := Dictionary new.
	young do: [:o | hist at: o class put: (hist at: o class ifAbsent: [0]) + 1].
	^ {
		'ms' -> ms.
		'youngCount' -> young size.
		'topClasses' -> ((hist associations asSortedCollection: [:a :b | a value > b value])
			asArray first: (hist size min: 15)) }
]

{
	#category : #buffers,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:21'
}
SWAYoungSpaceTally class >> tailSize [
	"How many entries at the end of allObjects to scan. New space is the contiguous tail;
	measured movers span the last ~100k, so 300k is a safe window with headroom. Larger
	is slower (defeats the atomicity win); smaller risks clipping the young band. Buffer
	length is sized to this."
	^ 300000
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
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:08'
}
SWAYoungSpaceTally >> collect [
	"Collect the current live young objects into `survivors` (a plain snapshot, no ages).
	Delegates to the reused old-space state's allocation-free, block-free young walk."
	survivors := SWAYoungSpaceState default collectYoungObjects.
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
	#'squeak_changestamp' : 'MCPServer 8/20/2026 15:59'
}
SWAYoungSpaceTally >> newObjects [
	"The collected young survivors -- the object universe for all inherited enrichment
	(#spaceTally, #addProvenanceBranchUnder:, #openEnrichedTreemap*). No filtering needed:
	the sampling stores only identityHashes and the final #collect allocates nothing, so
	no measurement object ends up in the young set."
	^ survivors
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 17:03'
}
SWAYoungSpaceTally >> openTreemap [
	"Collect the current young objects and open the enriched Space Tally treemap -- a plain
	young-space snapshot."
	self collect.
	survivors isEmpty ifTrue: [^ self inform: 'young space is empty'].
	^ self openEnrichedTreemapWithProgress
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:21'
}
SWAYoungSpaceTally >> tailSize [
	"Instance-side convenience; the value lives on the class (buffers are sized to it)."
	^ self class tailSize
]
