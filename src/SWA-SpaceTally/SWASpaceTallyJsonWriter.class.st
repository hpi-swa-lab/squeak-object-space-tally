"
Streams a SWASpaceTally node tree to JSON in a single pass.

Holds the write stream plus an IdentityDictionary (idMap) that mints a stable
integer id the first time it sees any node (mint-on-first-sight via #idFor:).
Each node emits its own ""id""; its ""otherParents"" are emitted as a list of ids
resolved through the SAME idMap, so shared-reference (other-parent) structure
survives the tree->JSON flattening and can be reconstructed on load.

Because ids are minted on first sight, forward references (an otherParent whose
own tree node has not been emitted yet) simply mint the id early; when the tree
walk later reaches that node it emits the matching id -- no second pass needed.

Usage:
	SWASpaceTallyJsonWriter writeTree: aRootNode to: 'tally.json'.
	SWASpaceTallyJsonWriter stringFor: aRootNode.
"
Class {
	#name : #SWASpaceTallyJsonWriter,
	#superclass : #Object,
	#instVars : [
		'stream',
		'idMap',
		'nextId'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #writing,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:24'
}
SWASpaceTallyJsonWriter class >> stringFor: aRootNode [
	"Answer the JSON String for the tree rooted at aRootNode."
	^ String streamContents: [:s |
		(self new on: s) writeNode: aRootNode]
]

{
	#category : #writing,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:24'
}
SWASpaceTallyJsonWriter class >> writeTree: aRootNode to: aFilePath [
	"Stream the tree rooted at aRootNode to aFilePath as JSON. Answers aFilePath."
	| file |
	file := FileStream forceNewFileNamed: aFilePath.
	[(self new on: file) writeNode: aRootNode] ensure: [file close].
	^ aFilePath
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:23'
}
SWASpaceTallyJsonWriter >> idFor: aNode [
	"Mint-on-first-sight: return aNode's stable integer id, assigning a fresh one
	(keyed on object identity) the first time aNode is seen. Both the tree walk and
	the otherParents refs go through here, so a forward reference and the node's own
	later emission resolve to the SAME id."
	^ idMap at: aNode ifAbsentPut: [nextId := nextId + 1. nextId]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:23'
}
SWASpaceTallyJsonWriter >> initialize [
	idMap := IdentityDictionary new.
	nextId := 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:23'
}
SWASpaceTallyJsonWriter >> on: aStream [
	"Serialize onto an existing write stream."
	stream := aStream
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:26'
}
SWASpaceTallyJsonWriter >> writeJsonString: aString [
	"Write aString to the stream as a JSON string literal. Escaping is delegated to
	Json (Json escapeForCharacter: answers the escape sequence, or nil if the char
	needs none), so we don't maintain our own escape table."
	stream nextPut: $".
	aString do: [:ch |
		(Json escapeForCharacter: ch)
			ifNil: [stream nextPut: ch]
			ifNotNil: [:esc | stream nextPutAll: esc]].
	stream nextPut: $"
]

{
	#category : #writing,
	#'squeak_changestamp' : 'MCPServer 7/2/2026 15:26'
}
SWASpaceTallyJsonWriter >> writeNode: aNode [
	"Recursively emit aNode and its subtree as JSON. Single pass: aNode's own id
	and every otherParents id resolve through the shared idMap (#idFor:)."
	| ops |
	stream nextPutAll: '{"id":'.
	(self idFor: aNode) printOn: stream.
	stream nextPutAll: ',"name":'.
	self writeJsonString: aNode name.
	stream nextPutAll: ',"className":'.
	self writeJsonString: (aNode className ifNil: ['']).
	stream nextPutAll: ',"edgeLabel":'.
	self writeJsonString: (aNode edgeLabel ifNil: ['']).
	stream nextPutAll: ',"self":'.
	aNode selfSize printOn: stream.
	stream nextPutAll: ',"total":'.
	(aNode totalSize ifNil: [aNode selfSize]) printOn: stream.
	stream nextPutAll: ',"depth":'.
	aNode depth printOn: stream.
	stream nextPutAll: ',"truncated":'.
	stream nextPutAll: (aNode truncated ifTrue: ['true'] ifFalse: ['false']).
	stream nextPutAll: ',"pruned":'.
	stream nextPutAll: (aNode pruned ifTrue: ['true'] ifFalse: ['false']).
	stream nextPutAll: ',"prunedChildCount":'.
	aNode prunedChildCount printOn: stream.
	stream nextPutAll: ',"prunedChildBytes":'.
	aNode prunedChildBytes printOn: stream.
	stream nextPutAll: ',"otherParents":['.
	ops := aNode otherParents ifNil: [#()].
	ops doWithIndex: [:op :i |
		i > 1 ifTrue: [stream nextPut: $,].
		(self idFor: op) printOn: stream].
	stream nextPutAll: '],"children":['.
	aNode children doWithIndex: [:c :i |
		i > 1 ifTrue: [stream nextPut: $,].
		self writeNode: c].
	stream nextPutAll: ']}'
]
