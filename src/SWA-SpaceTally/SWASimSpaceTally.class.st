"
A space tally that walks the heap of a *simulated* Squeak image driven by a StackInterpreterSimulator, while the tally tree itself lives in the host image.

I reuse the whole SWASpaceTally tree model, rollUp, explorer and treemap. The only difference is how I reach into objects: instead of the host VM's Context mirror primitives (thisContext objectClass: / instVarAt: / basicAt:), I go through SimObjectMirror, which forwards to the simulator's object memory.

Each node wraps one simulated object:
  - oop     : the followed (non-forwarder) heap address (a SmallInteger /
              LargePositiveInteger). This is the identity key.
  - mirror  : a SimObjectMirror on that oop, used to read class, size, slots.
  - sim     : the StackInterpreterSimulator.

Identity dedup: host IdentityDictionary can't dedup mirrors (each is a fresh
instance) nor large oops (LargePositiveInteger ~~). So the walk keys its seen
set on the oop via a plain Dictionary (oopSeen: oop -> node), bypassing the
inherited IdentityDictionary-based seen entirely.

Roots default to the simulator's special objects array plus nil/true/false's
classes; or set explicit root oops via #rootOops: / a single object via
#rootOop:.

Usage:
  | t |
  t := SWASimSpaceTally onSimulator: aStackInterpreterSimulator.
  t rootOop: someOop.
  t walk; compact: 100000.
  t openTreemap.
