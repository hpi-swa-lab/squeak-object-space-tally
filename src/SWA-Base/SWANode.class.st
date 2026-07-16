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
