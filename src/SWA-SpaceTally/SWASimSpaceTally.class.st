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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:37'
}
SWASimSpaceTally >> defaultRootOops [
	"Default roots for a whole-image walk: the special objects array
	(reaches the class table, nil/true/false, the active process, etc.).
	Labelled for readability in the explorer/treemap."
	| om |
	om := sim objectMemory.
	^ Array with: ('specialObjectsArray' -> om specialObjectsOop)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:44'
}
SWASimSpaceTally >> expandSimNode: aNode [
	"Visit one node: enumerate its simulated referents and enqueue first-time
	ones. Dedup keyed on followed oop via oopSeen. No depth cap is needed: the
	closed (finite) oop space + oopSeen make the BFS finite."

	visitCount := visitCount + 1.
	aNode mirror ifNil: [^ self].

	aNode mirror referentOopsDo: [:refOop :slotIndex |
		(self isTallyableOop: refOop) ifTrue: [
			| followed existingNode |
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
					| child label |
					label := self simLabelForOwner: aNode slotIndex: slotIndex.
					child := self newSimChildFor: followed parent: aNode edge: label.
					oopSeen at: followed put: child.
					queue addLast: child]]]
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:39'
}
SWASimSpaceTally >> instVarNamesOfClassOop: aClassOop [
	"Reading instVar names out of the simulated class is possible but not yet
	implemented; returning nil makes slot labels fall back to '[N]'."
	^ nil
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:46'
}
SWASimSpaceTally >> walk [
	"BFS over the simulated heap from the configured root oops, building a tree
	of lean SWASimSpaceTallyNode objects rooted at rootNode. Dedup is keyed on
	oop via a plain Dictionary (oopSeen), since host identity can't dedup
	mirrors or large oops. Records run metadata on this group. Returns self.

	TERMINATION: like the live-heap walk, the simulated heap is a closed,
	finite oop space that does not grow under us during the walk, and oopSeen
	claims each followed oop exactly once -- so the BFS terminates on its own.
	maxVisits is OPTIONAL (nil = unlimited); set it to bound a walk for testing.

	Unlike the live walk we have no cheap exact object count for the simulated
	heap, so oopSeen starts at the default capacity and grows. The progress bar
	is bounded by maxVisits when set, otherwise tracks visitCount as a spinner."

	| progressStep nextProgress startMs progressMax |
	sim ifNil: [^ self error: 'no simulator set'].
	roots ifNil: [roots := self defaultRootOops].
	startMs := Time millisecondClockValue.
	startedAt := DateAndTime now.
	oopSeen := Dictionary new.
	queue := OrderedCollection new.
	visitCount := 0.
	limitHit := nil.
	compacted := false.

	rootNode := SWASimSpaceTallyNode new.
	rootNode setSimulator: sim.
	rootNode setClassName: 'SWASimSpaceTally root' selfSize: 0 totalSize: 0.

	roots do: [:each |
		| label rootOop |
		(each isKindOf: Association)
			ifTrue: [label := each key. rootOop := each value]
			ifFalse: [label := nil. rootOop := each].
		(self isTallyableOop: rootOop) ifTrue: [
			| followed |
			followed := self followOop: rootOop.
			(oopSeen includesKey: followed) ifFalse: [
				| childNode |
				childNode := self newSimChildFor: followed parent: rootNode edge: label.
				oopSeen at: followed put: childNode.
				queue addLast: childNode]]].

	progressMax := maxVisits.
	progressStep := ((progressMax ifNil: [1000]) // 200) max: 1000.
	nextProgress := progressStep.
	'Walking simulated heap...' displayProgressFrom: 0 to: (progressMax ifNil: [1]) during: [:bar |
		[queue notEmpty and: [self visitBudgetRemains]] whileTrue: [
				self expandSimNode: queue removeFirst.
				visitCount >= nextProgress ifTrue: [
					bar value: (progressMax ifNil: [visitCount \\ 2] ifNotNil: [visitCount]).
					nextProgress := nextProgress + progressStep]]].

	queue notEmpty ifTrue: [limitHit := #maxVisits].
	queue do: [:n | n markTruncated].
	rootNode rollUp.
	durationMs := Time millisecondClockValue - startMs.
	self captureParamsSnapshot.
	self clearWalkerState.
	^ self
]
