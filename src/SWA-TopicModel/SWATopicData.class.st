"
Image-independent topic-model result for the Code Map, mirroring SWACoverageData.

Produced by SWABitermTopicModel, persisted as JSON, loaded to drive the #topic
color mode and topic filter on the treemap.

Instance vars:
- k                the number of topics
- topWords         Array (size k) of Arrays of top word Strings per topic (labels)
- methodNames      OrderedCollection of crossRefKey strings ('Class>>selector')
- methodTopics     Dictionary methodName -> Array of {topicId. weight} pairs
                   (sparse distribution, sorted desc, only the significant topics)
- topicHue         Array (size k) mapping topicId -> hue family index (0..hueFamilyCount-1)
- hueFamilyCount   number of distinct hue families the k topics collapse to

JSON shape (format 'SWATopicData/1'):
{ #format, #k, #hueFamilyCount,
  #topWords:[[w,w,...], ...],        one per topic
  #topicHue:[familyIdx, ...],        one per topic
  #methods:[crossRefKey, ...],
  #topics:{ methodId(string): [[topicId, weight], ...] } }
methodId is the 1-based position into #methods.

Query protocol used by the overlay:
- dominantTopicFor: aKey   -> topicId (argmax) or nil
- distributionFor: aKey    -> {topicId. weight} pairs
- hueFamilyFor: aKey       -> family index or nil
- labelForTopic: id        -> top words joined
"
Class {
	#name : #SWATopicData,
	#superclass : #Object,
	#instVars : [
		'k',
		'topWords',
		'methodNames',
		'methodTopics',
		'topicHue',
		'hueFamilyCount'
	],
	#category : #'SWA-TopicModel',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> asJsonString [
	"Serialise to the reusable, image-independent JSON form (see class comment).
	Method ids are 1-based positions into #methods; JSON object keys are strings."
	| dict topicsJson |
	topicsJson := Dictionary new.
	methodNames doWithIndex: [:nm :i |
		| dist |
		dist := methodTopics at: nm ifAbsent: [nil].
		(dist notNil and: [dist notEmpty]) ifTrue: [
			topicsJson
				at: i printString
				put: (dist collect: [:pair | Array with: pair first with: pair last])]].
	dict := Dictionary new
		at: 'format' put: 'SWATopicData/1';
		at: 'k' put: k;
		at: 'hueFamilyCount' put: hueFamilyCount;
		at: 'topWords' put: (topWords collect: [:ws | ws asArray]) asArray;
		at: 'topicHue' put: topicHue asArray;
		at: 'methods' put: methodNames asArray;
		at: 'topics' put: topicsJson;
		yourself.
	^ String streamContents: [:s | dict jsonWriteOn: s]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> distributionFor: aKey [
	"Answer the sparse topic distribution for a method crossRefKey: an Array of
	{topicId. weight} pairs sorted by descending weight, or empty if unknown."
	^ methodTopics at: aKey ifAbsent: [#()]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> dominantTopicFor: aKey [
	"Answer the argmax topic id for a method key, or nil if unknown.
	The distribution is stored weight-sorted, so the first pair wins."
	| dist |
	dist := self distributionFor: aKey.
	dist isEmpty ifTrue: [^ nil].
	^ (dist first) first
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> hueFamilyCount [
	^ hueFamilyCount
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> hueFamilyFor: aKey [
	"Answer the hue family index (0-based) for a method key's dominant topic, or nil."
	| topic |
	topic := self dominantTopicFor: aKey.
	topic ifNil: [^ nil].
	^ self hueFamilyForTopic: topic
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> hueFamilyForTopic: topicId [
	"topicId is 0-based; topicHue is a 1-indexed Array indexed by topicId+1."
	(topicId isNil or: [topicId < 0 or: [topicId >= topicHue size]]) ifTrue: [^ nil].
	^ topicHue at: topicId + 1
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> initialize [
	k := 0.
	topWords := Array new: 0.
	methodNames := OrderedCollection new.
	methodTopics := Dictionary new.
	topicHue := Array new: 0.
	hueFamilyCount := 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> k [
	^ k
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> labelForTopic: topicId [
	"Human-readable label for a topic: its top words joined. topicId is 0-based."
	| words |
	(topicId isNil or: [topicId < 0 or: [topicId >= topWords size]])
		ifTrue: [^ '?'].
	words := topWords at: topicId + 1.
	words isEmpty ifTrue: [^ 'topic ', topicId printString].
	^ words fold: [:a :b | a, ' ', b]
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> loadFromFile: aFilePath [
	"Read and parse JSON from aFilePath into the receiver."
	| stream contents |
	stream := FileStream readOnlyFileNamed: aFilePath.
	contents := [stream contentsOfEntireFile] ensure: [stream close].
	self loadFromJson: (Json readFrom: contents readStream).
	^ self
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> loadFromJson: json [
	"Populate from a parsed JSON object (see #asJsonString for the shape)."
	| topicsJson |
	k := json at: 'k' ifAbsent: [0].
	hueFamilyCount := json at: 'hueFamilyCount' ifAbsent: [0].
	topWords := (json at: 'topWords' ifAbsent: [#()])
		collect: [:ws | ws asArray].
	topicHue := (json at: 'topicHue' ifAbsent: [#()]) asArray.
	methodNames := (json at: 'methods' ifAbsent: [#()]) asOrderedCollection.
	methodTopics := Dictionary new.
	topicsJson := json at: 'topics' ifAbsent: [Dictionary new].
	topicsJson keysAndValuesDo: [:midStr :pairs |
		| idx nm dist |
		idx := midStr asNumber.
		nm := methodNames at: idx.
		dist := pairs collect: [:p |
			Array with: (p first) with: (p last)].
		methodTopics at: nm put: dist asArray]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> methodNames [
	^ methodNames
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> setK: anInt topWords: wordsArray methodNames: names methodTopics: topicsDict topicHue: hueArray hueFamilyCount: families [
	"Populate from a completed BTM run."
	k := anInt.
	topWords := wordsArray.
	methodNames := names asOrderedCollection.
	methodTopics := topicsDict.
	topicHue := hueArray.
	hueFamilyCount := families
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> topWords [
	^ topWords
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:35'
}
SWATopicData >> writeToFile: aFilePath [
	"Write the JSON form to aFilePath."
	| stream |
	stream := FileStream forceNewFileNamed: aFilePath.
	[stream nextPutAll: self asJsonString] ensure: [stream close].
	^ aFilePath
]
