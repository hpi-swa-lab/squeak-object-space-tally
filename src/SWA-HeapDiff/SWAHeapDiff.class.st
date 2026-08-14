"
Lightweight heap-diff experiment. Snapshots the whole image twice with
SystemNavigation allObjectsOrNil (a flat O(heap) sweep, NOT the SWASpaceTally
graph walk), and reports how many objects are new in the second snapshot and
how they distribute per class. No visualization.

Two-phase by design. Capturing a snapshot is just the raw sweep (~50 ms), so
#captureBaseline and #captureAfter can run back-to-back inside a single frame.
All the expensive work -- building an identity set of the first snapshot and
probing the second against it -- is deferred to #diff, which runs afterward off
the hot path on the two already-frozen arrays. No GC happens between the two
sweeps: a collect would drop exactly the short-lived objects we may want to see.

Usage:
	(SWAHeapDiff around: [ anAction ]) report.
or
	d := SWAHeapDiff baseline.  d captureAfter.  d diff.  d report.

The diff excludes its own scaffolding (both snapshot arrays, the identity set,
the counts dictionary) by identity, but genuine transient churn in a live image
(the XR render loop, the MCP server servicing the call) still shows up -- expect
a noise floor of ~1500-2300 objects even when 'nothing' happens.
"
Class {
	#name : #SWAHeapDiff,
	#superclass : #Object,
	#instVars : [
		'before',
		'after',
		'countsByClass',
		'newCount',
		'navigator'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:06'
}
SWAHeapDiff class >> around: aBlock [
	"Fast-snapshot, run aBlock, fast-snapshot again, THEN diff. The two sweeps
	are ~50 ms each; the slow set-build happens afterward off the hot path.
	Returns the SWAHeapDiff; send #report to it. The running image keeps
	churning (XR render loop, MCP server), so expect ~2000 unrelated objects."

	| d |
	d := self new captureBaseline.
	aBlock value.
	d captureAfter.
	^ d diff
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:06'
}
SWAHeapDiff class >> baseline [
	"Fast baseline snapshot. Do something, send #captureAfter, then #diff."

	^ self new captureBaseline
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:49'
}
SWAHeapDiff class >> initialize [
	"Register the Apps-menu entry, alongside the other SWA tools. The 'SWA ' label
	prefix groups them in the (alphabetically sorted) Apps menu. Idempotent:
	removes any prior entry for this receiver first.

		SWAHeapDiff initialize"

	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Heap Diff (1 Morphic step)'.
		{self. #openMorphicStepTreemap}.
		'Snapshot the heap, run one Morphic world cycle, and open an enriched Space Tally treemap of what that single step allocated' }
]

