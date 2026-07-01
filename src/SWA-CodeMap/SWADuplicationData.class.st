"
Image-independent, persistable result of a code-duplication (near-clone) scan, the offline counterpart to SWADuplicationData generation what SWACoverageData is for coverage.

A duplication scan over a set of packages is expensive (inverted-shingle Jaccard over all eligible method leaves). This class lets you GENERATE the result once -- in a Workspace or headless from the CLI -- and persist it to a JSON file, then LOAD it later into a Code Map (SWACodeTreemapMorph) instead of recomputing.

State (all image-independent; methods are matched by 'Class>>selector' crossRefKey strings against whatever image loads the data):
  methodNames  -- OrderedCollection of crossRefKey strings (the id table)
  methodIds    -- reverse lookup crossRefKey -> 1-based id
  matches      -- Dictionary methodId -> Array of (scoreFloat -> partnerId), best-first
  locs         -- Dictionary methodId -> lines-of-code (so partner LOC is known even
                  when the partner method is not present in the loaded tree, which the
                  shared-LOC link width needs)
  params       -- Dictionary of the scan parameters (k, threshold, minLoc) used, for the record

JSON form (see #asJsonString):
  { #format: 'SWADuplicationData/1',
    #params: { k:N, threshold:F, minLoc:N },
    #methods: [ crossRefKey, ... ],
    #locs: { methodId(string): N },
    #pairs: { methodId(string): [ [score, partnerId], ... ] } }

Generate:
  SWADuplicationData generatePackages: #('Morphic*') toFile: 'morphic-dup.json'.
Load (into an open Code Map via the nav panel's import button), or programmatically:
  data := SWADuplicationData fromFile: 'morphic-dup.json'.
  treemap loadDuplicationData: data.
"
Class {
	#name : #SWADuplicationData,
	#superclass : #Object,
	#instVars : [
		'methodNames',
		'methodIds',
		'matches',
		'locs',
		'params'
	],
	#category : #'SWA-CodeMap-Duplication',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> defaultListFloor [
	"Minimum Jaccard score for a match to be recorded. Mirrors
	SWACodeTreemapMorph>>dupListFloor so offline-generated data is identical to a
	live computeDuplicationScores."
	^ 0.5
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> defaultMinLoc [
	"Minimum non-blank LOC for a method to take part. Mirrors
	SWACodeTreemapMorph>>dupMinLoc."
	^ 4
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> defaultSimilarity [
	"The shingle/Jaccard engine with the same parameters the live Code Map uses
	(k=4, threshold 0 so every candidate gets a score; the list floor does the
	cutoff). Mirrors SWACodeTreemapMorph>>dupSimilarity."
	^ SWACodeSimilarity new k: 4; threshold: 0.0; yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:40'
}
SWADuplicationData class >> fromFile: aFilePath [
	"Reconstruct from a JSON file written by #writeToFile:."
	| contents |
	contents := (FileStream readOnlyFileNamed: aFilePath) contentsOfEntireFile.
	^ self fromJsonString: contents
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:40'
}
SWADuplicationData class >> fromJsonString: aJsonString [
	"Reconstruct from the JSON form written by #asJsonString. Image-independent:
	method names are matched by 'Class>>selector' against whatever image loads them."
	| json data |
	json := Json readFrom: aJsonString readStream.
	data := self new.
	data loadFromJson: json.
	^ data
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> generatePackages: aGlobArray [
	"Build (in memory) the duplication scan for the given package globs, using the
	same parameters as the live Code Map. Shows a progress bar. Returns a
	SWADuplicationData; persist with #writeToFile: or use #generatePackages:toFile:."
	| data nodes |
	data := self new.
	nodes := self methodNodesForPackages: aGlobArray.
	'Duplication analysis' displayProgressFrom: 0 to: 1 during: [:bar |
		data
			buildFromMethodNodes: nodes
			similarity: self defaultSimilarity
			floor: self defaultListFloor
			minLoc: self defaultMinLoc
			progress: [:msg | bar value: msg]].
	^ data
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> generatePackages: aGlobArray toFile: aFilePath [
	"Offline duplication generation, the counterpart to
	SWACoverage class>>generatePackages:tests:toFile:. Runs the inverted-shingle
	Jaccard scan over every eligible method leaf in the matching packages and
	writes the reusable, image-independent JSON to aFilePath. Load it later into a
	Code Map (nav panel 'Load dup' button, or treemap loadDuplicationData:) instead
	of paying the scan cost interactively.

	  SWADuplicationData
	    generatePackages: #('Morphic*')
	    toFile: 'morphic-dup.json'."
	| data |
	data := self generatePackages: aGlobArray.
	data writeToFile: aFilePath.
	^ data
]

{
	#category : #generating,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:41'
}
SWADuplicationData class >> methodNodesForPackages: aGlobArray [
	"All SWACodeMethodNode leaves under the packages matching any glob in
	aGlobArray (e.g. #('Morphic*' 'Collections-*')), built via the SWACodeMap node
	model -- exactly the leaves a Code Map opened on those packages would show, so
	the offline scan matches the live one."
	| root leaves collect |
	root := SWACodeRootNode new.
	aGlobArray do: [:glob | root addPackages: glob].
	root name: (aGlobArray fold: [:a :b | a, ',', b]).
	leaves := OrderedCollection new.
	collect := nil.
	collect := [:node |
		(node isKindOf: SWACodeMethodNode)
			ifTrue: [leaves add: node]
			ifFalse: [node children do: collect]].
	collect value: root.
	^ leaves
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> asJsonString [
	"Serialise to the reusable, image-independent JSON form:
	{ #format, #params:{k,threshold,minLoc}, #methods:[crossRefKeys],
	  #locs:{ methodId(string): loc }, #pairs:{ methodId(string): [[score, partnerId], ...] } }.
	Method ids are 1-based positions into #methods. JSON object keys must be
	strings, so id keys are printed as strings."
	| pairs locDict dict |
	pairs := Dictionary new.
	matches keysAndValuesDo: [:id :ms |
		pairs at: id printString put: (ms collect: [:assoc | { assoc key. assoc value }])].
	locDict := Dictionary new.
	locs keysAndValuesDo: [:id :loc | locDict at: id printString put: loc].
	dict := Dictionary new
		at: 'format' put: 'SWADuplicationData/1';
		at: 'params' put: params;
		at: 'methods' put: methodNames asArray;
		at: 'locs' put: locDict;
		at: 'pairs' put: pairs;
		yourself.
	^ String streamContents: [:s | dict jsonWriteOn: s]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:40'
}
SWADuplicationData >> buildFromMethodNodes: methodNodes similarity: sim floor: floor minLoc: minLoc progress: aProgressBlockOrNil [
	"Run the inverted-shingle Jaccard scan over methodNodes and record the result.
	This is the same EXACT (not approximate) algorithm as
	SWACodeTreemapMorph>>computeDuplicationScores -- an inverted shingle index so
	only candidate pairs sharing >= 1 k-gram are compared -- factored out here so it
	can run offline (Workspace / headless) without a morph.

	floor   = minimum Jaccard score to record a match (SWACodeTreemapMorph dupListFloor),
	minLoc  = minimum non-blank LOC for a method to take part (dupMinLoc).
	aProgressBlockOrNil, if non-nil, is sent value: aFractionOrString for progress.

	Records params, every eligible method's LOC, and its best-first match list."
	| leaves n shingles index |
	params := Dictionary new
		at: 'k' put: sim k;
		at: 'threshold' put: floor;
		at: 'minLoc' put: minLoc;
		yourself.
	leaves := (methodNodes reject: [:m | m loc < minLoc]) asArray.
	n := leaves size.
	n = 0 ifTrue: [^ self].
	"--- shingle + inverted index ---"
	aProgressBlockOrNil ifNotNil: [:b | b value: 'Shingling ', n printString, ' methods...'].
	index := Dictionary new.
	shingles := Array new: n.
	1 to: n do: [:i |
		| s |
		s := sim shinglesFor: (leaves at: i) sourceString.
		shingles at: i put: s.
		s do: [:sh | (index at: sh ifAbsentPut: [OrderedCollection new]) add: i]].
	"--- candidate compare ---"
	1 to: n do: [:i |
		| si cands ms |
		si := shingles at: i.
		ms := OrderedCollection new.
		si isEmpty ifFalse: [
			cands := Set new.
			si do: [:sh | (index at: sh) do: [:j | j ~= i ifTrue: [cands add: j]]].
			cands do: [:j |
				| sc |
				sc := (sim jaccardBetween: si and: (shingles at: j)) asFloat.
				sc >= floor ifTrue: [ms add: sc -> (leaves at: j) crossRefKey]]].
		ms := ms asSortedCollection: [:a :b | a key >= b key].
		self recordMatchesForKey: (leaves at: i) crossRefKey
			loc: (leaves at: i) loc
			matches: ms asArray.
		(aProgressBlockOrNil notNil and: [i \\ 25 = 0]) ifTrue: [
			aProgressBlockOrNil value: 'Comparing ', i printString, ' / ', n printString]]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> initialize [
	methodNames := OrderedCollection new.
	methodIds := Dictionary new.
	matches := Dictionary new.
	locs := Dictionary new.
	params := Dictionary new
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:40'
}
SWADuplicationData >> loadFromJson: json [
	"Populate from a parsed JSON object (see #asJsonString for the shape)."
	| pairs locDict |
	params := (json at: 'params' ifAbsent: [Dictionary new]).
	methodNames := (json at: 'methods' ifAbsent: [#()]) asOrderedCollection.
	methodIds := Dictionary new.
	methodNames doWithIndex: [:nm :i | methodIds at: nm put: i].
	locs := Dictionary new.
	locDict := json at: 'locs' ifAbsent: [Dictionary new].
	locDict keysAndValuesDo: [:idStr :loc | locs at: idStr asNumber put: loc].
	matches := Dictionary new.
	pairs := json at: 'pairs' ifAbsent: [Dictionary new].
	pairs keysAndValuesDo: [:idStr :ms |
		matches at: idStr asNumber put: (ms collect: [:pair |
			(pair at: 1) asFloat -> (pair at: 2)])]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> locForKey: aCrossRefKey [
	"Recorded lines-of-code for a method crossRefKey, or 0 if unknown. Used so a
	partner that is NOT present in the loaded tree still has a LOC for the
	shared-duplicated-lines link-width estimate."
	| id |
	id := methodIds at: aCrossRefKey ifAbsent: [^ 0].
	^ locs at: id ifAbsent: [0]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> matchedMethodCount [
	"How many methods have at least one near-duplicate partner."
	^ matches values count: [:m | m notEmpty]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> matchesByKeyDo: aBlock [
	"Evaluate aBlock with (methodCrossRefKey, matchesArray) for every method that
	has recorded matches, where matchesArray is an Array of
	(scoreFloat -> partnerCrossRefKey) associations, best-first."
	matches keysAndValuesDo: [:id :ms |
		aBlock
			value: (methodNames at: id)
			value: (ms collect: [:assoc | assoc key -> (methodNames at: assoc value)])]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADuplicationData >> matchesForKey: aCrossRefKey [
	"Answer the recorded matches for a method crossRefKey as an Array of
	(scoreFloat -> partnerCrossRefKey) associations, best-first, or an empty Array
	if none. Non-mutating (unlike #methodIdFor:)."
	| id ms |
	id := methodIds at: aCrossRefKey ifAbsent: [^ #()].
	ms := matches at: id ifAbsent: [^ #()].
	^ ms collect: [:assoc | assoc key -> (methodNames at: assoc value)]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> methodIdFor: aCrossRefKey [
	"1-based id for a method crossRefKey, registering it on first sight."
	^ methodIds at: aCrossRefKey ifAbsentPut: [
		methodNames add: aCrossRefKey.
		methodNames size]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> methodNames [
	^ methodNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> params [
	^ params
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:39'
}
SWADuplicationData >> recordMatchesForKey: aCrossRefKey loc: anInteger matches: anArrayOfScorePartnerKeyAssocs [
	"Record the (best-first) near-duplicate matches for one method. matches is an
	Array of (scoreFloat -> partnerCrossRefKey) associations. Partner keys are
	registered too so #methodNames is complete and partner LOC can be looked up."
	| id |
	id := self methodIdFor: aCrossRefKey.
	locs at: id put: anInteger.
	matches at: id put: (anArrayOfScorePartnerKeyAssocs collect: [:assoc |
		assoc key -> (self methodIdFor: assoc value)])
]

{
	#category : #persistence,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:40'
}
SWADuplicationData >> writeToFile: aFilePath [
	"Write the reusable JSON form to a file (overwriting)."
	| f |
	f := FileStream forceNewFileNamed: aFilePath.
	[f nextPutAll: self asJsonString] ensure: [f close].
	^ aFilePath
]
