"
One level of a hyphenated system category, nested under the package that owns it: the categories 'SqueakXR-Core' and 'SqueakXR-Tests-Objects' become Core, and Tests then Objects, beneath the SqueakXR package node.

A Squeak package IS a category prefix, so these are sub-packages in every sense except being declared: nothing registers 'SqueakXR-Tests', it exists only as a prefix shared by the categories under it.

The subject is the full category String rather than a PackageInfo on purpose. A synthesised PackageInfo claims every class beneath its prefix, and the owning package claims them too, so each class would be tiled twice -- the prefix-overlap problem SWACodeRootNode>>ownerOfSystemCategory: exists to solve, and that one resolves only among SELECTED packages. Splitting the owning package's own class list has no such overlap.
"
Class {
	#name : #SWACodeSubpackageNode,
	#superclass : #SWACodeNode,
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:56'
}
SWACodeSubpackageNode class >> childrenFor: someClasses prefix: aPrefix parent: aNode [
	"Split someClasses into the ones whose system category IS aPrefix -- which become
	class tiles right here -- and the ones below it, grouped by their NEXT segment into
	one sub-level each. Sub-levels first, then classes, matching how a package node
	already orders sub-packages before its own classes.

	Only the next segment is grouped on: deeper levels split again when that child
	builds its own children, so 'A-B-C' nests rather than appearing as one flat 'B-C'."
	| direct groups result |
	direct := OrderedCollection new.
	groups := Dictionary new.
	someClasses do: [:cls |
		| classCategory rest |
		classCategory := cls category asString.
		classCategory = aPrefix
			ifTrue: [direct add: cls]
			ifFalse: [
				rest := classCategory copyFrom: aPrefix size + 2 to: classCategory size.
				(groups
					at: aPrefix , '-' , ((rest findTokens: '-') first)
					ifAbsentPut: [OrderedCollection new]) add: cls]].
	result := OrderedCollection new.
	(groups keys asSortedCollection: [:a :b | a <= b]) do: [:each |
		result add: (SWACodeSubpackageNode on: each parent: aNode)].
	(direct asSortedCollection: [:a :b | a name <= b name]) do: [:cls |
		result add: (SWACodeClassNode on: cls parent: aNode)].
	^ result
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> browse [
	^ Browser fullOnCategory: self fullCategory
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> buildChildren [
	"The owning package's classes that live at or below my category, split again."
	| owner prefix mine |
	owner := self owningPackageNode.
	owner ifNil: [^ OrderedCollection new].
	prefix := self fullCategory.
	mine := owner ownedClasses select: [:cls |
		| category |
		category := cls category asString.
		category = prefix or: [category beginsWith: prefix , '-']].
	^ SWACodeSubpackageNode childrenFor: mine prefix: prefix parent: self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> fullCategory [
	"The whole system category this level stands for, e.g. 'SqueakXR-Tests'."
	^ subject asString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> kind [
	"The same level as a package to a reader, and to the Depth button."
	^ #package
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> markKey [
	"The FULL category: #name is only a segment, and 'Objects' alone would collide
	with every other package that has one."
	^ self fullCategory
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> name [
	"Just this level's segment -- the parent tile already shows the prefix, and a
	breadcrumb then reads SqueakXR / Tests / Objects."
	| segments |
	segments := self fullCategory findTokens: '-'.
	^ segments isEmpty ifTrue: [self fullCategory] ifFalse: [segments last]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 15:55'
}
SWACodeSubpackageNode >> owningPackageNode [
	"The real package this level sits under. The class list is kept there, so the
	split is always of the same set no matter how deep it nests."
	| node |
	node := self parent.
	[node notNil and: [(node isKindOf: SWACodePackageNode) not]]
		whileTrue: [node := node parent].
	^ node
]
