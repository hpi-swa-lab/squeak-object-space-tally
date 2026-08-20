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
		'survivors',
		'ageByHash',
		'anomalies',
		'snapshots'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 15:58'
}
SWAYoungSpaceTally class >> defaultSampleCount [
	"How many young-space snapshots a sample run takes by default."
	^ 10
]

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
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:15'
}
SWAYoungSpaceTally class >> openTreemapAcrossScavenges: nScavenges [
	"Sample the running loop's young space after each of its next nScavenges scavenges,
	building survivor age, then open the age-coloured treemap. Shows an SRTextField
	progress label (scavenge N / nScavenges) in the world meanwhile. Needs a running
	SRWorld; answers nil if there is none."
	| world |
	world := SRWorld current.
	world ifNil: [^ nil].
	^ self new
		sampleAcrossScavenges: nScavenges
		in: world
		thenOpen: true
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
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:51'
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
	ms := [state detectYoungInto: young hashesOnly: false] timeToRun.
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
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:15'
}
SWAYoungSpaceTally class >> xrMenuYoungSpaceTenScavenges: aMenu [
	"Sample young space after each of the loop's next 10 scavenges (building survivor
	age), showing a progress label, then open the age-coloured treemap -- cruft that
	survives many scavenges shows hot, fresh churn cool. The pragma is only ever scanned
	by SRMenuRegistry, so this method is inert without SqueakXR."

	<xrMenu: #(world profile) label: 'young space age (10 scavenges)' priority: 217>
	^ self openTreemapAcrossScavenges: 10
]

{
	#category : #'age tracking',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 15:58'
}
SWAYoungSpaceTally >> ageOf: anObject [
	"How many consecutive samples anObject has been a young survivor. 0 if untracked or
	expired (last seen before the current generation). Approximate under identityHash
	collision. Reads the tenured tables directly -- no per-object allocation."
	"Longest run from the last snapshot (see #computeAges). 0 if untracked."
	ageByHash ifNil: [^ 0].
	^ ageByHash at: anObject ifAbsent: [0]
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:00'
}
SWAYoungSpaceTally >> armSampleIn: aWorld remaining: remaining total: total sincePar9: p9AtStart label: label thenOpen: openTreemap [
	"One re-armed frame step. If the loop has scavenged since p9AtStart, take a sample
	(collect + age update), advance the progress label, and recurse with remaining-1;
	when remaining hits 0, remove the label and open the age-coloured treemap. Otherwise
	wait a frame. Runs in the between-frame action, so the render loop is blocked while we
	sample -- clean, and the label text update is picked up on the next presented frame."
	aWorld addDeferredFrameMessage: [
		(Smalltalk vmParameterAt: 9) > p9AtStart
			ifTrue: [
				| done |
				done := total - remaining + 1.
				"Take the done-th HASH snapshot (allocation-free) right after the loop's
				own scavenge -- so the young set sampled is the post-scavenge survivor
				floor, and consecutive snapshots span real loop scavenges."
				self class takeSampleAt: done.
				label text: 'young space: scavenge ', done printString, ' / ', total printString.
				remaining <= 1
					ifTrue: [
						"All snapshots taken: now collect the real objects and compute ages."
						self collect.
						self computeAges.
						label remove.
						openTreemap ifTrue: [self openEnrichedTreemapWithProgress]]
					ifFalse: [
						self armSampleIn: aWorld
							remaining: remaining - 1
							total: total
							sincePar9: (Smalltalk vmParameterAt: 9)
							label: label
							thenOpen: openTreemap]]
			ifFalse: [
				self armSampleIn: aWorld
					remaining: remaining
					total: total
					sincePar9: p9AtStart
					label: label
					thenOpen: openTreemap]]
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
	#category : #'age tracking',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:55'
}
SWAYoungSpaceTally >> computeAges [
	"After sampling AND a final #collect, compute each survivor's age from the N hash
	snapshots. Measuring is over, so we allocate freely.

	AGE = longest run counting back from the LAST snapshot: an object is age k iff its
	identityHash is present in the last k snapshots consecutively (k = 0 if absent from the
	final snapshot). Appeared-then-vanished-then-reappeared is logged as an anomaly (likely
	a 22-bit identityHash collision) so we can gauge how often it happens.

	Fills ageByHash (object -> age) for the treemap, and anomalies (a count) for intuition."
	"Compute each survivor's age from the accumulated #sample snapshots (Sets of stable
	identity oops). AGE = longest run counting back from the LAST snapshot: age k iff the
	object's oop is in the last k snapshots consecutively. Appeared-vanished-reappeared is
	counted as an anomaly. Measuring is over, so allocate freely."
	| snaps nSnaps |
	snaps := snapshots ifNil: [#()].
	nSnaps := snaps size.
	ageByHash := IdentityDictionary new: survivors size * 4 // 3 + 16.
	anomalies := 0.
	survivors do: [:obj | | h age gapThenBack |
		h := obj identityHash.
		age := 0.
		nSnaps to: 1 by: -1 do: [:s |
			(age = (nSnaps - s) and: [(snaps at: s) includes: h])
				ifTrue: [age := age + 1]].
		ageByHash at: obj put: age.
		gapThenBack := false.
		1 to: nSnaps - age do: [:s |
			((snaps at: s) includes: h) ifTrue: [gapThenBack := true]].
		gapThenBack ifTrue: [anomalies := anomalies + 1]].
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
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:00'
}
SWAYoungSpaceTally >> openEnrichedTreemapWithProgress [
	"Open the enriched treemap, then inject the object->age map so the 'By survivor age'
	colour mode becomes available. ageByHash is computed by #computeAges after sampling;
	nil if the tally was only #collect-ed, in which case no age mode is offered."
	| win morph |
	win := super openEnrichedTreemapWithProgress.
	ageByHash ifNotNil: [
		morph := win ifNotNil: [self treemapMorphIn: win].
		morph ifNotNil: [morph ageByObject: ageByHash]].
	^ win
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:15'
}
SWAYoungSpaceTally >> openProgressLabelIn: aWorld for: nScavenges [
	"A transient SRTextField in the running world showing scavenge progress. Added as a
	child (and removed when done, in #armSampleIn:...). Placed a couple of metres in front
	and slightly up so it is visible in the headset."
	| label |
	label := SRTextField new
		text: 'young space: scavenge 0 / ', nScavenges printString;
		color: Color yellow;
		position: (Vector3 x: -0.6 y: 1.6 z: -2);
		scale: (Vector3 one * 0.2);
		yourself.
	aWorld addChild: label.
	^ label
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:54'
}
SWAYoungSpaceTally >> openTreemap [
	"Collect the current young objects and open the enriched Space Tally treemap. If any
	#sample snapshots were taken, colour by survivor age (run of consecutive snapshots from
	the last); otherwise it is a plain young-space snapshot."
	self collect.
	survivors isEmpty ifTrue: [^ self inform: 'young space is empty'].
	(snapshots notNil and: [snapshots notEmpty]) ifTrue: [self computeAges].
	^ self openEnrichedTreemapWithProgress
]

