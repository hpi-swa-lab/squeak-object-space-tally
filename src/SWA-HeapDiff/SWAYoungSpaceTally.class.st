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
		'fate',
		'retainers',
		'retainerParents',
		'unownedMarker',
		'noRootMarker',
		'youngBytesAtCapture',
		'scavengesAtCapture'
	],
	#category : #'SWA-HeapDiff',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:42'
}
SWAYoungSpaceTally class >> gcComparison [
	"Print the VM's survivor counts beside ours so the panel and this tool can be read
	against each other.

	Two scavenges first: a count that does not move between them is not transient. It is
	consistent with floating garbage -- young objects pinned by a DEAD old object through
	the remembered set, which no scavenge can reach -- but flatness alone does not prove
	it, and 2026-09-18c records the same inference being made and retracted.

	The last line is a RESIDUAL, not a measurement of floating garbage. It also contains
	objects that died normally during the pass, and it subtracts counts taken over two
	different populations: p35 counts the survivors of a scavenge, ours are a snapshot
	taken afterwards. Measuring floating garbage needs the scavenge and full-GC verdicts
	on the SAME objects, which #fateAcrossScavenge and #fateOfYoungSpaceExact could
	provide but do not yet combine."
	| scav1 scav2 state r stats residual |
	state := SWAYoungSpaceState default.
	Smalltalk garbageCollectMost.
	scav1 := Smalltalk vmParameterAt: 35.
	Smalltalk garbageCollectMost.
	scav2 := Smalltalk vmParameterAt: 35.
	r := state scavengeFate.
	stats := r at: #stats.
	residual := scav2 - (stats at: #survived) - (stats at: #promoted).
	^ String streamContents: [:s |
		s nextPutAll: 'VM (p35, object counts)'; cr.
		s tab; nextPutAll: 'after scavenge 1 : '; print: scav1; cr.
		s tab; nextPutAll: 'after scavenge 2 : '; print: scav2;
			nextPutAll: (scav1 = scav2 ifTrue: ['   (flat -- not transient)'] ifFalse: ['']); cr.
		s tab; nextPutAll: 'our scavenge     : '; print: (stats at: #vmSurvivorsAfter); cr.
		s cr; nextPutAll: 'Ours, same scavenge'; cr.
		s tab; nextPutAll: 'sampled   : '; print: (stats at: #sampled); cr.
		s tab; nextPutAll: 'survived  : '; print: (stats at: #survived);
			nextPutAll: '   (VM said '; print: (stats at: #vmSurvivorsAfter); nextPutAll: ')'; cr.
		s tab; nextPutAll: 'promoted  : '; print: (stats at: #promoted); cr.
		s tab; nextPutAll: 'collected : '; print: (stats at: #collected); cr.
		s cr; nextPutAll: 'Residual (NOT a floating-garbage measurement)'; cr.
		s tab; print: scav2; nextPutAll: ' - survived - promoted = '; print: residual; cr.
		s tab; nextPutAll: 'young bytes ours '; print: (stats at: #sampledBytes);
			nextPutAll: '  vs VM p2 '; print: (stats at: #vmYoungBytesBefore);
			nextPutAll: '  ('; print: (stats at: #bytesVsVmPercent); nextPutAll: '%)']
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:38'
}
SWAYoungSpaceTally class >> initialize [
	"Register the two Apps-menu entries. Same 'SWA ' prefix as the rest of the suite so
	they sort together. Idempotent.

		SWAYoungSpaceTally initialize"

	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Young Space now (no GC)'.
		{self. #openYoungSpaceNow}.
		'Young space exactly as it stands -- no scavenge, no full GC, nothing collected -- with the old-space objects that point into it and who owns those. Makes no claim about what survives, because deciding that requires a collection that would destroy it' }.
	TheWorldMenu registerOpenCommand: {
		'SWA Young Space fate at next scavenge'.
		{self. #openScavengeFate}.
		'What the next scavenge does to young space: red survived it, blue was tenured out to old space, green was collected -- with the old-space objects holding each survivor. No full GC' }.
	TheWorldMenu registerOpenCommand: {
		'SWA Young Space fate (runs a FULL GC)'.
		{self. #openTreemap}.
		'Everything standing in young space at one instant, coloured by fate: red survived, blue promoted to old space, green collected, amber the old-space object capturing each survivor' }.
	TheWorldMenu registerOpenCommand: {
		'SWA Young Space retained (no collected)'.
		{self. #openRetained}.
		'Only what young space is still holding -- survivors and promoted -- with the collected mass left out so the retained objects are readable' }
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:03'
}
SWAYoungSpaceTally class >> openRetained [
	"Mode B, for the Apps menu: survivors and promoted only. Does not answer the tally --
	it holds the young objects, and an MCP or inspector reference to it would keep them
	alive (2026-08-14)."
	self new openRetained.
	^ nil
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:38'
}
SWAYoungSpaceTally class >> openScavengeFate [
	"Fate at the next scavenge, no full GC. Does not answer the tally -- it holds the
	young objects."
	self new openScavengeFate.
	^ nil
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
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:32'
}
SWAYoungSpaceTally class >> openYoungSpaceNow [
	"Default entry point: young space as it stands, no collection of any kind. Does not
	answer the tally -- it holds the young objects."
	self new openYoungSpaceNow.
	^ nil
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
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:32'
}
SWAYoungSpaceTally class >> sampleOnce [
	"Take ONE young-space sample and answer a quick report: how long it took, how many
	young objects, and the class histogram. For manual inspection -- no fate, no treemap,
	no held state, and no GC of any kind.

	Live and dead together, since prim 178 reports what is physically in eden. Use
	#fateOfYoungSpace to tell the two apart."
	| state young ms hist |
	state := SWAYoungSpaceState default.
	ms := [young := state collectYoungObjects] timeToRun.
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
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:31'
}
SWAYoungSpaceTally class >> xrMenuYoungSpaceNow: aMenu [
	"Open a Space Tally treemap of everything standing in young space right now, coloured
	by fate: red kept, green collected. The snapshot is taken before anything is
	collected, so the green tiles are objects that were really there and really died.

	This DOES run one full GC -- see SWAYoungSpaceState>>fateOfYoungSpace for why the
	instrument leaves no other option. Deferred to the next frame boundary so it runs with
	the render loop blocked, like the other memory entries. The pragma is only ever
	scanned by SRMenuRegistry, so this method is inert without SqueakXR."

	<xrMenu: #(world profile) label: 'young space now' priority: 215>
	| world |
	world := SRWorld current.
	world ifNil: [^ nil].
	^ world addDeferredFrameMessage: [self new openTreemap]
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:15'
}
SWAYoungSpaceTally >> addCollectedBranchUnder: rootNode [
	"A branch for the objects the full GC reclaimed, one node per class, sized by the
	bytes they occupied. They are aggregates and not expandable because nothing of them
	survives to expand: the pass recorded class and basicSize and then let go, since a
	reference is precisely what would have kept them alive.

	Each node HOLDS its class, which gives the fate colouring a key and makes the tile
	selectable. Answers whether anything was collected."
	| byClass byBytes branch |
	fate ifNil: [^ false].
	byClass := fate at: #collectedByClass.
	byClass isEmpty ifTrue: [^ false].
	byBytes := fate at: #collectedBytesByClass.
	branch := self labelNode:
		'Collected (' , ((fate at: #stats) at: #collected) printString , ', by class)'
		under: rootNode.
	(byClass associations asSortedCollection: [:a :b | a value >= b value]) do: [:assoc |
		| node bytes |
		bytes := byBytes at: assoc key ifAbsent: [0].
		node := SWASpaceTallyNode new.
		node setParent: branch depth: branch depth + 1.
		node
			setObject: assoc key
			className: assoc key name , ' x' , assoc value printString
			selfSize: bytes.
		branch addChild: node].
	^ true
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:31'
}
SWAYoungSpaceTally >> applyFateTo: aWindow [
	"Hand the fate table to the treemap morph inside aWindow and open in #fate mode."
	| morph |
	aWindow ifNil: [^ self].
	morph := aWindow allMorphs
		detect: [:each | each isKindOf: SWASpaceTallyTreemapMorph]
		ifNone: [nil].
	morph ifNil: [^ self].
	morph fateByObject: self fateByObject.
	morph fateSummary: (fate ifNil: [self summaryStringNoGC] ifNotNil: [self summaryString]).
	(morph respondsTo: #colorMode:) ifTrue: [morph colorMode: #fate].
	morph changed.
	^ self
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:02'
}
SWAYoungSpaceTally >> buildFateTreeIncludingCollected: includeCollected [
	"The whole tree. One group per fate, each from its own confined walk so the group
	really contains all of its members and can be zoomed into on its own.

	Survivors and Promoted sit together under a 'Retained' node: they are the same
	question -- what is still alive -- and the collected half outweighs them by two orders
	of magnitude, so without a node of their own they are a sliver. With includeCollected
	false they are the only thing in the tree."
	| tally survivorBranch promotedList promotedBranch retained stats |
	stats := fate at: #stats.
	promotedList := fate at: #promoted.
	tally := self confinedTallyFor: (fate at: #survivors).
	retained := self labelNode:
		'Retained (' , (stats at: #survived) printString , ' survivors + '
			, (stats at: #promoted) printString , ' promoted)'
		under: tally rootNode.
	survivorBranch := self labelNode:
		'Survivors (' , (stats at: #survived) printString , ')'
		under: retained.
	tally rootNode children: (tally rootNode children
		reject: [:each | each == retained or: [each == survivorBranch]]).
	self moveChildrenOf: tally under: survivorBranch.
	tally rootNode children: (OrderedCollection with: retained).
	self fileByRetainerUnder: survivorBranch.
	promotedList isEmpty ifFalse: [
		promotedBranch := self labelNode:
			'Promoted to old space (' , promotedList size printString , ')'
			under: retained.
		self moveChildrenOf: (self confinedTallyFor: promotedList) under: promotedBranch].
	includeCollected ifTrue: [self addCollectedBranchUnder: tally rootNode].
	tally rootNode rollUp.
	^ tally
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:30'
}
SWAYoungSpaceTally >> buildNoGCTree [
	"One group: everything in young space, filed under whatever in old space points at it.
	No fate branches, because no collection was run to decide any."
	| tally branch |
	tally := self confinedTallyFor: survivors.
	branch := self labelNode:
		'Young space now (' , survivors size printString , ' objects)'
		under: tally rootNode.
	tally rootNode children: (tally rootNode children copyWithout: branch).
	self moveChildrenOf: tally under: branch.
	tally rootNode children: (OrderedCollection with: branch).
	self fileByRetainerUnder: branch.
	tally rootNode rollUp.
	^ tally
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:43'
}
SWAYoungSpaceTally >> collect [
	"Everything standing in young space at the instant of the snapshot, with its fate.
	Exactly two outcomes, because that is all a snapshot can have: `survivors` are still
	there after a full GC, and `fate` carries the classes of those that were collected
	(they cannot be carried as objects -- holding one is what stops it dying).

	Objects born DURING the pass are deliberately not here. The pass has to take a second
	sample to recover the survivors as real objects, and that sample also catches
	newcomers, but they were not in the snapshot and have no fate in it. They are counted
	in #stats as a measure of how much the image moved while we looked, and nowhere else."
	fate := SWAYoungSpaceState default fateOfYoungSpaceExact.
	"Promoted objects were in the snapshot, so they belong in the picture; they are split
	out again when the tree is built."
	survivors := OrderedCollection new: (fate at: #survivors) size + (fate at: #promoted) size + 1.
	survivors addAll: (fate at: #survivors); addAll: (fate at: #promoted).
	^ self
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:32'
}
SWAYoungSpaceTally >> collectNoGC [
	"Everything standing in young space right now. No scavenge, no full GC, nothing
	collected, nothing promoted, nothing perturbed.

	There is no fate here and there cannot be: deciding it needs a collection, and a
	collection destroys the thing being shown. prim 178 leaves a 55 MB array in OLD space
	that pins all of young through the remembered set, so a scavenge answers 'everything
	survived'; nextObject leaves no such corpse but reaches only a fraction of young space
	and races the collector mid-walk. Both measured. So this view reports what is THERE,
	and what is holding it, and makes no claim about what happens next."
	fate := nil.
	"Read p2 HERE, not at report time: the retainer scan runs for seconds afterwards and
	the image keeps allocating, so a later reading describes a different young space."
	youngBytesAtCapture := Smalltalk vmParameterAt: 2.
	scavengesAtCapture := Smalltalk vmParameterAt: 9.
	survivors := SWAYoungSpaceState default collectYoungObjects.
	^ self
]

{
	#category : #retainers,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:20'
}
SWAYoungSpaceTally >> collectRetainerParents [
	"Who holds the captors. Answers an IdentityDictionary captor -> owner.

	Without this level the answer is unreadable: the biggest captor in every run so far has
	been a bare Array, and 'an Array holds 474' names nothing. It took a manual
	inboundPointers query to discover that one such Array was SRGCFpsGraph's frame-time
	buffer. This is that query, done once for all of them.

	The scan is generic over its target set, so it is the same pass aimed at the captors
	instead of the survivors. Our own pair Arrays have to be excluded explicitly: they are
	elements of the retainers collection rather than slots of it, so expanding the
	collection's slots does not reach them and every captor would be reported as held by
	the tool."
	| captors ours parents |
	retainers ifNil: [^ IdentityDictionary new].
	retainers isEmpty ifTrue: [^ IdentityDictionary new].
	captors := retainers collect: [:pair | pair at: 1].
	ours := OrderedCollection new.
	ours add: retainers; add: captors; add: survivors; add: fate.
	retainers do: [:pair | ours add: pair; add: (pair at: 2)].
	parents := IdentityDictionary new.
	(SWAYoungSpaceState default retainersOf: captors excluding: ours) do: [:pair |
		(pair at: 2) do: [:captor |
			(parents includesKey: captor) ifFalse: [parents at: captor put: (pair at: 1)]]].
	retainerParents := parents.
	^ parents
]

{
	#category : #retainers,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:31'
}
SWAYoungSpaceTally >> collectRetainers [
	"The old-space objects that point into the young set -- the answer to 'what is holding
	this'. A direct observation: a slot either contains that object or it does not.

	No GC. Leftover allObjectsOrNil arrays are rejected by #isHeapSnapshotArray: instead,
	which is what the full GC here used to be for.

	Our own collections are excluded together with their backing Arrays, or the tool
	reports itself as the thing capturing young space."
	| target ours |
	target := fate ifNil: [survivors] ifNotNil: [fate at: #survivors].
	(target isNil or: [target isEmpty]) ifTrue: [^ OrderedCollection new].
	ours := OrderedCollection new.
	ours add: target; add: survivors.
	fate ifNotNil: [
		ours add: fate; add: (fate at: #born); add: (fate at: #collectedByClass)].
	retainers := SWAYoungSpaceState default retainersOf: target excluding: ours.
	^ retainers
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:38'
}
SWAYoungSpaceTally >> collectScavengeFate [
	"Fate of young space at the next SCAVENGE. No full GC anywhere."
	fate := SWAYoungSpaceState default scavengeFate.
	youngBytesAtCapture := (fate at: #stats) at: #vmYoungBytesBefore.
	survivors := OrderedCollection new: (fate at: #survivors) size + (fate at: #promoted) size + 1.
	survivors addAll: (fate at: #survivors); addAll: (fate at: #promoted).
	^ self
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:56'
}
SWAYoungSpaceTally >> confinedTallyFor: objects [
	"A containment walk rooted at objects and confined to them, so every node in the
	result belongs to that one fate.

	One walk per fate, rather than one walk over all of them, because fate is a property
	of an OBJECT and containment is a property of the WALK, and they do not line up: with
	a single walk an object appears wherever the BFS first reached it, so a group can only
	move the nodes that happen to be top-level. That is how the Promoted branch came out
	empty with 51055 promotions -- one Array held 60000 of them, so they were its children
	and never top-level at all.

	The price is that containment ACROSS fates is not shown: a survivor holding a promoted
	object no longer shows it beneath itself."
	| roots |
	roots := OrderedCollection new: objects size + 1.
	objects doWithIndex: [:obj :i |
		roots add: (obj class name , '[' , i printString , ']') -> obj].
	^ SWAHeapDiffSpaceTally new
		diffObjects: objects;
		roots: roots;
		walk;
		yourself
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
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:30'
}
SWAYoungSpaceTally >> fateByObject [
	"object -> #survived | #collected | #born for the treemap colouring. The collected
	entries are keyed by CLASS, because that is all that is left of an object that was
	allowed to die; those are the keys #addCollectedBranchUnder: gives its nodes."
	| map |
	map := IdentityDictionary new.
	fate ifNil: [
		"No-GC view: no fate is known, so an object is simply present. The colours that
		matter here are the retention chain and the objects nothing in old space holds."
		survivors ifNotNil: [survivors do: [:each | map at: each put: #survived]].
		retainers ifNotNil: [retainers do: [:pair | map at: (pair at: 1) put: #retainer]].
		retainerParents ifNotNil: [
			retainerParents valuesDo: [:owner | map at: owner put: #owner]].
		map at: self unownedMarker put: #unowned.
		map at: self noRootMarker put: #noRoot.
		^ map].
	(fate at: #survivors) do: [:each | map at: each put: #survived].
	(fate at: #promoted) do: [:each | map at: each put: #promoted].
	(fate at: #collectedByClass) keysDo: [:cls | map at: cls put: #collected].
	"After the survivors, so a retainer that is itself young is shown as what it does to
	the others rather than as its own fate."
	retainers ifNotNil: [
		retainers do: [:pair | map at: (pair at: 1) put: #retainer]].
	"Owners last: an owner that is itself a captor is shown at the outer level it occupies
	in the tree."
	retainerParents ifNotNil: [
		retainerParents valuesDo: [:owner | map at: owner put: #owner]].
	map at: self unownedMarker put: #unowned.
	map at: self noRootMarker put: #noRoot.
	^ map
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 18:31'
}
SWAYoungSpaceTally >> fateReport [
	"One line per statistic from the last #collect, for reading without a treemap."
	| out stats |
	fate ifNil: [^ 'no fate pass yet -- send #collect'].
	stats := fate at: #stats.
	out := WriteStream on: String new.
	(stats associations asSortedCollection: [:a :b | a key <= b key]) do: [:assoc |
		out nextPutAll: assoc key; nextPutAll: ' = '; print: assoc value; cr].
	^ out contents
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:56'
}
SWAYoungSpaceTally >> fileByRetainerUnder: aBranch [
	"Re-file aBranch's existing children under the old-space object that captures each of
	them, so capture reads as containment. Every child is a survivor here, because the
	branch came from a walk confined to the survivors."
	| objectKids byObject heldNodes unheld |
	objectKids := aBranch children select: [:each | each object notNil].
	objectKids isEmpty ifTrue: [^ aBranch].
	aBranch children: (aBranch children reject: [:each | objectKids identityIncludes: each]).
	byObject := IdentityDictionary new.
	retainers ifNotNil: [
		retainers do: [:pair |
			(pair at: 2) do: [:each |
				(byObject includesKey: each) ifFalse: [byObject at: each put: (pair at: 1)]]]].
	heldNodes := IdentityDictionary new.
	unheld := OrderedCollection new.
	objectKids do: [:node |
		(byObject at: node object ifAbsent: [nil])
			ifNil: [unheld add: node]
			ifNotNil: [:r | (heldNodes at: r ifAbsentPut: [OrderedCollection new]) add: node]].
	(heldNodes associations asSortedCollection: [:a :b | a value size >= b value size]) do: [:assoc |
		| rn parent under |
		parent := retainerParents ifNil: [nil] ifNotNil: [retainerParents at: assoc key ifAbsent: [nil]].
		under := parent
			ifNil: [self unownedNodeUnder: aBranch]
			ifNotNil: [self ownerNodeFor: parent under: aBranch].
		rn := SWASpaceTallyNode new.
		rn setParent: under depth: under depth + 1.
		rn
			setObject: assoc key
			className: assoc key class name , ' holds ' , assoc value size printString
			selfSize: 0.
		under addChild: rn.
		assoc value do: [:node |
			rn addChild: node.
			node setParent: rn depth: rn depth + 1.
			self fixDepthsUnder: node]].
	unheld isEmpty ifFalse: [
		| un |
		un := SWASpaceTallyNode new.
		un setParent: aBranch depth: aBranch depth + 1.
		un
			setObject: self noRootMarker
			className: 'No old-space root (' , unheld size printString , ')'
			selfSize: 0.
		aBranch addChild: un.
		unheld do: [:node |
			un addChild: node.
			node setParent: un depth: un depth + 1.
			self fixDepthsUnder: node]].
	(aBranch children detect: [:each | each object == self unownedMarker] ifNone: [nil])
		ifNotNil: [:node |
			node
				setObject: self unownedMarker
				className: 'No owner found (' , node children size printString , ')'
				selfSize: 0].
	^ aBranch
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:13'
}
SWAYoungSpaceTally >> fixDepthsUnder: aNode [
	"Re-stamp depth through aNode's subtree after a reparent. Depth is stored on the node,
	not derived, and the treemap uses it for shading and recursion limits."
	aNode children ifNil: [^ self].
	aNode children do: [:child |
		child setParent: aNode depth: aNode depth + 1.
		self fixDepthsUnder: child].
	^ self
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:50'
}
SWAYoungSpaceTally >> groupPromotedUnder: rootNode [
	"Split the promoted objects into their own group. They were in the snapshot and did
	not die, but they are old-space objects now, so filing them with the survivors would
	claim young space still holds them. Answers the branch, or nil.

	Runs before the survivors are grouped by captor, while every top-level node still
	holds its object."
	| promotedSet nodes branch |
	fate ifNil: [^ nil].
	promotedSet := IdentitySet new.
	(fate at: #promoted) do: [:each | promotedSet add: each].
	promotedSet isEmpty ifTrue: [^ nil].
	nodes := rootNode children select: [:each |
		each object notNil and: [promotedSet includes: each object]].
	nodes isEmpty ifTrue: [^ nil].
	branch := self labelNode:
		'Promoted to old space (' , ((fate at: #stats) at: #promoted) printString , ')'
		under: rootNode.
	rootNode children: (rootNode children reject: [:each | nodes identityIncludes: each]).
	nodes do: [:node |
		branch addChild: node.
		node setParent: branch depth: branch depth + 1.
		self fixDepthsUnder: node].
	^ branch
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:39'
}
SWAYoungSpaceTally >> groupSurvivorsByRetainerUnder: rootNode [
	"Put the survivors under the old-space object that captures each of them, so capture
	is read as containment rather than as a second branch listing the same objects twice.
	Answers the branch.

	The survivors nothing in old space points at end up under one node of their own, and
	that node is the interesting one: those are held by a stack, or by nothing the scan
	can see.

	A survivor with several retainers is filed under the first. Showing it under each
	would restore the duplication this is meant to remove."
	| objectKids branch byObject unheld heldNodes |
	objectKids := rootNode children select: [:each | each object notNil].
	objectKids isEmpty ifTrue: [^ nil].
	branch := self labelNode:
		'Survivors (' , ((fate at: #stats) at: #survived) printString , ')'
		under: rootNode.
	rootNode children: (rootNode children reject: [:each | objectKids identityIncludes: each]).
	byObject := IdentityDictionary new.
	retainers ifNotNil: [
		retainers do: [:pair |
			(pair at: 2) do: [:each |
				(byObject includesKey: each) ifFalse: [byObject at: each put: (pair at: 1)]]]].
	heldNodes := IdentityDictionary new.
	unheld := OrderedCollection new.
	objectKids do: [:node |
		(byObject at: node object ifAbsent: [nil])
			ifNil: [unheld add: node]
			ifNotNil: [:r | (heldNodes at: r ifAbsentPut: [OrderedCollection new]) add: node]].
	(heldNodes associations asSortedCollection: [:a :b | a value size >= b value size]) do: [:assoc |
		| rn parent under |
		parent := retainerParents ifNil: [nil] ifNotNil: [retainerParents at: assoc key ifAbsent: [nil]].
		under := parent
			ifNil: [self unownedNodeUnder: branch]
			ifNotNil: [self ownerNodeFor: parent under: branch].
		rn := SWASpaceTallyNode new.
		rn setParent: under depth: under depth + 1.
		rn
			setObject: assoc key
			className: assoc key class name , ' holds ' , assoc value size printString
			selfSize: 0.
		under addChild: rn.
		assoc value do: [:node |
			rn addChild: node.
			node setParent: rn depth: rn depth + 1.
			self fixDepthsUnder: node]].
	unheld isEmpty ifFalse: [
		| un |
		un := SWASpaceTallyNode new.
		un setParent: branch depth: branch depth + 1.
		un
			setObject: self noRootMarker
			className: 'No old-space root (' , unheld size printString , ')'
			selfSize: 0.
		branch addChild: un.
		unheld do: [:node |
			un addChild: node.
			node setParent: un depth: un depth + 1.
			self fixDepthsUnder: node]].
	"Named last, once the stand-in has collected its captors."
	(branch children detect: [:each | each object == self unownedMarker] ifNone: [nil])
		ifNotNil: [:node |
			node
				setObject: self unownedMarker
				className: 'No owner found (' , node children size printString , ')'
				selfSize: 0].
	^ branch
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
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:56'
}
SWAYoungSpaceTally >> moveChildrenOf: aTally under: aBranch [
	"Reparent a confined tally's top-level nodes under aBranch, re-stamping depth."
	aTally rootNode children do: [:node |
		aBranch addChild: node.
		node setParent: aBranch depth: aBranch depth + 1.
		self fixDepthsUnder: node].
	^ aBranch
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
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:38'
}
SWAYoungSpaceTally >> noRootMarker [
	"Stand-in object for the survivors nothing in old space points at -- the bucket where a
	stack-held object, or a retention the scan cannot see, ends up."
	^ noRootMarker ifNil: [
		noRootMarker := 'survivors with no old-space pointer' copy]
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:02'
}
SWAYoungSpaceTally >> openEnrichedTreemapWithProgress [
	"SWAHeapDiff's entry point; here it is mode A, the whole of young space."
	^ self openTreemapIncludingCollected: true
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:02'
}
SWAYoungSpaceTally >> openRetained [
	"Mode B: what young space is still holding, without the collected mass."
	self collect.
	survivors isEmpty ifTrue: [^ self inform: 'nothing retained in young space'].
	^ self openTreemapIncludingCollected: false
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:38'
}
SWAYoungSpaceTally >> openScavengeFate [
	"What the next scavenge does to young space, and what holds whatever it keeps."
	| tally win p7 |
	p7 := Smalltalk vmParameterAt: 7.
	self collectScavengeFate.
	survivors isEmpty ifTrue: [^ self inform: 'nothing survived the scavenge'].
	'Young space: fate at next scavenge...' displayProgressFrom: 0 to: 4 during: [:bar |
		bar value: 1; value: 'Young space: finding what holds the survivors...'.
		self collectRetainers.
		bar value: 2; value: 'Young space: finding who holds those...'.
		self collectRetainerParents.
		bar value: 3; value: 'Young space: building treemap...'.
		tally := self buildFateTreeIncludingCollected: true.
		win := (tally compact: 0) openTreemap.
		bar value: 4].
	self applyFateTo: win.
	Transcript cr; show: 'scavenge fate: fullGCs=', ((Smalltalk vmParameterAt: 7) - p7) printString.
	^ win
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
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:02'
}
SWAYoungSpaceTally >> openTreemapIncludingCollected: includeCollected [
	"Build and open the fate treemap. With includeCollected false the Collected group is
	left out entirely -- it is interesting but it is also two orders of magnitude bigger
	than everything else, so leaving it in makes the retained objects unreadable."
	| tally win |
	'Young space: analyzing...' displayProgressFrom: 0 to: 5 during: [:bar |
		bar value: 1; value: 'Young space: finding what captures the survivors...'.
		self collectRetainers.
		bar value: 2; value: 'Young space: finding who holds the captors...'.
		self collectRetainerParents.
		bar value: 3; value: 'Young space: walking each fate...'.
		tally := self buildFateTreeIncludingCollected: includeCollected.
		bar value: 4; value: 'Young space: building treemap...'.
		win := (tally compact: 0) openTreemap.
		bar value: 5].
	self applyFateTo: win.
	^ win
]

{
	#category : #'space tally',
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:30'
}
SWAYoungSpaceTally >> openYoungSpaceNow [
	"Young space as it stands, and what is holding it. No collection of any kind."
	| tally win p7 p9 |
	p7 := Smalltalk vmParameterAt: 7.
	p9 := Smalltalk vmParameterAt: 9.
	self collectNoGC.
	survivors isEmpty ifTrue: [^ self inform: 'young space is empty'].
	'Young space now...' displayProgressFrom: 0 to: 4 during: [:bar |
		bar value: 1; value: 'Young space: finding what points into it...'.
		self collectRetainers.
		bar value: 2; value: 'Young space: finding who holds those...'.
		self collectRetainerParents.
		bar value: 3; value: 'Young space: building treemap...'.
		tally := self buildNoGCTree.
		win := (tally compact: 0) openTreemap.
		bar value: 4].
	self applyFateTo: win.
	"Proof, not decoration: if either counter moved, this view perturbed what it showed."
	Transcript cr; show: 'young space now: fullGCs=', ((Smalltalk vmParameterAt: 7) - p7) printString,
		' forcedScavenges=', ((Smalltalk vmParameterAt: 9) - p9) printString.
	^ win
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:20'
}
SWAYoungSpaceTally >> ownerNodeFor: anOwner under: aBranch [
	"The node for anOwner beneath aBranch, made once and reused, so several captors
	belonging to the same owner gather under it rather than repeating it."
	| existing node |
	existing := aBranch children
		detect: [:each | each object == anOwner]
		ifNone: [nil].
	existing ifNotNil: [^ existing].
	node := SWASpaceTallyNode new.
	node setParent: aBranch depth: aBranch depth + 1.
	node setObject: anOwner className: anOwner class name selfSize: 0.
	aBranch addChild: node.
	^ node
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:40'
}
SWAYoungSpaceTally >> summaryString [
	"Whole-run statistics for the panel's info area, for either fate pass.

	Every key is read with at:ifAbsent:. The two passes report different VM counters --
	the scavenge one has #vmSurvivorsAfter, the full-GC one #vmSurvivorsBefore -- and
	reading one unconditionally is what made the scavenge view die in #applyFateTo:.

	printShowingDecimalPlaces:, not roundTo:, which leaves float trailing garbage."
	| stats fmt at |
	fate ifNil: [^ self summaryStringNoGC].
	stats := fate at: #stats.
	at := [:key | stats at: key ifAbsent: [0]].
	fmt := [:bytes | | kb |
		kb := bytes / 1024.0.
		kb > 1024.0
			ifTrue: [((kb / 1024.0) printShowingDecimalPlaces: 2) , ' MB']
			ifFalse: [(kb printShowingDecimalPlaces: 1) , ' KB']].
	^ String streamContents: [:s |
		s nextPutAll: ((stats includesKey: #vmSurvivorsAfter)
			ifTrue: ['at next SCAVENGE: ']
			ifFalse: ['at a FULL GC: ']).
		s print: (at value: #sampled); nextPutAll: ' objects, ';
			nextPutAll: (fmt value: (at value: #sampledBytes));
			nextPutAll: ' ('; print: (at value: #bytesVsVmPercent);
			nextPutAll: '% of VM p2)'.
		s nextPutAll: '   |   survived '; print: (at value: #survived);
			nextPutAll: ' ('; nextPutAll: (fmt value: (at value: #survivedBytes)); nextPutAll: ')'.
		s nextPutAll: '   |   promoted '; print: (at value: #promoted);
			nextPutAll: ' ('; nextPutAll: (fmt value: (at value: #promotedBytes)); nextPutAll: ')'.
		s nextPutAll: '   |   collected '; print: (at value: #collected);
			nextPutAll: ' ('; nextPutAll: (fmt value: (at value: #collectedBytes)); nextPutAll: ')'.
		retainers ifNotNil: [
			s nextPutAll: '   |   held by '; print: retainers size; nextPutAll: ' old objects'].
		(stats includesKey: #vmSurvivorsAfter)
			ifTrue: [
				"Independent check: the VM's own survivor count for the same scavenge."
				s nextPutAll: '   ||   VM p35 after '; print: (at value: #vmSurvivorsAfter);
					nextPutAll: ' vs ours '; print: (at value: #survived);
					nextPutAll: ', fullGCs '; print: (at value: #fullGCs)]
			ifFalse: [
				"A RESIDUAL, not a measurement: it mixes floating garbage, objects that died
				normally during the pass, and a population mismatch, since p35 counts the
				survivors of a scavenge while ours are a snapshot taken afterwards."
				s nextPutAll: '   ||   VM p35 before '; print: (at value: #vmSurvivorsBefore);
					nextPutAll: ', unaccounted residual ';
					print: (at value: #vmSurvivorsBefore) - (at value: #survived) - (at value: #promoted)]]
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 11:32'
}
SWAYoungSpaceTally >> summaryStringNoGC [
	| bytes state fmt |
	state := SWAYoungSpaceState default.
	fmt := [:b | | kb |
		kb := b / 1024.0.
		kb > 1024.0
			ifTrue: [((kb / 1024.0) printShowingDecimalPlaces: 2) , ' MB']
			ifFalse: [(kb printShowingDecimalPlaces: 1) , ' KB']].
	bytes := 0.
	survivors do: [:o |
		bytes := bytes + (state
			byteSizeOfClass: (thisContext objectClass: o)
			size: (thisContext objectSize: o)
			object: o)].
	^ String streamContents: [:s |
		s nextPutAll: 'young space NOW (no GC): '; print: survivors size;
			nextPutAll: ' objects, '; nextPutAll: (fmt value: bytes);
			nextPutAll: ' (VM p2 at capture '; nextPutAll: (fmt value: youngBytesAtCapture);
			nextPutAll: ', '; print: (youngBytesAtCapture > 0
				ifTrue: [bytes * 100 // youngBytesAtCapture] ifFalse: [0]);
			nextPutAll: '%)'.
		retainers ifNotNil: [
			s nextPutAll: '   |   pointed into from '; print: retainers size;
				nextPutAll: ' old objects via ';
				print: (retainers inject: 0 into: [:a :r | a + (r at: 2) size]);
				nextPutAll: ' refs'].
		"Not forced by us -- caused by us: the scan allocates, and eden fills. Stated
		because a view of young space that silently triggered 105 scavenges would be
		lying by omission."
		s nextPutAll: '   |   no GC run; '; print: ((Smalltalk vmParameterAt: 9) - scavengesAtCapture);
			nextPutAll: ' scavenges fired while analysing'.
		s nextPutAll: '   |   no fate shown: deciding it needs a collection, and a collection destroys this']
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
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:38'
}
SWAYoungSpaceTally >> unownedMarker [
	"Stand-in object for the captors whose owner the scan did not find, so their node can
	carry a colour like any other. A node colours by the object it holds, and a label node
	holds none; a fresh String is unique by identity and says something useful when the
	tile is clicked."
	^ unownedMarker ifNil: [
		unownedMarker := 'captors whose owner the scan did not find' copy]
]

{
	#category : #fate,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 10:38'
}
SWAYoungSpaceTally >> unownedNodeUnder: aBranch [
	"The stand-in node gathering captors with no known owner, made once and reused. Keeps
	them at the same depth as the owned ones instead of hanging them off the branch."
	| existing node |
	existing := aBranch children
		detect: [:each | each object == self unownedMarker]
		ifNone: [nil].
	existing ifNotNil: [^ existing].
	node := SWASpaceTallyNode new.
	node setParent: aBranch depth: aBranch depth + 1.
	node setObject: self unownedMarker className: 'No owner found' selfSize: 0.
	aBranch addChild: node.
	^ node
]
