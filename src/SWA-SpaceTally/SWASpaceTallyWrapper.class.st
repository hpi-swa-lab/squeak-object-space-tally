"
ObjectExplorerWrapper subclass for SWASpaceTally nodes.

Overrides the default explorer behavior so that:
- Tree expansion uses the tally node children (preserving the tally tree structure)
- The workspace self binding is the real analyzed object (so inspect-it/do-it work on the actual object, not the tally node)

The item association stores name -> realObject. The tallyNode ivar holds the SWASpaceTally node for tree navigation.
"
Class {
	#name : #SWASpaceTallyWrapper,
	#superclass : #ObjectExplorerWrapper,
	#instVars : [
		'tallyNode'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTallyWrapper class >> withTally: aTallyNode name: aString model: aModel [
	"Create a wrapper whose workspace self is the real object
	but whose tree expansion follows the tally node's children."

	^ self new
		setTallyNode: aTallyNode name: aString model: aModel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTallyWrapper >> contents [
	"Use the tally node's explorer contents for tree navigation,
	not the real object's."

	^ [tallyNode explorerContents
		do: [:wrapper | wrapper parent: self];
		yourself] ifError: [:msg | {self class forError: msg}]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTallyWrapper >> hasContents [
	"Use the tally node to determine expandability."

	^ tallyNode hasContentsInExplorer
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTallyWrapper >> objectString [
	"Show the tally node's size summary, not the real object's printString."

	^ tallyNode asExplorerString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:02'
}
SWASpaceTallyWrapper >> preferredColor [
	"In a diff tree, color new objects green and old/context objects gray.
	Returns nil for ordinary tallies so the theme default applies."

	^ tallyNode diffColor
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/10/2026 11:02'
}
SWASpaceTallyWrapper >> setTallyNode: aTallyNode name: aString model: aModel [
	"Store the tally node for tree navigation. Set item to name -> realObject
	so the workspace self binding is the real analyzed object."

	| realObject |
	tallyNode := aTallyNode.
	realObject := aTallyNode object ifNil: [aTallyNode].
	self setItem: aString -> realObject model: aModel
]
