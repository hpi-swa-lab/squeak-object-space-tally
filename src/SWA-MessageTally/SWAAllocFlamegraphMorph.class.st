"
An allocation flamegraph coloured by RETENTION, with the call stack greyed out.

The stock flamegraph gives every frame a warm hue by name -- meaningless here. This colours only the ALLOCATION nodes (the deepest bare-class-name frames where objects are actually made); the call stack above them is scaffolding and stays grey, so the eye goes straight to the allocation sites.

Colour is retention, and the polarity is deliberate: GC reclaiming an object is the GOOD outcome, so
  RED   = the objects made here were KEPT across a scavenge -- the working set that plateaus and gets re-copied forever (the 2026-08-14b hunt), the thing to fix.
  GREEN = the objects made here DIED in the scavenge -- transient, reclaimed, healthy.
Width is still allocation count (inherited), so the worst sites are the WIDE RED ones: allocate a lot AND keep it. A wide green band is a lot of churn that costs nothing to collect.

Retention fraction per site comes from SWAAllocTracer>>survivalFractionOf: (hashes recorded at allocation, matched against the live traced-class instances after a scavenge).
"
Class {
	#name : #SWAAllocFlamegraphMorph,
	#superclass : #SWASamplingTallyFlamegraphMorph,
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'alloc trace',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:47'
}
SWAAllocFlamegraphMorph >> addToAllocTrace: aClass [
	SWAAllocTracer traceClass: aClass
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 16:46'
}
SWAAllocFlamegraphMorph >> baseColorForNode: aNode [
	"Only ALLOCATION nodes carry colour; the call stack above them is scaffolding and
	stays grey, so the eye goes straight to where objects are made and what became of
	them. An allocation node is the deepest frame -- a bare class name (no '>>'), the
	one #recordAllocationOf:from: appends per allocation.

	Colour = RETENTION, not survival, because GC doing its job is the good outcome:
	  RED   = the objects made here were KEPT (survived the scavenge) -- the churn that
	          plateaus and gets re-copied forever, the thing we are hunting.
	  GREEN = the objects made here DIED in the scavenge -- transient, reclaimed, fine.
	So hue runs green(120) at 0% retained to red(0) at 100% retained."
	| survived |
	(aNode name includesSubstring: '>>')
		ifTrue: [^ Color gray: 0.32].
	survived := SWAAllocTracer survivalFractionOf: aNode.
	survived ifNil: [^ Color gray: 0.32].
	^ Color h: (1.0 - survived) * 120.0 s: 0.8 v: 0.85
]

{
	#category : #'alloc trace',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:47'
}
SWAAllocFlamegraphMorph >> classForNode: aNode [
	"The traceable Class a flamegraph node stands for, or nil. An allocation leaf's name
	is a bare class name (Vector3, Array); a stack frame is Class>>selector, whose class
	is the part before '>>'. Only answer a class with a known allocation funnel (see
	SWAAllocTracer>>funnelsFor:), so the menu item never appears for something we cannot
	trace."
	| name clsName cls |
	name := aNode name ifNil: [^ nil].
	clsName := (name includesSubstring: '>>')
		ifTrue: [name copyFrom: 1 to: (name indexOfSubCollection: '>>') - 1]
		ifFalse: [name].
	(clsName notEmpty and: [clsName first isUppercase]) ifFalse: [^ nil].
	"metaclass frame 'Foo class>>bar' -> Foo"
	clsName := (clsName endsWith: ' class')
		ifTrue: [clsName copyFrom: 1 to: clsName size - 6]
		ifFalse: [clsName].
	cls := Smalltalk at: clsName asSymbol ifAbsent: [^ nil].
	cls isBehavior ifFalse: [^ nil].
	^ (SWAAllocTracer funnelsFor: (IdentitySet with: cls)) isEmpty
		ifTrue: [nil]
		ifFalse: [cls]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:47'
}
SWAAllocFlamegraphMorph >> mouseDown: evt [
	"Right-click opens a context menu (add/remove the node's class to the allocation
	trace, plus explore) instead of jumping straight to an explorer as the base
	flamegraph does. Left-click keeps the base select/zoom behaviour."
	| f node |
	evt yellowButtonPressed ifFalse: [^ super mouseDown: evt].
	f := self frameAt: evt position.
	f isNil ifTrue: [^ self].
	node := f at: 1.
	node ifNil: [^ self].
	self showContextMenuFor: node event: evt
]

{
	#category : #'alloc trace',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:47'
}
SWAAllocFlamegraphMorph >> removeFromAllocTrace: aClass [
	SWAAllocTracer stopTracingClass: aClass
]

{
	#category : #'alloc trace',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 17:47'
}
SWAAllocFlamegraphMorph >> showContextMenuFor: aNode event: evt [
	"Right-click menu: manage the node's class in the allocation trace's classes of
	interest, browse the allocating method, and explore. The alloc-trace items appear
	only when the node resolves to a traceable class."
	| menu cls |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (aNode name ifNil: ['?']).
	cls := self classForNode: aNode.
	cls ifNotNil: [
		(SWAAllocTracer tracedClasses includes: cls)
			ifTrue: [menu add: 'remove ', cls name, ' from allocation trace'
				target: self selector: #removeFromAllocTrace: argument: cls]
			ifFalse: [menu add: 'add ', cls name, ' to allocation trace'
				target: self selector: #addToAllocTrace: argument: cls].
		menu addLine].
	(aNode crossRefKey notNil and: [aNode isSmalltalkFrame]) ifTrue: [
		menu add: 'browse' target: aNode selector: #browse.
		menu addLine].
	menu add: 'explore node' target: ToolSet selector: #explore: argument: aNode.
	menu popUpEvent: evt in: self world
]
