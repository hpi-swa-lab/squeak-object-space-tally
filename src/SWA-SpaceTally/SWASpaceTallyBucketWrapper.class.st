"
A purely-visual grouping row for the SWASpaceTally explorer.

When a tally node has very many children (e.g. a LostAndFound bin with 100k
siblings), rendering one tree row per child is slow and unusable. This wrapper
groups an already-built slice of child wrappers under a single expandable
""bucket"" row labelled with the index range and the slice's total bytes. The
underlying SWASpaceTallyNode tree is NOT modified -- bucketing exists only in
the explorer's wrapper layer. Expanding a bucket reveals its slice (or further
sub-buckets if the slice is itself still large).

ivars:
  childWrappers -- the OrderedCollection of wrappers this bucket contains
  totalBytes    -- summed totalSize of the contained nodes, for the value column
"
Class {
	#name : #SWASpaceTallyBucketWrapper,
	#superclass : #ObjectExplorerWrapper,
	#instVars : [
		'childWrappers',
		'totalBytes'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper class >> withWrappers: aCollectionOfWrappers name: aString bytes: anInteger model: aModel [
	"Create a bucket row holding the given child wrappers, labelled aString and
	summarising anInteger bytes."

	^ self new
		setWrappers: aCollectionOfWrappers name: aString bytes: anInteger model: aModel
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> bucketTotalBytes [
	^ totalBytes
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> contents [
	"The wrappers in this bucket, re-bucketed again if the slice is itself still
	too large (so a million children become a shallow tree of buckets). Sets
	each child's parent to self for tree navigation."

	| grouped |
	grouped := SWASpaceTallyNode bucketize: childWrappers model: self model.
	grouped do: [:w | w parent: self].
	^ grouped
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> formatBytes: n [
	^ SWASpaceTally formatBytes: n
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> hasContents [
	^ childWrappers notEmpty
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> objectString [
	"Value-column text: a className-like blank, then the bucket's total bytes and
	child count, tab-separated to line up with real rows
	(className | total | self | children | ...)."

	^ String streamContents: [:s |
		s nextPut: Character tab.                          "className column blank"
		s nextPutAll: (self formatBytes: totalBytes).
		s nextPut: Character tab.                          "self column blank"
		s nextPut: Character tab.
		childWrappers size printOn: s.
		s nextPutAll: ' items']
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 12:04'
}
SWASpaceTallyBucketWrapper >> setWrappers: aCollectionOfWrappers name: aString bytes: anInteger model: aModel [
	childWrappers := aCollectionOfWrappers.
	totalBytes := anInteger.
	"item is a name -> self association so the workspace 'self' binding is this
	bucket (harmless; buckets aren't real objects)."
	self setItem: aString -> self model: aModel
]
