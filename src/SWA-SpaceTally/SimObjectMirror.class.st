"
A far-reference / proxy to an object living inside a simulated Squeak image driven by a StackInterpreterSimulator.

I wrap a single object pointer (oop, a SmallInteger address into the simulated heap) together with the simulator (sis) and its object memory (om). I forward reflective queries -- class, size, slot access, byte access -- to the simulator's memory manager instead of the host VM.

Forwarders are followed eagerly: my oop is always the followed (non-forwarder) address, so identity and identityHash are stable and correspond to the real target object.

Immediates (SmallIntegers, Characters, SmallFloats) in the simulated heap are NOT wrapped; they are decoded to host values by the mirror factory, since they carry no heap footprint and are not interesting to a space tally.

Identity: two mirrors are = and have the same hash iff they wrap the same followed oop in the same object memory. This lets an IdentityDictionary-based graph walk (SWASpaceTally) treat mirrors like ordinary objects.

Instances are created via the class-side #on:oop: which follows forwarders. Use #referentMirrorsDo: to enumerate the mirrors of my heap-object slots.
"
Class {
	#name : #SimObjectMirror,
	#superclass : #Object,
	#instVars : [
		'sis',
		'om',
		'oop'
	],
	#category : #'SWA-SpaceTally-Sim',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror class >> on: aSimulator oop: anOop [
	"Create a mirror for anOop in aSimulator's object memory.
	Follows forwarders so the stored oop is the real target.
	Answers nil for immediates (they have no heap footprint)."

	| om followed |
	om := aSimulator objectMemory.
	(om isImmediate: anOop) ifTrue: [^ nil].
	followed := (om isForwarded: anOop)
		ifTrue: [om followForwarded: anOop]
		ifFalse: [anOop].
	^ self basicNew setSimulator: aSimulator oop: followed
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> = anObject [
	"Two mirrors are equal iff they wrap the same oop in the same object memory."
	^ self class == anObject class
		and: [oop = anObject oop
		and: [om == anObject objectMemory]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:02'
}
SimObjectMirror >> byteSize [
	"Total heap bytes I occupy in the simulated image, INCLUDING the object
	header. `byteSizeOf:` / `numBytesOf:` return only the content (body) bytes
	and omit the header, which undercounts every object by 8-16 bytes; for a
	memory tally we want the real footprint, so use `bytesInBody:`."

	^ om bytesInBody: oop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> hash [
	"Hash on the wrapped oop so equal mirrors hash equally.
	This lets SWASpaceTally's IdentityDictionary-based seen set work --
	but note SWASpaceTally uses IdentitySet/IdentityDictionary, so for the
	sim walk we must key on a normal Dictionary (= / hash). The sim tally
	subclass uses an oop-keyed Dictionary instead; this hash is for general use."
	^ oop hash
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> numPointerSlots [
	"Number of pointer-bearing slots (handles fixed, variable, and
	compiled-method objects uniformly)."
	^ om numPointerSlotsOf: oop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> objectMemory [
	^ om
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> oop [
	"The followed (non-forwarder) heap address I wrap."
	^ oop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> pointerSlotOopAt: zeroBasedIndex [
	"The raw oop in pointer slot zeroBasedIndex (0-based, following
	the simulator's fetchPointer:ofObject: convention)."
	^ om fetchPointer: zeroBasedIndex ofObject: oop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:36'
}
SimObjectMirror >> printOn: aStream [
	aStream
		nextPutAll: 'a SimObjectMirror(';
		nextPutAll: self simClassName;
		nextPutAll: ' @ ';
		print: oop;
		nextPut: $)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:02'
}
SimObjectMirror >> referentOopsDo: aBlock [
	"Evaluate aBlock with each non-immediate, non-nil STRONG referent oop and
	its 0-based slot index. Skips immediates and the nil oop (no heap footprint).
	Uniform across fixed/variable/compiled-method objects via numPointerSlots.

	WEAK SLOTS ARE NOT FOLLOWED. For a weak object only the named (fixed) slots
	are strong; the indexed part holds weak references that do not express
	ownership, so following them would impose a misleading parent in the tree.
	We therefore only enumerate the fixed slots of a weak object. Anything
	reachable only through a weak slot is claimed later via a strong path or
	ends up in LostAndFound -- which is fine."

	| n nilOop |
	n := self numPointerSlots.
	(om isWeakNonImm: oop) ifTrue: [n := om numFixedSlotsOf: oop].
	nilOop := om nilObject.
	0 to: n - 1 do: [:i |
		| ref |
		ref := om fetchPointer: i ofObject: oop.
		(ref ~= nilOop and: [(om isImmediate: ref) not])
			ifTrue: [aBlock value: ref value: i]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> setSimulator: aSimulator oop: anOop [
	sis := aSimulator.
	om := aSimulator objectMemory.
	oop := anOop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:52'
}
SimObjectMirror >> simClassName [
	"The name of my class in the simulated image, as a host String.

	The VM's #nameOfClass: returns 'bad class' for VM-internal heap-management
	objects (free lists, remembered set, class-table page backing, ...) that
	have no real Smalltalk class. Substitute a role-based name for those so the
	tally reads sensibly instead of lumping them under 'bad class'."

	| name |
	name := [sis nameOfClass: self simClassOop]
		on: Error do: [:e | '<? ', oop printString, '>'].
	(name = 'bad class') ifTrue: [^ self vmRoleName].
	^ name
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> simClassOop [
	"The oop of my class in the simulated image."
	^ om fetchClassOfNonImm: oop
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/16/2026 14:35'
}
SimObjectMirror >> simulator [
	^ sis
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 11:52'
}
SimObjectMirror >> vmRoleName [
	"A friendly name for a VM-internal heap-management object that has no real
	Smalltalk class (the VM's #nameOfClass: reports 'bad class' for these). We
	identify the few singletons we can by oop and label the rest generically.

	These objects are the memory manager's own scaffolding -- free lists, the
	GC remembered set, class-table page backing, and assorted index/bitmap word
	arrays -- not user data. They scale with heap size, not with the program."

	| numSlots |
	oop = om freeListsObject ifTrue: [^ '<VM: freeLists>'].
	(om respondsTo: #rememberedSetObj) ifTrue: [
		oop = om rememberedSetObj ifTrue: [^ '<VM: rememberedSet>']].
	"The big anonymous word arrays: classify by size/format heuristically."
	numSlots := om numSlotsOf: oop.
	(om formatOf: oop) >= 9 ifTrue: [
		numSlots = om classTablePageSize ifTrue: [^ '<VM: classTablePage>'].
		numSlots >= 4092 ifTrue: [^ '<VM: classTablePage>'].
		^ '<VM internal (' , numSlots printString , ' words)>'].
	^ '<VM internal>'
]