{
	#category : #'running-morphic',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:49'
}
SWAHeapDiff class >> measureMorphicStepIn: aWorld [
	"Snapshot the heap, run EXACTLY one Morphic world cycle, snapshot again, diff.
	Answer the SWAHeapDiff. The Morphic parallel to #measureXRFrames:in:.

	Uses #doOneCycleNowFor: (not #doOneCycleFor:) so the inter-cycle Delay -- which
	allocates and blocks -- is not part of the measured step; we want the input +
	stepping + display work of one frame, nothing else.

	Meant to run in the UI process (an Apps-menu action does), i.e. between cycles,
	so this one manual cycle is well-defined. No GC between the sweeps.

	Everything is pre-resolved before the baseline (see #captureBaseline), so
	nothing of ours allocates between the two snapshots except the measured cycle."

	| d |
	d := self new.
	d captureBaseline.
	aWorld doOneCycleNow.
	d captureAfter.
	^ d diff
]

{
	#category : #'running-xr',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:36'
}
SWAHeapDiff class >> measureXRFrames: aCount in: aWorld [
	"Snapshot the heap, render EXACTLY aCount frames, snapshot again, diff. Answer
	the SWAHeapDiff.

	MUST be called inside a between-frame action -- it drives the frames itself with
	#doOneCycle, so the loop has to be blocked and nothing may allocate on the render
	path except the frames we are measuring. Frame-exact: aCount sends of #doOneCycle
	are aCount frames, and because we ARE the world process, not one extra frame can
	slip in between the two sweeps.

	No GC between the sweeps (see #captureAfter): a collect would drop exactly the
	short-lived per-frame objects we want to see. The slow diff runs here too, with
	the loop still blocked -- acceptable because the measurement is deliberately a
	one-shot pause, not a per-frame cost."

	| d |
	"Allocate and initialize the diff object, and let it resolve the navigator,
	all BEFORE the baseline snapshot -- so nothing of ours allocates between the
	two sweeps."
	d := self new.
	d captureBaseline.
	aCount timesRepeat: [aWorld doOneCycle].
	d captureAfter.
	^ d diff
]

{
	#category : #'running-morphic',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:57'
}
SWAHeapDiff class >> openMorphicStepTreemap [
	"Apps-menu entry: snapshot the heap, run ONE Morphic world cycle, snapshot
	again, and open the enriched Space Tally treemap on what that one step
	allocated. The Morphic parallel to the XR 'memory 1 frame' menu entry.

	Runs in the UI process (menu actions do), so the manual cycle is between the
	loop's own cycles. Answers the treemap window, or nil if there is no world."

	| world |
	world := ActiveWorld ifNil: [World].
	world ifNil: [^ nil].
	^ (self measureMorphicStepIn: world) openEnrichedTreemapWithProgress
]

{
	#category : #'running-xr',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:11'
}
SWAHeapDiff class >> openWorkspaceOn: aHeapDiff frames: aCount [
	"Open the diff's text report in a Workspace. Called from the world process
	after the frames were measured; opening a window there is fine (the frame
	flamegraph does the same)."

	| text |
	text := String streamContents: [:s |
		s nextPutAll: 'XR memory-alloc profile: '; print: aCount; nextPutAll: ' frame(s)'; cr.
		s nextPutAll: (aHeapDiff newCount / aCount) asFloat printString.
		s nextPutAll: ' new objects per frame (avg)'; cr; cr.
		s nextPutAll: aHeapDiff report].
	^ (Workspace new contents: text) openLabel:
		'XR Memory Profile: ', aCount printString, ' frame(s)'
]

{
	#category : #'running-xr',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:11'
}
SWAHeapDiff class >> profileXRFrames: aCount [
	"Memory-alloc profile of exactly aCount frames of the running XR world, opened
	in a Workspace. Same in-frame mechanism as SWAPane>>profileXRFrames:packages:.

	  SWAHeapDiff profileXRFrames: 1.
	  SWAHeapDiff profileXRFrames: 60.

	Everything -- snapshot, the frames, snapshot, diff, open -- happens inside
	SRWorld>>addDeferredFrameMessage:, i.e. in the world process at a frame boundary
	with the render loop blocked. That placement IS the measurement: the two heap
	sweeps and the aCount frames between them see no interleaved rendering, so the
	diff is the allocation of exactly those frames and nothing else."

	| world |
	world := SRWorld current.
	world ifNil: [^ nil].
	^ world addDeferredFrameMessage: [
		self openWorkspaceOn: (self measureXRFrames: aCount in: world) frames: aCount]
]

{
	#category : #'running-xr',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:58'
}
SWAHeapDiff class >> spaceTallyXRFrames: aCount [
	"Like #profileXRFrames:, but open an ENRICHED Space Tally TREEMAP on this diff's
	new objects instead of the flat Workspace report. Same in-frame capture (two
	fast array sweeps around exactly aCount frames); the structural graph walk
	happens afterward, from the diff's new objects only.

	  SWAHeapDiff spaceTallyXRFrames: 1.

	The walk's universe IS the diff (SWAHeapDiffSpaceTally), so it needs no
	full-heap snapshot and is bounded by the diff size. A root pre-pass seeds only
	the diff objects no other diff object references, so the treemap shows
	containment; the enriched tally adds the Provenance branch (closures grouped by
	the code that made them). All of it runs inside the frame-blocked between-frame
	action -- no full image walk, so still safe there."

	| world |
	world := SRWorld current.
	world ifNil: [^ nil].
	^ world addDeferredFrameMessage: [
		(self measureXRFrames: aCount in: world) openEnrichedTreemapWithProgress]
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:44'
}
SWAHeapDiff class >> xrMenuMemoryHundredFrames: aMenu [
	"Memory-alloc profile of a hundred frames, opened as a Space Tally treemap --
	long enough that periodic allocators (a step every n frames, a texture
	re-upload) show up. The world is frozen for the whole run plus the walk
	afterward, so this reads as a hang, not slow rendering."

	<xrMenu: #(world profile) label: 'memory 100 frames' priority: 200>
	^ self spaceTallyXRFrames: 100
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:44'
}
SWAHeapDiff class >> xrMenuMemoryOneFrame: aMenu [
	"Memory-alloc profile of a single frame, opened as a Space Tally treemap of the
	diff's new objects. Deferred to the next frame boundary like the time profiler,
	so the frame this click is part of is NOT the one measured. The pragma is only
	ever scanned by SRMenuRegistry, so this method is inert without SqueakXR."

	<xrMenu: #(world profile) label: 'memory 1 frame' priority: 180>
	^ self spaceTallyXRFrames: 1
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:44'
}
SWAHeapDiff class >> xrMenuMemoryTenFrames: aMenu [
	"Memory-alloc profile of ten frames, opened as a Space Tally treemap:
	per-frame jitter averages out, still short enough that the two array sweeps
	do not freeze the world for long."

	<xrMenu: #(world profile) label: 'memory 10 frames' priority: 190>
	^ self spaceTallyXRFrames: 10
]

{
	#category : #'enrichment-support',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 11:19'
}
SWAHeapDiff >> addObjectLeaf: anObject under: parentNode [
	"A leaf node holding a real object, with its class name and own byte size, so
	it renders and rolls up like a walked node. Used for closures under Provenance
	and for the anchored roots. No graph walk out of anObject -- it is a leaf here."

	| node size cls |
	node := SWASpaceTallyNode new.
	node setParent: parentNode depth: parentNode depth + 1.
	cls := anObject class.
	size := [cls isVariable
		ifTrue: [cls byteSizeOfInstanceOfSize: anObject basicSize]
		ifFalse: [cls byteSizeOfInstance]] on: Error do: [:e | 0].
	node setObject: anObject className: cls name asString selfSize: size.
	parentNode addChild: node.
	^ node
]

{
	#category : #enrichment,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 13:03'
}
SWAHeapDiff >> addProvenanceBranchUnder: rootNode [
	"Feature (b): a 'Provenance' branch grouping the diff's code-bearing objects --
	block closures AND method-activation Contexts -- by where their code lives:
	category > Class > selector > the objects. Contexts belong here too: each is an
	activation of a method (it answers #method), and a Context is frequently the
	PARENT of a closure (the closure's outerContext), so grouping both by their
	home method keeps them together. Answers whether anything was found (so the
	caller can drop an empty branch).

	Synthetic SWASpaceTallyNodes for the category/class levels; the method level is
	a #methodNode:label:under: that HOLDS the CompiledMethod, so selecting it shows
	the method's code in the Source pane and Browse opens it. The objects
	themselves are real leaves (className distinguishes Context from closure), so
	their bytes roll up under their method.

	An object that was a TOP-LEVEL diff root is then removed from the containment
	forest (#removeRootChildrenOf:under:), so it shows once under its method rather
	than twice. Objects nested inside another root's subtree keep their structural
	position (their own subtree would be orphaned by a move) and are also indexed
	here -- Provenance is a cross-cutting view, not a relocation."

	| coded branch catNodes clsNodes selNodes placed |
	coded := self newObjects select: [:o |
		(o isKindOf: BlockClosure) or: [o isKindOf: Context]].
	coded isEmpty ifTrue: [^ false].
	branch := self labelNode: 'Provenance (closures & contexts by code)' under: rootNode.
	catNodes := Dictionary new. clsNodes := Dictionary new. selNodes := Dictionary new.
	placed := IdentitySet new.
	coded do: [:c | | m cls catName clsKey selKey catN clsN selN |
		m := self homeMethodOf: c.
		m ifNotNil: [
			cls := m methodClass.
			catName := cls category ifNil: ['(uncategorized)'].
			catN := catNodes at: catName ifAbsentPut: [self labelNode: catName under: branch].
			clsKey := catName , '|' , cls name.
			clsN := clsNodes at: clsKey ifAbsentPut: [self labelNode: cls name under: catN].
			selKey := clsKey , '>>' , m selector.
			selN := selNodes at: selKey ifAbsentPut: [
				self methodNode: m label: cls name , '>>' , m selector under: clsN].
			self addObjectLeaf: c under: selN.
			placed add: c]].
	placed isEmpty ifTrue: [rootNode children: (rootNode children copyWithout: branch). ^ false].
	"Drop the ORIGINAL top-level root of each object now under Provenance, so it
	shows once under its method instead of twice. Objects nested deeper inside
	another root's subtree are left in place."
	self removeRootChildrenOf: placed under: rootNode.
	^ true
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:34'
}
SWAHeapDiff >> baselineMembership [
	"An IdentityDictionary (value ignored) of every before-snapshot object, used as
	a membership test.

	NOT an IdentitySet: Set>>scanFor: sends #enclosedSetElement to each stored
	element, which a doesNotUnderstand:-proxy (e.g. TestCoverage, a ProtoObject
	method wrapper) intercepts and mis-answers -- so the proxy never matches itself
	and shows up as 'new' in every diff. IdentityDictionary>>scanFor: compares with
	the primitive #== (prim 110) only, which the proxy cannot intercept, so
	membership is correct for proxies too."

	| membership |
	membership := IdentityDictionary new: before size * 4 // 3 + 16.
	1 to: before size do: [:i | membership at: (before at: i) put: nil].
	^ membership
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:35'
}
SWAHeapDiff >> captureAfter [
	"Fast: grab the second flat object array (~50 ms). Comparison happens in
	#diff. No GC here -- a collect between the two sweeps would drop exactly
	the short-lived objects we may want to see.

	Reuses the navigator resolved in #captureBaseline, so this is a single bare
	primitive send with no intervening allocation of ours."

	navigator ifNil: [^ self error: 'captureAfter without captureBaseline'].
	after := navigator allObjectsOrNil.
	after ifNil: [^ self error: 'could not snapshot heap (low memory)'].
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:35'
}
SWAHeapDiff >> captureBaseline [
	"Fast: just grab the flat object array (~50 ms). The slow membership-map build
	is deferred to #diff, so both snapshots can be taken back-to-back.

	DEFENSIVE: resolve the navigator BEFORE the snapshot (it is cached, but we do
	not want the lookup counted), then the only work between here and #captureAfter
	is the two bare #allObjectsOrNil primitives -- nothing of ours allocates in
	between, so the diff is the measured workload and not our own machinery."

	navigator := SystemNavigation default.
	before := navigator allObjectsOrNil.
	before ifNil: [^ self error: 'could not snapshot heap (low memory)'].
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:35'
}
SWAHeapDiff >> classOf: anObject [
	"The class of anObject WITHOUT sending it #class -- a doesNotUnderstand:-proxy
	would intercept that. Uses the same reflective primitive the space-tally walker
	relies on, so a wrapper is bucketed as its real class (e.g. TestCoverage), not
	whatever its DNU handler forwards #class to."

	^ thisContext objectClass: anObject
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 09:59'
}
SWAHeapDiff >> countsByClass [
	"An IdentityDictionary class -> count of new instances."

	^ countsByClass
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:35'
}
SWAHeapDiff >> diff [
	"Compare the two captured arrays. Take all the time we need here -- both
	snapshots are already frozen. Build an identity membership map of the `before`
	objects, then tally every `after` object not in it, grouped by class.

	Excludes our own scaffolding (both snapshot arrays, the membership map, the
	counts dictionary) by identity so it does not inflate the result. Class
	bucketing goes through #classOf: (not #class) so doesNotUnderstand:-proxies
	are counted as their real class."

	| membership counts n |
	(before isNil or: [after isNil])
		ifTrue: [^ self error: 'need captureBaseline then captureAfter first'].
	membership := self baselineMembership.
	counts := IdentityDictionary new: 1024.
	n := 0.
	1 to: after size do: [:i | | obj cls |
		obj := after at: i.
		((membership includesKey: obj)
			or: [obj == before or: [obj == after
				or: [obj == membership or: [obj == counts or: [obj == self]]]]])
			ifFalse: [
				n := n + 1.
				cls := self classOf: obj.
				counts at: cls put: (counts at: cls ifAbsent: [0]) + 1]].
	newCount := n.
	countsByClass := counts.
	^ self
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:21'
}
SWAHeapDiff >> enrichedSpaceTally [
	"The diff-confined space tally (see #spaceTally) with the Provenance branch
	appended: closures grouped by the code that made them. Cheap -- no image
	walk -- so this is a fine default. Returns the diff tally with the branch."

	| diffTally |
	diffTally := self spaceTally.
	self addProvenanceBranchUnder: diffTally rootNode.
	diffTally rootNode rollUp.
	^ diffTally
]

{
	#category : #'enrichment-support',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 13:03'
}
SWAHeapDiff >> homeMethodOf: aCodeBearer [
	"The CompiledMethod behind a closure or a Context, or nil. A Context and a
	FullBlockClosure both answer #method directly; for other block kinds fall back
	through the outer context."

	^ [aCodeBearer method] on: Error do: [:e |
		[aCodeBearer outerContext ifNotNil: [:c | c method]] on: Error do: [:e2 | nil]]
]

{
	#category : #'enrichment-support',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 11:18'
}
SWAHeapDiff >> labelNode: aString under: parentNode [
	"A synthetic tree node that shows aString and carries no live object. Used for
	the branch headers and the package/class/method provenance nodes. selfSize 0
	so it does not inflate byte totals; totalSize is fixed by a later rollUp."

	| node |
	node := SWASpaceTallyNode new.
	node setParent: parentNode depth: parentNode depth + 1.
	node setClassName: aString selfSize: 0 totalSize: 0.
	parentNode addChild: node.
	^ node
]

{
	#category : #'enrichment-support',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 13:01'
}
SWAHeapDiff >> methodNode: aCompiledMethod label: aString under: parentNode [
	"A synthetic method-provenance node that DISPLAYS aString and HOLDS the method,
	so the treemap's Source pane and Browse button can show its code (see
	SWASpaceTallyNode>>sourceString / #browse, which dispatch on a held method).
	selfSize 0 so it does not inflate byte totals; #name still shows aString
	because a CompiledMethod is neither a Behavior nor a String."

	| node |
	node := SWASpaceTallyNode new.
	node setParent: parentNode depth: parentNode depth + 1.
	node setObject: aCompiledMethod className: aString selfSize: 0.
	parentNode addChild: node.
	^ node
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 09:59'
}
SWAHeapDiff >> newCount [
	"How many objects are new since the baseline."

	^ newCount
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:35'
}
SWAHeapDiff >> newObjects [
	"The actual objects present in the after-snapshot but not the before-snapshot,
	excluding our own scaffolding. Computed from the two frozen arrays, so it can
	be called any time after #captureAfter."

	| membership new |
	(before isNil or: [after isNil])
		ifTrue: [^ self error: 'need captureBaseline then captureAfter first'].
	membership := self baselineMembership.
	new := OrderedCollection new.
	1 to: after size do: [:i | | obj |
		obj := after at: i.
		((membership includesKey: obj)
			or: [obj == before or: [obj == after
				or: [obj == membership or: [obj == self]]]])
			ifFalse: [new add: obj]].
	^ new
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:22'
}
SWAHeapDiff >> openEnrichedTreemap [
	"Build the enriched tally (diff containment + Provenance) and open a treemap.
	Answers the window."

	^ (self enrichedSpaceTally compact: 0) openTreemap
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:57'
}
SWAHeapDiff >> openEnrichedTreemapWithProgress [
	"Like #openEnrichedTreemap, but show a progress bar over the post-snapshot work
	(it takes a few seconds: the diff-confined walk, the provenance grouping, and
	building the treemap). Snapshots are already taken by the caller, so this only
	covers the analysis. Answers the window.

	The confined walk shows its own 'Walking heap...' bar during phase 2; the
	captions here bracket it so the user sees continuous motion."

	| tally win |
	'Heap diff: analyzing...' displayProgressFrom: 0 to: 4 during: [:bar |
		bar value: 1; value: 'Heap diff: walking new objects...'.
		tally := self spaceTally.
		bar value: 2; value: 'Heap diff: grouping closures by code...'.
		self addProvenanceBranchUnder: tally rootNode.
		tally rootNode rollUp.
		bar value: 3; value: 'Heap diff: building treemap...'.
		win := (tally compact: 0) openTreemap.
		bar value: 4].
	^ win
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:35'
}
SWAHeapDiff >> openSpaceTallyTreemap [
	"Build a Space Tally on this diff's new objects, compact tiny nodes, and open
	a treemap. Answers the window."

	^ (self spaceTally compact: 0) openTreemap
]

{
	#category : #'enrichment-support',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 12:24'
}
SWAHeapDiff >> removeRootChildrenOf: anObjectSet under: rootNode [
	"Remove the top-level root children whose object is in anObjectSet (the closures
	re-homed under Provenance), so they are not shown twice. Only top-level roots
	are touched; a closure nested inside another root's subtree stays there."

	rootNode children: (rootNode children reject: [:n |
		n object notNil and: [anObjectSet includes: n object]])
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:00'
}
SWAHeapDiff >> report [
	"A plain-text summary: total new objects and the per-class distribution,
	sorted by count descending."

	| s pairs |
	countsByClass ifNil: [^ 'no diff yet; send #captureBaseline, do something, then #diff'].
	s := WriteStream on: String new.
	s nextPutAll: newCount printString; nextPutAll: ' new objects across '.
	s nextPutAll: countsByClass size printString; nextPutAll: ' classes'; cr; cr.
	pairs := countsByClass associations asSortedCollection: [:a :b | a value >= b value].
	pairs do: [:assoc | | num |
		num := assoc value printString.
		s next: (10 - num size max: 0) put: $ .
		s nextPutAll: num; nextPutAll: '  '; nextPutAll: assoc key name; cr].
	^ s contents
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 10:37'
}
SWAHeapDiff >> spaceTally [
	"Build a SWASpaceTally rooted at THIS diff's new objects, so the structural
	walk shows how the freshly-allocated objects compose -- not the whole image.
	The diff objects are ALSO the walk's closed universe (SWAHeapDiffSpaceTally),
	so the BFS never follows a reference out of the diff into a pre-existing
	shared object: every object in the tree is new. No full-heap snapshot.

	Returns the walked (uncompacted) tally; send #openTreemap to it."

	| new roots |
	new := self newObjects.
	roots := OrderedCollection new: new size.
	new doWithIndex: [:obj :i |
		roots add: (obj class name , '[' , i printString , ']') -> obj].
	^ SWAHeapDiffSpaceTally new
		diffObjects: new;
		roots: roots;
		walk;
		yourself
]
