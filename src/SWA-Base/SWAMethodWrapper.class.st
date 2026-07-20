"
Shared base for the SWA method-instrumentation wrappers (SWACoverageWrapper,
SWATallyWrapper).

A wrapper is installed IN PLACE of a CompiledMethod in a class's method
dictionary. When the method is sent, the VM dispatches #run:with:in: here; we do
our bookkeeping and then #forward:with:in: to the real (captured) method. Any
reflection the system performs on the installed 'method' is forwarded via
#doesNotUnderstand:.

This superclass exists so the instrumentation SUBSTRATE -- install/uninstall, the
forward, reflection forwarding, the precomputed name, and (critically) the rule
that the hot path must stay substrate-safe -- lives in ONE place. Subclasses
ONLY override #run:with:in: to decide what to record per call, and add their own
state. They MUST keep that hot path send-free except for sends into hard
substrate packages (Kernel*/Collections* are never wrapped). The two prior copies
drifted and the tally copy called Time>>millisecondClockValue (Chronology-Core,
NOT substrate), which got wrapped on a '*' run and crashed the VM by recursing.

Subclass contract:
 - call super onClass:selector: from your own initializer to set up the 4 base
   ivars + precomputed methodNameString;
 - implement #run:with:in: doing minimal, substrate-safe work then
   ^ self forward: aSelector with: anArray in: aReceiver.
