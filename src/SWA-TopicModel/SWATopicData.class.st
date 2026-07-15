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
		'hueFamilyCount',
		'topicLabels'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData class >> defaultLlmEndpoint [
	"Ollama-compatible /api/generate endpoint used by the topic-labeling stage."
	^ 'http://172.16.64.127:11434/api/generate'
]

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData class >> defaultLlmModel [
	"Local model name (Ollama tag) used by the topic-labeling stage."
	^ 'qwen3.6:latest'
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> asJsonString [
	"Serialise to the reusable, image-independent JSON form (see class comment).
	Method ids are 1-based positions into #methods; JSON object keys are strings.
	'topicLabels' (optional) carries the LLM-produced short labels, one per topic."
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
	(topicLabels notNil and: [topicLabels notEmpty])
		ifTrue: [dict at: 'topicLabels' put: topicLabels asArray].
	^ String streamContents: [:s | dict jsonWriteOn: s]
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:47'
}
SWATopicData >> colorForKey: aCrossRefKey [
	"Self-contained categorical tile color for a METHOD key, mirroring the leaf case of
	SWACodeTreemapMorph>>colorByTopic: but reading straight from this data (no tree-set
	topicData needed). Hue = dominant topic's hue family; brightness encodes the
	dominant topic's weight (confidence). nil when the method has no topic (pruned or
	unknown) so the caller can pick a neutral tile."
	| topic fam dist conf n hue |
	aCrossRefKey ifNil: [^ nil].
	topic := self dominantTopicFor: aCrossRefKey.
	topic ifNil: [^ nil].
	fam := self hueFamilyForTopic: topic.
	fam ifNil: [^ nil].
	n := hueFamilyCount > 0 ifTrue: [hueFamilyCount] ifFalse: [12].
	hue := (fam \\ n) * 360.0 / n.
	dist := self distributionFor: aCrossRefKey.
	conf := dist isEmpty ifTrue: [0.5] ifFalse: [(dist first last) min: 1.0].
	^ Color h: hue s: 0.65 v: (0.55 + (conf * 0.4))
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 11:30'
}
SWATopicData >> colorForTopic: topicId [
	"The full-strength hue-family color for a topic id (the same hue used to tint its
	dominant methods in #colorForKey:), or nil if the topic has no hue family. Used by
	the single-topic focus highlight, which fades THIS color by weight."
	| fam n hue |
	fam := self hueFamilyForTopic: topicId.
	fam ifNil: [^ nil].
	n := hueFamilyCount > 0 ifTrue: [hueFamilyCount] ifFalse: [12].
	hue := (fam \\ n) * 360.0 / n.
	^ Color h: hue s: 0.65 v: 0.95
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> initialize [
	k := 0.
	topWords := Array new: 0.
	methodNames := OrderedCollection new.
	methodTopics := Dictionary new.
	topicHue := Array new: 0.
	hueFamilyCount := 0.
	topicLabels := Array new: 0
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> labelForTopic: topicId [
	"Human-readable label for a topic. Prefer the short LLM-produced label (see the
	labeling stage) when present; otherwise fall back to the joined top words.
	topicId is 0-based."
	| lbl |
	(topicId isNil or: [topicId < 0]) ifTrue: [^ '?'].
	(topicLabels notNil and: [topicId < topicLabels size]) ifTrue: [
		lbl := (topicLabels at: topicId + 1) ifNil: [''].
		lbl := lbl asString withBlanksTrimmed.
		lbl notEmpty ifTrue: [^ lbl]].
	^ self topWordsLabelForTopic: topicId
]

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:49'
}
SWATopicData >> labelTopicsWithLlm [
	"Convenience: label every topic with the default local LLM, no UI, no stop.
	Answers the number of topics labeled."
	^ self
		labelTopicsWithLlmEndpoint: self class defaultLlmEndpoint
		model: self class defaultLlmModel
		progress: nil
		untilStopped: nil
]

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:49'
}
SWATopicData >> labelTopicsWithLlmEndpoint: anEndpoint model: aModel progress: aBlock untilStopped: aStopBlock [
	"Fill #topicLabels by asking the local LLM to name each topic from its top words.
	aBlock is evaluated with (fractionDone, topicId0Based, label) after each topic so
	callers can show progress (mirrors the sweep progressBlock in stage 1). aStopBlock
	answers true to abort early, keeping whatever labels were produced so far.
	Topics that fail to get an LLM label keep nil (so #labelForTopic: falls back to the
	top words). Answers the number of topics actually labeled by the LLM."
	| labels done |
	labels := (topicLabels notNil and: [topicLabels size = k])
		ifTrue: [topicLabels asArray copy]
		ifFalse: [Array new: k withAll: nil].
	done := 0.
	0 to: k - 1 do: [:t |
		| lbl |
		(aStopBlock notNil and: [aStopBlock value])
			ifTrue: [topicLabels := labels. ^ done].
		lbl := self llmLabelForTopic: t endpoint: anEndpoint model: aModel.
		lbl notNil ifTrue: [labels at: t + 1 put: lbl. done := done + 1].
		aBlock notNil ifTrue: [
			aBlock value: (k = 0 ifTrue: [1.0] ifFalse: [(t + 1) / k]) asFloat
				value: t
				value: (lbl ifNil: [self topWordsLabelForTopic: t])]].
	topicLabels := labels.
	^ done
]

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:49'
}
SWATopicData >> llmLabelForTopic: topicId endpoint: anEndpoint model: aModel [
	"Ask the local LLM for a short label for one topic (0-based). POST directly from
	the image via WebClient (Ollama /api/generate). Answer the sanitized label, or
	nil on any failure so the caller can fall back to the top-words label."
	| payload resp json raw |
	payload := String streamContents: [:s |
		(Dictionary new
			at: 'model' put: aModel;
			at: 'prompt' put: (self llmLabelPromptForTopic: topicId);
			at: 'stream' put: false;
			at: 'think' put: false;
			yourself) jsonWriteOn: s].
	[resp := WebClient httpPost: anEndpoint content: payload type: 'application/json'.
	resp isSuccess ifFalse: [^ nil].
	json := Json readFrom: resp content readStream.
	raw := json at: 'response' ifAbsent: [^ nil].
	raw := self sanitizeLabel: raw.
	^ raw isEmpty ifTrue: [nil] ifFalse: [raw]]
		on: Error do: [:e | ^ nil]
]

