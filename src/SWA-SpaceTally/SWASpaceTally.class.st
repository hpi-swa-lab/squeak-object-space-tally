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
		'maxDepth',
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
		'paramsSnapshot'
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:50'
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
	  Resources      -- metaclasses that have class instance variables
	                    (singletons, caches, registries, font tables, etc.
	                    The BFS walks their instVars, exposing cached state.)
	
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:12'
}
SWASpaceTally >> captureParamsSnapshot [
	"Record the walk parameters used for this run, for display/diagnostics."

	paramsSnapshot := Dictionary new.
	paramsSnapshot at: #maxDepth put: maxDepth.
	paramsSnapshot at: #maxVisits put: maxVisits.
	paramsSnapshot at: #trackOtherParents put: (trackOtherParents == true).
	paramsSnapshot at: #rootLabels put: (roots
		ifNil: [#()]
		ifNotNil: [roots collect: [:r | (r isKindOf: Association) ifTrue: [r key] ifFalse: [r printString]]]).
	paramsSnapshot at: #instancesMode put: (ignoreSet notNil or: [ignoreClasses notNil])
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:12'
}
SWASpaceTally >> clearWalkerState [
	"Drop the transient BFS machinery now that the tree is built. The lean
	nodes never held this state; it lives only on the group during a walk."

	seen := nil.
	queue := nil.
	classInfo := nil
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:12'
}
SWASpaceTally >> expandNode: aNode [
	"Visit one node: enumerate its referents and enqueue first-time ones.
	The slot label is built lazily, only when a child node is created.

	When trackOtherParents is true, second hits record aNode on the target's
	otherParents collection.

	Skips referents that are SWASpaceTally or SWASpaceTallyNode instances so
	the walker's own tree is never tallied."

	| obj |
	visitCount := visitCount + 1.
	aNode depth >= maxDepth ifTrue: [
		aNode markTruncated.
		^ self].
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:11'
}
SWASpaceTally >> initialize [
	super initialize.
	maxDepth := 40.
	maxVisits := 2000000.
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 17:50'
}
SWASpaceTally >> isTallyable: anObject [
	"Return true if anObject is a real heap object we want to record.
	Reject nil and immediates. Uses classInfo cache if available.
	
	In instances-mode (ignoreSet/ignoreClasses set), also reject:
	  - objects on the ignore list
	  - any Behavior (class or metaclass) -- so an instance's reference to
	    its class does not drag in the whole class hierarchy.
	This keeps an application's instance walk from pulling in the system."

	| cls info |
	anObject ifNil: [^ false].
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:26'
}
SWASpaceTally >> labelForKind: slotKind index: slotIndex ownerObject: ownerObject [
	"Build the human-readable edge label for a slot. Called only when a child
	node is actually created (lazy)."

	| ownerClass info names |
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
SWASpaceTally >> maxDepth: anInteger [
	maxDepth := anInteger
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:05'
}
SWASpaceTally >> openExplorerWindow [
	"Open a SWASpaceTallyExplorer, configure columns, return {window. treeMorph}.
	The title shows a 'DIFF' prefix for diff trees, a '[compacted]' marker when
	the tree has been compacted, and a loud WARNING when the walk stopped early
	due to a timeout or the maxVisits cap (the result is then incomplete)."

	| explorer window treeMorph colBlock parts |
	explorer := SWASpaceTallyExplorer new.
	explorer tallyRoot: self.
	window := ToolBuilder open: explorer.

	parts := OrderedCollection new.
	self isDiff ifTrue: [parts add: 'DIFF'].
	parts add: 'SWASpaceTally'.
	parts add: (self formatBytes: self totalSize).
	parts add: self visitCount asString , ' visits'.
	self compacted ifTrue: [parts add: '[compacted]'].
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
	#'squeak_changestamp' : 'MCPServer 6/9/2026 16:54'
}
SWASpaceTally >> referentsOf: anObject do: aBlock [
	"Enumerate the heap-object referents of anObject, calling
		aBlock value: referent value: slotKind value: slotIndex
	for each slot. slotKind is one of #instVar / #index / #literal.
	slotIndex is the 1-based index (used to look up instVar names or printed
	as '[N]' / '#literals[N]'). Callers that don't need labels can simply
	ignore the kind/index args.
	
	Uses cached per-class metadata (#classInfoFor:) and Context mirror primitives."

	| ctx class info instSize spec isVar instVarNames isCompiled basicSize |
	ctx := thisContext.
	class := ctx objectClass: anObject.
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTally >> visitCount [
	^ visitCount
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:36'
}
SWASpaceTally >> walk [
	"Perform the BFS walk from the configured roots, building a tree of lean
	SWASpaceTallyNode objects. Records run metadata (timestamp, duration,
	visitCount, limitHit) on this group. Returns self.

	roots may be a list of Associations (label -> object) or bare objects.

	Self-exclusion: pre-seed the seen-set with the walker's own infrastructure
	(this group, seen, queue, classInfo) and structurally reject any
	SWASpaceTally / SWASpaceTallyNode instance reached via the active process.
	Each node's children collection is seeded in #newChildNodeFor:parent:edge:
	once it actually exists (children are lazily allocated)."

	| seenCapacity progressStep nextProgress startMs |
	roots ifNil: [roots := self class defaultRoots asArray].
	deadlineMs ifNil: [self deadlineMs: 10000].
	startMs := Time millisecondClockValue.
	startedAt := DateAndTime now.
	seenCapacity := maxVisits min: 4000000.
	seen := IdentityDictionary new: seenCapacity.
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

	progressStep := (maxVisits // 200) max: 1000.
	nextProgress := progressStep.
	'Walking heap...' displayProgressFrom: 0 to: maxVisits during: [:bar |
		[queue notEmpty
			and: [visitCount < maxVisits
			and: [self deadlineReached not]]] whileTrue: [
				self expandNode: queue removeFirst.
				visitCount >= nextProgress ifTrue: [
					bar value: visitCount.
					nextProgress := nextProgress + progressStep]]].

	queue notEmpty ifTrue: [
		limitHit := self deadlineReached
			ifTrue: [#timeout]
			ifFalse: [#maxVisits]].

	queue do: [:n | n markTruncated].
	rootNode rollUp.
	durationMs := Time millisecondClockValue - startMs.
	self captureParamsSnapshot.
	self clearWalkerState.
	^ self
]
