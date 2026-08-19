"
A SWAHeapDiff that reports the objects which SURVIVED a scavenge, not merely those allocated.

SWAHeapDiff answers ""what did one step allocate?"" -- (after - before) with no GC between the snapshots, so short-lived garbage is included on purpose. This asks the retention question from the 2026-08-14b survivor hunt instead: of what a step allocates, which objects are still reachable after a young-space collection?

The mechanism is one line different: run the work, then #garbageCollectMost (young-only; p9 +1, p7 +0) BEFORE #captureAfter. Everything the collect reclaims drops out of the after-snapshot, so (after - before) is exactly the newly allocated objects that survived -- the ~4000 Vector3 + ~3000 FullBlockClosure/Context set the journal could name by class but not by code.

Because the survivors are real objects here (not identityHash fingerprints as in SRSurvivorCensus), the inherited enrichment applies unchanged: the Provenance branch groups the surviving closures and Contexts by home method (category > Class > Class>>selector), naming the CODE that keeps them reachable. That is the journal's next-step #1, reusing the tool that already implements it.
"
Class {
	#name : #SWASurvivorDiff,
	#superclass : #SWAHeapDiff,
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:51'
}
SWASurvivorDiff class >> around: aBlock [
	"Like SWAHeapDiff>>around: but scavenge between the work and the after-snapshot, so
	the result is the surviving objects, not all allocated ones."
	| d |
	d := self new captureBaseline.
	aBlock value.
	Smalltalk garbageCollectMost.
	d captureAfter.
	^ d diff
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:51'
}
SWASurvivorDiff class >> initialize [
	"Register the Apps-menu entry beside 'SWA Heap Diff (1 Morphic step)'. Same 'SWA '
	prefix and neighbouring label so the two sit together (alphabetically) in the Apps
	menu; the action reuses the inherited #openMorphicStepTreemap, which dispatches
	through self to the survivor-diff measurement. Idempotent.

		SWASurvivorDiff initialize"

	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Heap Diff survivors (1 Morphic step)'.
		{self. #openMorphicStepTreemap}.
		'Snapshot the heap, run one Morphic step, scavenge, and open an enriched Space Tally treemap of what SURVIVED the collection -- with closures & Contexts grouped by home method' }
]

{
	#category : #'running-morphic',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:50'
}
SWASurvivorDiff class >> measureMorphicStepIn: aWorld [
	"Like SWAHeapDiff>>measureMorphicStepIn: but scavenge AFTER the step and BEFORE the
	after-snapshot, so the diff is what survived the collection, not merely what was
	allocated. #garbageCollectMost is young-only -- it reclaims this step's dead eden
	objects while leaving old space alone, which is precisely the scavenge whose
	survivors we want to name."
	| d |
	d := self new.
	d captureBaseline.
	aWorld doOneCycleNow.
	Smalltalk garbageCollectMost.
	d captureAfter.
	^ d diff
]

{
	#category : #'running-xr',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:55'
}
SWASurvivorDiff class >> measureXRFrames: aCount in: aWorld [
	"Like SWAHeapDiff>>measureXRFrames:in: but scavenge AFTER rendering the frames and
	BEFORE the after-snapshot, so the diff is what survived the collection, not merely
	what was allocated. Runs inside the between-frame action that drives the frames, so
	we ARE the world process -- the scavenge lands with the loop blocked, and no frame
	slips between the collect and the after-snapshot. #garbageCollectMost is young-only
	(p9 +1, p7 +0): exactly the scavenge whose survivors we want to name."
	| d |
	d := self new.
	d captureBaseline.
	aCount timesRepeat: [aWorld doOneCycle].
	Smalltalk garbageCollectMost.
	d captureAfter.
	^ d diff
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:55'
}
SWASurvivorDiff class >> xrMenuSurvivorsHundredFrames: aMenu [
	"Survivors of a hundred frames: long enough for periodic allocators to show, and
	for the retained working set to settle to its plateau. The world is frozen for the
	whole run plus the walk. Sits beside 'memory 100 frames'."

	<xrMenu: #(world profile) label: 'survivors 100 frames' priority: 201>
	^ self spaceTallyXRFrames: 100
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:55'
}
SWASurvivorDiff class >> xrMenuSurvivorsOneFrame: aMenu [
	"Survivors of a single frame: render one frame, scavenge, treemap what survived --
	with closures & Contexts grouped by home method. Sits beside 'memory 1 frame'."

	<xrMenu: #(world profile) label: 'survivors 1 frame' priority: 181>
	^ self spaceTallyXRFrames: 1
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 15:55'
}
SWASurvivorDiff class >> xrMenuSurvivorsTenFrames: aMenu [
	"Survivors of ten frames: per-frame jitter averages out, still a short freeze.
	Sits beside 'memory 10 frames'."

	<xrMenu: #(world profile) label: 'survivors 10 frames' priority: 191>
	^ self spaceTallyXRFrames: 10
]
