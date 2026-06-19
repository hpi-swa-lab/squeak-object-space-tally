"
A node in a sampled call tree built from an st-spy chrome-trace recording.

Duck-typed to work in BOTH the SWA Explorer (PluggableTreeMorph via #explorerContents / #explorerItemName / #hasContentsInExplorer) and the SWA TreeMap (SWATreemapMorph, which reads #children / #totalSize / #name / #depth / #pathString / #selfSize / #otherParents).

Tree semantics: each node is a method frame (or the synthetic 'root'). #selfCount is the number of samples in which this frame was the innermost (leaf) frame; #totalCount is the rolled-up sample count over the whole subtree (this frame appeared on the stack). The treemap squarifies tiles by #totalSize (= totalCount), so hot call paths get larger tiles.

Build with: parent addChildNamed: aString -- which finds-or-creates a child. After folding all samples, send #rollUpTotals to compute totalCount bottom-up.
"
Class {
	#name : #SWAStSpyNode,
	#superclass : #Object,
	#instVars : [
		'name',
		'children',
		'parent',
		'selfCount',
		'totalCount',
		'category',
		'filename'
	],
	#category : #'SWA-StSpy',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:00'
}
SWAStSpyNode >> addSelfTime: micros [
	"Add `micros` microseconds of time during which this frame was the innermost
	(leaf) frame on the stack."
	selfCount := selfCount + micros
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWAStSpyNode >> browse [
	"Open a system browser on this frame's method, if it resolves to one. Returns
	true if a browser was opened, false for native/unresolvable frames."
	| ref |
	ref := self methodReference.
	ref ifNil: [^ false].
	ToolSet browse: ref first selector: ref second.
	^ true
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:00'
}
SWAStSpyNode >> bumpSelf [
	"Legacy single-count bump (1 sample as leaf). Prefer #addSelfTime: for
	flamechart traces that carry real durations."
	selfCount := selfCount + 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> category [
	^ category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> category: aString [
	category := aString
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> childNamed: aString [
	"Find or create the child frame with this name, allocating the children
	collection lazily."
	children ifNil: [children := OrderedCollection new].
	^ children
		detect: [:c | c name = aString]
		ifNone: [ | child |
			child := SWAStSpyNode new.
			child name: aString; parent: self.
			children add: child.
			child]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> children [
	"Child frames. Returns #() (not a fresh collection) for leaves so reads are
	cheap. Use #childNamed: to add; never #children add:."
	^ children ifNil: [#()]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> depth [
	^ parent isNil ifTrue: [0] ifFalse: [parent depth + 1]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> edgeLabel [
	^ nil
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> explorerContents [
	"Child frames sorted by totalCount descending (hottest first), wrapped for the
	ObjectExplorer tree."
	| sorted |
	sorted := self children asSortedCollection: [:a :b | a totalCount > b totalCount].
	^ sorted asArray collect: [:child |
		ObjectExplorerWrapper
			with: child
			name: child explorerItemName
			model: self]
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:01'
}
SWAStSpyNode >> explorerItemName [
	"Tree-line label: 'total% duration  name' so hot frames are obvious.
	Counts/times are in microseconds (flamechart durations)."
	| pct rootTotal |
	rootTotal := self rootTotalCount.
	pct := rootTotal > 0
		ifTrue: [((totalCount * 100.0 / rootTotal) roundTo: 0.1) printString, '%  ']
		ifFalse: [''].
	^ pct, (self formatMicros: totalCount),
		(selfCount > 0 ifTrue: [' (self ', (self formatMicros: selfCount), ')'] ifFalse: ['']),
		'  ', self name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> filename [
	^ filename
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> filename: aString [
	filename := aString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:01'
}
SWAStSpyNode >> formatMicros: micros [
	"Human-readable duration from a microsecond count."
	micros < 1000 ifTrue: [^ micros printString, ' us'].
	micros < 1000000 ifTrue: [^ ((micros / 1000.0) roundTo: 0.1) printString, ' ms'].
	^ ((micros / 1000000.0) roundTo: 0.01) printString, ' s'
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> hasContentsInExplorer [
	"Show a disclosure triangle only if we have child frames."
	^ self children notEmpty
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> initialize [
	super initialize.
	selfCount := 0.
	totalCount := 0.
	children := nil   "lazily allocated on first addChild"
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWAStSpyNode >> isSmalltalkFrame [
	"True if this frame names a resolvable Smalltalk method we can browse."
	^ self methodReference notNil
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWAStSpyNode >> methodReference [
	"If this frame's name looks like a Smalltalk method -- 'Class>>selector' or
	'Class class>>selector' -- answer { theClass. selectorSymbol }, else nil.
	Native/VM frames (epoll_wait, copyBits, 0x7858..., poll) answer nil."
	| nm idx classPart selPart cls meta |
	nm := self name.
	nm ifNil: [^ nil].
	idx := nm indexOfSubCollection: '>>'.
	idx = 0 ifTrue: [^ nil].
	classPart := (nm copyFrom: 1 to: idx - 1) withBlanksTrimmed.
	selPart := (nm copyFrom: idx + 2 to: nm size) withBlanksTrimmed.
	(classPart isEmpty or: [selPart isEmpty]) ifTrue: [^ nil].

	"Handle metaclass: 'Foo class>>bar'."
	meta := false.
	(classPart endsWith: ' class')
		ifTrue: [meta := true.
			classPart := (classPart copyFrom: 1 to: classPart size - 6) withBlanksTrimmed].

	cls := Smalltalk classNamed: classPart.
	cls ifNil: [^ nil].
	meta ifTrue: [cls := cls class].
	^ { cls. selPart asSymbol }
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> name [
	"Short label for treemap/explorer."
	^ name ifNil: ['root']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> name: aString [
	name := aString
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> otherParents [
	"Call-tree nodes have a single parent; the overlay guards on nil, so answering
	nil disables that decoration."
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> parent: aNode [
	parent := aNode
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> pathString [
	"Slash-separated path from the root to the receiver (for balloon help)."
	^ parent isNil
		ifTrue: [self name]
		ifFalse: [parent pathString, ' / ', self name]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> printOn: aStream [
	aStream
		nextPutAll: 'SWAStSpyNode(';
		nextPutAll: self name;
		nextPutAll: ' self=';
		print: selfCount;
		nextPutAll: ' total=';
		print: totalCount;
		nextPutAll: ' kids=';
		print: self children size;
		nextPut: $)
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> rollUpTotals [
	"Compute totalCount bottom-up: own self samples plus all descendants.
	Returns this node's totalCount."
	totalCount := selfCount + (self children
		inject: 0 into: [:sum :c | sum + c rollUpTotals]).
	^ totalCount
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> rootTotalCount [
	"totalCount of the tree root, for percentage display."
	^ parent isNil ifTrue: [totalCount] ifFalse: [parent rootTotalCount]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> selfCount [
	"Number of samples in which this frame was the innermost frame."
	^ selfCount
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> selfSize [
	"Samples owned directly by this frame (it was the innermost frame)."
	^ selfCount
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> totalCount [
	"Rolled-up sample count over the whole subtree (this frame was on the stack).
	Valid only after #rollUpTotals."
	^ totalCount
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWAStSpyNode >> totalSize [
	"Treemap weight: rolled-up sample count over the subtree. Tiles are squarified
	by this, so hot call paths get the largest tiles. Min 0 so the treemap skips
	empty frames."
	^ totalCount
]
