"
Rebuilds a SWASpaceTallyNode tree from the JSON produced by
SWASpaceTallyJsonWriter, the inverse of that writer.

The serialized graph is a spanning tree (parent/children) plus shared-reference
back-edges carried as otherParents id-refs. Reconstruction is a single recursive
descent that:
  - mints/looks up a live node per serialized id via idMap (an id may be
    referenced as an otherParent before its own tree node is visited, so the map
    is populated on first sight, exactly mirroring the writer's idFor:);
  - populates each node's flat fields via #restoreFromJson:;
  - wires parent/children links as it descends;
  - records each node's otherParents id list in pendingOtherParents, then
    resolves them all to live nodes in a second pass once every id is known.

Entry points:
  SWASpaceTallyJsonReader readFrom: aFilePath   -> root SWASpaceTallyNode
  SWASpaceTallyJsonReader readFromString: aJsonString -> root SWASpaceTallyNode

Higher-level: SWASpaceTally class>>loadFromFile: wraps a loaded tree in a tally.
"
Class {
	#name : #SWASpaceTallyJsonReader,
	#superclass : #Object,
	#instVars : [
		'idMap',
		'pendingOtherParents',
		'realIds'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:51'
}
SWASpaceTallyJsonReader class >> readFrom: aFilePath [
	"Read the JSON dataset at aFilePath and answer the reconstructed root
	SWASpaceTallyNode."

	| file json |
	file := FileStream readOnlyFileNamed: aFilePath.
	json := [Json readFrom: file] ensure: [file close].
	^ self readJsonObject: json
]

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:51'
}
SWASpaceTallyJsonReader class >> readFromString: aJsonString [
	"Parse aJsonString and answer the reconstructed root SWASpaceTallyNode."

	^ self readJsonObject: (Json readFrom: aJsonString readStream)
]

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:51'
}
SWASpaceTallyJsonReader class >> readJsonObject: aJsonObject [
	"Answer the reconstructed root SWASpaceTallyNode for an already-parsed JSON
	object tree."

	^ self new buildFrom: aJsonObject
]

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:51'
}
SWASpaceTallyJsonReader >> buildFrom: rootJsonObject [
	"Rebuild the whole tree from the top-level JSON object and answer its root
	SWASpaceTallyNode, with all otherParents back-edges resolved."

	| root |
	root := self buildNode: rootJsonObject parent: nil.
	self resolveOtherParents.
	^ root
]

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:52'
}
SWASpaceTallyJsonReader >> buildNode: aJsonObject parent: parentNode [
	"Reconstruct the node for aJsonObject (and, recursively, its subtree),
	linking it under parentNode. Answers the live node."

	| node id |
	id := aJsonObject at: 'id'.
	node := self nodeForId: id.
	realIds add: id.  "this id has a real emitted node, not just a dangling ref"
	node restoreFromJson: aJsonObject.
	parentNode ifNotNil: [
		node setParent: parentNode depth: node depth.
		parentNode addChild: node].
	"Defer otherParents wiring until every id has a node (forward refs)."
	pendingOtherParents add: node -> (aJsonObject at: 'otherParents' ifAbsent: [#()]).
	(aJsonObject at: 'children' ifAbsent: [#()]) do: [:childJson |
		self buildNode: childJson parent: node].
	^ node
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:52'
}
SWASpaceTallyJsonReader >> initialize [
	super initialize.
	idMap := Dictionary new.  "serialized id -> live SWASpaceTallyNode"
	realIds := Set new.  "ids that were actually emitted as a tree node (vs only referenced)"
	pendingOtherParents := OrderedCollection new  "assocs node -> array of ids"
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:50'
}
SWASpaceTallyJsonReader >> nodeForId: anInteger [
	"Mint-on-first-sight, mirroring the writer's idFor:. An id may be seen as an
	otherParent ref before its own tree node is visited; either way the SAME id
	always yields the SAME live node."

	^ idMap at: anInteger ifAbsentPut: [SWASpaceTallyNode new]
]

{
	#category : #reading,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 09:52'
}
SWASpaceTallyJsonReader >> resolveOtherParents [
	"Second pass: turn each node's serialized otherParents id list into live node
	links. An otherParent id can point at a node that was pruned during
	compaction (its own tree node was never emitted); such dangling refs are
	dropped rather than resolved to an empty stub -- realIds tells them apart."

	pendingOtherParents do: [:assoc |
		| node live |
		node := assoc key.
		live := (assoc value
			select: [:eachId | realIds includes: eachId])
			collect: [:eachId | self nodeForId: eachId].
		node setOtherParents: (live isEmpty ifTrue: [nil] ifFalse: [live])]
]
