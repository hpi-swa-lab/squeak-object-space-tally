"
A single node in a SWASpaceTally tree. Kept as lean as possible: one node is
allocated per reachable object during a heap walk, so it carries only the
per-node data needed to render the tree and treemap.

Per-node state:
  objectRef         - WeakArray(1) holding the analyzed object (or nil after GC)
  className         - captured class name (survives GC and compaction)
  selfSize          - bytes of this object itself
  totalSize         - selfSize + sum of children's totalSize (rolled up)
  parent / children - tree structure
  depth             - distance from the synthetic root
  truncated         - true if the walk stopped expanding here (depth/limit)
  edgeLabel         - how we reached this node from parent (instVar/slot/literal)
  pruned, prunedChildCount, prunedChildBytes - compaction pruning bookkeeping
  otherParents      - extra referrers (when trackOtherParents is on)
  isNew             - diff marker: true=new, false=context, nil=not a diff node

Walk machinery (seen/queue/classInfo) and run metadata (timestamp, params,
duration, limits) live on the owning SWASpaceTally group, NOT here.
"
Class {
	#name : #SWASpaceTallyNode,
	#superclass : #Object,
	#instVars : [
		'obj',
		'className',
		'selfSize',
		'totalSize',
		'parent',
		'children',
		'depth',
		'truncated',
		'edgeLabel',
		'pruned',
		'prunedChildCount',
		'prunedChildBytes',
		'otherParents',
		'isNew'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyNode class >> bucketize: aCollectionOfWrappers model: aModel [
	"UI-only grouping. Given an ordered collection of explorer wrappers (already
	sorted), return either the same collection (if small enough) or a smaller
	collection of SWASpaceTallyBucketWrapper rows, each holding a contiguous
	slice. The bucket size is chosen so neither this level nor the next exceeds
	the threshold (size ~ sqrt(n) rounded up to the threshold), keeping the tree
	shallow. The underlying SWASpaceTallyNode tree is never touched.

	Wrappers may be real child wrappers or, on recursion, bucket wrappers; both
	answer #bucketTotalBytes so a bucket can sum its slice."

	| n threshold bucketSize buckets |
	n := aCollectionOfWrappers size.
	threshold := self explorerBucketThreshold.
	n <= threshold ifTrue: [^ aCollectionOfWrappers].

	"Slice size: at least `threshold`, and large enough that the number of
	buckets also stays within `threshold` (so two levels suffice for up to
	threshold^2 children, three for threshold^3, ...)."
	bucketSize := threshold max: (n / threshold) ceiling.

	buckets := OrderedCollection new.
	1 to: n by: bucketSize do: [:start |
		| stop slice bytes label |
		stop := (start + bucketSize - 1) min: n.
		slice := (aCollectionOfWrappers copyFrom: start to: stop) asOrderedCollection.
		bytes := slice inject: 0 into: [:sum :w | sum + w bucketTotalBytes].
		label := '[', start printString, '..', stop printString, ']'.
		buckets add: (SWASpaceTallyBucketWrapper
			withWrappers: slice name: label bytes: bytes model: aModel)].
	^ buckets
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyNode class >> explorerBucketThreshold [
	"Maximum number of rows shown directly under one expanded node before the
	explorer groups them into visual buckets. Purely a UI concern."

	^ 200
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> addChild: aNode [
	"Append aNode, lazily creating the children collection on first use.
	This is the only sanctioned way to add a child (the #children reader may
	return a shared empty Array)."

	children ifNil: [children := OrderedCollection new].
	children addLast: aNode.
	^ aNode
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> allObjects [
	"Return an IdentitySet of all live objects in this subtree."

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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:51'
}
SWASpaceTallyNode >> asBulletListString [
	"A nested-bullet (markdown) pretty-print of this subtree, for pasting into
	chat / issues. Indented two spaces per level. See #printBulletOn:depth:."

	^ String streamContents: [:s | self printBulletOn: s depth: 0]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:52'
}
SWASpaceTallyNode >> asBulletListStringMaxDepth: maxLevels [
	"Like #asBulletListString but only descends maxLevels deep (nil = unlimited).
	A node whose own depth is at the limit prints its bullet but not its
	children, with a '...' marker if it has any. Keeps a clipboard copy of a huge
	tree manageable."

	^ String streamContents: [:s |
		self printBulletOn: s depth: 0 maxDepth: maxLevels]
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:37'
}
SWASpaceTallyNode >> asExplorerString [
	"The right-column value text. Tab-separated for column alignment:
	  className | total | self | children | pruned | refs | [truncated]"

	| kids |
	kids := self children.
	^ String streamContents: [:s |
		s nextPutAll: className.
		s nextPut: Character tab.
		s nextPutAll: (self formatBytes: self totalSize).
		s nextPut: Character tab.
		selfSize > 0 ifTrue: [
			s nextPutAll: (self formatBytes: selfSize)].
		s nextPut: Character tab.
		kids isEmpty ifFalse: [
			kids size printOn: s.
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:11'
}
SWASpaceTallyNode >> asJsonString [
	^ String streamContents: [:s | self printTreemapJsonOn: s]
]

{
	#category : #compacting,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 19:36'
}
SWASpaceTallyNode >> binChildrenByClass [
	"Group this node's direct children into synthetic 'bin' nodes, one per
	class, so a UI tree can expand hundreds of thousands of lost objects by
	class instead of choking on a flat sibling list. Bins are sorted by child
	count descending. Each bin is labelled with the class name and count; the
	original children become the bin's children (depth +1)."

	| originals byClass bins |
	originals := self children asArray.  "snapshot; we replace children below"
	originals isEmpty ifTrue: [^ self].
	"Group children by their className (preserving order within a class)."
	byClass := Dictionary new.
	originals do: [:child |
		(byClass at: child className ifAbsentPut: [OrderedCollection new])
			addLast: child].
	"Detach current children; bins take ownership."
	children := nil.
	bins := OrderedCollection new: byClass size.
	(byClass associations asSortedCollection: [:a :b | a value size > b value size])
		do: [:assoc |
			| bin members |
			members := assoc value.
			bin := SWASpaceTallyNode new.
			bin setParent: self depth: self depth + 1.
			bin edgeLabel: assoc key asString.
			bin setClassName: assoc key asString , ' (', members size printString, ')'
				selfSize: 0 totalSize: 0.
			members do: [:child |
				child setParent: bin depth: bin depth + 1.
				bin addChild: child].
			bins addLast: bin].
	self children: bins
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> children [
	"The child nodes. Returns an empty Array (not a fresh OrderedCollection)
	when this node is a leaf, so reads are cheap and allocation-free. Use
	#addChild: to add children; never #children add:."

	^ children ifNil: [#()]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> children: aCollection [
	"Replace the children collection (used by compaction). Stores nil for an
	empty collection so leaves stay allocation-free."

	children := (aCollection isNil or: [aCollection isEmpty])
		ifTrue: [nil]
		ifFalse: [aCollection]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> className [
	^ className
]

{
	#category : #compacting,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> compact: threshold [
	"Prune children whose totalSize < threshold (in-place, whole subtree).
	Pruned children are counted into prunedChildCount/prunedChildBytes.
	threshold = 0 prunes nothing. Walker state is not held on nodes, so there
	is nothing else to drop here."

	| stack node keep drop |
	threshold <= 0 ifTrue: [^ self].
	stack := OrderedCollection new.
	stack add: self.
	[stack notEmpty] whileTrue: [
		node := stack removeLast.
		keep := OrderedCollection new.
		drop := OrderedCollection new.
		node children do: [:c |
			c totalSize >= threshold
				ifTrue: [keep add: c]
				ifFalse: [drop add: c]].
		drop isEmpty ifFalse: [
			node markPrunedDropping: drop.
			node children: keep].
		node children do: [:c | stack add: c]].
	^ self
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> copyFilteredBy: isNewBlock [
	"Return a new node tree keeping only branches that reach a node for which
	isNewBlock is true. Context nodes get selfSize zeroed and isNew: false;
	new nodes keep selfSize and isNew: true. Subtrees matching the diff ignore
	preference (SWASpaceTally diffIgnorePatterns) are dropped entirely.

	Returns a fresh synthetic root node with rolled-up totals."

	| root patterns |
	patterns := SWASpaceTally diffIgnorePatterns.
	root := SWASpaceTallyNode new.
	root setClassName: 'DIFF root' selfSize: 0 totalSize: 0.
	root isNew: false.
	self children do: [:child |
		| copied |
		copied := child copySubtreeFilteredBy: isNewBlock depth: 1 ignoring: patterns.
		copied ifNotNil: [
			copied setParent: root depth: 1.
			root addChild: copied]].
	root rollUp.
	^ root
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> copySubtreeFilteredBy: isNewBlock depth: d ignoring: patterns [
	"Recursively copy this subtree, keeping only branches that reach a node
	satisfying isNewBlock. Returns a copy, or nil if the subtree has no new
	objects or this node matches a parent->child ignore pattern (whole subtree
	dropped). Records isNew on each copied node."

	| iAmNew keptChildren copy |
	(self isIgnoredByDiffPatterns: patterns) ifTrue: [^ nil].

	iAmNew := isNewBlock value: self.

	keptChildren := OrderedCollection new.
	self children do: [:child |
		| copied |
		copied := child copySubtreeFilteredBy: isNewBlock depth: d + 1 ignoring: patterns.
		copied ifNotNil: [keptChildren add: copied]].

	(iAmNew not and: [keptChildren isEmpty]) ifTrue: [^ nil].

	copy := SWASpaceTallyNode new.
	copy setObject: self object.
	copy setClassName: className selfSize: (iAmNew ifTrue: [selfSize] ifFalse: [0]) totalSize: 0.
	copy setParent: nil depth: d.
	copy edgeLabel: edgeLabel.
	copy setTruncated: truncated.
	copy isNew: iAmNew.

	keptChildren do: [:c |
		c setParent: copy depth: d + 1.
		copy addChild: c].

	^ copy
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> depth [
	^ depth
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> diffColor [
	"Row text color for diff trees: new objects green, old context gray.
	nil lets the explorer use the theme's normal color."

	isNew isNil ifTrue: [^ nil].
	^ isNew
		ifTrue: [Color green muchDarker]
		ifFalse: [Color gray]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> edgeLabel [
	"The label describing how we got from parent to self: an instVar name,
	an indexed-slot tag ('[42]'), or a special slot. Nil on roots."

	^ edgeLabel
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> edgeLabel: aString [
	edgeLabel := aString
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:05'
}
SWASpaceTallyNode >> explorerContents [
	"A wrapper per child, sorted by totalSize descending. When there are very
	many children, the wrappers are grouped into visual buckets (UI only -- the
	node tree is unchanged) so the explorer stays responsive."

	| sorted wrappers |
	sorted := self children asSortedCollection: [:a :b | a totalSize > b totalSize].
	wrappers := (sorted asArray collect: [:child |
		SWASpaceTallyWrapper
			withTally: child
			name: child explorerItemName
			model: self]) asOrderedCollection.
	^ SWASpaceTallyNode bucketize: wrappers model: self
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:11'
}
SWASpaceTallyNode >> explorerItemName [
	"Left-column label for a child line: 'edgeLabel: name' or just name."

	edgeLabel ifNil: [^ self name].
	^ edgeLabel , ': ' , self name
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:11'
}
SWASpaceTallyNode >> explorerItemName: ignored [
	"Compatibility no-op; the name is derived from edgeLabel/name."

	^ self explorerItemName
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> formatBytes: n [
	^ SWASpaceTally formatBytes: n
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:37'
}
SWASpaceTallyNode >> hasContentsInExplorer [
	"Show a disclosure triangle only if we have real children."

	^ self children notEmpty
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:34'
}
SWASpaceTallyNode >> initialize [
	"Note: children is left nil until the first addChild: -- 3 of 4 nodes are
	leaves in a typical walk, so we avoid allocating an OrderedCollection for
	them. Read access goes through #children, which returns #() when nil."

	super initialize.
	depth := 0.
	truncated := false.
	pruned := false.
	prunedChildCount := 0.
	prunedChildBytes := 0.
	edgeLabel := nil
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> isIgnoredByDiffPatterns: patterns [
	"True if this node matches any ignore pattern parentToken -> childToken:
	the node matches childToken, and either parentToken is nil (any parent)
	or the direct parent matches parentToken."

	patterns isEmptyOrNil ifTrue: [^ false].
	^ patterns anySatisfy: [:p |
		(self matchesIgnoreToken: p value)
			and: [p key isNil
				or: [parent notNil and: [parent matchesIgnoreToken: p key]]]]
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> isNew [
	"In a diff tree: true if new, false if old/context, nil if not a diff."

	^ isNew
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> isNew: aBoolean [
	isNew := aBoolean
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> markPrunedDropping: droppedChildren [
	"Record that droppedChildren were pruned from this node during compaction."

	pruned := true.
	prunedChildCount := prunedChildCount + droppedChildren size.
	droppedChildren do: [:c |
		prunedChildBytes := prunedChildBytes + c totalSize]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> markTruncated [
	truncated := true
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> matchesIgnoreToken: aToken [
	"True if aToken (Symbol/String) equals this node's className or edgeLabel."

	| s |
	aToken ifNil: [^ false].
	s := aToken asString.
	^ (className notNil and: [className asString = s])
		or: [edgeLabel notNil and: [edgeLabel asString = s]]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:15'
}
SWASpaceTallyNode >> morphNodesDo: aBlock [
	"Evaluate aBlock with the topmost on-screen Morph nodes in this subtree,
	considering every on-screen morph. See morphNodesDo:select: for the
	owner-topmost semantics; here the candidate filter accepts all morphs."

	self morphNodesDo: aBlock select: [:m | true]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:15'
}
SWASpaceTallyNode >> morphNodesDo: aBlock select: aPredicate [
	"Evaluate aBlock with the topmost on-screen Morph nodes in this subtree,
	restricted to morphs for which aPredicate answers true. A morph is yielded
	only when none of its display owners is another *selected* morph found here
	(a submorph sits inside its owner's bounds, so the owner's overlay covers
	it). De-duplicates by morph identity. Non-selected morphs (e.g. the World or
	hands) are ignored entirely, so they neither get yielded nor block their
	descendants."

	| nodes morphs |
	nodes := OrderedCollection new.
	morphs := IdentitySet new.
	self morphNodesUnfilteredDo: [:n |
		((morphs includes: n object) not and: [aPredicate value: n object])
			ifTrue: [morphs add: n object. nodes addLast: n]].
	nodes do: [:n |
		(self owner: n object isUnderAnyOf: morphs)
			ifFalse: [aBlock value: n]]
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:15'
}
SWASpaceTallyNode >> morphNodesUnfilteredDo: aBlock [
	"Evaluate aBlock with every node in this subtree whose analyzed object is a
	Morph currently on screen (in a world). No owner filtering or de-duplication."

	| stack node obj |
	stack := OrderedCollection new.
	stack addLast: self.
	[stack notEmpty] whileTrue: [
		node := stack removeLast.
		obj := node object.
		((obj isKindOf: Morph) and: [obj world notNil])
			ifTrue: [aBlock value: node].
		node children do: [:c | stack addLast: c]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:35'
}
SWASpaceTallyNode >> name [
	"A short label for this node, suitable for treemap display."

	parent ifNil: [^ 'root'].  "synthetic root"
	obj ifNil: [^ className asString].  "no object captured (e.g. diff context)"
	obj isBehavior ifTrue: [^ obj name asString].
	(obj isString and: [obj size <= 40]) ifTrue: [^ className asString , ' ' , obj printString].
	^ className asString
]

{
	#category : #diff,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> nodeForObject: anObject [
	"Find the first node in this subtree whose object is identical to anObject,
	or nil. Used to map a diff selection back to the baseline node."

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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:35'
}
SWASpaceTallyNode >> object [
	"The analyzed object. Held by a strong reference, so it stays reachable
	for as long as this tally tree is held."

	^ obj
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:35'
}
SWASpaceTallyNode >> objectRef: anObject classInfo: classInfo [
	"Record anObject (strong reference) and capture class name + self-size up
	front so the info survives even if the analyzed object is later mutated.

	For classes and metaclasses, className stores the behavior's own name
	rather than the generic 'Metaclass'/'Class'.

	classInfo (an IdentityDictionary class->info-array, or nil) lets the walk
	avoid repeated metadata lookups; nil falls back to direct lookup."

	| ctx cls info basicSize byteSizeFixed |
	ctx := thisContext.
	obj := anObject.
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:01'
}
SWASpaceTallyNode >> openExplorerSelecting: aNode [
	"Open an explorer rooted at THIS node, then expand to and select aNode.
	aNode must be a descendant of self (or self itself). Node-level twin of
	SWASpaceTally>>openExplorerSelecting: -- used from the treemap overlay, which
	holds a node, not a group, so it works for both live and Sim nodes."

	| pair window treeMorph chain pathItems n |
	pair := self openExplorerWindow.
	window := pair first.
	treeMorph := pair second.
	treeMorph ifNil: [^ window].

	"Build the chain from self's child down to aNode."
	chain := OrderedCollection new.
	n := aNode.
	[n notNil and: [n ~~ self]] whileTrue: [
		chain addFirst: n.
		n := n parent].

	"Path items matching what the tree widget stores: the root item is
	 'root' -> self; each child is explorerItemName -> (object ifNil: [node])."
	pathItems := OrderedCollection new.
	pathItems add: 'root' -> self.
	chain do: [:node |
		pathItems add: (node explorerItemName -> (node object ifNil: [node]))].

	pathItems size > 1 ifTrue: [
		WorldState addDeferredUIMessage: [
			treeMorph selectPath: pathItems asArray]].

	^ window
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:01'
}
SWASpaceTallyNode >> openExplorerWindow [
	"Open a SWASpaceTallyExplorer rooted at THIS node (used when we only have a
	node, e.g. from the treemap overlay, with no owning SWASpaceTally group).
	Returns { window. treeMorph }. Configures the same columns the group's
	#openExplorerWindow does."

	| explorer window treeMorph colBlock |
	explorer := SWASpaceTallyExplorer new.
	explorer tallyRoot: self.
	window := ToolBuilder open: explorer.
	window setLabel: 'SWASpaceTally  ', (self formatBytes: self totalSize).

	treeMorph := window allMorphs
		detect: [:m | m isKindOf: PluggableTreeMorph]
		ifNone: [nil].
	treeMorph ifNotNil: [
		colBlock := [:col | [:listMorph |
			(listMorph filteredItems collect: [:item |
				item preferredWidthOfColumn: col]) max]].
		treeMorph columns: {
			colBlock value: 1.
			colBlock value: 2.
			colBlock value: 3.
			colBlock value: 4.
			colBlock value: 5.
			colBlock value: 6.
			colBlock value: 7.
			nil }].
	^ { window. treeMorph }
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> otherParents [
	^ otherParents
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:15'
}
SWASpaceTallyNode >> owner: aMorph isUnderAnyOf: aMorphSet [
	"True when one of aMorph's display owners is a member of aMorphSet (i.e.
	aMorph is nested inside another discovered morph)."

	| owner |
	owner := aMorph owner.
	[owner notNil] whileTrue: [
		(aMorphSet includes: owner) ifTrue: [^ true].
		owner := owner owner].
	^ false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> path [
	"An Array of path segment Strings from the synthetic root to self."

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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> pathSegment [
	"One step of the path: 'edgeLabel (nodeName)' if both, else whichever."

	| nm |
	nm := self name.
	edgeLabel ifNil: [^ nm].
	^ edgeLabel , ' (' , nm , ')'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> pathString [
	^ self path inject: '' into: [:acc :seg |
		acc isEmpty ifTrue: [seg] ifFalse: [acc , ' / ' , seg]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:52'
}
SWASpaceTallyNode >> printBulletOn: aStream depth: anInteger [
	"Write one '- ' bullet for this node at the given depth (2 spaces per level),
	then recurse into children sorted by totalSize descending. Each line shows
	the edge label (if any), the node name, total size, self size, child count,
	other-parent count and a [truncated] marker -- enough to share a tree shape
	for debugging."

	aStream next: anInteger * 2 put: $ .
	aStream nextPutAll: '- '.
	edgeLabel ifNotNil: [aStream nextPutAll: edgeLabel; nextPutAll: ': '].
	aStream nextPutAll: self name.
	aStream nextPutAll: '  ('.
	aStream nextPutAll: (self formatBytes: self totalSize).
	selfSize > 0 ifTrue: [
		aStream nextPutAll: ', self '; nextPutAll: (self formatBytes: selfSize)].
	self children isEmpty ifFalse: [
		aStream nextPutAll: ', '; print: self children size; nextPutAll: ' children'].
	otherParents ifNotNil: [:op |
		op isEmpty ifFalse: [
			aStream nextPutAll: ', '; print: op size; nextPutAll: ' other-parents']].
	truncated ifTrue: [aStream nextPutAll: ', truncated'].
	aStream nextPutAll: ')'.
	aStream nextPut: Character lf.
	(self children asSortedCollection: [:a :b | a totalSize > b totalSize])
		do: [:child | child printBulletOn: aStream depth: anInteger + 1]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:52'
}
SWASpaceTallyNode >> printBulletOn: aStream depth: anInteger maxDepth: maxLevels [
	"Depth-limited bullet print. maxLevels nil = unlimited. When the limit is
	reached, print this node's bullet and, if it has children, a single
	'...(N children)' line instead of recursing."

	aStream next: anInteger * 2 put: $ .
	aStream nextPutAll: '- '.
	edgeLabel ifNotNil: [aStream nextPutAll: edgeLabel; nextPutAll: ': '].
	aStream nextPutAll: self name.
	aStream nextPutAll: '  ('.
	aStream nextPutAll: (self formatBytes: self totalSize).
	selfSize > 0 ifTrue: [
		aStream nextPutAll: ', self '; nextPutAll: (self formatBytes: selfSize)].
	self children isEmpty ifFalse: [
		aStream nextPutAll: ', '; print: self children size; nextPutAll: ' children'].
	otherParents ifNotNil: [:op |
		op isEmpty ifFalse: [
			aStream nextPutAll: ', '; print: op size; nextPutAll: ' other-parents']].
	truncated ifTrue: [aStream nextPutAll: ', truncated'].
	aStream nextPutAll: ')'.
	aStream nextPut: Character lf.

	(maxLevels notNil and: [anInteger + 1 >= maxLevels]) ifTrue: [
		self children isEmpty ifFalse: [
			aStream next: (anInteger + 1) * 2 put: $ .
			aStream nextPutAll: '- ...('; print: self children size; nextPutAll: ' children)'.
			aStream nextPut: Character lf].
		^ self].

	(self children asSortedCollection: [:a :b | a totalSize > b totalSize])
		do: [:child | child printBulletOn: aStream depth: anInteger + 1 maxDepth: maxLevels]
]

{
	#category : #output,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:11'
}
SWASpaceTallyNode >> printJsonString: aString on: aStream [
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:37'
}
SWASpaceTallyNode >> printOn: aStream [
	aStream
		nextPutAll: 'SWASpaceTallyNode(';
		nextPutAll: self name;
		nextPutAll: ' self=';
		print: selfSize;
		nextPutAll: ' total=';
		print: self totalSize;
		nextPutAll: ' kids=';
		print: self children size.
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:37'
}
SWASpaceTallyNode >> printTreemapJsonOn: aStream [
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
	self children doWithIndex: [:c :i |
		i > 1 ifTrue: [aStream nextPut: $,].
		c printTreemapJsonOn: aStream].
	aStream nextPutAll: ']}'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> pruned [
	^ pruned
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> prunedChildBytes [
	^ prunedChildBytes
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> prunedChildCount [
	^ prunedChildCount
]

{
	#category : #walking,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> rollUp [
	"Post-order: totalSize := selfSize + sum of children's totalSize.
	Iterative to avoid blowing the call stack on deep trees."

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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> selfSize [
	^ selfSize
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> setClassName: aName selfSize: aSelfSize totalSize: aTotalSize [
	className := aName.
	selfSize := aSelfSize.
	totalSize := aTotalSize
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:35'
}
SWASpaceTallyNode >> setObject: anObject [
	"Set the analyzed object reference directly (used by diff subtree copying)."

	obj := anObject
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:10'
}
SWASpaceTallyNode >> setOtherParents: aCollection [
	otherParents := aCollection
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> setParent: parentNode depth: anInteger [
	parent := parentNode.
	depth := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> setTotalSize: anInteger [
	totalSize := anInteger
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> setTruncated: aBoolean [
	truncated := aBoolean
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> totalSize [
	^ totalSize
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:09'
}
SWASpaceTallyNode >> truncated [
	^ truncated
]
