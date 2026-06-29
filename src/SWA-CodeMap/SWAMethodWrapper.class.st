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
	#classVars : [
		'InWrapper'
	],
	#category : #'SWA-CodeMap',
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
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:24'
}
SWAMethodWrapper class >> guardedDo: aBlock [
	"Evaluate aBlock with the reentrancy guard RAISED, restoring it afterwards. Use
	this to run any instrumentation-framework code -- capture hooks, the runner loop,
	the logger, recording -- so that wrapped methods it touches fall straight through
	their wrappers instead of recursing. Re-entrant safe: nested calls save/restore.

	Send-free in the common case is not required here (this is meta code), but the
	read/write of InWrapper is a class-var access, cheap."
	| was |
	was := InWrapper.
	InWrapper := true.
	^ aBlock ensure: [InWrapper := was]
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:24'
}
SWAMethodWrapper class >> isInWrapper [
	"THE general reentrancy guard, shared by ALL wrapper subclasses (one class var on
	the common superclass). True means 'control is currently inside instrumentation
	machinery' -- a wrapper's capture hook, the runner, the logger, the recording
	code. While true, EVERY wrapper's #run:with:in: must skip its capture and just
	forward, so the instrumentation can never recurse into itself (the cause of the
	unbounded context allocation on a broad run).

	This is a MECHANISM, not a semantic flag: it answers 'am I inside my own code',
	never 'should I record/count' -- those are separate per-tool flags."
	^ InWrapper == true
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:24'
}
SWAMethodWrapper class >> resetGuard [
	"Force the reentrancy guard down. Call before/after a run so a crash or stray
	raise can't leave all wrappers permanently passing through."
	InWrapper := false
]

{
	#category : #'reentrancy guard',
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:52'
}
SWAMethodWrapper class >> whileUnguardedDo: aBlock [
	"Evaluate aBlock with the reentrancy guard LOWERED (InWrapper=false) -- the
	MEASURING WINDOW -- restoring it afterwards. This is the inverse of #guardedDo:.

	The runner keeps the guard RAISED for all its own machinery (install, the loop,
	logging, uninstall) so none of that is counted/captured or recurses; it opens this
	window ONLY around the actual code under test (#testCase run). So 'unguarded' ==
	'we are in target code, capture is allowed'."
	| was |
	was := InWrapper.
	InWrapper := false.
	^ aBlock ensure: [InWrapper := was]
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
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:45'
}
SWAMethodWrapper >> onClass: aClass selector: aSelector [
	"Base initialization shared by all wrappers. Captures the class, selector, and
	the REAL method (so the forward and reflection always reach the original even
	after we replace it in the dict), precomputes the 'Class>>selector' name NOW
	(never in the hot path), and initializes the base COUNT/EVICT state.

	Eviction is ON BY DEFAULT (evictAt := self class defaultEvictAt). This is a
	SURVIVAL valve: a hot method MUST drop out or it grinds the system to a halt.
	Raise the threshold per-instance with #evictAt: if needed; pass nil only when you
	are certain the watched methods are cold."
	theClass := aClass.
	selector := aSelector.
	originalMethod := aClass >> aSelector.
	methodNameString := aClass name asString, '>>', aSelector.
	count := 0.
	evictAt := self class defaultEvictAt.
	evicted := false
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 12:59'
}
SWAMethodWrapper >> run: aSelector with: anArray in: aReceiver [
	"THE shared template every wrapper runs. SEND-FREE on the hot path until we commit
	to capturing (every wrapped method dispatches here; a per-call send or block
	allocation explodes memory and recurses).

	 1. REENTRANCY GUARD: InWrapper is a CLASS VAR read directly (bytecode, NO send).
	    Raised means 'inside our own machinery' -> just forward. The runner keeps it
	    raised for everything except the code under test (#whileUnguardedDo: around
	    #testCase run), so install/loop/log/uninstall never count, capture, or recurse.
	 2. COUNT: count := count + 1 (Kernel-Numbers substrate, never wrapped).
	 3. EVICT-AFTER-N: once past evictAt, mark evicted and restore the real method in
	    the dict (#uninstallNoFlush). CRITICAL: do NOT #flushCache here. We are CURRENTLY
	    EXECUTING inside this wrapper's own dispatch; flushing the global method cache
	    (primitive 89) mid-frame, then continuing into #withArgs:executeMethod:, can
	    corrupt the in-flight send and abort the VM with a recursive doesNotUnderstand:
	    (seen as ByteSymbol DNU on the Slider/ScrollBar #sliderColor theme path, but
	    only in long runs where a hot method actually reaches evictAt mid-test). Just
	    swapping the dict entry stops wrapping on the NEXT send; the stale cache entry
	    for THIS method is harmless (it points at this wrapper, which still forwards to
	    originalMethod) and is cleared by the run's final bulk #flushSystemCache. Also
	    do the eviction GUARDED so #uninstallNoFlush's sends never re-enter.
	 4. CAPTURE: raise the guard, call the hook, RESTORE it (it was false here, since
	    we only got past step 1 when unguarded). One block/ensure: allocation, and only
	    in the measuring window -- not on the (vast majority) guarded pass-throughs.

	Forward via inline withArgs:executeMethod: (Kernel-Objects substrate)."
	InWrapper == true ifTrue: [
		^ aReceiver withArgs: anArray executeMethod: originalMethod].
	count := count + 1.
	(evictAt notNil and: [count >= evictAt]) ifTrue: [
		evicted := true.
		InWrapper := true.
		[self uninstallNoFlush] ensure: [InWrapper := false].
		^ aReceiver withArgs: anArray executeMethod: originalMethod].
	InWrapper := true.
	[self captureIn: aReceiver] ensure: [InWrapper := false].
	^ aReceiver withArgs: anArray executeMethod: originalMethod
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