"
Class {
	#name : #SWASimSpaceTally,
	#superclass : #SWASpaceTally,
	#instVars : [
		'sim',
		'oopSeen'
	],
	#category : #'SWA-SpaceTally-Sim',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:20'
}
SWASimSpaceTally class >> chooseImage [
	"Pop a file chooser for a *.image file and answer a SWASimSpaceTally opened
	on the selected image (simulator loaded but not run). Answers nil if the
	user cancels.

	Example:
		SWASimSpaceTally chooseImage walkDeep; openExplorer."

	| result path |
	result := StandardFileMenu
		oldFileFrom: FileDirectory default
		withPattern: '*.image'.
	result ifNil: [^ nil].
	path := result directory fullNameFor: result name.
	^ self onImage: path
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:20'
}
SWASimSpaceTally class >> chooseImageAndExplore [
	"Pop a file chooser for a *.image file, run a deep walk of that simulated
	heap (findDeep: so unreached objects are swept into LostAndFound, no
	compaction so the tree keeps full detail), and open an explorer window on
	the result. Answers the tally (or nil if the user cancels).

	Equivalent to:
		tally := SWASimSpaceTally onImage: <chosen>.
		tally findDeep: true.
		tally walk.
		tally openExplorerWindow."

	| tally |
	tally := self chooseImage.
	tally ifNil: [^ nil].
	tally findDeep: true.
	tally walk.
	tally openExplorerWindow.
	^ tally
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:24'
}
SWASimSpaceTally class >> initialize [
	"Register an Apps/World menu entry next to 'Space Tally' that walks a
	simulated image picked from a file, rather than the running image.
	registerOpenCommand: is idempotent by label, so re-running is safe."

	(TheWorldMenu respondsTo: #registerOpenCommand:)
		ifTrue: [TheWorldMenu registerOpenCommand: {
			'Space Tally (image file)'.
			{self. #chooseImageAndExplore}.
			'Walk and explore the heap of a Squeak image file (via the VM simulator)'}]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 15:12'
}
SWASimSpaceTally class >> onImage: anImageFileName [
	"Open a StackInterpreterSimulator on the given image file and answer a
	SWASimSpaceTally ready to #walk it. The simulator is created and the
	image loaded, but NOT run -- we only need a quiescent heap to traverse.

	Example:
		(SWASimSpaceTally onImage: 'xr-surface.19.image')
			walk; compact: 2000; openTreemap."

	^ self onSimulator: (self openSimulatorOn: anImageFileName)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally class >> onSimulator: aStackInterpreterSimulator [
	^ self new setSimulator: aStackInterpreterSimulator
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 15:16'
}
SWASimSpaceTally class >> openSimulatorOn: anImageFileName [
	"Create and configure a StackInterpreterSimulator and load anImageFileName
	into it, returning the simulator (not started). Mirrors the standard
	interactive setup: 64-bit Spur memory manager, multiple bytecode sets,
	8 stack pages, per-step execution-pointer asserts off.

	The simulator class is resolved lazily so this package loads even when
	VMMaker is absent; the dependency only bites when you actually open an
	image."

	| simulatorClass sis |
	simulatorClass := self simulatorClass.
	sis := simulatorClass newWithOptions: #(
		ObjectMemory Spur64BitMemoryManager
		MULTIPLEBYTECODESETS true).
	sis desiredNumStackPages: 8.
	sis assertValidExecutionPointersAtEachStep: false.
	sis openOn: anImageFileName extraMemory: 0.
	^ sis
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 15:16'
}
SWASimSpaceTally class >> simulatorClass [
	"The StackInterpreterSimulator class, resolved lazily from the system
	dictionary so this package loads without VMMaker installed. Signals a
	clear error if VMMaker (which provides the simulator) is not present."

	^ Smalltalk
		at: #StackInterpreterSimulator
		ifAbsent: [self error: 'StackInterpreterSimulator not found -- VMMaker (VMMaker-InterpreterSimulation) must be loaded to open a simulated image']
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:00'
}
SWASimSpaceTally >> captureSimUniverse [
	"Snapshot the entire simulated heap into `deepUniverse`, a Dictionary of
	every enumerable object oop -> nil. This is the sim analogue of the live
	walk's #captureDeepUniverse: it gives a closed, finite oop set so the walk
	terminates, and it is the candidate set for the LostAndFound sweep.

	Keyed on FOLLOWED oop (forwarders resolved) so membership tests match the
	oops the walk actually enqueues. The simulated heap does not change while we
	traverse it, so this snapshot stays valid for the whole walk."

	| om |
	om := sim objectMemory.
	deepUniverse := Dictionary new: 200000.
	om allObjectsDo: [:oop |
		| followed |
		followed := self followOop: oop.
		(om isFreeObject: followed) ifFalse: [
			deepUniverse at: followed put: nil]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:27'
}
SWASimSpaceTally >> clearWalkerState [
	"Also drop the oop-keyed seen dictionary used during the sim walk."

	super clearWalkerState.
	oopSeen := nil
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:14'
}
SWASimSpaceTally >> defaultRootOops [
	"Curated, labelled roots for a whole-image walk of the simulated heap,
	mirroring SWASpaceTally>>defaultRoots but resolved INSIDE the simulated
	image (host globals don't translate to sim oops).

	ORDER MATTERS: the BFS claims each object for its FIRST reacher, so root
	order is attribution priority. We list SPECIFIC, interesting categories
	first so they claim their own state, and put the broad catch-alls (Globals,
	Classes, SpecialObjects) LATER so 'Classes' -- which reaches almost the
	whole image via methods/strings/symbols -- doesn't absorb everything.

	Resolution sources:
	  Display        -- the global named 'Display'.
	  ActiveWorld    -- the global named 'ActiveWorld' (a PasteUpMorph), if set.
	  Processes      -- EVERY Process instance (heap scan), like the live
	                    walker's `Process allInstances`. A collection-valued root
	                    -> one synthetic 'Processes' parent node. The scheduler
	                    only reaches runnable processes, so this is the accurate
	                    source (suspended / semaphore-blocked processes too).
	  Processor      -- the global named 'Processor' (run queues, active process).
	  Globals        -- the simulated Smalltalk (SmalltalkImage), via
	                    specialObjectsArray slot 8.
	  Classes        -- the class table (classTableRootObj, a hidden root that
	                    holds every class/metaclass; not reachable from
	                    specialObjects). Broad.
	  SpecialObjects -- the VM's specialObjectsArray.

	The deep-sweep nets anything no root reached into LostAndFound. Absent
	globals are simply skipped."

	| om roots processOops |
	om := sim objectMemory.
	roots := OrderedCollection new.
	"Specific / interesting first."
	(self globalNamed: 'Display') ifNotNil: [:o | roots add: 'Display' -> o].
	(self globalNamed: 'ActiveWorld') ifNotNil: [:o | roots add: 'ActiveWorld' -> o].
	processOops := self instanceOopsOfClassNamed: 'Process'.
	processOops isEmpty ifFalse: [roots add: 'Processes' -> processOops].
	(self globalNamed: 'Processor') ifNotNil: [:o | roots add: 'Processor' -> o].
	"Broad catch-alls last."
	roots add: 'Globals' -> self smalltalkOop.
	roots add: 'Classes' -> om classTableRootObj.
	roots add: 'SpecialObjects' -> om specialObjectsOop.
	^ roots
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:14'
}
SWASimSpaceTally >> enqueueGroupRoot: oopCollection label: aLabel [
	"A root whose value is a host collection of oops (e.g. all Process
	instances). Create one synthetic parent node labelled aLabel so the group is
	a single expandable node, then enqueue each member oop as a child of it. The
	sim equivalent of the live walker's synthetic-Array roots.

	The synthetic node holds no simulated oop (selfSize 0); it's registered in
	oopSeen under a fresh host key is unnecessary -- it's never a referent. Its
	children are the real instances, deduped via oopSeen like any other node."

	| groupNode |
	groupNode := SWASimSpaceTallyNode new.
	groupNode setSimulator: sim.
	groupNode setParent: rootNode depth: rootNode depth + 1.
	groupNode edgeLabel: aLabel.
	groupNode setClassName: (aLabel ifNil: ['(group)']) selfSize: 0 totalSize: 0.
	rootNode addChild: groupNode.

	oopCollection do: [:oop |
		(self isTallyableOop: oop) ifTrue: [
			self enqueueSimReferent: oop parent: groupNode labelBlock: [nil]]]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:06'
}
SWASimSpaceTally >> enqueueSimReferent: refOop parent: aNode labelBlock: aLabelBlock [
	"Shared dedup/enqueue step for #expandSimNode:. Skips non-tallyable oops.
	On a repeat hit, records aNode as an other-parent (when tracking is on); on
	a first hit, creates a lean child (label computed lazily via aLabelBlock
	only now that we know a node is needed) and enqueues it."

	| followed existingNode |
	(self isTallyableOop: refOop) ifFalse: [^ self].
	followed := self followOop: refOop.
	existingNode := oopSeen at: followed ifAbsent: [nil].
	existingNode
		ifNotNil: [
			trackOtherParents == true ifTrue: [
				| op |
				op := existingNode otherParents.
				op ifNil: [op := OrderedCollection new: 2. existingNode setOtherParents: op].
				op addLast: aNode]]
		ifNil: [
			| child |
			child := self newSimChildFor: followed parent: aNode edge: aLabelBlock value.
			oopSeen at: followed put: child.
			queue addLast: child]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:14'
}
SWASimSpaceTally >> enqueueSingleRoot: rootOop label: aLabel [
	"Enqueue a single-oop root as a direct child of rootNode (if tallyable and
	not already seen)."

	(self isTallyableOop: rootOop) ifFalse: [^ self].
	(self enqueueSimReferent: rootOop parent: rootNode labelBlock: [aLabel])
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:06'
}
SWASimSpaceTally >> expandSimNode: aNode [
	"Visit one node: enumerate its simulated referents and enqueue first-time
	ones. Dedup keyed on followed oop via oopSeen. No depth cap is needed: the
	closed (finite) oop space + oopSeen make the BFS finite.

	Class-pointer fix (mirrors the live walker's #referentsOf:do:): the mirror's
	#referentOopsDo: only follows pointer slots, NOT the class header field, so a
	class would never reach its metaclass and all metaclasses (plus their
	class-instance-var state) would land in LostAndFound. When this node's oop is
	a class/metaclass we therefore ALSO follow its class oop, labelled
	'<class>': Foo -> Foo class -> Metaclass. Restricted to class oops so an
	ordinary object never gets a class edge."

	| obj |
	visitCount := visitCount + 1.
	aNode mirror ifNil: [^ self].
	obj := aNode oop.

	"Follow the class pointer for classes/metaclasses only."
	(self isClassOop: obj) ifTrue: [
		self enqueueSimReferent: aNode mirror simClassOop parent: aNode labelBlock: ['<class>']].

	aNode mirror referentOopsDo: [:refOop :slotIndex |
		self
			enqueueSimReferent: refOop
			parent: aNode
			labelBlock: [self simLabelForOwner: aNode slotIndex: slotIndex]]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:00'
}
SWASimSpaceTally >> findSimLostObjects [
	"Deep sweep for the simulated heap: after a complete walk, find every
	universe oop the walk never reached and bucket them flat under a synthetic
	'LostAndFound' node, then group those into per-class bins.

	Lost = in deepUniverse and NOT in oopSeen. Mirrors #findLostObjects on the
	live walker, oop-keyed. Honors the optional maxVisits budget."

	| lostRoot |
	deepUniverse ifNil: [^ self].

	lostRoot := SWASimSpaceTallyNode new.
	lostRoot setSimulator: sim.
	lostRoot setParent: rootNode depth: rootNode depth + 1.
	lostRoot edgeLabel: 'LostAndFound'.
	lostRoot setClassName: 'LostAndFound' selfSize: 0 totalSize: 0.
	rootNode addChild: lostRoot.

	'Deep sweep: collecting lost objects...'
		displayProgressFrom: 0 to: deepUniverse size
		during: [:bar |
			| i |
			i := 0.
			deepUniverse keysDo: [:oop |
				i := i + 1.
				self visitBudgetRemains ifFalse: [
					limitHit isNil ifTrue: [limitHit := #maxVisits].
					^ self finishLost: lostRoot queue: #()].
				(i \\ 50000 = 0) ifTrue: [bar value: i].
				((oopSeen includesKey: oop) not and: [self isTallyableOop: oop])
					ifTrue: [
						| node |
						node := self newSimChildFor: oop parent: lostRoot edge: nil.
						oopSeen at: oop put: node.
						visitCount := visitCount + 1]]].

	self finishLost: lostRoot queue: #()
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally >> followOop: anOop [
	"Resolve forwarders to the real target address."
	| om |
	om := sim objectMemory.
	^ (om isForwarded: anOop)
		ifTrue: [om followForwarded: anOop]
		ifFalse: [anOop]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:18'
}
SWASimSpaceTally >> globalBindingsArrayOop [
	"The oop of the array backing the simulated image's global bindings
	dictionary. Navigates Smalltalk -> globals (Environment) -> bindings
	(IdentityDictionary) -> array. Each non-nil slot of that array is an
	Association (Symbol -> global value)."

	| om smalltalk globals bindings |
	om := sim objectMemory.
	smalltalk := self smalltalkOop.
	globals := om fetchPointer: 0 ofObject: smalltalk.       "SmalltalkImage>>globals"
	bindings := om fetchPointer: 2 ofObject: globals.        "Environment>>bindings"
	^ om fetchPointer: 1 ofObject: bindings                  "Dictionary>>array"
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:18'
}
SWASimSpaceTally >> globalNamed: aString [
	"Look up a global by name in the simulated image's Smalltalk and answer its
	value oop, or nil if absent. Scans the global bindings array for an
	Association whose key Symbol prints as aString."

	| om array nilOop |
	om := sim objectMemory.
	array := self globalBindingsArrayOop.
	nilOop := om nilObject.
	0 to: (om numSlotsOf: array) - 1 do: [:i |
		| assoc |
		assoc := om fetchPointer: i ofObject: array.
		(assoc ~= nilOop and: [(om isImmediate: assoc) not]) ifTrue: [
			| keyOop keyStr |
			keyOop := om fetchPointer: 0 ofObject: assoc.
			keyStr := [sim stringOf: keyOop] on: Error do: [:e | nil].
			keyStr = aString ifTrue: [^ om fetchPointer: 1 ofObject: assoc]]].
	^ nil
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:39'
}
SWASimSpaceTally >> instVarNamesOfClassOop: aClassOop [
	"Reading instVar names out of the simulated class is possible but not yet
	implemented; returning nil makes slot labels fall back to '[N]'."
	^ nil
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:13'
}
SWASimSpaceTally >> instanceOopsOfClassNamed: aString [
	"Answer an OrderedCollection of every heap oop whose class is the simulated
	global class named aString (direct instances only, like #allInstances). The
	sim has no #allInstances, so we scan the heap via objectMemory allObjectsDo:.
	Answers an empty collection if the class global is absent."

	| om classOop result |
	om := sim objectMemory.
	classOop := self globalNamed: aString.
	result := OrderedCollection new.
	classOop ifNil: [^ result].
	om allObjectsDo: [:oop |
		(om fetchClassOfNonImm: oop) = classOop ifTrue: [result add: oop]].
	^ result
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:18'
}
SWASimSpaceTally >> isClassOop: anOop [
	"True if anOop is a class or metaclass registered in the simulated image's
	class table. Spur stores a class's class-table index in its identity-hash
	field, so an object is a class iff the class table at its hash resolves back
	to itself. This is the oop-level analogue of `isKindOf: Behavior` and lets us
	follow a class's class pointer to its metaclass (see #expandSimNode:).

	CRITICAL: for a non-class object the hash is an arbitrary identity hash, NOT
	a class index, and may fall outside the legal class-index range. We must
	range-check it BEFORE calling #classOrNilAtIndex:, which asserts the index is
	valid (`idx <= tagMask or: [idx >= arrayClassIndexPun]`) and indexes the
	fixed-capacity class table -- an out-of-range hash would trip the assertion
	or read past the table. Legal indices are: (<= tagMask OR >= arrayClassIndexPun)
	AND < the class-table capacity."

	| om h capacity |
	om := sim objectMemory.
	h := om rawHashBitsOf: anOop.
	h = 0 ifTrue: [^ false].
	"Reject hashes that aren't legal class-table indices."
	(h <= om tagMask or: [h >= om arrayClassIndexPun]) ifFalse: [^ false].
	capacity := om numClassTablePages * om classTablePageSize.
	h >= capacity ifTrue: [^ false].
	^ (om classOrNilAtIndex: h) = anOop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally >> isTallyableOop: anOop [
	"True if anOop is a real, enumerable heap object worth recording:
	non-immediate, non-nil, not free, not a forwarder target that resolves
	to free. Immediates carry no heap footprint."
	| om followed |
	om := sim objectMemory.
	anOop ifNil: [^ false].
	(om isImmediate: anOop) ifTrue: [^ false].
	anOop = om nilObject ifTrue: [^ false].
	followed := self followOop: anOop.
	(om isFreeObject: followed) ifTrue: [^ false].
	^ true
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:36'
}
SWASimSpaceTally >> newSimChildFor: anOop parent: parentNode edge: aLabel [
	"Create a lean sim child node wrapping the simulated object at anOop
	(already followed). Captures className and selfSize immediately from the
	mirror, and hooks the node into the tree."

	| node m |
	node := SWASimSpaceTallyNode new.
	node setSimulator: sim.
	node setParent: parentNode depth: parentNode depth + 1.
	node edgeLabel: aLabel.
	m := SimObjectMirror on: sim oop: anOop.
	node setOop: anOop mirror: m.
	parentNode addChild: node.
	^ node
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally >> rootOop: anOop [
	"Walk from a single simulated object."
	^ self rootOops: (Array with: anOop)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally >> rootOops: oopCollection [
	"Set explicit root oops (raw simulated addresses, or label -> oop
	Associations). Each becomes a top-level node."
	roots := oopCollection asArray.
	^ self
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:27'
}
SWASimSpaceTally >> setSimulator: aStackInterpreterSimulator [
	"Set the simulator this group will walk."

	sim := aStackInterpreterSimulator
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:38'
}
SWASimSpaceTally >> simLabelForOwner: ownerNode slotIndex: zeroBasedIndex [
	"Human-readable edge label for a slot. Uses the owner's class instVar
	names when available; otherwise an index label. zeroBasedIndex is the
	0-based pointer slot index from SimObjectMirror."

	| names oneBased |
	oneBased := zeroBasedIndex + 1.
	names := self instVarNamesOfClassOop: ownerNode mirror simClassOop.
	^ (names notNil and: [oneBased <= names size])
		ifTrue: [names at: oneBased]
		ifFalse: ['[', oneBased printString, ']']
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:27'
}
SWASimSpaceTally >> simulator [
	"The StackInterpreterSimulator whose memory this group walked."

	^ sim
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:17'
}
SWASimSpaceTally >> smalltalkOop [
	"The simulated image's SmalltalkImage (i.e. `Smalltalk`), held in the
	specialObjectsArray (slot 8)."

	| om |
	om := sim objectMemory.
	^ om fetchPointer: 8 ofObject: om specialObjectsOop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:14'
}
SWASimSpaceTally >> walk [
	"BFS over the simulated heap from the configured root oops, building a tree
	of lean SWASimSpaceTallyNode objects rooted at rootNode. Dedup is keyed on
	oop via a plain Dictionary (oopSeen). Records run metadata. Returns self.

	TERMINATION & COVERAGE: like the live-heap walk, we first snapshot a closed
	universe of every object oop in the simulated heap (#captureSimUniverse).
	That universe is finite and oopSeen claims each oop once, so the BFS always
	terminates. The universe size also drives a real progress bar.

	A root's value may be a single oop (label -> oop) OR a host collection of
	oops (label -> #(oop ...)). A collection root becomes one synthetic parent
	node with the oops as children -- the sim equivalent of the live walker's
	synthetic Arrays (e.g. 'Processes' -> all Process instances).

	maxVisits is OPTIONAL (nil = unlimited); set it to bound a walk for testing.

	When findDeep is set and the walk completed, a whole-heap sweep buckets
	every oop the walk did not reach under a LostAndFound node (see
	#findSimLostObjects) -- so the reported total covers the entire image, not
	just what the roots reached."

	| progressStep nextProgress startMs universeSize |
	sim ifNil: [^ self error: 'no simulator set'].
	roots ifNil: [roots := self defaultRootOops].
	findDeepSkipped := false.

	"Snapshot the closed universe first."
	self captureSimUniverse.
	universeSize := deepUniverse size.

	startMs := Time millisecondClockValue.
	startedAt := DateAndTime now.
	oopSeen := Dictionary new: universeSize.
	queue := OrderedCollection new.
	visitCount := 0.
	limitHit := nil.
	compacted := false.

	rootNode := SWASimSpaceTallyNode new.
	rootNode setSimulator: sim.
	rootNode setClassName: 'SWASimSpaceTally root' selfSize: 0 totalSize: 0.

	roots do: [:each |
		| label rootValue |
		(each isKindOf: Association)
			ifTrue: [label := each key. rootValue := each value]
			ifFalse: [label := nil. rootValue := each].
		(rootValue isCollection and: [(rootValue isKindOf: Association) not])
			ifTrue: [self enqueueGroupRoot: rootValue label: label]
			ifFalse: [self enqueueSingleRoot: rootValue label: label]].

	progressStep := (universeSize // 200) max: 1000.
	nextProgress := progressStep.
	'Walking simulated heap...' displayProgressFrom: 0 to: universeSize during: [:bar |
		[queue notEmpty and: [self visitBudgetRemains]] whileTrue: [
				self expandSimNode: queue removeFirst.
				visitCount >= nextProgress ifTrue: [
					bar value: visitCount.
					nextProgress := nextProgress + progressStep]]].

	queue notEmpty ifTrue: [limitHit := #maxVisits].
	queue do: [:n | n markTruncated].
	rootNode rollUp.

	self findDeep ifTrue: [
		limitHit isNil
			ifTrue: [self findSimLostObjects]
			ifFalse: [findDeepSkipped := true]].

	durationMs := Time millisecondClockValue - startMs.
	self captureParamsSnapshot.
	self clearWalkerState.
	^ self
]
