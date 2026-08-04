"
Abstract superclass for all SWA treemap nodes (static code map, message tally, space tally). Defines the shared tree protocol so views can be walked and cross-referenced uniformly.

Shared structure: parent + children form the tree.

Subclass responsibilities:
- children: answer child nodes (#() for leaves)
- name: short display label
- totalSize: treemap weight (LOC / sample count / bytes)
- crossRefKey: canonical cross-view identity String, or nil if this node is not cross-referenceable. Classes answer their class name; methods answer 'ClassName>>selector' (metaclass: 'ClassName class>>selector'). Packages/categories/native frames answer nil.

The crossRefKey lets the three independent views (CodeMap, StSpy, SpaceTally) be linked: class names are unique, and methods are identified by 'Class>>selector'.
"
Class {
	#name : #SWANode,
	#superclass : #Object,
	#instVars : [
		'parent',
		'children'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> children [
	"Child nodes. Answer #() (not a fresh collection) for leaves so reads are cheap.
	Subclasses with lazy/computed children override."
	^ children ifNil: [#()]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 16:56'
}
SWANode >> crossRefKey [
	"Canonical cross-view identity String, or nil if this node is not
	cross-referenceable. Classes answer their class name; methods answer
	'ClassName>>selector'. Packages/categories/native frames answer nil.
	Used to link the independent CodeMap / SamplingTally / SpaceTally views."
	^ nil
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> depth [
	^ parent isNil ifTrue: [0] ifFalse: [parent depth + 1]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWANode >> eventGroupKey [
	"The identity of the ATOMIC ACT this node was part of -- a git commit, an image
	save -- or nil when it does not belong to one. Used by the temporal views'
	'commits' measure, which counts distinct acts rather than individual changes.
	nil by default."
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWANode >> eventTimeStamp [
	"WHEN this node happened, as a DateAndTime/TimeStamp, or nil if it has no
	position in time. This is the whole contract the temporal views
	(SWATimelineMorph, SWACalendarMorph) need -- implementing it is what makes a
	node family placeable on a time axis, without those views knowing anything about
	changes, commits or methods.

	nil by default: most nodes (a package, a heap object) are not events."
	^ nil
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> isLeaf [
	^ self children isEmpty
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:56'
}
SWANode >> markKey [
	"Cross-view identity String used by the GLOBAL mark set (SWAMarkSet) to bookmark
	this node across every open view, or nil if this node is not markable. Defaults
	to #crossRefKey (class name, or 'ClassName>>selector' for methods). Node kinds
	that have no crossRefKey but ARE meaningful marks -- notably PACKAGES and
	CATEGORIES -- override this to answer their own name. Kept distinct from
	crossRefKey so the coverage/space-tally cross-referencing (which is deliberately
	class-granular and nil for packages) is unaffected."
	^ self crossRefKey
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> name [
	^ self subclassResponsibility
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:10'
}
SWANode >> nodeKind [
	"A machine-readable Symbol naming the KIND of thing this node represents -- what its
	markKey points at -- independent of the view it is shown in. For code nodes this is
	the existing #kind (#class / #package / #method / #category); other node families
	answer their own (#spaceTally, #samplingTally, #change). Recorded in mark provenance
	(as a String) so a mark remembers whether it is a class, a package, a space-tally
	node, etc. Default: #kind if the node defines one, else a symbol derived from the
	class name (strip 'SWA'/'Node', lowercase first letter)."
	| n |
	(self respondsTo: #kind) ifTrue: [^ self kind].
	n := self class name asString.
	(n beginsWith: 'SWA') ifTrue: [n := n allButFirst: 3].
	(n endsWith: 'Node') ifTrue: [n := n allButLast: 4].
	n isEmpty ifTrue: [^ #node].
	^ (n first asLowercase asString, n allButFirst) asSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> parent: aNode [
	parent := aNode
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> pathString [
	"Slash-separated path from the root to the receiver (for balloon help)."
	^ parent isNil
		ifTrue: [self name]
		ifFalse: [parent pathString, ' / ', self name]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> totalSize [
	"Treemap weight (LOC / sample count / bytes). Subclasses define."
	^ self subclassResponsibility
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> withAllChildrenDo: aBlock [
	"Evaluate aBlock with the receiver and every descendant (depth-first)."
	aBlock value: self.
	self children do: [:c | c withAllChildrenDo: aBlock]
]