{
	#category : #'age tracking',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:08'
}
SWAYoungSpaceTally >> runSamples: nSamples [
	"The whole measurement, Jens's sketch:
	  1. take nSamples young-space HASH snapshots (allocation-free, block-free -- only
	     SmallInteger identityHashes are stored, in preallocated old-space Arrays);
	  2. #collect the real young objects once;
	  3. #computeAges: each object's age = longest run back from the last snapshot.
	When driven inline (desktop) the samples are back-to-back; the frame-driven class-side
	sampler spaces them across the render loop's own scavenges instead."
	| state |
	state := SWAYoungSpaceState default.
	state prepareForSamples: nSamples.
	1 to: nSamples do: [:i | state recordHashesAt: i].
	survivors := state collectYoungObjects.
	self computeAges.
	^ self
]

{
	#category : #'age tracking',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:55'
}
SWAYoungSpaceTally >> sample [
	"Take ONE young-space snapshot and remember it. Call as many times as you like -- each
	call appends a snapshot; #openTreemap then computes each object's age as the run of
	consecutive snapshots (from the last) it appeared in. One move-detection pass over
	allObjectsOrNil (~3s); the young objects' stable identity oops (asOop -- survives
	scavenge moves, no 22-bit hash collision) go into this snapshot."
	| young snapshot |
	snapshots ifNil: [snapshots := OrderedCollection new].
	young := OrderedCollection new.
	SWAYoungSpaceState default detectYoungInto: young hashesOnly: false.
	"Store this snapshot as a Set of identityHashes for fast membership later. identityHash
	is stable across scavenge moves (unlike the physical address) and safe (unlike asOop).
	The 22-bit collision at a few thousand objects is minor and surfaces as anomalies."
	snapshot := Set new: young size * 4 // 3 + 16.
	young do: [:o | snapshot add: o identityHash].
	snapshots add: snapshot.
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 16:00'
}
SWAYoungSpaceTally >> sampleAcrossScavenges: nScavenges in: aWorld thenOpen: openTreemap [
	"Watch the render loop's own scavenges and #sample after each one, for nScavenges
	scavenges, so survivor ages accumulate across real loop scavenges (persistent cruft
	climbs, transient churn stays age 1). A progress bar tracks 1..nScavenges. When done,
	optionally open the age-coloured treemap.

	Frame-driven: re-arm a between-frame action each frame; when p9 (vmParameterAt: 9,
	the scavenge counter) has ticked since the last sample, a scavenge just ran, so we
	#sample (at the boundary, loop blocked -- clean) and advance. Between scavenges we
	just wait a frame. #sample folds the survivors into the persistent age table."
	| label |
	self class startSamplingWith: nScavenges.
	label := self openProgressLabelIn: aWorld for: nScavenges.
	self armSampleIn: aWorld
		remaining: nScavenges
		total: nScavenges
		sincePar9: (Smalltalk vmParameterAt: 9)
		label: label
		thenOpen: openTreemap.
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/20/2026 11:21'
}
SWAYoungSpaceTally >> tailSize [
	"Instance-side convenience; the value lives on the class (buffers are sized to it)."
	^ self class tailSize
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 10:53'
}
SWAYoungSpaceTally >> treemapMorphIn: aWindow [
	"Find the SWASpaceTallyTreemapMorph inside the opened window, so we can hand it the
	age table."
	^ aWindow
		ifNil: [nil]
		ifNotNil: [aWindow allMorphs
			detect: [:m | m isKindOf: SWASpaceTallyTreemapMorph]
			ifNone: [nil]]
]
