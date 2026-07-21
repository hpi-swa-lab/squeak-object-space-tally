"
A named STRUCTURE (tree projection) that a SWADataset can supply as a treemap/flamegraph's base structure. One dataset may expose several: its PRIMARY (native) structure plus DERIVED projections of the same underlying data (e.g. a call-tally dataset's primary call tree, plus a derived code-map-style grouping of the same calls).

Each structure knows:
- key: a symbol identifying it within the dataset's structure set (used by the Tree menu / setStructureMode:).
- label: human-readable menu text.
- rootBlock: a zero-arg block that lazily builds the node tree (a SWANode) the first time it is asked for; the result is cached in root.
- viewClass: the SWAView subclass that renders this tree (e.g. SWASamplingTallyFlamegraphMorph for a call tree, SWASpaceTallyTreemapMorph for a space-tally tree, a code treemap for a grouped structure).

The dataset owns the primary data; a structure is just a re-projection of it into a tree + the morph class that draws that tree. Derivation lives here (on the dataset/projector), keeping SWANode lean.
"
Class {
	#name : #SWAStructure,
	#superclass : #Object,
	#instVars : [
		'key',
		'label',
		'rootBlock',
		'viewClass',
		'root'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure class >> key: aSymbol label: aString view: aViewClass rootBlock: aBlock [
	"A structure identified by aSymbol, shown as aString in the Tree menu, rendered by
	aViewClass, whose node tree is built lazily by aBlock (evaluated once, cached)."
	^ self new setKey: aSymbol label: aString view: aViewClass rootBlock: aBlock
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> buildViewExtent: anExtent [
	"Instantiate this structure's view morph (viewClass) on its (lazily built) node
	tree, sized to anExtent. Answers nil if the tree can't be built."
	| r |
	r := self root.
	r ifNil: [^ nil].
	^ (viewClass on: r) extent: anExtent; yourself
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> key [
	^ key
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> label [
	^ label
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> root [
	"The node tree for this structure, built lazily (once) from rootBlock and cached."
	^ root ifNil: [root := rootBlock value]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> setKey: aSymbol label: aString view: aViewClass rootBlock: aBlock [
	key := aSymbol.
	label := aString.
	viewClass := aViewClass.
	rootBlock := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWAStructure >> viewClass [
	^ viewClass
]
