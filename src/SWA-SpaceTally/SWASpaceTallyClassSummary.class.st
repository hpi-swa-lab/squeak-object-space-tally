"
A per-class aggregation of a walked (or loaded) space-tally node tree, keyed by
class name -- the data structure the Code Map's #spaceTally decorate dataset reads
through (see SWADataset class>>spaceTallyFrom:named:).

For every SWASpaceTallyNode with a real className it accumulates:
  selfByClass  -- sum of selfSize (shallow: bytes the instances occupy themselves)
  totalByClass -- sum of totalSize (retained: contents included)
  countByClass -- number of nodes (instances) of that class in the tree

maxSelf / maxTotal cache the largest per-class value, so a color scale can
log-normalize against the dataset's own range.

Because a full object-space walk reaches an object once (spanning tree), a class's
summed selfSize approximates the live bytes owned by that class's reachable
instances. Shared objects reached via otherParents are NOT double-counted here
(they appear once in the tree). Build via #accumulateTree: from any node.

Note this is the OBJECT-SPACE view (bytes reached while walking from roots, with
contents), distinct from the system-wide SpaceTally (pure per-class instance
usage) which will feed a separate, alternative metric.
"
Class {
	#name : #SWASpaceTallyClassSummary,
	#superclass : #Object,
	#instVars : [
		'selfByClass',
		'totalByClass',
		'countByClass',
		'maxSelf',
		'maxTotal'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:07'
}
SWASpaceTallyClassSummary class >> fromAnyJsonFile: aFilePath [
	"Load a per-class summary from EITHER JSON flavor:
	 - a flat class-summary census (kind = classSummary, from #writeToFile:), or
	 - a full space-tally node tree (from SWASpaceTallyJsonWriter), which is
	   aggregated per class on load.
	Dispatch on the top-level 'kind' key."

	| file json |
	file := FileStream readOnlyFileNamed: aFilePath.
	json := [Json readFrom: file] ensure: [file close].
	^ self fromAnyJsonObject: json
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:07'
}
SWASpaceTallyClassSummary class >> fromAnyJsonObject: aJsonObject [
	"Build a per-class summary from an ALREADY-PARSED space-tally JSON object of
	either flavor: a flat class-summary census (kind = classSummary) or a full node
	tree. Dispatch on the top-level 'kind' key."

	(aJsonObject at: 'kind' ifAbsent: [nil]) = 'classSummary'
		ifTrue: [^ self new loadFlatJson: aJsonObject].
	^ self fromTree: (SWASpaceTallyJsonReader readJsonObject: aJsonObject)
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary class >> fromJsonFile: aFilePath [
	"Load a space-tally tree JSON (written by SWASpaceTallyJsonWriter) and
	aggregate it into a per-class summary in one step."
	^ self fromTree: (SWASpaceTallyJsonReader readFrom: aFilePath)
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary class >> fromTree: aRootNode [
	"Aggregate the node tree rooted at aRootNode into a per-class summary."
	^ self new accumulateTree: aRootNode
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:07'
}
SWASpaceTallyClassSummary class >> isSpaceTallyJson: aJsonObject [
	"Answer whether an already-parsed JSON object is a space-tally dataset this
	class can consume -- either the flat class-summary census (kind = classSummary)
	or a node tree (a node object carries an 'id' and a 'children' array). Coverage
	and duplication files carry a 'format' marker instead and are NOT ours."

	(aJsonObject includesKey: 'format') ifTrue: [^ false].
	(aJsonObject at: 'kind' ifAbsent: [nil]) = 'classSummary' ifTrue: [^ true].
	^ (aJsonObject includesKey: 'id') and: [aJsonObject includesKey: 'children']
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:52'
}
SWASpaceTallyClassSummary class >> systemWide [
	"Build a pure per-class instance-usage census over the WHOLE image, keyed by
	class name -- the classic 'system space tally' view (bytes the live instances
	of each class occupy), independent of any reachability walk.

	ONE heap pass: snapshot every object via SystemNavigation and bucket each by
	its class, summing byte sizes. This is O(heap), NOT O(classes x heap) -- do not
	go back to per-class allInstancesDo:, which re-scans the whole heap once per
	class and takes minutes. self == total in this flat census (no retained
	dimension); count is the live instance count per class."

	| summary all |
	all := SystemNavigation default allObjectsOrNil.
	all ifNil: [^ self error: 'not enough memory for a whole-heap sweep'].
	summary := self new.
	all do: [:obj | summary accumulateHeapObject: obj].
	summary recomputeMaxima.
	^ summary
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:52'
}
SWASpaceTallyClassSummary >> accumulateHeapObject: obj [
	"Fold one live object into the per-class buckets during a whole-heap sweep.
	Keyed by the object's class name; byte size from the class (fixed) or from the
	object's basicSize (variable). Behaviors key by their own name so metaclasses
	don't all collapse into 'Metaclass'."

	| cls key bytes |
	cls := obj class.
	key := (cls includesBehavior: Behavior)
		ifTrue: [obj name asString]
		ifFalse: [cls name asString].
	bytes := cls isVariable
		ifTrue: [cls byteSizeOfInstanceOfSize: obj basicSize]
		ifFalse: [cls byteSizeOfInstance].
	selfByClass at: key put: (selfByClass at: key ifAbsent: [0]) + bytes.
	totalByClass at: key put: (totalByClass at: key ifAbsent: [0]) + bytes.
	countByClass at: key put: (countByClass at: key ifAbsent: [0]) + 1
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> accumulateNode: aNode [
	"Fold one node's sizes into the per-class buckets, keyed by className.
	Nodes without a real className (synthetic root, aggregate bins) are skipped."

	| key s t |
	key := aNode className.
	(key isNil or: [key isEmpty]) ifTrue: [^ self].
	s := aNode selfSize ifNil: [0].
	t := aNode totalSize ifNil: [s].
	selfByClass at: key put: (selfByClass at: key ifAbsent: [0]) + s.
	totalByClass at: key put: (totalByClass at: key ifAbsent: [0]) + t.
	countByClass at: key put: (countByClass at: key ifAbsent: [0]) + 1
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> accumulateTree: aRootNode [
	"Walk the whole subtree rooted at aRootNode, accumulating per-class sizes,
	then refresh the cached maxima. Answers self. Iterative (explicit stack) so a
	deep tree can't blow the Smalltalk call stack."

	| stack |
	stack := OrderedCollection new.
	stack addLast: aRootNode.
	[stack isEmpty] whileFalse: [
		| node |
		node := stack removeLast.
		self accumulateNode: node.
		node children do: [:c | stack addLast: c]].
	self recomputeMaxima.
	^ self
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> bytesForKey: aClassName [
	"Shallow (self) bytes summed over this class's instances, or nil if unknown.
	nil (not 0) so the Code Map can distinguish 'class not in the tally' from
	'measured zero' and leave the tile a neutral base."

	^ selfByClass at: aClassName ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary >> classCount [
	"How many distinct classes carry a measurement."
	^ selfByClass size
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> countForKey: aClassName [
	"Number of nodes (instances) of aClassName in the tally, or nil if unknown."

	^ countByClass at: aClassName ifAbsent: [nil]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> initialize [
	super initialize.
	selfByClass := Dictionary new.
	totalByClass := Dictionary new.
	countByClass := Dictionary new.
	maxSelf := 0.
	maxTotal := 0
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:44'
}
SWASpaceTallyClassSummary >> loadFlatJson: aJsonObject [
	"Populate this summary from a flat class-summary JSON object (see #writeJsonOn:).
	Answers self."

	(aJsonObject at: 'classes' ifAbsent: [#()]) do: [:rec |
		| key |
		key := rec at: 'name'.
		selfByClass at: key put: (rec at: 'self' ifAbsent: [0]).
		totalByClass at: key put: (rec at: 'total' ifAbsent: [rec at: 'self' ifAbsent: [0]]).
		countByClass at: key put: (rec at: 'count' ifAbsent: [0])].
	self recomputeMaxima.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary >> maxSelf [
	^ maxSelf
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary >> maxTotal [
	^ maxTotal
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWASpaceTallyClassSummary >> printOn: aStream [
	aStream
		nextPutAll: 'SWASpaceTallyClassSummary(';
		print: self classCount;
		nextPutAll: ' classes, maxSelf=';
		print: maxSelf;
		nextPutAll: ' maxTotal=';
		print: maxTotal;
		nextPut: $)
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> recomputeMaxima [
	"Cache the largest per-class self and total, for scale normalization."

	maxSelf := selfByClass isEmpty ifTrue: [0] ifFalse: [selfByClass values max].
	maxTotal := totalByClass isEmpty ifTrue: [0] ifFalse: [totalByClass values max]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:38'
}
SWASpaceTallyClassSummary >> totalBytesForKey: aClassName [
	"Retained (total) bytes summed over this class's instances -- contents
	included -- or nil if unknown."

	^ totalByClass at: aClassName ifAbsent: [nil]
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:43'
}
SWASpaceTallyClassSummary >> writeJsonOn: aStream [
	"Stream this summary as a flat, image-independent class census with a kind tag
	and a classes array of name/self/total/count records -- one per class name,
	exactly what the Code Map spaceTally decorate metric reads. Class names are
	Smalltalk identifiers, but escaping is still routed through Json for safety."

	| first |
	aStream nextPutAll: '{"kind":"classSummary","classes":['.
	first := true.
	selfByClass keysAndValuesDo: [:key :selfBytes |
		first ifFalse: [aStream nextPut: $,].
		first := false.
		aStream nextPutAll: '{"name":'.
		self writeJsonString: key on: aStream.
		aStream nextPutAll: ',"self":'.
		selfBytes printOn: aStream.
		aStream nextPutAll: ',"total":'.
		(totalByClass at: key ifAbsent: [selfBytes]) printOn: aStream.
		aStream nextPutAll: ',"count":'.
		(countByClass at: key ifAbsent: [0]) printOn: aStream.
		aStream nextPut: $}].
	aStream nextPutAll: ']}'
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:43'
}
SWASpaceTallyClassSummary >> writeJsonString: aString on: aStream [
	"Emit aString as a JSON string literal, delegating per-character escaping to the
	image's Json (same approach as SWASpaceTallyJsonWriter)."

	aStream nextPut: $".
	aString do: [:ch |
		(Json escapeForCharacter: ch)
			ifNil: [aStream nextPut: ch]
			ifNotNil: [:esc | aStream nextPutAll: esc]].
	aStream nextPut: $"
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:43'
}
SWASpaceTallyClassSummary >> writeToFile: aFilePath [
	"Stream this class-summary census to aFilePath as flat JSON. Answers aFilePath."

	| file |
	file := FileStream forceNewFileNamed: aFilePath.
	[self writeJsonOn: file] ensure: [file close].
	^ aFilePath
]