"
Class {
	#name : #SWAMethodWrapper,
	#superclass : #Object,
	#instVars : [
		'theClass',
		'selector',
		'originalMethod',
		'methodNameString',
		'count',
		'evictAt',
		'evicted'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #eviction,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:45'
}
SWAMethodWrapper class >> defaultEvictAt [
	"The default self-eviction threshold for EVERY wrapper. Eviction is a SURVIVAL
	mechanism, not a tuning knob you turn off: a hot method that keeps paying wrapper
	overhead grinds the whole system to a halt, so after this many invocations the
	wrapper uninstalls itself NO MATTER WHAT, and is marked #evicted. That a method
	evicted (it is hot) is more important than any data we'd gather from it.

	Start small and raise as it proves stable (Jens: 'go from the small side';
	practically ~1000 is expected to be fine). Set per-instance via #evictAt: only to
	RAISE it for a specific case; nil disables eviction and should be used only when
	you are certain the watched methods are cold."
	^ 1000
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:00'
}
SWAMethodWrapper class >> flushSystemCache [
	"Flush the entire VM method lookup cache ONCE (primitive 89 is a global flush).
	Send this once after a BULK #installNoFlush / #uninstallNoFlush loop instead of
	flushing per method."
	Object flushCache
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:48'
}
SWAMethodWrapper class >> guardedDo: aBlock [
	"Run aBlock with capturing SUPPRESSED (COP `withoutLayers(Capturing)`), restoring
	afterwards. Use for any instrumentation-framework code -- capture hooks, the runner
	loop, the logger, recording -- so wrapped methods it touches fall straight through
	their wrappers instead of recursing. Now delegates to the process-specific
	SWACapturingLayer, so this is re-entrant AND correct across concurrent processes."
	^ SWACapturingLayer withoutCapturing: aBlock
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:48'
}
SWAMethodWrapper class >> isInWrapper [
	"THE general reentrancy guard, shared by ALL wrapper subclasses. True means
	'control is currently inside instrumentation machinery' in THIS process -- a
	capture hook, the runner, the logger, the recording code -- so every wrapper's
	#run:with:in: must skip capture and just forward. Now backed by the process-
	specific SWACapturingLayer (true == layer suppressed here)."
	^ SWACapturingLayer isActive not
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:48'
}
SWAMethodWrapper class >> resetGuard [
	"Force capturing back ACTIVE in THIS process so a crash or stray suppression can't
	leave wrappers permanently passing through. Delegates to SWACapturingLayer reset."
	SWACapturingLayer reset
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:29'
}
SWAMethodWrapper class >> uninstallAllStrayWrappers [
	"SAFETY NET: scan EVERY method dictionary -- INSTANCE side AND METACLASS side -- and,
	for any slot holding a SWAMethodWrapper, restore the REAL underlying CompiledMethod
	(peeling through ANY number of stacked wrapper layers), then flush the VM cache
	ONCE. Answers the number of slots cleaned.

	CRITICAL: must cover metaclasses. `Smalltalk allClassesAndTraits` does NOT include
	metaclasses, but #methodsForPackages: instruments CLASS-SIDE methods too. Scanning
	only instance-side left class-side wrappers installed forever -- they survived every
	cleanup and crashed the image on the NEXT tally (the '2nd run crashes' bug). We scan
	both `cls` and `cls class` for each class/trait.

	WHY LAYER-AWARE: pressing Tally while a prior run's wrappers are still installed
	(after a crash/snapshot, or an abandoned run) installs a NEW wrapper OVER the old
	one, so the new wrapper's originalMethod IS the old wrapper. A per-owner #uninstall
	only restores its own originalMethod -- which puts the OLDER wrapper back, leaving
	it stranded. Peeling to the first non-wrapper originalMethod fixes every layer at
	once, regardless of which owner installed them (owner may be gone/GC'd).

	Runs under #guardedDo: so nothing is captured/re-entered."
	| cleaned cleanDict |
	cleaned := 0.
	cleanDict := [:md |
		md keysAndValuesDo: [:sel :entry |
			(entry isKindOf: SWAMethodWrapper) ifTrue: [ | real |
				real := entry.
				[real isKindOf: SWAMethodWrapper] whileTrue: [
					real := real instVarNamed: 'originalMethod'].
				md at: sel put: real.
				cleaned := cleaned + 1]]].
	self guardedDo: [
		Smalltalk allClassesAndTraits do: [:cls |
			cleanDict value: cls methodDictionary.
			cleanDict value: cls class methodDictionary]].
	self flushSystemCache.
	^ cleaned
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 10:48'
}
SWAMethodWrapper class >> whileUnguardedDo: aBlock [
	"Run aBlock with capturing forced ACTIVE (COP MEASURING WINDOW), restoring the
	previous layer state afterwards. The runner opens this ONLY around the actual code
	under test (#testCase run) so the wrapped methods that code exercises -- at ANY
	depth -- capture, while the surrounding machinery stays suppressed via #guardedDo:.
	Delegates to the process-specific SWACapturingLayer."
	^ SWACapturingLayer whileCapturing: aBlock
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:07'
}
SWAMethodWrapper >> at: index [
	"Forward indexing to the real method. A CompiledMethod is indexable (bytes/
	literals) and the compile/methodModified: path indexes the installed 'method';
	these selectors hit the indexing PRIMITIVE on Object (not doesNotUnderstand:), so
	we must override them explicitly or get 'not indexable'."
	^ originalMethod at: index
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:07'
}
SWAMethodWrapper >> at: index put: value [
	"Forward indexed store to the real method (see #at:)."
	^ originalMethod at: index put: value
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:07'
}
SWAMethodWrapper >> basicAt: index [
	^ originalMethod basicAt: index
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:08'
}
SWAMethodWrapper >> basicAt: index put: value [
	^ originalMethod basicAt: index put: value
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:08'
}
SWAMethodWrapper >> basicSize [
	^ originalMethod basicSize
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:24'
}
SWAMethodWrapper >> captureIn: aReceiver [
	"Subclass capture hook, called by the template #run:with:in: with the reentrancy
	guard already RAISED. Do the tool's minimal per-call work here (consulting the
	tool's OWN semantic flags -- e.g. coverage's recording-active layer + currentTest).
	Default: nothing extra (a plain counting wrapper). Subclasses override.

	Because the guard is raised around this, you may freely send to Collections /
	Streams / Files etc. -- those sends fall through their wrappers."
	"no-op by default"
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:25'
}
SWAMethodWrapper >> count [
	"Base invocation count -- how many times the wrapped method was sent while this
	wrapper was installed (and not skipped by the reentrancy guard)."
	^ count
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> crossRefKey [
	"The Code Map cross-ref key for the method I wrap: 'Class>>selector'. Same string
	as methodName (precomputed)."
	^ methodNameString
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> doesNotUnderstand: aMessage [
	"While installed I sit where a CompiledMethod is expected. Forward any reflection
	the system performs on the 'method' (e.g. #methodClass, #pragmas, #flushCache) to
	the real method."
	^ originalMethod perform: aMessage selector withArguments: aMessage arguments
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:25'
}
SWAMethodWrapper >> evictAt: anIntegerOrNil [
	"Set the self-eviction threshold: after this many invocations the wrapper
	uninstalls itself no matter what. nil = never evict (the default; required for
	coverage, which must keep watching every method for the whole run)."
	evictAt := anIntegerOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:25'
}
SWAMethodWrapper >> evicted [
	"True if this wrapper self-evicted (uninstalled) after passing evictAt."
	^ evicted == true
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> forward: aSelector with: anArray in: aReceiver [
	"Run the REAL method. The ONE substrate-safe forward all subclasses use:
	Object>>withArgs:executeMethod: is Kernel-Objects (hard substrate, never
	wrapped), and originalMethod was captured at install, so this is safe even after
	we replaced the dict entry. Subclass #run:with:in: ends with this."
	^ aReceiver withArgs: anArray executeMethod: originalMethod
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> install [
	"Replace the real method in the dictionary with me, so a send dispatches to my
	#run:with:in:. Flush the method cache so the change takes effect."
	theClass methodDictionary at: selector put: self.
	theClass flushCache
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:00'
}
SWAMethodWrapper >> installNoFlush [
	"Replace the real method in the dictionary WITHOUT flushing the method cache.
	For BULK installs: flushCache is primitive 89, a GLOBAL VM-cache flush, so calling
	it once per method over tens of thousands of methods re-flushes the whole cache
	tens of thousands of times -- pathologically slow (this is the '*' hang after the
	provenance-run banner). Install all wrappers with this, then send #flushCache ONCE
	(e.g. SWAMethodWrapper flushCache)."
	theClass methodDictionary at: selector put: self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> methodName [
	"Precomputed 'Class>>selector' (built at install, never in the hot path)."
	^ methodNameString
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:08'
}
SWAMethodWrapper >> objectAt: index [
	"Forward literal access (CompiledMethod>>objectAt: reads header/literals)."
	^ originalMethod objectAt: index
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:08'
}
SWAMethodWrapper >> objectAt: index put: value [
	^ originalMethod objectAt: index put: value
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 11:33'
}
SWAMethodWrapper >> onClass: aClass selector: aSelector [
	"Base initialization shared by all wrappers. Captures the class, selector, and
	the REAL method (so the forward and reflection always reach the original even
	after we replace it in the dict), precomputes the 'Class>>selector' name NOW
	(never in the hot path), and initializes the base COUNT/EVICT state.

	CRITICAL: originalMethod MUST be a real CompiledMethod, never another wrapper.
	`aClass >> aSelector` returns the currently-installed dict ENTRY, which is a
	SWAMethodWrapper if this method is ALREADY wrapped (a prior run's wrapper still
	installed after a crash/snapshot or an abandoned run). Capturing a wrapper as
	originalMethod is the LAYERING bug: forwarding then hands a non-CompiledMethod to
	#withArgs:executeMethod:, whose primitive-188 fallback corrupts the in-flight send
	(ByteSymbol>>lookupClass DNU on the world-menu path; Message>(nil) on the theme
	path) AND per-owner uninstall restores the older wrapper instead of the real
	method, stranding it. So peel through any installed wrapper layers here.

	Eviction is ON BY DEFAULT (evictAt := self class defaultEvictAt). This is a
	SURVIVAL valve: a hot method MUST drop out or it grinds the system to a halt.
	Raise the threshold per-instance with #evictAt: if needed; pass nil only when you
	are certain the watched methods are cold."
	| m |
	theClass := aClass.
	selector := aSelector.
	m := aClass >> aSelector.
	[m isKindOf: SWAMethodWrapper] whileTrue: [m := m instVarNamed: 'originalMethod'].
	originalMethod := m.
	methodNameString := aClass name asString, '>>', aSelector.
	count := 0.
	evictAt := self class defaultEvictAt.
	evicted := false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 11:42'
}
SWAMethodWrapper >> realMethod [
	"The real CompiledMethod this wrapper forwards to. originalMethod is guaranteed a
	CompiledMethod by #onClass:selector: (which peels at install), so the common path
	is: read the ivar, one #isKindOf: that is immediately false, return. The loop only
	iterates in the pathological layered case (originalMethod is itself a wrapper),
	peeling to the first non-wrapper so #withArgs:executeMethod: never gets a
	non-method (which crashes the VM via the primitive-188 fallback)."
	| m |
	m := originalMethod.
	[m isKindOf: SWAMethodWrapper] whileTrue: [m := m instVarNamed: 'originalMethod'].
	^ m
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 11:42'
}
SWAMethodWrapper >> run: aSelector with: anArray in: aReceiver [
	"THE shared template every wrapper runs. Every wrapped method dispatches here.

	CONTEXT-ORIENTED GUARD (SWACapturingLayer): capturing is a process-specific LAYER.
	The instrumentation's own machinery runs inside #withoutCapturing: (COP
	`withoutLayers(Capturing)`), which deactivates the layer for its dynamic extent in
	THAT process only.

	 0. COUNT FIRST, ALWAYS: count := count + 1 (Kernel-Numbers, never wrapped).
	 1. LAYER CHECK: if capturing is SUPPRESSED in this process, just forward.
	 2. CAPTURE / EVICT (layer active) inside #withoutCapturing:.
	 3. FORWARD with the layer left as-is so coverage sees the full subtree.

	FORWARD SAFETY: #withArgs:executeMethod: REQUIRES a real CompiledMethod. If handed
	a wrapper (the layering bug -- originalMethod is another wrapper) primitive 188
	FAILS into the slow #executeMethod:forSelector:withArgs:receiver: fallback, which
	corrupts the in-flight send and blows up recursively (seen as ByteSymbol>>lookupClass,
	Message>(nil), Array>>jump -- crash to the emergency evaluator). #onClass:selector:
	now peels originalMethod to a real method at install, but we also guarantee it HERE:
	forwarding always uses #realMethod so a stale/layered wrapper can never reach the
	primitive as a method. The check is one #isKindOf: on the (already substrate) hot
	path; realMethod only loops when actually layered (normally originalMethod IS real,
	so the whileTrue never iterates)."
	count := count + 1.
	SWACapturingLayer isActive ifFalse: [
		^ aReceiver withArgs: anArray executeMethod: self realMethod].
	(evictAt notNil and: [count >= evictAt])
		ifTrue: [evicted := true. SWACapturingLayer withoutCapturing: [self uninstallNoFlush]]
		ifFalse: [SWACapturingLayer withoutCapturing: [self captureIn: aReceiver]].
	^ aReceiver withArgs: anArray executeMethod: self realMethod
]

{
	#category : #'method-impersonation',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 17:07'
}
SWAMethodWrapper >> size [
	"Forward #size to the real method (its indexable byte count)."
	^ originalMethod size
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 14:30'
}
SWAMethodWrapper >> uninstall [
	"Restore the real method. Idempotent: only restores if I am still the one
	installed (so double-uninstall, or uninstall after someone recompiled, is safe)."
	(theClass methodDictionary at: selector ifAbsent: [nil]) == self
		ifTrue: [theClass methodDictionary at: selector put: originalMethod.
			theClass flushCache]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:00'
}
SWAMethodWrapper >> uninstallNoFlush [
	"Restore the real method WITHOUT flushing the cache (idempotent). For BULK
	uninstall: do this for all wrappers, then #flushCache ONCE. See #installNoFlush."
	(theClass methodDictionary at: selector ifAbsent: [nil]) == self
		ifTrue: [theClass methodDictionary at: selector put: originalMethod]
]