{
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:49'
}
SWATopicData >> llmLabelPromptForTopic: topicId [
	"The instruction we send the local LLM to name a topic from its top words.
	topicId is 0-based."
	^ 'You are labeling clusters of Smalltalk source-code identifiers.
Given the most representative words for one topic, reply with a SINGLE short label
of one or two words (Title Case), naming the concept. No punctuation, no quotes,
no explanation -- just the label.

Top words: ', (self topWordsLabelForTopic: topicId), '

Label:'
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> loadFromJson: json [
	"Populate from a parsed JSON object (see #asJsonString for the shape)."
	| topicsJson |
	k := json at: 'k' ifAbsent: [0].
	hueFamilyCount := json at: 'hueFamilyCount' ifAbsent: [0].
	topWords := (json at: 'topWords' ifAbsent: [#()])
		collect: [:ws | ws asArray].
	topicHue := (json at: 'topicHue' ifAbsent: [#()]) asArray.
	topicLabels := (json at: 'topicLabels' ifAbsent: [#()]) asArray.
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
	#category : #'llm labeling',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:52'
}
SWATopicData >> sanitizeLabel: aString [
	"Reduce a raw LLM reply to a clean one-or-two-word label: strip whitespace,
	surrounding quotes and trailing punctuation, drop any <think> block, and keep
	at most the first two words."
	| s think ws words |
	s := aString ifNil: [^ ''].
	s := s asString.
	"Drop a leading <think>...</think> block some models emit."
	think := s asLowercase indexOfSubCollection: '</think>'.
	think > 0 ifTrue: [s := s copyFrom: think + 8 to: s size].
	s := s withBlanksTrimmed.
	"Take only the first non-empty line."
	(s indexOf: Character cr) > 0 ifTrue: [s := s copyUpTo: Character cr].
	(s indexOf: Character lf) > 0 ifTrue: [s := s copyUpTo: Character lf].
	"Strip wrapping quotes/backticks."
	s := s copyWithoutAll: (String with: $" with: $` with: $').
	s := s withBlanksTrimmed.
	"Keep at most the first two whitespace-separated words."
	ws := String with: Character space with: Character tab.
	words := s findTokens: ws.
	words := words first: (words size min: 2).
	s := words isEmpty ifTrue: [''] ifFalse: [words fold: [:a :b | a, ' ', b]].
	"Trim trailing punctuation."
	[s notEmpty and: [(#($. $, $: $; $! $?) includes: s last)]]
		whileTrue: [s := s allButLast].
	^ s withBlanksTrimmed
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
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> topWordsLabelForTopic: topicId [
	"The raw top-words label for a topic (its top words joined). topicId is 0-based.
	This is what #labelForTopic: falls back to when there is no LLM label, and what
	the labeling stage feeds to the LLM."
	| words |
	(topicId isNil or: [topicId < 0 or: [topicId >= topWords size]])
		ifTrue: [^ '?'].
	words := topWords at: topicId + 1.
	words isEmpty ifTrue: [^ 'topic ', topicId printString].
	^ words fold: [:a :b | a, ' ', b]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> topicLabels [
	"An Array of short human-readable labels (one per topic, 1-based) produced by
	the LLM labeling stage, or nil/empty if unlabeled. See #labelForTopic:."
	^ topicLabels
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:48'
}
SWATopicData >> topicLabels: anArray [
	"Set the LLM-produced short labels (one per topic, 1-based)."
	topicLabels := anArray
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
