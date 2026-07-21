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
	#superclass : #SWAMethodWrapper,
	#classVars : [
		'CallTreeRoot',
		'CallTreeWatched'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:25'
}
SWATallyWrapper class >> beginCallTreeFor: aCollectionOfCompiledMethods [
	"Start capturing a flamegraph-style call tree for a tally run. Records the set of
	watched real methods (identity) so #captureIn: can pick out exactly the
	instrumented frames from a live stack, and resets the shared root node. Each
	wrapped call folds its root->leaf stack (of watched frames) into this tree,
	weighting nodes by invocation count -- the same SWASamplingTallyNode structure the
	sampling flamegraph uses, but counts instead of microseconds."
	CallTreeWatched := IdentitySet new: aCollectionOfCompiledMethods size * 2.
	aCollectionOfCompiledMethods do: [:m | CallTreeWatched add: m].
	CallTreeRoot := SWASamplingTallyNode new name: 'root'; yourself
]

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:25'
}
SWATallyWrapper class >> callTreeActive [
	"Is call-tree capture armed for this run? (Fast guard for the per-call #captureIn:.)"
	^ CallTreeRoot notNil
]

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:25'
}
SWATallyWrapper class >> callTreeRoot [
	"The shared SWASamplingTallyNode call tree accumulated during the last tally run
	(nil before #beginCallTreeFor:). Ready to hand to a flamegraph after #rollUpTotals."
	^ CallTreeRoot
]

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:25'
}
SWATallyWrapper class >> finishCallTree [
	"Roll self counts up into totals and answer the finished call tree (or nil if none
	was captured / it stayed empty). Called at collection time."
	CallTreeRoot ifNil: [^ nil].
	CallTreeRoot rollUpTotals.
	CallTreeRoot totalCount = 0 ifTrue: [^ nil].
	^ CallTreeRoot
]

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:26'
}
SWATallyWrapper class >> recordStackFrom: aContext leaf: aLeafKey [
	"Fold the current live call stack -- restricted to WATCHED (instrumented) frames --
	into the shared call tree, exactly like the sampling flamegraph folds a sampled
	stack. Walk senders from aContext up to the root collecting each frame whose real
	method is in CallTreeWatched (leaf->root order); aLeafKey is the currently-entering
	wrapped method (its real frame is not on the stack yet), appended as the deepest
	frame. Then descend the tree in root->leaf order via #childNamed: and credit one
	invocation (selfCount) to the leaf frame.

	Runs with the capturing layer suppressed (called from #captureIn:), so the
	collection sends here do not re-enter the wrappers."
	| keys ctx node |
	CallTreeRoot ifNil: [^ self].
	keys := OrderedCollection new.
	ctx := aContext.
	[ctx notNil] whileTrue: [ | m |
		m := ctx method.
		(m notNil and: [CallTreeWatched includes: m]) ifTrue: [
			keys addFirst: m methodClass name asString, '>>', m selector].
		ctx := ctx sender].
	keys addLast: aLeafKey.
	node := CallTreeRoot.
	keys do: [:k | node := node childNamed: k].
	node addSelfTime: 1
]

{
	#category : #'call tree',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:26'
}
SWATallyWrapper class >> resetCallTree [
	"Disarm call-tree capture and drop any accumulated tree (a plain counting tally
	pays no per-call stack-walk cost when disarmed -- #callTreeActive answers false)."
	CallTreeRoot := nil.
	CallTreeWatched := nil
]

{
	#category : #evaluation,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:26'
}
SWATallyWrapper >> captureIn: aReceiver [
	"Per-call hook (guard already raised, capturing layer suppressed). When call-tree
	capture is armed, fold this call's live stack of watched frames into the shared
	flamegraph tree, with THIS wrapped method as the leaf. The stack walk filters to
	watched real methods, so the wrapper's own internal frames are ignored
	automatically. When capture is disarmed this is a no-op (plain counting tally)."
	SWATallyWrapper callTreeActive ifFalse: [^ self].
	SWATallyWrapper recordStackFrom: thisContext leaf: self crossRefKey
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/26/2026 15:25'
}
SWATallyWrapper >> onClass: aClass selector: aSelector evictAt: anIntegerOrNil [
	"A tally is just a base wrapper that opts into self-eviction: base setup (which
	includes count/evict state) plus the eviction threshold. The counting and
	eviction now live entirely in SWAMethodWrapper>>run:with:in:; this class adds NO
	per-call behaviour (the default no-op #captureIn: is exactly right)."
	self onClass: aClass selector: aSelector.
	evictAt := anIntegerOrNil
]
