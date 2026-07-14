"
A node in a sampled call tree built from an st-spy chrome-trace recording.

Duck-typed to work in BOTH the SWA Explorer (PluggableTreeMorph via #explorerContents / #explorerItemName / #hasContentsInExplorer) and the SWA TreeMap (SWATreemapMorph, which reads #children / #totalSize / #name / #depth / #pathString / #selfSize / #otherParents).

Tree semantics: each node is a method frame (or the synthetic 'root'). #selfCount is the number of samples in which this frame was the innermost (leaf) frame; #totalCount is the rolled-up sample count over the whole subtree (this frame appeared on the stack). The treemap squarifies tiles by #totalSize (= totalCount), so hot call paths get larger tiles.

Build with: parent addChildNamed: aString -- which finds-or-creates a child. After folding all samples, send #rollUpTotals to compute totalCount bottom-up.
"
Class {
	#name : #SWASamplingTallyNode,
	#superclass : #SWANode,
	#instVars : [
		'name',
		'selfCount',
		'totalCount',
		'category',
		'filename'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:00'
}
SWASamplingTallyNode >> addSelfTime: micros [
	"Add `micros` microseconds of time during which this frame was the innermost
	(leaf) frame on the stack."
	selfCount := selfCount + micros
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWASamplingTallyNode >> browse [
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
SWASamplingTallyNode >> bumpSelf [
	"Legacy single-count bump (1 sample as leaf). Prefer #addSelfTime: for
	flamechart traces that carry real durations."
	selfCount := selfCount + 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> category [
	^ category
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> category: aString [
	category := aString
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 16:57'
}
SWASamplingTallyNode >> childNamed: aString [
	"Find or create the child frame with this name, allocating the children
	collection lazily."
	children ifNil: [children := OrderedCollection new].
	^ children
		detect: [:c | c name = aString]
		ifNone: [ | child |
			child := SWASamplingTallyNode new.
			child name: aString; parent: self.
			children add: child.
			child]
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:40'
}
SWASamplingTallyNode >> compiledMethod [
	"The CompiledMethod this frame names, or nil for native/unresolvable frames."
	| ref |
	ref := self methodReference.
	ref ifNil: [^ nil].
	^ (ref first includesSelector: ref second)
		ifTrue: [ref first >> ref second]
		ifFalse: [nil]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:33'
}
SWASamplingTallyNode >> crossRefKey [
	"A resolvable Smalltalk frame cross-references as 'ClassName>>selector'
	(matching SWACodeMethodNode). Native/unresolvable frames answer nil.
	The class portion is taken from the resolved class so metaclass framing
	('Foo class>>bar') is normalised consistently with the static view."
	| ref |
	ref := self methodReference.
	ref ifNil: [^ nil].
	^ ref first name asString, '>>', ref second
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> edgeLabel [
	^ nil
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> explorerContents [
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
SWASamplingTallyNode >> explorerItemName [
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
SWASamplingTallyNode >> filename [
	^ filename
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> filename: aString [
	filename := aString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 14:01'
}
SWASamplingTallyNode >> formatMicros: micros [
	"Human-readable duration from a microsecond count."
	micros < 1000 ifTrue: [^ micros printString, ' us'].
	micros < 1000000 ifTrue: [^ ((micros / 1000.0) roundTo: 0.1) printString, ' ms'].
	^ ((micros / 1000000.0) roundTo: 0.01) printString, ' s'
]

{
	#category : #exploring,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> hasContentsInExplorer [
	"Show a disclosure triangle only if we have child frames."
	^ self children notEmpty
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> initialize [
	super initialize.
	selfCount := 0.
	totalCount := 0.
	children := nil   "lazily allocated on first addChild"
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWASamplingTallyNode >> isSmalltalkFrame [
	"True if this frame names a resolvable Smalltalk method we can browse."
	^ self methodReference notNil
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 15:16'
}
SWASamplingTallyNode >> methodReference [
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
SWASamplingTallyNode >> name [
	"Short label for treemap/explorer."
	^ name ifNil: ['root']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> name: aString [
	name := aString
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> otherParents [
	"Call-tree nodes have a single parent; the overlay guards on nil, so answering
	nil disables that decoration."
	^ nil
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 16:57'
}
SWASamplingTallyNode >> printOn: aStream [
	aStream
		nextPutAll: 'SWASamplingTallyNode(';
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
SWASamplingTallyNode >> rollUpTotals [
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
SWASamplingTallyNode >> rootTotalCount [
	"totalCount of the tree root, for percentage display."
	^ parent isNil ifTrue: [totalCount] ifFalse: [parent rootTotalCount]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> selfCount [
	"Number of samples in which this frame was the innermost frame."
	^ selfCount
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> selfSize [
	"Samples owned directly by this frame (it was the innermost frame)."
	^ selfCount
]

{
	#category : #browsing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 16:00'
}
SWASamplingTallyNode >> sourceString [
	"The source code of this frame's method, or -- for native/VM or missing frames
	-- a note wrapped as a single Smalltalk comment so the Shout styler renders it
	cleanly (as comment text) instead of choking on non-Smalltalk."
	| ref m |
	ref := self methodReference.
	ref ifNil: [^ '"', self name, ' is a native / VM frame -- no Smalltalk source."'].
	m := self compiledMethod.
	m ifNil: [^ '"', ref first name, ' >> ', ref second, ' is not present in this image."'].
	^ m getSource asString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> totalCount [
	"Rolled-up sample count over the whole subtree (this frame was on the stack).
	Valid only after #rollUpTotals."
	^ totalCount
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:57'
}
SWASamplingTallyNode >> totalSize [
	"Treemap weight: rolled-up sample count over the subtree. Tiles are squarified
	by this, so hot call paths get the largest tiles. Min 0 so the treemap skips
	empty frames."
	^ totalCount
]
