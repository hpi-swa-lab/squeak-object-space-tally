"
SWASpaceTally builds a tree of memory usage suitable for treemap visualization.

It walks the object graph breadth-first from a labelled set of roots, charging each object to its first-reached parent (BFS-order-dependent). Each node records its own size (computed from class metadata + basicSize) and, after the walk, a rolled-up total of its subtree. Every non-root node also carries an edgeLabel describing the slot through which BFS reached it (instVar name, '[N]' for indexable slots, '#literals[N]' for CompiledCode literals).

Slot access goes through thisContext mirror primitives (#objectClass:, #objectSize:, #object:instVarAt:, #object:basicAt:) so we bypass class-side overrides on proxies like FutureMaker and Context. This is the same defense the standard SpaceTally references via the Mirror alias.

References to analyzed objects are strong during the walk. Call #compact afterwards to nil out the object refs (and all walker state) so the long-lived tally tree doesn't pin objects. See doc/SWASpaceTally.md for the full design rationale.

== Typical usage ==

One-liner: walk the live heap from default roots, drop walker state, open an ObjectExplorer.

	SWASpaceTally explore.

Two-phase, with explicit configuration:

	| t |
	t := SWASpaceTally new
		maxDepth: 200;
		maxVisits: 3000000;
		deadlineMs: 300000;   ""5 min budget for a full walk""
		walk;
		compact;
		yourself.

Then browse at multiple granularities without re-walking:

	t exploreCoarse: 1000000.   ""1 MB - overview, ~12 nodes""
	t exploreCoarse: 100000.    ""100 KB - ~70 nodes""
	t exploreCoarse: 10000.     ""10 KB - ~1500 nodes""
	t explore.                  ""full unpruned tree - millions of nodes""

Custom roots, e.g. analyse retention from a specific morph:

	(SWASpaceTally new
		roots: { 'myMorph' -> someMorph };
		walk;
		compact)
		exploreCoarse: 1024.

Export for an external treemap viewer:

	(t pruneBelow: 100000) asJsonString.

Inspect a specific node's provenance:

	selectedNode pathString.   ""Classes (Array) -> [14] (ClassBinding) -> ...""

== Defaults ==

	maxDepth    30        (raise to ~200 for full walks)
	maxVisits   200,000   (raise to ~3,000,000 for full walks)
	deadlineMs  10,000    (a duration, set from now)

== Default roots (see #defaultRoots) ==

	Classes      -> Smalltalk allClasses
	Processes    -> Process allInstances
	Globals      -> Smalltalk
	SymbolTable  -> Symbol allInstances
	Display, ActiveWorld, SourceFiles, Processor

Each becomes one labelled top-level subtree. First-reached-parent charging means whichever group BFS hits first claims a shared object (SymbolTable typically looks tiny because Classes enqueues most symbols first).

== Instance Variables (every node) ==

	objectRef:   <Object | nil>    the analyzed object; nilled by #compact
	className:   <Symbol>          captured at node creation
	selfSize:    <Integer>         bytes of just this object
	totalSize:   <Integer | nil>   selfSize + sum of children totalSize (filled by rollUp)
	parent:      <SWASpaceTally>   first-reached parent (nil on synthetic root)
	children:    <OrderedCollection of SWASpaceTally>
	depth:       <Integer>         BFS depth from nearest root
	truncated:   <Boolean>         true if walker stopped here on a limit
	edgeLabel:   <String | nil>    slot label from parent to self
	pruned:      <Boolean>         children were dropped by #pruneBelow:
	prunedChildCount:  <Integer>   how many children were pruned
	prunedChildBytes:  <Integer>   total bytes of pruned children

== Instance Variables (walker state, only the synthetic root uses them) ==

	seen:        <IdentityDictionary>  object -> node (also holds walker self-exclusion entries)
	queue:       <OrderedCollection>   BFS queue of nodes
	classInfo:   <IdentityDictionary>  class -> {instSize. instSpec. isVariable. isImmediate. isCompiledCodeClass. instVarNames. byteSizeIfFixed}
	roots:       <Array>               original root objects (Associations or bare)
	maxDepth:    <Integer>
	maxVisits:   <Integer>
	deadlineMs:  <Integer | nil>       millisecondClockValue at which to abort
	visitCount:  <Integer>             diagnostic
	infrastructure: unused; kept for backward compat

== See also ==

	notes/SWASpaceTally.md    full design doc + caveats
	journal/2026-06-09-swaspacetally.md   build log + lessons
"
Class {
	#name : #SWASpaceTally,
	#superclass : #Object,
	#instVars : [
		'rootNode',
		'roots',
		'maxVisits',
		'deadlineMs',
		'visitCount',
		'limitHit',
		'compacted',
		'baseTally',
		'trackOtherParents',
		'ignoreSet',
		'ignoreClasses',
		'seen',
		'queue',
		'classInfo',
		'runLabel',
		'startedAt',
		'durationMs',
		'paramsSnapshot',
		'findDeep',
		'findDeepSkipped',
		'deepUniverse'
	],
	#classVars : [
		'DiffIgnoreSet'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:32'
}
SWASpaceTally class >> addDiffIgnore: aParentToChildAssociation [
	"Add one parent->child path pattern to the diff ignore preference, e.g.
		SWASpaceTally addDiffIgnore: #NewParagraph -> #caretRect.
	No-op if an equal pattern is already present."

	| patterns |
	patterns := self diffIgnorePatterns.
	(patterns anySatisfy: [:p |
		p key = aParentToChildAssociation key
			and: [p value = aParentToChildAssociation value]])
		ifFalse: [patterns add: aParentToChildAssociation].
	^ aParentToChildAssociation
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:32'
}
SWASpaceTally class >> defaultDiffIgnorePatterns [
	"The built-in set of parent->child path patterns to ignore when diffing.
	Each pattern is an Association whose key matches the parent node and whose
	value matches the child node. A pattern symbol matches a node when it
	equals either the node's className or its edgeLabel (instVar/slot label).

	Example: #NewParagraph -> #caretRect ignores a caretRect slot reached
	directly from a NewParagraph -- editor caret noise that changes on every
	keystroke and pollutes diffs."

	^ OrderedCollection new
		add: #NewParagraph -> #caretRect;
		yourself
]

{
	#category : #'instances mode',
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally class >> defaultIgnoreClasses [
	"Classes whose instances an instances-mode walk should NOT descend into.
	These are system-structural objects (the class system, the environment)
	that an application's instances reference but don't 'own'. Extend as needed."

	| set |
	set := IdentitySet new.
	"The class/metaclass system itself."
	set add: Metaclass.
	set add: ClassDescription.
	set add: Class.
	"System dictionaries and environment."
	(Smalltalk at: #SystemDictionary ifAbsent: [nil]) ifNotNil: [:c | set add: c].
	(Smalltalk at: #Environment ifAbsent: [nil]) ifNotNil: [:c | set add: c].
	(Smalltalk at: #SystemOrganizer ifAbsent: [nil]) ifNotNil: [:c | set add: c].
	^ set
]

{
	#category : #'instances mode',
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally class >> defaultIgnoreObjects [
	"Specific objects an instances-mode walk should NOT descend into.
	These are the global anchors that would otherwise pull in the whole
	system. Extend this list as needed."

	| set |
	set := IdentitySet new.
	set add: Smalltalk.
	set add: Smalltalk globals.
	Display ifNotNil: [set add: Display].
	Processor ifNotNil: [set add: Processor].
	Sensor ifNotNil: [set add: Sensor].
	SourceFiles ifNotNil: [set add: SourceFiles].
	(Smalltalk at: #SystemOrganization ifAbsent: [nil]) ifNotNil: [:so | set add: so].
	^ set
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:36'
}
SWASpaceTally class >> defaultRoots [
	"Default labelled root groups. Each entry is label -> object. Synthetic
	Arrays are built where it makes sense so each top-level group appears as
	one expandable node rather than thousands of siblings.
	
	Groups:
	  Classes        -- every class in the system
	  Processes      -- every Process instance
	  Globals        -- the Smalltalk SystemDictionary
	  SymbolTable    -- every Symbol instance
	  Display        -- the DisplayScreen
	  ActiveWorld    -- the current world (PasteUpMorph)
	  SourceFiles    -- the change/sources file array
	  Processor      -- the ProcessorScheduler
	  SpecialObjects -- the VM's specialObjectsArray (nil/true/false, the
	                    compact-class table, selectors the VM sends, etc.)
	  Resources      -- metaclasses that have class instance variables
	                    (singletons, caches, registries, font tables, etc.
	                    The BFS walks their instVars, exposing cached state.)
	
	The more specific groups come first so they claim their objects; the
	catch-all Resources group is last and only nets what the earlier groups
	did not already capture (BFS claims each object for its first reacher).
	
	Returns an OrderedCollection of Associations so iteration order is stable."

	| roots |
	roots := OrderedCollection new.
	roots add: 'Classes' -> Smalltalk allClasses asArray.
	roots add: 'Processes' -> Process allInstances.
	roots add: 'Globals' -> Smalltalk.
	roots add: 'SymbolTable' -> Symbol allInstances.
	Display ifNotNil: [roots add: 'Display' -> Display].
	ActiveWorld ifNotNil: [roots add: 'ActiveWorld' -> ActiveWorld].
	SourceFiles ifNotNil: [roots add: 'SourceFiles' -> SourceFiles].
	Processor ifNotNil: [roots add: 'Processor' -> Processor].
	roots add: 'SpecialObjects' -> Smalltalk specialObjectsArray.
	roots add: 'Resources' -> self resourceRoots asArray.
	^ roots
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:32'
}
SWASpaceTally class >> diffIgnorePatterns [
	"The current preference: a collection of parent->child path-pattern
	Associations ignored when diffing. Persists in the image (class variable).
	Initialised from #defaultDiffIgnorePatterns on first access."

	DiffIgnoreSet ifNil: [DiffIgnoreSet := self defaultDiffIgnorePatterns].
	^ DiffIgnoreSet
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:32'
}
SWASpaceTally class >> diffIgnorePatterns: aCollectionOfAssociations [
	"Set the diff ignore preference. Each element is a parent->child
	Association of Symbols/Strings. Pass an empty collection to ignore nothing."

	DiffIgnoreSet := aCollectionOfAssociations
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 13:13'
}
SWASpaceTally class >> explore [
	"Walk + compact + open a multi-column explorer on the result.
	Returns the tally root for further use.
	
	Example:
		SWASpaceTally explore.
		(SWASpaceTally explore) pruneBelow: 100000; openExplorer."

	| t |
	t := self walk compact.
	t openExplorer.
	^ t
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:37'
}
SWASpaceTally class >> exploreDeep [
	"walkDeep + open an explorer (no compaction, so the LostAndFound subtree
	keeps full detail). Returns the tally."

	| t |
	t := self walkDeep.
	t openExplorer.
	^ t
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:58'
}
SWASpaceTally class >> exploreDiffFrom: baseTally [
	"Walk the heap again, diff against baseTally, compact, and explore.
	
	Usage:
		base := SWASpaceTally walk compact.
		'... open your app, do things ...'
		SWASpaceTally exploreDiffFrom: base.
	
	Returns the diff tally root."

	| after diff |
	after := self walk compact.
	diff := after diffFrom: baseTally.
	diff compact.
	diff openExplorer.
	^ diff
]

{
	#category : #'instances mode',
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally class >> exploreInstancesOf: aClass [
	"Tally the instances of aClass (ignore-list active), compact, and explore."

	| t |
	t := (self tallyInstancesOf: aClass) compact: 0.
	t openExplorer.
	^ t
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 13:01'
}
SWASpaceTally class >> exploreWithOtherParents [
	"Walk with other-parents tracking, compact, and open a multi-column explorer.
	
	Example:
		SWASpaceTally exploreWithOtherParents."

	| t |
	t := self new
		trackOtherParents: true;
		walk;
		compact;
		yourself.
	t openExplorer.
	^ t
]

{
	#category : #utility,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:58'
}
SWASpaceTally class >> formatBytes: anInteger [
	"Pretty-print a byte count: 27914256 -> '27.9 MB'."

	| n |
	anInteger < 1024 ifTrue: [^ anInteger printString , ' B'].
	n := anInteger / 1024.0.
	n < 1024 ifTrue: [^ (n printShowingDecimalPlaces: 1) , ' KB'].
	n := anInteger / (1024.0 * 1024.0).
	n < 1024 ifTrue: [^ (n printShowingDecimalPlaces: 1) , ' MB'].
	n := anInteger / (1024.0 * 1024.0 * 1024.0).
	^ (n printShowingDecimalPlaces: 2) , ' GB'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:07'
}
SWASpaceTally class >> initialize [
	(TheWorldMenu respondsTo: #registerOpenCommand:)
		ifTrue: [TheWorldMenu registerOpenCommand: {'Space Tally'. {self. #open}}]
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:46'
}
SWASpaceTally class >> open [
	"Open a space tally explorer from the Apps/World menu.
	Unlike #explore, this does NOT compact the walk, so the full walker
	state (object refs, etc.) is kept around for diffing the result later."

	| t |
	t := self walk.
	t openExplorer.
	^ t
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 16:18'
}
SWASpaceTally class >> openTreemap [
	"One-liner: walk default roots, compact, open the treemap morph."

	| t |
	t := self new walk; compact; yourself.
	^ t openTreemap
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:32'
}
SWASpaceTally class >> removeDiffIgnore: aParentToChildAssociation [
	"Remove a parent->child path pattern from the diff ignore preference.
	Matches by equal key and value. No-op if not present."

	DiffIgnoreSet := self diffIgnorePatterns reject: [:p |
		p key = aParentToChildAssociation key
			and: [p value = aParentToChildAssociation value]].
	^ aParentToChildAssociation
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:50'
}
SWASpaceTally class >> resourceRoots [
	"Collect metaclasses that have their own class instance variables.
	These hold singletons, caches, registries, font tables, and other
	heavyweight state. The BFS walker will traverse their instVars,
	exposing that cached state in the tree.
	
	Only includes metaclasses where at least one own class instance
	variable is defined (not inherited), keeping the set focused."

	^ Smalltalk allClasses
		select: [:cls | cls class instVarNames notEmpty]
		thenCollect: [:cls | cls class]
]

{
	#category : #'instances mode',
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally class >> tallyInstancesOf: aClass [
	"Walk rooted at every instance of aClass, with the default ignore lists
	active so global anchors (Smalltalk, Display, the class system) are not
	followed. This isolates the memory genuinely owned by aClass's instances.
	
	Each instance becomes its own root, labelled 'anInstance[N]'.
	Returns the walked (uncompacted) tally root."

	| instances roots |
	instances := aClass allInstances.
	roots := OrderedCollection new: instances size.
	instances doWithIndex: [:inst :i |
		roots add: (aClass name , '[' , i printString , ']') -> inst].
	^ self new
		roots: roots;
		ignoreSet: self defaultIgnoreObjects;
		ignoreClasses: self defaultIgnoreClasses;
		walk;
		yourself
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally class >> walk [
	"Convenience: walk from the default roots with default limits.
	Returns a synthetic root node whose children are the per-root nodes.
	
	Example:
		(SWASpaceTally walk) asTreemapDictionary."

	^ self walkRoots: self defaultRoots
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:17'
}
SWASpaceTally class >> walkDeep [
	"Walk from the default roots, then sweep the whole heap for objects no root
	reached and bucket them under a LostAndFound node.

	maxVisits is left nil (unlimited): the closed snapshot universe guarantees
	the walk terminates and completes, so the sweep always has a meaningful
	reachability answer. Pass a maxVisits only to deliberately bound a test run.

	Example:
		SWASpaceTally walkDeep openExplorer."

	^ self new
		roots: self defaultRoots;
		findDeep: true;
		walk;
		yourself
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally class >> walkRoots: aCollection [
	"Walk from the supplied roots with default limits."

	^ self new
		roots: aCollection;
		walk;
		yourself
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:43'
}
SWASpaceTally >> allHeapObjectsForSweep [
	"The candidate object list for the LostAndFound sweep: a GC'd snapshot of
	the entire heap. Returns nil on low memory (caller skips the sweep).
	Factored out so tests can override with a small, controlled object set."

	Smalltalk garbageCollect.
	^ SystemNavigation default allObjectsOrNil
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> allObjects [
	"IdentitySet of all live objects in the tree (delegates to the root node)."

	^ rootNode ifNil: [IdentitySet new] ifNotNil: [rootNode allObjects]
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:01'
}
SWASpaceTally >> baseTally [
	"In a diff tree, the original baseline SWASpaceTally this was diffed
	against. Only the diff root carries it. nil otherwise."

	^ baseTally
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:01'
}
SWASpaceTally >> baseTally: aTally [
	baseTally := aTally
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:40'
}
SWASpaceTally >> captureDeepUniverse [
	"Snapshot the heap into `deepUniverse`, an IdentityDictionary of every
	object that existed BEFORE the walk began. Called from #walk before any
	walker state is allocated, so the universe excludes all of our own
	scaffolding by construction. The walk and sweep only ever consider / follow
	objects in this universe.

	allObjectsOrNil returns nil under low memory; without the snapshot the
	closed-universe termination guarantee is void, so we refuse to continue
	rather than fall back to a guess."

	| allObjects |
	Smalltalk garbageCollect.
	allObjects := self allHeapObjectsForSweep.
	allObjects ifNil: [
		^ self error: 'SWASpaceTally: could not snapshot the heap (allObjectsOrNil = nil, low memory). Aborting walk.'].
	"Pre-size so inserting all N entries never triggers a rehash. A HashedCollection
	grows once it is ~3/4 full, so to hold N without growing it needs capacity
	>= N / (3/4) = N * 4/3. The + 16 is headroom for very small N."
	deepUniverse := IdentityDictionary new: allObjects size * 4 // 3 + 16.
	1 to: allObjects size do: [:i | deepUniverse at: (allObjects at: i) put: nil]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:44'
}
SWASpaceTally >> captureParamsSnapshot [
	"Record the walk parameters used for this run, for display/diagnostics."

	paramsSnapshot := Dictionary new.
	paramsSnapshot at: #maxVisits put: maxVisits.
	paramsSnapshot at: #trackOtherParents put: (trackOtherParents == true).
	paramsSnapshot at: #rootLabels put: (roots
		ifNil: [#()]
		ifNotNil: [roots collect: [:r | (r isKindOf: Association) ifTrue: [r key] ifFalse: [r printString]]]).
	paramsSnapshot at: #instancesMode put: (ignoreSet notNil or: [ignoreClasses notNil]).
	paramsSnapshot at: #findDeep put: self findDeep.
	paramsSnapshot at: #findDeepSkipped put: self findDeepSkipped
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> children [
	^ rootNode ifNil: [#()] ifNotNil: [rootNode children]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 16:54'
}
SWASpaceTally >> classInfoFor: aClass [
	"Return a cached Array describing aClass:
		#(instSize instSpec isVariable isImmediate isCompiledCodeClass instVarNames byteSizeIfFixed)
	The cache (classInfo) is built lazily and reused for the lifetime of the walk."

	^ classInfo at: aClass ifAbsentPut: [
		| spec isImm isVar size instVarNames byteSizeFixed isCompiled |
		spec := aClass instSpec.
		isImm := aClass isImmediateClass.
		isVar := aClass isVariable.
		size := aClass instSize.
		instVarNames := size > 0 ifTrue: [aClass allInstVarNames] ifFalse: [#()].
		byteSizeFixed := (isVar or: [isImm]) ifTrue: [nil] ifFalse: [aClass byteSizeOfInstance].
		isCompiled := aClass includesBehavior: CompiledCode.
		{ size. spec. isVar. isImm. isCompiled. instVarNames. byteSizeFixed }]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:18'
}
SWASpaceTally >> clearWalkerState [
	"Drop the transient BFS machinery now that the tree is built. The lean
	nodes never held this state; it lives only on the group during a walk."

	seen := nil.
	queue := nil.
	classInfo := nil.
	deepUniverse := nil
]

{
	#category : #compacting,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 10:14'
}
SWASpaceTally >> compact [
	"Drop walker state, preserving full tree topology. See #compact: for pruning variant."

	^ self compact: 0
]

{
	#category : #compacting,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:12'
}
SWASpaceTally >> compact: threshold [
	"Prune the tree's children below threshold (delegated to the root node)
	and mark this group as compacted. With threshold = 0 nothing is pruned;
	the marker is still set so the UI shows [compacted]."

	compacted := true.
	rootNode ifNotNil: [rootNode compact: threshold].
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:05'
}
SWASpaceTally >> compacted [
	"True if this tree has been compacted (walker state dropped, possibly
	pruned). Object references may be gone, so the tree can't be re-walked
	or used as a fresh diff baseline as effectively. Survives on the root."

	^ compacted == true
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> deadlineMs: anInteger [
	"Wall-clock budget for the walk, in milliseconds from now."

	deadlineMs := Time millisecondClockValue + anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:00'
}
SWASpaceTally >> deadlineReached [
	^ deadlineMs notNil and: [Time millisecondClockValue >= deadlineMs]
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:14'
}
SWASpaceTally >> diffFrom: aBaseTally [
	"Produce a new diff SWASpaceTally group containing only nodes whose objects
	are NOT present in aBaseTally. New nodes are shown green, old context nodes
	gray, and the diff keeps a reference back to aBaseTally so you can jump to
	the original.

	Usage:
		base := SWASpaceTally walk.
		'... do stuff ...'
		after := SWASpaceTally walk.
		diff := after diffFrom: base.
		diff openExplorer.

	Returns the diff group."

	| diff |
	diff := self diffFromObjects: aBaseTally allObjects.
	diff baseTally: aBaseTally.
	^ diff
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:14'
}
SWASpaceTally >> diffFromObjects: baseObjects [
	"Build a new diff SWASpaceTally group whose tree keeps only branches that
	contain at least one object not in baseObjects. New nodes are isNew: true
	(green), context nodes isNew: false (gray); ignore patterns are applied.
	The filtered node tree is produced by SWASpaceTallyNode>>copyFilteredBy:."

	| diff filteredRoot |
	filteredRoot := rootNode copyFilteredBy: [:node |
		| obj |
		obj := node object.
		obj notNil and: [(baseObjects includes: obj) not]].
	diff := SWASpaceTally new.
	diff rootNode: filteredRoot.
	^ diff
]

{
	#category : #metadata,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> durationMs [
	"Wall-clock milliseconds the walk took, or nil."

	^ durationMs
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:44'
}
SWASpaceTally >> expandNode: aNode [
	"Visit one node: enumerate its referents and enqueue first-time ones.
	The slot label is built lazily, only when a child node is created.

	When trackOtherParents is true, second hits record aNode on the target's
	otherParents collection.

	Skips referents that are SWASpaceTally or SWASpaceTallyNode instances so
	the walker's own tree is never tallied. No depth cap is needed: the closed
	universe + seen-set make the BFS finite regardless of structure depth."

	| obj |
	visitCount := visitCount + 1.
	obj := aNode object.
	obj ifNil: [^ self].

	self referentsOf: obj do: [:referent :slotKind :slotIndex |
		| refClass |
		refClass := thisContext objectClass: referent.
		((self isTallyable: referent)
			and: [refClass ~~ SWASpaceTally and: [refClass ~~ SWASpaceTallyNode]])
		ifTrue: [
			| existingNode |
			existingNode := seen at: referent ifAbsent: [nil].
			existingNode
				ifNotNil: [
					(trackOtherParents == true and: [existingNode isKindOf: SWASpaceTallyNode]) ifTrue: [
						| op |
						op := existingNode otherParents.
						op ifNil: [op := OrderedCollection new: 2. existingNode setOtherParents: op].
						op addLast: aNode]]
				ifNil: [
					| child label |
					label := self
						labelForKind: slotKind
						index: slotIndex
						ownerObject: obj.
					child := self newChildNodeFor: referent parent: aNode edge: label.
					seen at: referent put: child.
					queue addLast: child]]]
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 10:15'
}
SWASpaceTally >> exploreCoarse: threshold [
	"Convenience: compact with pruning threshold, then open explorer.
	If already compacted (e.g. via compact:), the re-compact is harmless.
	Example:
		tally exploreCoarse: 100000."

	self compact: threshold.
	self openExplorer.
	^ self
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:36'
}
SWASpaceTally >> findDeep [
	^ findDeep == true
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:36'
}
SWASpaceTally >> findDeep: aBoolean [
	"When true, after the normal walk completes, sweep the whole heap for
	objects no root reached and bucket them under a synthetic LostAndFound
	node (then recurse from there). Only runs if the normal walk finished;
	an incomplete (timeout/maxVisits) walk can't tell 'unreachable' from
	'not yet visited', so the sweep is skipped and flagged."

	findDeep := aBoolean
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:37'
}
SWASpaceTally >> findDeepSkipped [
	"True when a deep sweep was requested but skipped because the normal walk
	did not complete (so reachability is unknown)."

	^ findDeepSkipped == true
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:37'
}
SWASpaceTally >> findLostObjects [
	"Deep sweep: after a *complete* walk, find every heap object no root
	reached and bucket them flat under a synthetic 'LostAndFound' node, then
	group those into fixed-size bins so the UI can expand them.

	No recursive expansion / re-parenting: every unreached universe object is a
	direct (binned) child of LostAndFound. Simple and robust.

	Closed universe: the candidate set is `deepUniverse`, snapshotted by
	#captureDeepUniverse at the very start of #walk, BEFORE any walker
	scaffolding existed -- so our own nodes/collections/dictionaries are never
	in it. An object is 'lost' iff it is in the universe and NOT already in
	`seen` (the normal walk never reached it).

	The sweep honors the optional maxVisits budget (nil = unlimited); if a
	bounded run runs out mid-sweep it stops and records limitHit."

	| lostRoot |
	lostRoot := SWASpaceTallyNode new.
	lostRoot setParent: rootNode depth: rootNode depth + 1.
	lostRoot edgeLabel: 'LostAndFound'.
	lostRoot setClassName: 'LostAndFound' selfSize: 0 totalSize: 0.
	rootNode addChild: lostRoot.
	seen at: lostRoot put: self.

	'Deep sweep: collecting lost objects...'
		displayProgressFrom: 0 to: deepUniverse size
		during: [:bar |
			| i |
			i := 0.
			deepUniverse keysDo: [:obj |
				| cls |
				i := i + 1.
				self visitBudgetRemains ifFalse: [
					limitHit isNil ifTrue: [limitHit := #maxVisits].
					^ self finishLost: lostRoot queue: #()].
				(i \\ 50000 = 0) ifTrue: [bar value: i].
				cls := thisContext objectClass: obj.
				((self isTallyable: obj)
					and: [cls ~~ SWASpaceTally and: [cls ~~ SWASpaceTallyNode]]
					and: [(seen includesKey: obj) not])
						ifTrue: [
							| node |
							node := self newChildNodeFor: obj parent: lostRoot edge: nil.
							seen at: obj put: node.
							visitCount := visitCount + 1]]].

	self finishLost: lostRoot queue: #()
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:37'
}
SWASpaceTally >> finishLost: lostRoot queue: ignored [
	"Wrap up the deep sweep: group the LostAndFound children into per-class bins
	(a flat list of 200k siblings chokes the UI tree), then recompute sizes."

	lostRoot binChildrenByClass.
	rootNode rollUp
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:58'
}
SWASpaceTally >> formatBytes: anInteger [
	"Pretty-print a byte count. Delegates to the class-side utility."

	^ self class formatBytes: anInteger
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally >> ignoreClasses: anIdentitySet [
	"Set the IdentitySet of classes whose instances the walk must not descend
	into. Only consulted when non-nil (instances-mode tallies)."
	ignoreClasses := anIdentitySet
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:41'
}
SWASpaceTally >> ignoreSet: anIdentitySet [
	"Set the IdentitySet of specific objects the walk must not descend into.
	Only consulted when non-nil (instances-mode tallies)."
	ignoreSet := anIdentitySet
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:45'
}
SWASpaceTally >> initialize [
	super initialize.
	maxVisits := nil. "nil = unlimited; the closed universe guarantees termination. Set a value to bound a walk for testing."
	deadlineMs := nil.
	visitCount := 0.
	limitHit := nil.
	compacted := false.
	trackOtherParents := false
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:14'
}
SWASpaceTally >> isDiff [
	"True if this group is a diff result (has a baseline, or its root node was
	produced by the diff filter and so carries an isNew marker)."

	^ baseTally notNil
		or: [rootNode notNil and: [rootNode isNew notNil]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:18'
}
SWASpaceTally >> isTallyable: anObject [
	"Return true if anObject is a real heap object we want to record.
	Reject nil and immediates. Uses classInfo cache if available.

	When a deepUniverse snapshot is active (findDeep), ONLY objects that
	existed at snapshot time are tallyable. This gates BOTH the normal walk
	and the deep sweep through one membership set, so the walker's own
	scaffolding (allocated after the snapshot) is never tallied, and later
	filters can be applied to the universe in one place.

	In instances-mode (ignoreSet/ignoreClasses set), also reject:
	  - objects on the ignore list
	  - any Behavior (class or metaclass) -- so an instance's reference to
	    its class does not drag in the whole class hierarchy.
	This keeps an application's instance walk from pulling in the system."

	| cls info |
	anObject ifNil: [^ false].
	(deepUniverse notNil and: [(deepUniverse includesKey: anObject) not])
		ifTrue: [^ false].
	cls := thisContext objectClass: anObject.
	(classInfo notNil and: [classInfo includesKey: cls])
		ifTrue: [
			info := classInfo at: cls.
			(info at: 4) ifTrue: [^ false]]  "isImmediate"
		ifFalse: [
			cls isImmediateClass ifTrue: [^ false]].

	"Ignore-list / instances-mode checks (only when ignoreSet is configured)."
	ignoreSet ifNotNil: [
		(ignoreSet includes: anObject) ifTrue: [^ false].
		"Don't follow classes/metaclasses in instances mode."
		(cls includesBehavior: Behavior) ifTrue: [^ false]].
	ignoreClasses ifNotNil: [
		(ignoreClasses includes: cls) ifTrue: [^ false]].

	^ true
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:52'
}
SWASpaceTally >> labelForKind: slotKind index: slotIndex ownerObject: ownerObject [
	"Build the human-readable edge label for a slot. Called only when a child
	node is actually created (lazy)."

	| ownerClass info names |
	slotKind == #class ifTrue: [^ '<class>'].
	slotKind == #index ifTrue: [
		"For indexed slots, try to show a meaningful key when the
		 referent is an Association (e.g. inside a Dictionary's array)."
		| referent refClass |
		referent := thisContext object: ownerObject basicAt: slotIndex.
		refClass := thisContext objectClass: referent.
		(refClass includesBehavior: Association) ifTrue: [
			| key keyStr |
			key := thisContext object: referent instVarAt: 1. "key"
			keyStr := [key printString] ifError: ['?'].
			keyStr size > 50 ifTrue: [keyStr := (keyStr copyFrom: 1 to: 47) , '...'].
			^ '[' , slotIndex printString , '] ' , keyStr].
		^ '[' , slotIndex printString , ']'].
	slotKind == #literal ifTrue: [^ '#literals[' , slotIndex printString , ']'].
	"slotKind == #instVar"
	ownerClass := thisContext objectClass: ownerObject.
	info := self classInfoFor: ownerClass.
	names := info at: 6.
	^ slotIndex <= names size
		ifTrue: [names at: slotIndex]
		ifFalse: ['instVar' , slotIndex printString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:04'
}
SWASpaceTally >> limitHit [
	"Why the walk stopped early, or nil if it completed fully:
	  #maxVisits - the maxVisits cap was reached
	  #timeout   - the wall-clock deadline (deadlineMs) was reached
	The result is incomplete (some objects were never visited) when non-nil.
	Survives #compact so the UI can warn about it."

	^ limitHit
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:04'
}
SWASpaceTally >> limitWarning [
	"A short human-readable warning string for the title bar, or nil if the
	walk completed without hitting a limit."

	limitHit == #timeout ifTrue: [^ 'WARNING: TIMEOUT - incomplete'].
	limitHit == #maxVisits ifTrue: [^ 'WARNING: MAX VISITS - incomplete'].
	^ nil
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> maxVisits: anInteger [
	maxVisits := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:35'
}
SWASpaceTally >> newChildNodeFor: anObject parent: parentNode edge: aLabel [
	"Create a new lean node and hook it into the tree. Mark the node and (now
	that it exists) the parent's children collection as already-seen, so BFS
	skips our own tree if it reaches it via the active process's stack.

	Objects are held strongly now, so there is no per-node WeakArray to seed."

	| node |
	node := SWASpaceTallyNode new.
	node setParent: parentNode depth: parentNode depth + 1.
	node edgeLabel: aLabel.
	node objectRef: anObject classInfo: classInfo.
	parentNode addChild: node.
	seen at: node put: self.
	seen at: parentNode children put: self.
	^ node
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> nodeForObject: anObject [
	"Find the tree node whose object is identical to anObject, or nil."

	^ rootNode ifNil: [nil] ifNotNil: [rootNode nodeForObject: anObject]
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:27'
}
SWASpaceTally >> openExplorer [
	"Open a SWASpaceTallyExplorer with multi-column tree display
	and action buttons (Treemap, Diff)."

	self openExplorerWindow.
	^ self
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> openExplorerSelecting: aNode [
	"Open an explorer on this group, then expand the tree to aNode and select
	it. aNode must be a descendant of this group's rootNode."

	| pair window treeMorph chain pathItems n |
	pair := self openExplorerWindow.
	window := pair first.
	treeMorph := pair second.
	treeMorph ifNil: [^ window].

	"Build the chain from the root node's child down to aNode."
	chain := OrderedCollection new.
	n := aNode.
	[n notNil and: [n ~~ rootNode]] whileTrue: [
		chain addFirst: n.
		n := n parent].

	"Build path items matching what the tree widget stores. The root item is
	 'root' -> rootNode (created by ObjectExplorer>>root via rootObject:).
	 Each child item is explorerItemName -> (object ifNil: [node])."
	pathItems := OrderedCollection new.
	pathItems add: 'root' -> rootNode.
	chain do: [:node |
		pathItems add: (node explorerItemName -> (node object ifNil: [node]))].

	pathItems size > 1 ifTrue: [
		WorldState addDeferredUIMessage: [
			treeMorph selectPath: pathItems asArray]].

	^ window
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:40'
}
SWASpaceTally >> openExplorerWindow [
	"Open a SWASpaceTallyExplorer, configure columns, return {window. treeMorph}.
	The title shows a 'DIFF' prefix for diff trees, a 'DEEP' marker when the
	LostAndFound sweep ran, a '[compacted]' marker when the tree has been
	compacted, and a loud WARNING when the walk stopped early due to a timeout
	or the maxVisits cap (the result is then incomplete) or when a requested
	deep sweep was skipped."

	| explorer window treeMorph colBlock parts |
	explorer := SWASpaceTallyExplorer new.
	explorer tallyRoot: self.
	window := ToolBuilder open: explorer.

	parts := OrderedCollection new.
	self isDiff ifTrue: [parts add: 'DIFF'].
	(self findDeep and: [self findDeepSkipped not]) ifTrue: [parts add: 'DEEP'].
	parts add: 'SWASpaceTally'.
	parts add: (self formatBytes: self totalSize).
	parts add: self visitCount asString , ' visits'.
	self compacted ifTrue: [parts add: '[compacted]'].
	self findDeepSkipped ifTrue: [parts add: 'WARNING: DEEP SKIPPED - walk incomplete'].
	self limitWarning ifNotNil: [:w | parts add: w].
	window setLabel: (parts inject: '' into: [:acc :p |
		acc isEmpty ifTrue: [p] ifFalse: [acc , '  ' , p]]).

	treeMorph := window allMorphs
		detect: [:m | m isKindOf: PluggableTreeMorph]
		ifNone: [nil].
	treeMorph ifNotNil: [
		colBlock := [:col | [:listMorph |
			(listMorph filteredItems collect: [:item |
				item preferredWidthOfColumn: col]) max]].
		treeMorph columns: {
			colBlock value: 1.  "name"
			colBlock value: 2.  "className"
			colBlock value: 3.  "total"
			colBlock value: 4.  "self"
			colBlock value: 5.  "children"
			colBlock value: 6.  "pruned"
			colBlock value: 7.  "refs"
			nil                 "[truncated]"
		}].
	^ { window. treeMorph }
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> openTreemap [
	"Open a treemap morph on the node tree, with breadcrumb header, selection
	path, back button, and hover overlay."

	| treemap overlay breadcrumb selectionPath panel window headerRow backButton desiredExtent |
	treemap := SWASpaceTallyTreemapMorph on: rootNode.

	backButton := SimpleButtonMorph new
		label: 'Back';
		color: (Color gray: 0.3);
		target: treemap;
		actionSelector: #zoomOut;
		yourself.

	breadcrumb := StringMorph new
		contents: treemap breadcrumbString;
		font: Preferences standardSystemFont;
		color: Color white;
		yourself.
	treemap breadcrumbMorph: breadcrumb.

	selectionPath := StringMorph new
		contents: '';
		font: Preferences standardSystemFont;
		color: (Color gray: 0.7);
		yourself.
	treemap selectionPathMorph: selectionPath.

	headerRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	backButton hResizing: #rigid.
	backButton vResizing: #rigid.
	breadcrumb hResizing: #spaceFill.
	breadcrumb vResizing: #rigid.
	headerRow addMorph: backButton.
	headerRow addMorph: breadcrumb.

	overlay := SWASpaceTallyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		yourself.
	selectionPath hResizing: #spaceFill.
	selectionPath vResizing: #rigid.
	treemap hResizing: #spaceFill.
	treemap vResizing: #spaceFill.
	panel addMorph: headerRow.
	panel addMorph: selectionPath.
	panel addMorph: treemap.

	window := panel openInWindow.
	window setLabel: (self isDiff ifTrue: ['Space Treemap  DIFF'] ifFalse: ['Space Treemap']).

	desiredExtent := (Display extent * 0.75) rounded.
	window extent: desiredExtent.
	window center: Display center.
	^ window
]

{
	#category : #metadata,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> paramsSnapshot [
	"Dictionary of the walk parameters used for this run, or nil."

	^ paramsSnapshot
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:51'
}
SWASpaceTally >> referentsOf: anObject do: aBlock [
	"Enumerate the heap-object referents of anObject, calling
		aBlock value: referent value: slotKind value: slotIndex
	for each slot. slotKind is one of #instVar / #index / #literal / #class.
	slotIndex is the 1-based index (used to look up instVar names or printed
	as '[N]' / '#literals[N]'). Callers that don't need labels can simply
	ignore the kind/index args.

	Uses cached per-class metadata (#classInfoFor:) and Context mirror primitives.

	Special case: for a class or metaclass we ALSO follow its class pointer
	(anObject class), since that header field is not an instVar/index/literal
	slot and is otherwise never traversed. This is what makes metaclasses (and
	the class-instance-var state they hold -- singletons, caches, registries)
	reachable: Foo -> Foo class -> Metaclass. We restrict this to Behaviors so
	we don't add a class-pointer edge to every ordinary object."

	| ctx class info instSize spec isVar instVarNames isCompiled basicSize |
	ctx := thisContext.
	class := ctx objectClass: anObject.

	"Follow the class pointer for classes/metaclasses only."
	(anObject isKindOf: Behavior) ifTrue: [
		aBlock value: class value: #class value: 0].

	info := self classInfoFor: class.
	instSize := info at: 1.
	spec := info at: 2.
	isVar := info at: 3.
	isCompiled := info at: 5.

	isCompiled ifTrue: [
		| i |
		i := 0.
		anObject literalsDo: [:lit |
			i := i + 1.
			aBlock value: lit value: #literal value: i].
		^ self].
	(spec between: 2 and: 4) ifTrue: [
		basicSize := ctx objectSize: anObject.
		1 to: basicSize do: [:i |
			aBlock
				value: (ctx object: anObject basicAt: i)
				value: #index
				value: i]].
	instSize > 0 ifTrue: [
		instVarNames := info at: 6.
		1 to: instSize do: [:i |
			aBlock
				value: (ctx object: anObject instVarAt: i)
				value: #instVar
				value: i]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> rootNode [
	"The synthetic root SWASpaceTallyNode of the tally tree (or nil before walk)."

	^ rootNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> rootNode: aNode [
	rootNode := aNode
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:06'
}
SWASpaceTally >> roots: aCollection [
	"Accept either:
		- a Collection of Associations (label -> rootObject), recommended, or
		- a Collection of bare root objects (label defaults to the className)."

	roots := aCollection asArray
]

{
	#category : #metadata,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> runLabel [
	"User-assignable label for this tally run, or nil."

	^ runLabel
]

{
	#category : #metadata,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> runLabel: aString [
	runLabel := aString
]

{
	#category : #metadata,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:15'
}
SWASpaceTally >> startedAt [
	"DateAndTime when this walk ran, or nil if not yet walked."

	^ startedAt
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> totalSize [
	^ rootNode ifNil: [0] ifNotNil: [rootNode totalSize]
]

{
	#category : #configuration,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:37'
}
SWASpaceTally >> trackOtherParents: aBoolean [
	"When true, the walk records alternate parents for shared objects.
	Off by default. Set before #walk."

	trackOtherParents := aBoolean
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:17'
}
SWASpaceTally >> visitBudgetRemains [
	"True if the walk may keep going. maxVisits is optional: nil means
	unlimited (rely on the closed universe to terminate). A positive maxVisits
	bounds the walk for testing / partial runs."

	maxVisits ifNil: [^ true].
	^ visitCount < maxVisits
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> visitCount [
	^ visitCount
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 10:45'
}
SWASpaceTally >> walk [
	"Perform the BFS walk from the configured roots, building a tree of lean
	SWASpaceTallyNode objects. Records run metadata (timestamp, duration,
	visitCount, limitHit) on this group. Returns self.

	roots may be a list of Associations (label -> object) or bare objects.

	TERMINATION: every walk snapshots a closed `deepUniverse` of the heap
	BEFORE allocating any walker state, and #isTallyable: only admits objects
	in that universe. The universe is finite and the `seen` set claims each
	object once, so the BFS always terminates on its own. If the snapshot can't
	be taken (low memory), #captureDeepUniverse raises and the walk aborts --
	we never run without the closed-universe guarantee.

	maxVisits is OPTIONAL: nil means unlimited (the normal case, relying on the
	closed universe). Set maxVisits to a positive integer to deliberately bound
	a walk -- handy for testing / quick partial walks. A bounded walk that stops
	early records limitHit := #maxVisits and (when findDeep) skips the sweep,
	since reachability is then unknown.

	Self-exclusion: pre-seed the seen-set with the walker's own infrastructure
	(this group, seen, queue, classInfo) and structurally reject any
	SWASpaceTally / SWASpaceTallyNode instance reached via the active process.
	Each node's children collection is seeded in #newChildNodeFor:parent:edge:
	once it actually exists (children are lazily allocated).

	When findDeep is set and the walk completed (no limit hit), a whole-heap
	sweep then buckets unreached objects under a LostAndFound node (see
	#findLostObjects).

	CRITICAL: the universe is snapshotted HERE, at the very top, BEFORE we
	allocate seen/queue/classInfo/rootNode or any tree node, so the snapshot
	contains only objects that pre-existed the walk -- none of the walker's own
	scaffolding can ever be mistaken for a 'lost' object or be re-tallied."

	| progressStep nextProgress startMs universeSize |
	roots ifNil: [roots := self class defaultRoots asArray].
	findDeepSkipped := false.

	"Snapshot the closed universe first, before allocating anything.
	Raises (aborting the walk) if the heap can't be snapshotted."
	self captureDeepUniverse.
	universeSize := deepUniverse size.

	startMs := Time millisecondClockValue.
	startedAt := DateAndTime now.
	"reached objects are a subset of the universe, so universeSize is the exact
	upper bound for `seen` -- size it exactly, no rehashing, no arbitrary cap."
	seen := IdentityDictionary new: universeSize.
	queue := OrderedCollection new.
	classInfo := IdentityDictionary new: 2000.
	visitCount := 0.
	limitHit := nil.
	compacted := false.

	rootNode := SWASpaceTallyNode new.
	rootNode setClassName: 'SWASpaceTally root' selfSize: 0 totalSize: 0.

	seen at: self put: self.
	seen at: rootNode put: self.
	seen at: seen put: self.
	seen at: queue put: self.
	seen at: classInfo put: self.
	seen at: roots put: self.

	roots do: [:each |
		| label rootObj |
		(each isKindOf: Association)
			ifTrue: [label := each key. rootObj := each value]
			ifFalse: [label := nil. rootObj := each].
		(self isTallyable: rootObj) ifTrue: [
			(seen includesKey: rootObj) ifFalse: [
				| childNode |
				childNode := self newChildNodeFor: rootObj parent: rootNode edge: label.
				seen at: rootObj put: childNode.
				queue addLast: childNode]]].

	progressStep := (universeSize // 200) max: 1000.
	nextProgress := progressStep.
	'Walking heap...' displayProgressFrom: 0 to: universeSize during: [:bar |
		[queue notEmpty and: [self visitBudgetRemains]] whileTrue: [
				self expandNode: queue removeFirst.
				visitCount >= nextProgress ifTrue: [
					bar value: visitCount.
					nextProgress := nextProgress + progressStep]]].

	queue notEmpty ifTrue: [limitHit := #maxVisits].
	queue do: [:n | n markTruncated].
	rootNode rollUp.

	self findDeep ifTrue: [
		limitHit isNil
			ifTrue: [self findLostObjects]
			ifFalse: [findDeepSkipped := true]].

	durationMs := Time millisecondClockValue - startMs.
	self captureParamsSnapshot.
	self clearWalkerState.
	^ self
]
