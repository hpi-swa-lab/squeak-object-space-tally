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
		'deepUniverse',
		'mirror'
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:20'
}
SWASpaceTally class >> defaultRoots [
	"Default labelled root groups. Each entry is label -> object. Synthetic
	Arrays are built where it makes sense so each top-level group appears as
	one expandable node rather than thousands of siblings.

	ORDER MATTERS: the BFS claims each object for its FIRST reacher, so root
	order is attribution priority. We list the SPECIFIC, interesting categories
	first (UI/app/runtime state) so they claim their own objects, and put the
	broad catch-alls (Classes, then Globals, SymbolTable, SpecialObjects,
	Resources) LATER so they only net what the specific groups did not already
	capture. Otherwise 'Classes' -- which reaches almost the whole image via
	methods/strings/symbols -- would absorb everything and the interesting
	groups would look empty.

	Groups (in claim order):
	  Display        -- the DisplayScreen
	  ActiveWorld    -- the current world (PasteUpMorph)
	  Processes      -- every Process instance
	  Processor      -- the ProcessorScheduler
	  SourceFiles    -- the change/sources file array
	  Globals        -- the Smalltalk SystemDictionary
	  SymbolTable    -- every Symbol instance
	  Classes        -- every class in the system (broad)
	  SpecialObjects -- the VM's specialObjectsArray
	  Resources      -- metaclasses with class instance variables (singletons,
	                    caches, registries, font tables; their instVars expose
	                    cached state). Last catch-all.

	Returns an OrderedCollection of Associations so iteration order is stable."

	| roots |
	roots := OrderedCollection new.
	"Specific / interesting first."
	Display ifNotNil: [roots add: 'Display' -> Display].
	ActiveWorld ifNotNil: [roots add: 'ActiveWorld' -> ActiveWorld].
	roots add: 'Processes' -> Process allInstances.
	Processor ifNotNil: [roots add: 'Processor' -> Processor].
	SourceFiles ifNotNil: [roots add: 'SourceFiles' -> SourceFiles].
	"Broad catch-alls last."
	roots add: 'Globals' -> Smalltalk.
	roots add: 'SymbolTable' -> Symbol allInstances.
	roots add: 'Classes' -> Smalltalk allClasses asArray.
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:32'
}
SWASpaceTally class >> exploreWithOtherParents [
	"Walk, compact, and open a multi-column explorer. Other-parents tracking is
	now ON by default (see #initialize), so this is just walk + compact + open;
	kept for backward compatibility / explicitness.

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
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:26'
}
SWASpaceTally class >> generateToFile: aFilePath [
	"Convenience: walk the default roots and stream a compacted (1 KB byte cutoff)
	JSON dataset to aFilePath. See #generateToFile:compact: to tune or disable the
	compact step. Answers aFilePath.

	Example:
		SWASpaceTally generateToFile: 'tally.json'."
	^ self generateToFile: aFilePath compact: 1024
]

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:26'
}
SWASpaceTally class >> generateToFile: aFilePath compact: compactThreshold [
	"Walk the default roots, optionally prune tiny nodes, and stream the resulting
	node tree to aFilePath as JSON. compactThreshold is a byte cutoff:
	  positive -> prune subtrees under that many bytes (shrinks the dataset),
	  0        -> compact marker only, full topology kept,
	  nil      -> no compaction at all (raw walked tree).
	Answers aFilePath.

	Example:
		SWASpaceTally generateToFile: 'tally.json' compact: 1024."
	| tally |
	tally := self walk.
	compactThreshold ifNotNil: [tally compact: compactThreshold].
	^ tally writeToFile: aFilePath
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
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:51'
}
SWASpaceTally class >> loadFromFile: aFilePath [
	"Load a JSON dataset written by #writeToFile: / #generateToFile: back into a
	SWASpaceTally wrapping the reconstructed node tree. The result is a static,
	non-walkable tally suitable for opening a treemap/explorer or binding to a
	Code Map -- it has no live objects, only the serialized structure and sizes.

	Example:
		(SWASpaceTally loadFromFile: 'tally.json') openTreemap."

	| tally |
	tally := self new.
	tally rootNode: (SWASpaceTallyJsonReader readFrom: aFilePath).
	tally runLabel: (FileDirectory localNameFor: aFilePath).
	^ tally
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
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:30'
}
SWASpaceTally >> captureClassNameAndSelfSizeOf: anObject [
	"Reflectively compute { className. selfSize } for anObject through the
	walker's `mirror`, so all structural access stays centralized in the walker
	(the node does no reflection of its own). Captures the values up front so
	they survive even if anObject is later mutated.

	For classes and metaclasses, className is the behavior's own name rather
	than the generic 'Metaclass'/'Class'. Uses the classInfo cache when present
	to avoid repeated metadata lookups; nil falls back to direct lookup.

	Returns an Array { className <String>. selfSize <Integer> }."

	| cls info basicSize byteSizeFixed name size |
	cls := mirror objectClass: anObject.
	name := (cls includesBehavior: Behavior)
		ifTrue: [anObject name asString]
		ifFalse: [cls name].
	(classInfo notNil and: [classInfo includesKey: cls])
		ifTrue: [
			info := classInfo at: cls.
			byteSizeFixed := info at: 7.
			byteSizeFixed
				ifNotNil: [size := byteSizeFixed]
				ifNil: [
					basicSize := mirror objectSize: anObject.
					size := (info at: 4) "isImmediate"
						ifTrue: [0]
						ifFalse: [cls byteSizeOfInstanceOfSize: basicSize]]]
		ifFalse: [
			basicSize := mirror objectSize: anObject.
			size := cls isVariable
				ifTrue: [cls byteSizeOfInstanceOfSize: basicSize]
				ifFalse: [cls byteSizeOfInstance]].
	^ { name. size }
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
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> captureUniverse [
	"Hook: snapshot the closed `deepUniverse`. Live walker uses the live heap."

	self captureDeepUniverse
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> checkWalkPreconditions [
	"Hook: raise before a walk if we cannot run. The live walker always can;
	the sim walker overrides this to require a simulator."

	^ self
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
	#'squeak_changestamp' : 'MCPServer 6/18/2026 17:09'
}
SWASpaceTally >> classInfoFor: aClass [
	"Return a cached Array describing aClass:
		#(instSize instSpec isVariable isImmediate isCompiledCodeClass instVarNames byteSizeIfFixed isWeak storeSlotIndex)
	The cache (classInfo) is built lazily and reused for the lifetime of the walk.

	storeSlotIndex (slot 9): the 1-based instVar index of a Collection's private
	backing-store Array (the `array` instVar of OrderedCollection /
	HashedCollection & subclasses), or 0 if this class is not a Collection with
	such a slot. The walker follows that slot WITHOUT the universe gate, because
	a live collection reallocates its store as it grows/shrinks, so the store
	Array at traversal time may post-date the deepUniverse snapshot."

	^ classInfo at: aClass ifAbsentPut: [
		| spec isImm isVar size instVarNames byteSizeFixed isCompiled isWeak storeIdx |
		spec := aClass instSpec.
		isImm := aClass isImmediateClass.
		isVar := aClass isVariable.
		size := aClass instSize.
		instVarNames := size > 0 ifTrue: [aClass allInstVarNames] ifFalse: [#()].
		byteSizeFixed := (isVar or: [isImm]) ifTrue: [nil] ifFalse: [aClass byteSizeOfInstance].
		isCompiled := aClass includesBehavior: CompiledCode.
		isWeak := aClass isWeak.
		storeIdx := (aClass includesBehavior: Collection)
			ifTrue: [instVarNames indexOf: 'array']
			ifFalse: [0].
		{ size. spec. isVar. isImm. isCompiled. instVarNames. byteSizeFixed. isWeak. storeIdx }]
]

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTally >> classSummary [
	"Aggregate this tally's node tree into a per-class byte summary (the data
	structure the Code Map's #spaceTally decorate dataset reads through)."

	rootNode ifNil: [^ self error: 'no tree -- walk or load first'].
	^ SWASpaceTallyClassSummary fromTree: rootNode
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
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> defaultRootsForWalk [
	"Hook: the roots to walk when none were configured."

	^ self class defaultRoots asArray
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
}
SWASpaceTally >> expandNode: aNode [
	"Visit one node: enumerate its referents and enqueue first-time ones.
	The slot label is built lazily, only when a child node is created.

	When trackOtherParents is true, second hits record aNode on the target's
	otherParents collection.

	Skips referents that are SWASpaceTally or SWASpaceTallyNode instances so
	the walker's own tree is never tallied. No depth cap is needed: the closed
	universe + seen-set make the BFS finite regardless of structure depth.

	UNIVERSE-BYPASS FOR ARRAYS. A plain Array referent (and a Collection's
	#store backing array) bypasses the closed-universe membership gate via
	#isTallyableStore:. Reason: many objects hold an Array in an instVar and
	REPLACE it on mutation rather than mutating in place -- Morph>>submorphs
	(copyWith:/copyWithout:), collection backing stores, etc. So the Array
	referenced at traversal time often post-dates the deepUniverse snapshot;
	gating it would dead-end the BFS and dump the whole subtree (e.g. every
	world submorph) into LostAndFound. Letting Arrays through stays finite: an
	out-of-universe Array is only reached when an in-universe / already-reached
	object points at it, the seen-set dedupes, and our own tree nodes are still
	excluded by the refClass guards below. All other reject rules (immediates,
	ignore-list) still apply."

	| obj |
	visitCount := visitCount + 1.
	obj := aNode object.
	obj ifNil: [^ self].

	self referentsOf: obj do: [:referent :slotKind :slotIndex |
		| refClass tallyable |
		refClass := mirror objectClass: referent.
		tallyable := (slotKind == #store or: [refClass == Array])
			ifTrue: [self isTallyableStore: referent]
			ifFalse: [self isTallyable: referent].
		(tallyable
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
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
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
					^ self finishLost: lostRoot].
				(i \\ 50000 = 0) ifTrue: [bar value: i].
				cls := mirror objectClass: obj.
				((self isTallyable: obj)
					and: [cls ~~ SWASpaceTally and: [cls ~~ SWASpaceTallyNode]]
					and: [(seen includesKey: obj) not])
						ifTrue: [
							| node |
							node := self newChildNodeFor: obj parent: lostRoot edge: nil.
							seen at: obj put: node.
							visitCount := visitCount + 1]]].

	self finishLost: lostRoot
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:45'
}
SWASpaceTally >> finishLost: lostRoot [
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
}
SWASpaceTally >> initialize [
	super initialize.
	mirror := Context newForMethod: CompiledMethod toReturnSelf. "avoid dangling references to the current context or stack"
	maxVisits := nil. "nil = unlimited; the closed universe guarantees termination. Set a value to bound a walk for testing."
	visitCount := 0.
	limitHit := nil.
	compacted := false.
	"Track other-parents by default. It's cheap per step (a list append on a
	`seen` hit, no extra traversal) and the 'who else points here' information is
	always valuable. Memory grows with sharing (~12 MB on a full image walk);
	set trackOtherParents: false to skip it."
	trackOtherParents := true
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
}
SWASpaceTally >> isTallyable: anObject [
	"Return true if anObject is a real heap object we want to record.
	Reject nil and immediates. Uses classInfo cache if available.

	Every walk snapshots a closed deepUniverse before allocating any walker
	state, so once #walk is running deepUniverse is always set and ONLY objects
	that existed at snapshot time are tallyable. This single membership set
	gates BOTH the normal walk and the deep sweep, so the walker's own
	scaffolding (allocated after the snapshot) is never tallied, and later
	filters can be applied to the universe in one place. (deepUniverse is nil
	only outside a walk, e.g. unit tests calling this directly.)

	In instances-mode (ignoreSet/ignoreClasses set), also reject:
	  - objects on the ignore list
	  - any Behavior (class or metaclass) -- so an instance's reference to
	    its class does not drag in the whole class hierarchy.
	This keeps an application's instance walk from pulling in the system."

	| cls info |
	anObject ifNil: [^ false].
	(deepUniverse notNil and: [(deepUniverse includesKey: anObject) not])
		ifTrue: [^ false].
	cls := mirror objectClass: anObject.
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
}
SWASpaceTally >> isTallyableStore: anObject [
	"Like #isTallyable: but WITHOUT the closed-universe membership gate.

	Used only for a collection's private backing store (the `array` instVar
	of OrderedCollection / SortedCollection / HashedCollection & friends).
	That Array is an implementation detail: a live collection reallocates it
	when it grows or shrinks, so the Array referenced at TRAVERSAL time is
	frequently NOT the same identity that existed when deepUniverse was
	snapshotted. Gating it through the universe would dead-end the BFS right
	at the collection, dropping every element (and the whole subtree below
	them) into LostAndFound. We therefore let the store Array through even if
	it post-dates the snapshot.

	We still apply every OTHER reject rule (immediates, ignore-list,
	instances-mode Behavior skip) so this stays safe: the bypass is narrow
	(only the universe check) and only reached for a genuine collection
	storage slot, never for arbitrary Arrays -- which protects the walk's own
	freshly-allocated scaffolding."

	| cls info |
	anObject ifNil: [^ false].
	cls := mirror objectClass: anObject.
	(classInfo notNil and: [classInfo includesKey: cls])
		ifTrue: [
			info := classInfo at: cls.
			(info at: 4) ifTrue: [^ false]]  "isImmediate"
		ifFalse: [
			cls isImmediateClass ifTrue: [^ false]].
	ignoreSet ifNotNil: [
		(ignoreSet includes: anObject) ifTrue: [^ false].
		(cls includesBehavior: Behavior) ifTrue: [^ false]].
	ignoreClasses ifNotNil: [
		(ignoreClasses includes: cls) ifTrue: [^ false]].
	^ true
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:24'
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
		referent := mirror object: ownerObject basicAt: slotIndex.
		refClass := mirror objectClass: referent.
		(refClass includesBehavior: Association) ifTrue: [
			| key keyStr |
			key := mirror object: referent instVarAt: 1. "key"
			keyStr := [key printString] ifError: ['?'].
			keyStr size > 50 ifTrue: [keyStr := (keyStr copyFrom: 1 to: 47) , '...'].
			^ '[' , slotIndex printString , '] ' , keyStr].
		^ '[' , slotIndex printString , ']'].
	slotKind == #literal ifTrue: [^ '#literals[' , slotIndex printString , ']'].
	"#instVar or #store -- look up the instVar name; mark a #store edge."
	ownerClass := mirror objectClass: ownerObject.
	info := self classInfoFor: ownerClass.
	names := info at: 6.
	^ slotKind == #store
		ifTrue: [(slotIndex <= names size ifTrue: [names at: slotIndex] ifFalse: ['array']) , ' <store>']
		ifFalse: [slotIndex <= names size
			ifTrue: [names at: slotIndex]
			ifFalse: ['instVar' , slotIndex printString]]
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:43'
}
SWASpaceTally >> limitWarning [
	"A short human-readable warning string for the title bar, or nil if the
	walk completed without hitting a limit. The only limit a walk can hit now
	is the optional maxVisits cap (the closed universe removed timeouts)."

	limitHit == #maxVisits ifTrue: [^ 'WARNING: MAX VISITS - incomplete'].
	^ nil
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> makeRootNode [
	"Hook: create and configure the synthetic root node."

	| node |
	node := SWASpaceTallyNode new.
	node setClassName: 'SWASpaceTally root' selfSize: 0 totalSize: 0.
	^ node
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:30'
}
SWASpaceTally >> newChildNodeFor: anObject parent: parentNode edge: aLabel [
	"Create a new lean node and hook it into the tree. Mark the node and (now
	that it exists) the parent's children collection as already-seen, so BFS
	skips our own tree if it reaches it via the active process's stack.

	Objects are held strongly now, so there is no per-node WeakArray to seed.

	Reflection is done HERE, by the walker, through its `mirror`: we compute the
	child's className + selfSize and hand the node finished values. The node
	itself does no reflection and holds no mirror, staying lean."

	| node nameAndSize |
	node := SWASpaceTallyNode new.
	node setParent: parentNode depth: parentNode depth + 1.
	node edgeLabel: aLabel.
	nameAndSize := self captureClassNameAndSelfSizeOf: anObject.
	node setObject: anObject className: (nameAndSize at: 1) selfSize: (nameAndSize at: 2).
	parentNode addChild: node.
	seen at: node put: self.
	seen at: parentNode children put: self.
	^ node
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> newSeenOfSize: anInteger [
	"Hook: the dedup map. The live walker dedups on object identity."

	^ IdentityDictionary new: anInteger
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWASpaceTally >> openTreemap [
	"Open a treemap morph on the node tree, using the shared SWAPane window
	chrome (Back/Browse/Show + breadcrumb + selection-path + meta-info line +
	hover overlay)."
	| treemap overlay panel window desiredExtent |
	treemap := SWASpaceTallyTreemapMorph on: rootNode.

	overlay := SWASpaceTallyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := SWAPane on: treemap.

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
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> progressLabel [
	"Hook: the caption for the walk's progress bar."

	^ 'Walking heap...'
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 10:25'
}
SWASpaceTally >> referentsOf: anObject do: aBlock [
	"Enumerate the heap-object referents of anObject, calling
		aBlock value: referent value: slotKind value: slotIndex
	for each slot. slotKind is one of #instVar / #index / #literal / #class / #store.
	slotIndex is the 1-based index (used to look up instVar names or printed
	as '[N]' / '#literals[N]'). Callers that don't need labels can simply
	ignore the kind/index args.

	Uses cached per-class metadata (#classInfoFor:) and the cached `mirror`
	reflection primitives (captured once into `ctx`).

	WEAK SLOTS ARE NOT FOLLOWED. For a weak class, the *indexed* (variable)
	part holds weak references; a weak slot does not express ownership, so
	following it would impose a misleading parent in the tree. We therefore skip
	the indexed enumeration for weak classes (their named instVars stay strong
	and ARE followed). Anything reachable only through a weak slot will be
	claimed later via a strong path, or land in LostAndFound -- which is fine.

	COLLECTION BACKING STORE (slotKind #store): a Collection's private `array`
	instVar is yielded with kind #store instead of #instVar. The walker follows
	a #store referent WITHOUT the closed-universe gate, because a live
	collection reallocates that Array when it grows/shrinks -- so the store
	referenced at traversal time often post-dates the deepUniverse snapshot.
	Gating it would dead-end the BFS at the collection and drop all its elements
	(and their subtrees) into LostAndFound.

	Special case: for a class or metaclass we ALSO follow its class pointer
	(its class), since that header field is not an instVar/index/literal slot
	and is otherwise never traversed. This is what makes metaclasses (and the
	class-instance-var state they hold -- singletons, caches, registries)
	reachable: Foo -> Foo class -> Metaclass. We restrict this to Behaviors so
	we don't add a class-pointer edge to every ordinary object.

	PROXY-SAFE: the Behavior test is `class includesBehavior: Behavior` on the
	mirror-derived class, NOT `anObject isKindOf: Behavior`. #isKindOf: sends a
	real message to anObject, which a proxy / remote-image stub may answer
	misleadingly (or fault on) -- that once sent the walk off into a remote
	image. Testing the class reflectively never touches the object."

	| ctx class info instSize spec isVar instVarNames isCompiled basicSize isWeak storeIdx |
	ctx := mirror.
	class := ctx objectClass: anObject.

	"Follow the class pointer for classes/metaclasses only (proxy-safe test)."
	(class includesBehavior: Behavior) ifTrue: [
		aBlock value: class value: #class value: 0].

	info := self classInfoFor: class.
	instSize := info at: 1.
	spec := info at: 2.
	isVar := info at: 3.
	isCompiled := info at: 5.
	isWeak := info at: 8.
	storeIdx := info at: 9.

	isCompiled ifTrue: [
		| i |
		i := 0.
		anObject literalsDo: [:lit |
			i := i + 1.
			aBlock value: lit value: #literal value: i].
		^ self].
	"Indexed slots: skipped for weak classes (the weak part)."
	(isWeak not and: [spec between: 2 and: 4]) ifTrue: [
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
				value: (i = storeIdx ifTrue: [#store] ifFalse: [#instVar])
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
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> seedRoots [
	"Hook: enqueue the configured roots as children of rootNode. Each root is
	either a bare object or a (label -> object) Association."

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
				queue addLast: childNode]]]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:45'
}
SWASpaceTally >> seedSeenWithWalkerState [
	"Hook: allocate the live-walker's per-class metadata cache and pre-seed the
	dedup map with the walker's own infrastructure (this group, the seen/queue
	collections, classInfo, the roots array, rootNode) so the BFS never tallies
	its own scaffolding if it reaches it via the active process's stack. The sim
	walker, keyed on simulated oops, has no host scaffolding to hide and no
	classInfo cache, so it overrides this with a no-op."

	classInfo := IdentityDictionary new: 2000.
	seen at: self put: self.
	seen at: rootNode put: self.
	seen at: seen put: self.
	seen at: queue put: self.
	seen at: classInfo put: self.
	seen at: roots put: self
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:44'
}
SWASpaceTally >> walk [
	"Template method: perform the BFS walk from the configured roots, building a
	tree of lean nodes rooted at rootNode. Records run metadata (timestamp,
	duration, visitCount, limitHit). Returns self.

	The same skeleton drives both the live-heap walk (SWASpaceTally) and the
	simulated-image walk (SWASimSpaceTally); subclasses customize the steps via
	these hooks:
	  #checkWalkPreconditions   -- raise if we can't walk (e.g. no simulator)
	  #defaultRootsForWalk      -- the roots to use when none were configured
	  #captureUniverse          -- snapshot the closed `deepUniverse`
	  #newSeenOfSize:           -- the dedup map (identity vs oop-keyed)
	  #seedSeenWithWalkerState  -- register our own scaffolding as already-seen
	  #makeRootNode             -- create + configure the synthetic root node
	  #seedRoots                -- enqueue the configured roots
	  #expandNode:              -- visit one node, enqueue its referents
	  #progressLabel            -- the progress-bar caption
	  #findLostObjects          -- the deep sweep (when findDeep)

	TERMINATION: every walk snapshots a closed `deepUniverse` of the heap BEFORE
	allocating any walker state, and #isTallyable: only admits objects in that
	universe. The universe is finite and the dedup map claims each object once,
	so the BFS always terminates. If the snapshot can't be taken (low memory),
	#captureUniverse raises and the walk aborts -- we never run without the
	closed-universe guarantee.

	maxVisits is OPTIONAL: nil means unlimited (the normal case, relying on the
	closed universe). A positive integer deliberately bounds the walk (testing /
	quick partial walks); a bounded walk that stops early records
	limitHit := #maxVisits and (when findDeep) skips the sweep, since
	reachability is then unknown.

	CRITICAL: the universe is snapshotted at the very top, BEFORE we allocate
	seen/queue/rootNode or any tree node, so it contains only objects that
	pre-existed the walk -- none of the walker's own scaffolding can ever be
	mistaken for a 'lost' object or be re-tallied."

	| progressStep nextProgress startMs universeSize |
	self checkWalkPreconditions.
	roots ifNil: [roots := self defaultRootsForWalk].
	findDeepSkipped := false.

	"Snapshot the closed universe first, before allocating anything."
	self captureUniverse.
	universeSize := deepUniverse size.

	startMs := Time millisecondClockValue.
	startedAt := DateAndTime now.
	"reached objects are a subset of the universe, so universeSize is the exact
	upper bound for the dedup map -- size it exactly, no rehashing, no cap."
	seen := self newSeenOfSize: universeSize.
	queue := OrderedCollection new.
	visitCount := 0.
	limitHit := nil.
	compacted := false.

	rootNode := self makeRootNode.
	self seedSeenWithWalkerState.
	self seedRoots.

	progressStep := (universeSize // 200) max: 1000.
	nextProgress := progressStep.
	self progressLabel displayProgressFrom: 0 to: universeSize during: [:bar |
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

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:26'
}
SWASpaceTally >> writeToFile: aFilePath [
	"Stream this tally's node tree to aFilePath as JSON (single pass, node ids +
	otherParents id-refs). Serialize whatever tree you have built -- call #compact:
	first if you want a pruned dataset. Answers aFilePath.

	Example:
		(SWASpaceTally walk compact: 1024) writeToFile: 'tally.json'."
	rootNode ifNil: [^ self error: 'no tree to write -- walk first'].
	^ SWASpaceTallyJsonWriter writeTree: rootNode to: aFilePath
]
