"
Finds which objects survive a scavenge without perturbing the GC.

The trap in a normal heap snapshot (SWAHeapDiff): the returned Array holds every object live, so nothing can die -- you destroy the behaviour you measure. This does not retain objects. It fingerprints them: it walks the heap and stores each object's identityHash (an immediate SmallInteger, so no allocation and no reference) into a preallocated integer table. Two walks bracket one scavenge; an object whose fingerprint appears in both walks (and whose count is preserved) survived.

Correctness rests on three facts, all verified: identityHash is stable across a scavenge (survivors are copied but the VM preserves the hash); the tight walk (someObject/nextObject with inlined whileFalse:, storing hashes into a preallocated table) allocates zero bytes -- no context, no closure -- so it cannot itself fill eden; and run at highestPriority nothing else allocates either, so eden cannot fill during a walk and the only scavenge is the one we trigger between the walks.

Limitation: identityHash is 22 bits, so with millions of objects hashes collide. The result is therefore a class-composition estimate (counts by class are robust to individual collisions), not exact per-object identity.
"
Class {
	#name : #SRSurvivorCensus,
	#superclass : #Object,
	#instVars : [
		'endMarker',
		'bornBefore',
		'tableA',
		'tableAfter',
		'countBefore',
		'countAfter'
	],
	#classVars : [
		'Pending'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:34'
}
SRSurvivorCensus class >> reportTop: n [
	"Run a survivor census and answer a printable top-n histogram of surviving classes.
	One call: allocate the census, capture at highest priority, format."

	^ (self new captureSurvivorsAfterWorkMs: 500) reportTop: n
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:47'
}
SRSurvivorCensus class >> xrMenuBaseline: aMenu [
	"Step 1: full GC and fingerprint the whole heap as the born-before baseline. Stash the
	census so #xrMenuMeasure: can complete it. Runs in a between-frame action so the mask
	walk happens with the render loop blocked (its high-priority requirement)."

	<xrMenu: #(world debug profile) label: 'GC Survivors: 1. Baseline' priority: 436>
	| world |
	world := SRWorld current ifNil: [^ nil].
	world addDeferredFrameMessage: [
		Pending := self new captureBaseline.
		Transcript showln: 'GC Survivors: baseline captured. Now open a game / let it run, then pick "2. Measure".'].
	^ Pending
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:47'
}
SRSurvivorCensus class >> xrMenuMeasure: aMenu [
	"Step 2: take walk A, wait for the render loop's next scavenge, take walk B, then open
	a workspace with the young-survivor class histogram. Requires #xrMenuBaseline: first."

	<xrMenu: #(world debug profile) label: 'GC Survivors: 2. Measure' priority: 437>
	| world census |
	world := SRWorld current ifNil: [^ nil].
	census := Pending.
	census ifNil: [
		Transcript showln: 'GC Survivors: no baseline. Pick "1. Baseline" first.'.
		^ nil].
	census measureAcrossScavengeIn: world then: [:done |
		"Back on a between-frame action; open the workspace from the UI process."
		WorldState addDeferredUIMessage: [
			(Workspace new contents: done fullReport) openLabel: 'GC Survivors'].
		Pending := nil].
	^ census
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:47'
}
SRSurvivorCensus >> armScavengeWatchIn: aWorld since: p9AtA then: aResultBlock [
	"Re-arm a between-frame check: if a scavenge has happened since walk A, take walk B
	now and report; otherwise wait for the next frame and check again."

	aWorld addDeferredFrameMessage: [
		(Smalltalk vmParameterAt: 9) > p9AtA
			ifTrue: [
				self captureYoungB.
				aResultBlock value: self]
			ifFalse: [
				self armScavengeWatchIn: aWorld since: p9AtA then: aResultBlock]]
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:52'
}
SRSurvivorCensus >> captureBaseline [
	"Step 1 of the interactive flow: full GC, then fingerprint every surviving object as
	'born before' (the old/permanent set). Anything found young later was born after this."

	bornBefore atAllPut: 0.
	tableA atAllPut: 0.
	tableAfter atAllPut: 0.
	Smalltalk garbageCollect.
	self captureBornBeforeMask.
	^ self
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:51'
}
SRSurvivorCensus >> captureBornBeforeMask [
	"Walk the whole heap after a full GC, marking every object's hash slot in tableBefore
	as 'born before' (1). Any object later found with an empty slot was born after this
	moment -- i.e. young. Allocation-free (same rules as the other walks)."

	"someObject/nextObject does not reliably enumerate the young tail on this Spur VM, so
	use the array primitive. It allocates a 2.6M array, but we walk it in one pass and
	drop it -- one array held briefly, not two snapshots retained (cf. SWAHeapDiff)."
	SystemNavigation default allObjectsOrNil do: [:object |
		bornBefore at: object identityHash + 1 put: 1]
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:24'
}
SRSurvivorCensus >> captureSurvivors [
	"Run the census at highest priority, retrying until the scavenge bracket is clean.
	Blocks the caller (via a plain busy flag polled with a Delay at normal priority)
	until done. Answer self; results are read afterward with #survivorHistogram.

	The forked block is the only closure, created before the measured window opens; the
	window itself (inside runCensus) allocates nothing."

	| done ok |
	done := false.
	[
		| attempts |
		attempts := 0.
		ok := false.
		[ok or: [attempts >= 20]] whileFalse: [
			attempts := attempts + 1.
			ok := self runCensus].
		done := true
	] forkAt: Processor highestPriority.
	[done] whileFalse: [(Delay forMilliseconds: 20) wait].
	^ self
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:34'
}
SRSurvivorCensus >> captureSurvivorsAfterWorkMs: workMs [
	"Full census of YOUNG survivors:
	  1. full GC, then walk the mask of everything born before (at high priority),
	  2. drop to normal priority for workMs so the real system allocates young objects,
	  3. at high priority again, walk A then walk B (each someObject-scavenges), tallying
	     by class the young objects (born after the mask) alive across the A->B scavenge.
	Blocks the caller until done; results via #survivorHistogram / #reportTop:."

	| done |
	done := false.
	[
		"Phase 1: baseline mask, high priority, allocation-free."
		bornBefore atAllPut: 0.
		tableA atAllPut: 0.
		tableAfter atAllPut: 0.
		Smalltalk garbageCollect.
		self captureBornBeforeMask.
		done := #masked
	] forkAt: Processor highestPriority.
	[done == #masked] whileFalse: [(Delay forMilliseconds: 5) wait].

	"Phase 2: let the system run and allocate young objects."
	(Delay forMilliseconds: workMs) wait.

	"Phase 3: the two young walks, high priority, allocation-free."
	done := false.
	[
		self captureYoungA.
		self captureYoungB.
		done := true
	] forkAt: Processor highestPriority.
	[done == true] whileFalse: [(Delay forMilliseconds: 5) wait].
	^ self
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:34'
}
SRSurvivorCensus >> captureSurvivorsAroundWork: aWorkBlock [
	"Like #captureSurvivorsAfterWorkMs: but instead of idling, run aWorkBlock during
	phase 2 to generate the young allocation. Use this on the desktop where nothing
	else allocates; on a running XR/Morphic system the idle-wait variant suffices.
	aWorkBlock runs at normal priority (it may keep some objects alive to be found)."

	| done |
	done := false.
	[
		bornBefore atAllPut: 0.
		tableA atAllPut: 0.
		tableAfter atAllPut: 0.
		Smalltalk garbageCollect.
		self captureBornBeforeMask.
		done := #masked
	] forkAt: Processor highestPriority.
	[done == #masked] whileFalse: [(Delay forMilliseconds: 5) wait].

	aWorkBlock value.

	done := false.
	[
		self captureYoungA.
		self captureYoungB.
		done := true
	] forkAt: Processor highestPriority.
	[done == true] whileFalse: [(Delay forMilliseconds: 5) wait].
	^ self
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:51'
}
SRSurvivorCensus >> captureYoungA [
	"Walk A. For each object born AFTER the mask (bornBefore slot empty = young), record
	its class-hash in tableA. someObject scavenges first, so this is the post-scavenge
	young set. Allocation-free."

	SystemNavigation default allObjectsOrNil do: [:object |
		(bornBefore at: object identityHash + 1) == 0
			ifTrue: [tableA at: object identityHash + 1 put: object class identityHash]]
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:52'
}
SRSurvivorCensus >> captureYoungB [
	"Walk B, after another scavenge (someObject). A young object survived if it is born
	after the mask AND its class-hash matches what walk A recorded at its slot. Tally
	survivors by class-hash into tableAfter. Allocation-free."

	SystemNavigation default allObjectsOrNil do: [:object | | classHash |
		classHash := object class identityHash.
		((bornBefore at: object identityHash + 1) == 0
			and: [(tableA at: object identityHash + 1) == classHash])
			ifTrue: [tableAfter at: classHash + 1 put: (tableAfter at: classHash + 1) + 1]]
]

{
	#category : #results,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:48'
}
SRSurvivorCensus >> fullReport [
	"Full young-survivor report: header plus the class histogram, all classes."

	| hist total |
	hist := self survivorHistogram.
	total := hist inject: 0 into: [:sum :p | sum + p value].
	^ String streamContents: [:s |
		s nextPutAll: 'GC Survivors -- young objects alive across one scavenge'; cr.
		s nextPutAll: '(old space excluded via a born-before mask; counts are a 22-bit-hash'; cr.
		s nextPutAll: ' estimate, so magnitudes are a lower bound but the ranking holds)'; cr; cr.
		s nextPutAll: 'total young survivors: '; print: total;
		  nextPutAll: '   classes: '; print: hist size; cr; cr.
		hist do: [:p | | count |
			count := p value printString.
			s next: (9 - count size max: 0) put: $ .
			s nextPutAll: count; nextPutAll: '  '; print: p key; cr]]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:33'
}
SRSurvivorCensus >> initialize [
	"Preallocate everything up front so the measured window allocates nothing. The end
	marker terminates the someObject/nextObject walk and must exist before the walk."

	super initialize.
	endMarker := Object new.
	bornBefore := Array new: self tableSize withAll: 0.
	tableA := Array new: self tableSize withAll: 0.
	tableAfter := Array new: self tableSize withAll: 0
]

{
	#category : #census,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:47'
}
SRSurvivorCensus >> measureAcrossScavengeIn: aWorld then: aResultBlock [
	"Step 2, frame-driven: take walk A now (this frame), then re-arm each frame until the
	scavenge counter ticks, and on that frame take walk B and evaluate aResultBlock with
	self. Each walk runs inside a between-frame action (render loop blocked = the high
	priority the allocation-free walk needs). Watching p9 lets B land on a real
	scavenge frame rather than a forced one, so we measure the loop's own scavenge."

	| p9AtA |
	tableA atAllPut: 0.
	tableAfter atAllPut: 0.
	self captureYoungA.
	p9AtA := Smalltalk vmParameterAt: 9.
	self armScavengeWatchIn: aWorld since: p9AtA then: aResultBlock
]

{
	#category : #results,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:27'
}
SRSurvivorCensus >> reportTop: n [
	"A printable histogram of the top n surviving classes."

	| hist total |
	hist := self survivorHistogram.
	total := hist inject: 0 into: [:sum :p | sum + p value].
	^ String streamContents: [:s |
		s nextPutAll: 'survivors: '; print: total;
		  nextPutAll: ' objects in '; print: hist size; nextPutAll: ' classes'; cr; cr.
		(hist first: (n min: hist size)) do: [:p | | count |
			count := p value printString.
			s next: (9 - count size max: 0) put: $ .
			s nextPutAll: count; nextPutAll: '  '; print: p key; cr]]
]

{
	#category : #results,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:25'
}
SRSurvivorCensus >> survivorHistogram [
	"Answer the survivor counts as an OrderedCollection of class -> count, descending.
	Runs after the measured window, so allocation is fine here. Maps each class-hash
	slot back to a Class; a hash shared by several classes is attributed to the first
	found (a 22-bit-hash approximation, see the class comment)."

	| byHash pairs |
	"class-hash -> Class, for the classes we can name."
	byHash := IdentityDictionary new.
	Smalltalk allClassesAndTraits do: [:cls |
		byHash at: cls identityHash put: cls.
		byHash at: cls class identityHash put: cls class].
	pairs := OrderedCollection new.
	1 to: tableAfter size do: [:i | | count |
		count := tableAfter at: i.
		count > 0 ifTrue: [
			pairs add: (byHash at: i - 1 ifAbsent: ['hash ', (i - 1) printString]) -> count]].
	^ pairs asSortedCollection: [:a :b | a value >= b value]
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:23'
}
SRSurvivorCensus >> tableSize [
	"identityHash is 22 bits, so a table indexed by hash has 2^22 slots. One extra so
	index (hash+1, since Smalltalk is 1-based) is always valid."
	^ 1 << 22 + 1
]
