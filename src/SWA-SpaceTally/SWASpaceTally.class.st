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
		'objectRef',
		'className',
		'selfSize',
		'totalSize',
		'parent',
		'children',
		'depth',
		'truncated',
		'seen',
		'queue',
		'maxDepth',
		'maxVisits',
		'deadlineMs',
		'visitCount',
		'roots',
		'pruned',
		'prunedChildCount',
		'prunedChildBytes',
		'edgeLabel',
		'classInfo',
		'otherParents',
		'trackOtherParents',
		'ignoreSet',
		'ignoreClasses',
		'isNew',
		'baseTally'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:07'
}
SWASpaceTally class >> open [
	"Open a space tally explorer from the world menu."
	^ self explore
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 13:12'
}
SWASpaceTally >> allObjects [
	"Return an IdentitySet of all live objects in this tally tree.
	Traverses all nodes and collects their object references (skipping GC'd ones)."

	| result stack node obj |
	result := IdentitySet new.
	stack := OrderedCollection new.
	stack addLast: self.
	[stack notEmpty] whileTrue: [
		node := stack removeLast.
		obj := node object.
		obj ifNotNil: [result add: obj].
		node children do: [:c | stack addLast: c]].
	^ result
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 13:11'
}
SWASpaceTally >> asExplorerString [
	"The right-column value text. Tab-separated fields for column alignment:
	  className | total | self | children | pruned | refs | [truncated]"

	^ String streamContents: [:s |
		s nextPutAll: className.
		s nextPut: Character tab.
		s nextPutAll: (self formatBytes: self totalSize).
		s nextPut: Character tab.
		selfSize > 0 ifTrue: [
			s nextPutAll: (self formatBytes: selfSize)].
		s nextPut: Character tab.
		children isEmpty ifFalse: [
			children size printOn: s.
			s nextPutAll: ' children'].
		s nextPut: Character tab.
		pruned ifTrue: [
			prunedChildCount printOn: s.
			s nextPutAll: ' pruned '.
			s nextPutAll: (self formatBytes: prunedChildBytes)].
		s nextPut: Character tab.
		otherParents ifNotNil: [
			otherParents size printOn: s.
			s nextPutAll: ' refs'].
		s nextPut: Character tab.
		truncated ifTrue: [s nextPutAll: '[truncated]']]
]

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:01'
}
SWASpaceTally >> asJsonString [
	^ String streamContents: [:s | self printTreemapJsonOn: s]
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> children [
	^ children
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 10:14'
}
SWASpaceTally >> children: aCollection [
	children := aCollection
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> className [
	^ className
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:02'
}
SWASpaceTally >> clearWalkerState [
	"Nil out walker-only ivars. Called by #compact for every node.
	Root-only ivars (seen, queue, classInfo, etc.) are nil on non-root nodes
	anyway, so it's safe to nil them unconditionally.
	
	objectRef is a WeakArray and kept alive -- it doesn't pin the object
	(GC can reclaim it) and allows the explorer workspace to reach the
	real object via #object."

	seen := nil.
	queue := nil.
	roots := nil.
	classInfo := nil.
	maxDepth := nil.
	maxVisits := nil.
	deadlineMs := nil
	"Keep visitCount on the root for diagnostics; it's a SmallInteger, costs nothing.
	Keep objectRef -- it's a single-slot WeakArray, costs 24 bytes per node."
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 10:14'
}
SWASpaceTally >> compact: threshold [
	"Drop walker state (objectRefs, queue, seen-set, etc.) AND prune children
	whose totalSize < threshold, all in a single in-place pass.
	Pruned children are counted into prunedChildCount/prunedChildBytes.
	
	With threshold = 0 this behaves exactly like the old #compact.
	
	After #compact:, #object returns nil but #className, #selfSize,
	#totalSize, #depth, #truncated, #pruned still work."

	| stack node keep drop |
	stack := OrderedCollection new.
	stack add: self.
	[stack notEmpty] whileTrue: [
		node := stack removeLast.
		node clearWalkerState.
		threshold > 0 ifTrue: [
			keep := OrderedCollection new.
			drop := OrderedCollection new.
			node children do: [:c |
				c totalSize >= threshold
					ifTrue: [keep add: c]
					ifFalse: [drop add: c]].
			drop isEmpty ifFalse: [
				node markPrunedDropping: drop.
				node children: keep]].
		node children do: [:c | stack add: c]].
	^ self
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTally >> copyFilteredBy: isNewBlock [
	"Return a new tally tree keeping only branches that contain at least
	one node for which isNewBlock evaluates to true.

	Nodes on the path that are NOT new get selfSize zeroed (they're just
	structural context) and isNew: false. New nodes keep their full
	selfSize and isNew: true. Because a branch is kept only when it reaches
	a new node, every old context node is guaranteed to sit on a path that
	ends in a new object.

	The result is a proper SWASpaceTally root with rolled-up totals, flagged
	as a diff tree (isNew: false marks the synthetic root as structural)."

	| root |
	root := self class new.
	root setClassName: 'SWASpaceTally DIFF' selfSize: 0 totalSize: 0.
	root isNew: false.
	self children do: [:child |
		| copied |
		copied := child copySubtreeFilteredBy: isNewBlock depth: 1.
		copied ifNotNil: [
			copied setParent: root depth: 1.
			root children add: copied]].
	root rollUp.
	^ root
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTally >> copySubtreeFilteredBy: isNewBlock depth: d [
	"Recursively copy this subtree, keeping only branches that contain
	at least one node satisfying isNewBlock.

	Returns a copy of this node (with filtered children), or nil if
	this entire subtree contains no new objects.

	Each copied node records whether it is genuinely new (isNew: true) or
	merely structural context on the path to a new object (isNew: false).
	New nodes keep their full selfSize; context nodes get a zeroed selfSize
	so they don't inflate the byte totals."

	| iAmNew keptChildren copy |
	iAmNew := isNewBlock value: self.

	"Recurse into children first"
	keptChildren := OrderedCollection new.
	children do: [:child |
		| copied |
		copied := child copySubtreeFilteredBy: isNewBlock depth: d + 1.
		copied ifNotNil: [keptChildren add: copied]].

	"If I'm not new and no children survived, prune this branch"
	(iAmNew not and: [keptChildren isEmpty]) ifTrue: [^ nil].

	"Build a shallow copy of this node"
	copy := self class new.
	copy setObjectRef: objectRef.
	copy setClassName: className selfSize: (iAmNew ifTrue: [selfSize] ifFalse: [0]) totalSize: 0.
	copy setParent: nil depth: d.
	copy edgeLabel: edgeLabel.
	copy setTruncated: truncated.
	copy isNew: iAmNew.

	"Attach surviving children"
	keptChildren do: [:c |
		c setParent: copy depth: d + 1.
		copy children add: c].

	^ copy
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> depth [
	^ depth
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTally >> diffColor [
	"Row text color for diff trees. New objects are green, old context
	objects are grayed out. nil (the default) lets the explorer use the
	theme's normal color -- used for ordinary, non-diff tallies."

	isNew isNil ifTrue: [^ nil].
	^ isNew
		ifTrue: [Color green muchDarker]
		ifFalse: [Color gray]
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTally >> diffFrom: baseTally [
	"Produce a new SWASpaceTally tree containing only nodes whose objects
	are NOT present in baseTally. Preserves the tree structure (paths to roots)
	so you can see how new objects are reachable.

	The result is flagged as a DIFF tree: new nodes are marked isNew: true
	(shown green), old context nodes isNew: false (shown gray), and the diff
	root keeps a reference back to baseTally so you can jump to the original.

	Usage:
		base := SWASpaceTally walk compact.
		'... do stuff ...'
		after := SWASpaceTally walk compact.
		diff := after diffFrom: base.
		diff openExplorer.

	Returns a synthetic root node (like walk does)."

	| baseObjects diff |
	baseObjects := baseTally allObjects.
	diff := self diffFromObjects: baseObjects.
	diff baseTally: baseTally.
	^ diff
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 13:13'
}
SWASpaceTally >> diffFromObjects: baseObjects [
	"Build a filtered copy of this tally tree, keeping only branches
	that contain at least one object not in baseObjects.
	
	The algorithm works bottom-up:
	1. Walk the tree depth-first
	2. A leaf is 'new' if its object is not in baseObjects
	3. An interior node is kept if any descendant is new
	4. Kept nodes are shallow-copied into a new tree
	
	Nodes whose objects existed in the baseline are still shown along
	the path (as context), but their selfSize is zeroed out so they
	don't inflate the totals. Only genuinely new objects contribute bytes."

	^ self copyFilteredBy: [:node |
		| obj |
		obj := node object.
		obj notNil and: [(baseObjects includes: obj) not]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:05'
}
SWASpaceTally >> edgeLabel [
	"The label describing how we got from parent to self: an instVar name
	('array'), an indexed-slot tag ('[42]'), or a special slot ('class').
	Nil on the synthetic root and on per-root nodes."

	^ edgeLabel
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:05'
}
SWASpaceTally >> edgeLabel: aStringOrNil [
	edgeLabel := aStringOrNil
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:37'
}
SWASpaceTally >> expandNode: aNode [
	"Visit one node: enumerate its referents and enqueue first-time ones.
	The slot label is built lazily, only when we actually create a child node,
	so filtered-out slots don't allocate label strings.
	
	When trackOtherParents is true, second hits record aNode on the
	target's otherParents collection."

	| obj tallyClass |
	visitCount := visitCount + 1.
	aNode depth >= maxDepth ifTrue: [
		aNode markTruncated.
		^ self].
	obj := aNode object.
	obj ifNil: [^ self].

	tallyClass := SWASpaceTally.
	self referentsOf: obj do: [:referent :slotKind :slotIndex |
		((self isTallyable: referent)
			and: [(thisContext objectClass: referent) ~~ tallyClass])
		ifTrue: [
			| existingNode |
			existingNode := seen at: referent ifAbsent: [nil].
			existingNode
				ifNotNil: [
					trackOtherParents == true ifTrue: [
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
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTally >> explorerContents [
	"Return a wrapper per child, sorted by totalSize descending. Uses
	SWASpaceTallyWrapper so the tree navigates by tally structure while
	the workspace self binding is the real analyzed object."

	| sorted |
	sorted := children asSortedCollection: [:a :b | a totalSize > b totalSize].
	^ (sorted asArray collect: [:child |
		SWASpaceTallyWrapper
			withTally: child
			name: child explorerItemName
			model: self]) asOrderedCollection
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:07'
}
SWASpaceTally >> explorerItemName [
	"Left-column label for a child line in the ObjectExplorer.
	Format: 'edgeLabel: name' if there's an edge label, else just name."

	edgeLabel ifNil: [^ self name].
	^ edgeLabel , ': ' , self name
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
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:21'
}
SWASpaceTally >> hasContentsInExplorer [
	"Show a disclosure triangle only if we have real children. Pruning is
	communicated via the asExplorerString annotation on this node."

	^ children notEmpty
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
	#'squeak_changestamp' : 'SqueakXR 6/10/2026 10:32'
}
SWASpaceTally >> initialize [

	super initialize.
	children := OrderedCollection new.
	depth := 0.
	truncated := false.
	maxDepth := 40.
	maxVisits := 2000000.
	deadlineMs := nil.
	visitCount := 0.
	pruned := false.
	prunedChildCount := 0.
	prunedChildBytes := 0.
	edgeLabel := nil
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:01'
}
SWASpaceTally >> isDiff [
	"True if this tree is a diff result (holds a reference to a baseline tally)."

	^ baseTally notNil or: [isNew notNil]
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:01'
}
SWASpaceTally >> isNew [
	"In a diff tree: true if this node's object is new (not present in the
	baseline). false means it's an old/context node shown only because it
	lies on the path to a new object. nil means this is not a diff tree."

	^ isNew
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:01'
}
SWASpaceTally >> isNew: aBoolean [
	isNew := aBoolean
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
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:13'
}
SWASpaceTally >> markPrunedDropping: droppedChildren [
	"Record on self that some children were pruned away."

	pruned := true.
	prunedChildCount := prunedChildCount + droppedChildren size.
	droppedChildren do: [:c | prunedChildBytes := prunedChildBytes + c totalSize]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:00'
}
SWASpaceTally >> markTruncated [
	truncated := true
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:59'
}
SWASpaceTally >> name [
	"A short label for this node, suitable for treemap display."

	| obj |
	parent ifNil: [^ 'root'].  "synthetic root"
	objectRef ifNil: [^ className asString].  "post-compact: no weak ref to consult"
	obj := self object.
	obj ifNil: [^ className asString , ' (gc''d)'].
	obj isBehavior ifTrue: [^ obj name asString].
	(obj isString and: [obj size <= 40]) ifTrue: [^ className asString , ' ' , obj printString].
	^ className asString
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:59'
}
SWASpaceTally >> newChildNodeFor: anObject parent: parentNode edge: aLabel [
	"Create a new node and hook it into the tree. Also mark the node, its
	children OC, and its objectRef WeakArray as already-seen so BFS will
	skip them if it ever reaches our tree via the active process's stack."

	| node weakRef |
	node := self class new.
	node setParent: parentNode depth: parentNode depth + 1.
	node edgeLabel: aLabel.
	node objectRef: anObject.
	parentNode children add: node.
	seen at: node put: node.
	seen at: node children put: node.
	weakRef := node objectRefArray.
	weakRef ifNotNil: [seen at: weakRef put: node].
	^ node
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:03'
}
SWASpaceTally >> nodeForObject: anObject [
	"Find the first node in this tree whose analyzed object is identical to
	anObject. Returns nil if not found (or if anObject is nil). Used to map a
	selection in a diff tree back to the corresponding node in the baseline."

	| stack node |
	anObject ifNil: [^ nil].
	stack := OrderedCollection new.
	stack addLast: self.
	[stack notEmpty] whileTrue: [
		node := stack removeLast.
		node object == anObject ifTrue: [^ node].
		node children do: [:c | stack addLast: c]].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:58'
}
SWASpaceTally >> object [
	"Return the analyzed object, or nil if garbage-collected."

	objectRef ifNil: [^ nil].
	^ objectRef at: 1
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:58'
}
SWASpaceTally >> objectRef: anObject [
	"Record anObject as a weak reference. Capture class name and self-size
	up front so we still have useful info if the object is garbage-collected.
	
	For classes and metaclasses, className stores the behavior's own name
	(e.g. 'OrderedCollection' or 'MCRepositoryGroup class') rather than
	the generic 'Metaclass' or 'Class'. This gives useful labels in the
	explorer even after the object is GC'd.
	
	When called during a walk, uses the classInfo cache to avoid repeated metadata
	lookups. Falls back to direct lookup when called outside a walk (e.g. tests)."

	| ctx cls info basicSize byteSizeFixed |
	ctx := thisContext.
	objectRef := WeakArray new: 1.
	objectRef at: 1 put: anObject.
	cls := ctx objectClass: anObject.
	className := (cls includesBehavior: Behavior)
		ifTrue: [anObject name asString]
		ifFalse: [cls name].
	(classInfo notNil and: [classInfo includesKey: cls])
		ifTrue: [
			info := classInfo at: cls.
			byteSizeFixed := info at: 7.
			byteSizeFixed
				ifNotNil: [selfSize := byteSizeFixed]
				ifNil: [
					basicSize := ctx objectSize: anObject.
					selfSize := (info at: 4) "isImmediate"
						ifTrue: [0]
						ifFalse: [cls byteSizeOfInstanceOfSize: basicSize]]]
		ifFalse: [
			basicSize := ctx objectSize: anObject.
			selfSize := cls isVariable
				ifTrue: [cls byteSizeOfInstanceOfSize: basicSize]
				ifFalse: [cls byteSizeOfInstance]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:59'
}
SWASpaceTally >> objectRefArray [
	"Return the WeakArray holding the object reference, or nil if not set."

	^ objectRef
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:28'
}
SWASpaceTally >> openExplorerSelecting: aNode [
	"Open a SWASpaceTallyExplorer on self, then expand the tree
	to aNode and select it. aNode must be a descendant of self."

	| pair window treeMorph chain pathItems n |
	pair := self openExplorerWindow.
	window := pair first.
	treeMorph := pair second.
	treeMorph ifNil: [^ window].

	"Build the chain from root's child down to aNode"
	chain := OrderedCollection new.
	n := aNode.
	[n notNil and: [n ~~ self]] whileTrue: [
		chain addFirst: n.
		n := n parent].

	"Build path items matching what the tree widget stores.
	 The root item is 'root' -> self (created by ObjectExplorer>>root).
	 Each child item is explorerItemName -> (object ifNil: [tallyNode])."
	pathItems := OrderedCollection new.
	pathItems add: 'root' -> self.
	chain do: [:node |
		pathItems add: (node explorerItemName -> (node object ifNil: [node]))].

	"Defer selection to next UI cycle so the tree widget is fully built"
	pathItems size > 1 ifTrue: [
		WorldState addDeferredUIMessage: [
			treeMorph selectPath: pathItems asArray]].

	^ window
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTally >> openExplorerWindow [
	"Open a SWASpaceTallyExplorer, configure columns, return {window. treeMorph}.
	Diff trees get a 'DIFF' prefix in the window title."

	| explorer window treeMorph colBlock label |
	explorer := SWASpaceTallyExplorer new.
	explorer tallyRoot: self.
	window := ToolBuilder open: explorer.
	label := (self formatBytes: self totalSize) , '  ' , self visitCount asString , ' visits'.
	window setLabel: (self isDiff
		ifTrue: ['DIFF  SWASpaceTally  ' , label]
		ifFalse: ['SWASpaceTally  ' , label]).

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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:41'
}
SWASpaceTally >> openTreemap [
	"Open a treemap morph with breadcrumb header, selection path, back button, and hover overlay."

	| treemap overlay breadcrumb selectionPath panel window headerRow backButton desiredExtent |
	treemap := SWASpaceTallyTreemapMorph on: self.

	"Back button"
	backButton := SimpleButtonMorph new
		label: 'Back';
		color: (Color gray: 0.3);
		target: treemap;
		actionSelector: #zoomOut;
		yourself.

	"Breadcrumb label"
	breadcrumb := StringMorph new
		contents: treemap breadcrumbString;
		font: Preferences standardSystemFont;
		color: Color white;
		yourself.
	treemap breadcrumbMorph: breadcrumb.

	"Selection path label (second row)"
	selectionPath := StringMorph new
		contents: '';
		font: Preferences standardSystemFont;
		color: (Color gray: 0.7);
		yourself.
	treemap selectionPathMorph: selectionPath.

	"Header row: back button + breadcrumb"
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

	"Transparent overlay as submorph of treemap for click/selection"
	overlay := SWASpaceTallyTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	"Compose into a column panel"
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
	window setLabel: 'Space Treemap'.

	"Size to fit the display, centered"
	desiredExtent := (Display extent * 0.75) rounded.
	window extent: desiredExtent.
	window center: Display center.
	^ window
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:37'
}
SWASpaceTally >> otherParents [
	"Other tally nodes that also reference this object. nil when not tracked."

	^ otherParents
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:06'
}
SWASpaceTally >> path [
	"Return an Array describing the chain from the synthetic root to self.
	Each entry is a String. The synthetic root contributes nothing; per-root
	nodes contribute their group label (e.g. 'Classes'); inner nodes contribute
	the edge label combined with the node name, e.g. 'array (Array)'."

	| chain n |
	chain := OrderedCollection new.
	n := self.
	[n parent notNil] whileTrue: [
		chain addFirst: n pathSegment.
		n := n parent].
	^ chain asArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:06'
}
SWASpaceTally >> pathSegment [
	"One step of the path. Format: 'edgeLabel:nodeName' if both, else whichever
	is present. Examples:
		'Classes' (per-root node, no name distinction needed)
		'array (Array)' (instVar 'array' pointing to an Array)
		'[42] (Symbol)' (indexable slot 42 holding a Symbol)"

	| nm |
	nm := self name.
	edgeLabel ifNil: [^ nm].
	^ edgeLabel , ' (' , nm , ')'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:07'
}
SWASpaceTally >> pathString [
	"Human-readable path from root to self, joined with ' -> '.
	(Plain ASCII; the explorer's text widget handles non-ASCII inconsistently.)"

	^ String streamContents: [:s |
		self path doWithIndex: [:seg :i |
			i > 1 ifTrue: [s nextPutAll: ' -> '].
			s nextPutAll: seg]]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:27'
}
SWASpaceTally >> printJsonString: aString on: aStream [
	"Write aString as a JSON string literal, escaping the minimum needed."

	aStream nextPut: $".
	aString do: [:ch |
		ch = $\ ifTrue: [aStream nextPutAll: '\\']
		ifFalse: [ch = $" ifTrue: [aStream nextPutAll: '\"']
		ifFalse: [ch = Character lf ifTrue: [aStream nextPutAll: '\n']
		ifFalse: [ch = Character cr ifTrue: [aStream nextPutAll: '\r']
		ifFalse: [ch = Character tab ifTrue: [aStream nextPutAll: '\t']
		ifFalse: [ch asInteger < 32
			ifTrue: [aStream nextPutAll: '\u'.
				aStream nextPutAll: (ch asInteger printStringBase: 16 nDigits: 4)]
			ifFalse: [aStream nextPut: ch]]]]]]].
	aStream nextPut: $"
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:13'
}
SWASpaceTally >> printOn: aStream [
	aStream
		nextPutAll: 'SWASpaceTally(';
		nextPutAll: self name;
		nextPutAll: ' self=';
		print: selfSize;
		nextPutAll: ' total=';
		print: self totalSize;
		nextPutAll: ' kids=';
		print: children size.
	pruned ifTrue: [
		aStream
			nextPutAll: ' pruned=';
			print: prunedChildCount;
			nextPutAll: '/';
			print: prunedChildBytes].
	aStream nextPutAll: ')'
]

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 15:07'
}
SWASpaceTally >> printTreemapJsonOn: aStream [
	"Write a minimal JSON representation of this subtree to aStream."

	aStream nextPutAll: '{"name":'.
	self printJsonString: self name on: aStream.
	aStream nextPutAll: ',"edgeLabel":'.
	self printJsonString: (edgeLabel ifNil: ['']) on: aStream.
	aStream nextPutAll: ',"self":'.
	selfSize printOn: aStream.
	aStream nextPutAll: ',"total":'.
	self totalSize printOn: aStream.
	aStream nextPutAll: ',"depth":'.
	depth printOn: aStream.
	aStream nextPutAll: ',"truncated":'.
	aStream nextPutAll: (truncated ifTrue: ['true'] ifFalse: ['false']).
	aStream nextPutAll: ',"pruned":'.
	aStream nextPutAll: (pruned ifTrue: ['true'] ifFalse: ['false']).
	aStream nextPutAll: ',"prunedChildCount":'.
	prunedChildCount printOn: aStream.
	aStream nextPutAll: ',"prunedChildBytes":'.
	prunedChildBytes printOn: aStream.
	aStream nextPutAll: ',"children":['.
	children doWithIndex: [:c :i |
		i > 1 ifTrue: [aStream nextPut: $,].
		c printTreemapJsonOn: aStream].
	aStream nextPutAll: ']}'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:12'
}
SWASpaceTally >> pruned [
	^ pruned
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:12'
}
SWASpaceTally >> prunedChildBytes [
	^ prunedChildBytes
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:12'
}
SWASpaceTally >> prunedChildCount [
	^ prunedChildCount
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
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:00'
}
SWASpaceTally >> rollUp [
	"Post-order: totalSize := selfSize + sum of children's totalSize.
	Iterative (explicit stack) to avoid blowing the call stack on deep trees."

	| stack visited node sum |
	stack := OrderedCollection new.
	visited := IdentitySet new.
	stack addLast: self.
	[stack notEmpty] whileTrue: [
		node := stack last.
		(visited includes: node)
			ifTrue: [
				stack removeLast.
				sum := node selfSize.
				node children do: [:c | sum := sum + c totalSize].
				node setTotalSize: sum]
			ifFalse: [
				visited add: node.
				node children do: [:c | stack addLast: c]]]
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> selfSize [
	^ selfSize
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:13'
}
SWASpaceTally >> setClassName: aName selfSize: aSelfSize totalSize: aTotalSize [
	className := aName.
	selfSize := aSelfSize.
	totalSize := aTotalSize
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:58'
}
SWASpaceTally >> setObjectRef: aWeakArrayOrNil [
	"Set the weak object reference directly (used by shallowCopyForPrune)."

	objectRef := aWeakArrayOrNil
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:38'
}
SWASpaceTally >> setOtherParents: anOrderedCollection [

	otherParents := anOrderedCollection
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:00'
}
SWASpaceTally >> setParent: parentNode depth: anInteger [
	parent := parentNode.
	depth := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:00'
}
SWASpaceTally >> setTotalSize: anInteger [
	totalSize := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 14:13'
}
SWASpaceTally >> setTruncated: aBoolean [
	truncated := aBoolean
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> totalSize [
	^ totalSize ifNil: [selfSize]
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
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> truncated [
	^ truncated
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/9/2026 13:59'
}
SWASpaceTally >> visitCount [
	^ visitCount
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 10:53'
}
SWASpaceTally >> walk [
	"Perform the BFS walk from the configured roots, then roll up totals.
	Self is the synthetic root node; its children are the per-root nodes.
	Returns self.
	
	roots may be a list of Associations (label -> object) or bare objects.
	Each root gets its label recorded as its edgeLabel.
	
	Self-exclusion has two layers:
	  1. Pre-seed seen with the walker's own infrastructure (self, seen, queue,
	     roots, children OC). They're skipped if BFS reaches them via Processor.
	  2. Structural check in expandNode: rejects any SWASpaceTally instance."

	| seenCapacity progressStep nextProgress |
	roots ifNil: [roots := self class defaultRoots asArray].
	deadlineMs ifNil: [self deadlineMs: 10000].
	seenCapacity := maxVisits min: 4000000.
	seen := IdentityDictionary new: seenCapacity.
	queue := OrderedCollection new.
	classInfo := IdentityDictionary new: 2000.
	visitCount := 0.

	className := 'SWASpaceTally root'.
	selfSize := 0.

	seen at: self put: self.
	seen at: seen put: self.
	seen at: queue put: self.
	seen at: roots put: self.
	seen at: classInfo put: self.
	seen at: children put: self.

	roots do: [:each |
		| label rootObj |
		(each isKindOf: Association)
			ifTrue: [label := each key. rootObj := each value]
			ifFalse: [label := nil. rootObj := each].
		(self isTallyable: rootObj) ifTrue: [
			(seen includesKey: rootObj) ifFalse: [
				| rootNode |
				rootNode := self newChildNodeFor: rootObj parent: self edge: label.
				seen at: rootObj put: rootNode.
				queue addLast: rootNode]]].

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

	queue do: [:n | n markTruncated].
	self rollUp.
	^ self
]
