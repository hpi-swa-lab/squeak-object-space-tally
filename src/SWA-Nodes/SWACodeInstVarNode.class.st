"
A single instance variable of a class, as a markable/cross-referenceable node in the SWA
view layer. Its subject is the owning class (a SWACodeClassNode's class); ivarName is the
variable name. Cross-view identity ('markKey'/'crossRefKey') is 'ClassName>>#ivarName' --
the leading # distinguishes it from a method 'ClassName>>selector'. nodeKind is #instVar.

Introduced so instance variables can be BOOKMARKED (e.g. from a class diagram's state
row) and later carry EDGES to other nodes -- composition/type information harvested from
the space tally or from type harvesting -- the way method/class nodes already cross-link
the CodeMap / SpaceTally / SamplingTally views.
"
Class {
	#name : #SWACodeInstVarNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'ivarName'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> buildChildren [
	"An instance variable is a leaf in the code tree (edges to type/composition targets are
	a separate, future overlay, not tree children)."
	^ #()
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> crossRefKey [
	"Cross-view identity: 'ClassName>>#ivarName'. The leading # on the member distinguishes
	an ivar from a method ('ClassName>>selector'), and '>>' cannot occur in a valid ivar
	name, so the key is unambiguous."
	^ subject name asString, '>>#', ivarName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> ivarName [
	"The instance-variable name."
	^ ivarName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> ivarName: aString [
	"Set the instance-variable name this node represents. Returns self."
	ivarName := aString.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> kind [
	^ #instVar
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> name [
	"UML attribute label: the ivar name."
	^ ivarName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:43'
}
SWACodeInstVarNode >> theClass [
	"The class that owns this instance variable (the node's subject)."
	^ subject
]
