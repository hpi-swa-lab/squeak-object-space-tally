"
A wrap-and-replace invocation counter for a single CompiledMethod, in the style
of Dan Ingalls' Lively Kernel profiler (tallyFunc).

Installed into a method dictionary in place of the real method; on each call it
increments #count (and accrues #ticks, elapsed ms), then forwards to the original
via #doesNotUnderstand:. When #count reaches #evictAt it UNINSTALLS itself so a
very hot method stops paying the wrapper overhead -- the count is frozen at the
eviction point and the method runs at full speed again. This keeps the whole-image
tally from freezing the system the way an unbounded wrap would.

Use SWACoverage as the front end; it installs/uninstalls a batch of these and
collects them into a Class>>selector -> count map for the Code Map's #coverage
color mode.

Instance Variables
	theClass        <Behavior>        the method's class (instance- or meta-side)
	selector        <Symbol>
	originalMethod  <CompiledMethod>  restored on uninstall
	count           <Integer>         invocations seen (frozen once evicted)
	ticks           <Integer>         accrued elapsed milliseconds
	evictAt         <Integer|nil>     uninstall after this many calls; nil = never
	evicted         <Boolean>         true once self-uninstalled
"
Class {
	#name : #SWATallyWrapper,
	#superclass : #Object,
	#instVars : [
		'theClass',
		'selector',
		'originalMethod',
		'count',
		'ticks',
		'evictAt',
		'evicted'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> count [
	^ count
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> crossRefKey [
	"The Code Map cross-ref key for the method I wrap: 'Class>>selector'."
	^ theClass name asString, '>>', selector
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> doesNotUnderstand: aMessage [
	"Anything the system asks of a 'method' (e.g. for reflection while installed)
	is forwarded to the real method."
	^ originalMethod perform: aMessage selector withArguments: aMessage arguments
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> install [
	"Replace the real method in the dictionary with me."
	theClass methodDictionary at: selector put: self.
	theClass flushCache
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> onClass: aClass selector: aSelector evictAt: anIntegerOrNil [
	theClass := aClass.
	selector := aSelector.
	originalMethod := aClass >> aSelector.
	count := 0.
	ticks := 0.
	evictAt := anIntegerOrNil.
	evicted := false
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> run: aSelector with: anArray in: aReceiver [
	"Invoked by the VM when the wrapped method is sent (the wrapper sits in the
	method dict, so a send dispatches here). Count, time, evict-if-hot, forward."
	| t0 result |
	count := count + 1.
	(evictAt notNil and: [count >= evictAt])
		ifTrue: [evicted := true. self uninstall].
	t0 := Time millisecondClockValue.
	result := aReceiver withArgs: anArray executeMethod: originalMethod.
	ticks := ticks + (Time millisecondClockValue - t0).
	^ result
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> ticks [
	^ ticks
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:27'
}
SWATallyWrapper >> uninstall [
	"Restore the real method. Idempotent."
	(theClass methodDictionary at: selector ifAbsent: [nil]) == self
		ifTrue: [theClass methodDictionary at: selector put: originalMethod.
			theClass flushCache]
]
