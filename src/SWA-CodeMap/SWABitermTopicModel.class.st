"
Biterm Topic Model (Yan et al. 2013) for the Code Map, implemented in-image.

Unlike LDA, BTM models the whole corpus as a bag of BITERMS (unordered word
pairs co-occurring inside a short document = one method here) rather than per-
document word mixtures. This is robust for short texts, which method sources are.

Pipeline (see #buildFromMethodNodes: / #run):
1. Tokenise each method's source (camelCase-split + Smalltalk stopwords removed).
2. Prune the vocabulary to words with corpus frequency >= minWordFreq.
3. For each method (document) form its biterm set, capped at maxBitermsPerDoc
   (random sample if the method is long) to bound the corpus-wide biterm count.
4. Collapsed Gibbs sampling over the flat biterm bag for the topic assignments,
   maintaining word-topic counts (nWZ), topic totals (nZ) and biterms-per-topic
   (nB).
5. Post-hoc infer each method's topic distribution P(z|d) = sum_b P(z|b)P(b|d).
6. Collapse the k topics into hueFamilyCount hue families by top-word overlap,
   and emit an SWATopicData.

Gibbs update for a biterm (w1,w2):
  P(z) proportional to
    (nB_z + alpha) * (nW1z + beta)(nW2z + beta) / (nZ_z + W*beta)^2

Instance vars:
- k                 number of topics
- alpha beta        Dirichlet hyperparameters (defaults 50/k and 0.01)
- vocab             Array of word Strings (index = wordId)
- wordId            Dictionary word -> 1-based id
- docWords          OrderedCollection of Arrays of wordIds (one per method, pruned)
- biterms           OrderedCollection of {w1id. w2id. topic} triples (topic mutated)
- nWZ               Array (size W) of Arrays (size k): word-topic counts
- nZ                Array (size k): total word slots assigned to each topic
- nB                Array (size k): biterms assigned to each topic
- maxBitermsPerDoc  cap on biterms sampled per method (default 50)
- minWordFreq       vocab pruning floor (default 5)
- topWordCount      words kept per topic for labels (default 10)
- hueFamilyCount    number of hue families to collapse topics into (default 12)
- progressBlock     optional 1-arg block called with a fraction 0..1
- random            Random for sampling
"
Class {
	#name : #SWABitermTopicModel,
	#superclass : #Object,
	#instVars : [
		'k',
		'alpha',
		'beta',
		'vocab',
		'wordId',
		'docWords',
		'biterms',
		'nWZ',
		'nZ',
		'nB',
		'maxBitermsPerDoc',
		'minWordFreq',
		'topWordCount',
		'hueFamilyCount',
		'progressBlock',
		'random',
		'stopwordSet',
		'methodKeysAndSources',
		'methodKeys',
		'docBiterms'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:51'
}
SWABitermTopicModel class >> generateInBackground: aModelBlock label: aLabel k: kTopics sweeps: nSweeps toFile: aFilePath [
	"Shared background runner for the BTM generators (whole-image and per-package),
	mirroring SWACoverage class>>generatePackages:tests:toFile:. aModelBlock answers
	a fresh SWABitermTopicModel with its documents registered (evaluated in the
	background so method harvesting doesn't block the UI either).

	Opens a SWACoverageRunPanel Stop window, forks the corpus build + Gibbs fit +
	JSON write at userBackgroundPriority, updates the status line per phase, honours
	STOP between sweeps (writing the partially-converged model), and auto-closes.
	Headless: runs inline. Returns the file path immediately.

	See #generateInBackground:label:k:sweeps:toFile:thenDo: to chain the LLM
	labeling stage afterwards."
	^ self generateInBackground: aModelBlock label: aLabel k: kTopics sweeps: nSweeps
		toFile: aFilePath thenDo: nil
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:50'
}
SWABitermTopicModel class >> generateInBackground: aModelBlock label: aLabel k: kTopics sweeps: nSweeps toFile: aFilePath thenDo: aContinuationBlock [
	"As #generateInBackground:label:k:sweeps:toFile:, but when the fit finishes
	normally (not stopped, non-empty corpus) evaluate aContinuationBlock afterwards
	-- used to chain the LLM labeling stage. aContinuationBlock runs in the same
	background process, right after the JSON is written and this panel closes, so it
	may open its own progress panel. Pass nil for no continuation."
	| panel work |
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'BTM topics (', aLabel, ') -> ', aFilePath;
		yourself.
	work := [ | model td nDocs nBiterms ran completed |
		completed := false.
		panel status: 'Harvesting methods for ', aLabel, '...'.
		model := aModelBlock value.
		model k: kTopics.
		panel status: 'Building corpus (', model methodKeysAndSources size printString, ' methods)...'.
		nDocs := model buildCorpus.
		nDocs = 0
			ifTrue: [panel finishAndClose: 'Empty corpus after pruning -- nothing written.']
			ifFalse: [
				nBiterms := model buildBiterms.
				model progressBlock: [:frac |
					panel status: aLabel, ': sweep ', (frac * nSweeps) rounded printString,
						'/', nSweeps printString, '  (', nDocs printString, ' methods, ',
						nBiterms printString, ' biterms)'].
				ran := model runSweeps: nSweeps untilStopped: [panel stopRequested].
				panel status: 'Inferring distributions + writing JSON...'.
				td := model asTopicData.
				td writeToFile: aFilePath.
				completed := panel stopRequested not.
				panel finishAndClose: (panel stopRequested
					ifTrue: ['STOPPED after ', ran printString, ' sweeps; wrote ',
						td methodNames size printString, ' methods -> ', aFilePath]
					ifFalse: ['Done. ', ran printString, ' sweeps, ',
						td methodNames size printString, ' methods, k=', kTopics printString,
						' -> ', aFilePath])].
		(completed and: [aContinuationBlock notNil]) ifTrue: [aContinuationBlock value]].
	(Smalltalk at: #World ifAbsent: [nil]) isNil
		ifTrue: [work value. ^ aFilePath].
	work forkAt: Processor userBackgroundPriority.
	^ aFilePath
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:44'
}
SWABitermTopicModel class >> generatePackage: aPackageName k: kTopics sweeps: nSweeps toFile: aFilePath [
	"Fit a BTM over one package and write the SWATopicData JSON to aFilePath.
	Shows a progress bar over the Gibbs sweeps. Returns the file path (or nil if the
	corpus was empty after pruning).

	(SWABitermTopicModel generatePackage: 'Morphic' k: 40 sweeps: 200
		toFile: 'morphic-topics.json')"
	| model td result |
	model := self onPackageNamed: aPackageName.
	model k: kTopics.
	result := nil.
	'BTM on ', aPackageName, ' (k=', kTopics printString, ')'
		displayProgressFrom: 0 to: nSweeps during: [:bar |
			model progressBlock: [:frac | bar value: (frac * nSweeps) rounded].
			bar value: 0.
			td := model buildAndRun: nSweeps.
			result := td ifNil: [nil] ifNotNil: [td writeToFile: aFilePath]].
	^ result
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 12:00'
}
SWABitermTopicModel class >> generatePackageInBackground: aPackageName k: kTopics sweeps: nSweeps toFile: aFilePath [
	"Fit a per-package BTM in the BACKGROUND behind a Stop window (see
	#generateWholeImageInBackgroundK:sweeps:toFile:). Returns immediately.

	(SWABitermTopicModel generatePackageInBackground: 'Morphic' k: 40 sweeps: 200
		toFile: 'morphic-topics.json')"
	^ self generateInBackground: [self onPackageNamed: aPackageName]
		label: aPackageName
		k: kTopics sweeps: nSweeps toFile: aFilePath
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:50'
}
SWABitermTopicModel class >> generatePackageInBackground: aPackageName k: kTopics sweeps: nSweeps toFile: aFilePath thenLabel: labelBoolean [
	"Run the full pipeline for a package: STAGE 1 fits the BTM (own Stop panel), then
	-- if labelBoolean -- STAGE 2 labels the topics with the default local LLM in its
	own Stop panel. Stage 2 is chained AFTER stage 1's background work finishes (so
	the file exists first). Returns the file path immediately.

	(SWABitermTopicModel generatePackageInBackground: 'SqueakXR' k: 20 sweeps: 100
		toFile: 'squeakxr-topics.json' thenLabel: true)"
	labelBoolean ifFalse: [
		^ self generatePackageInBackground: aPackageName k: kTopics sweeps: nSweeps
			toFile: aFilePath].
	^ self
		generateInBackground: [self onPackageNamed: aPackageName]
		label: aPackageName
		k: kTopics sweeps: nSweeps toFile: aFilePath
		thenDo: [self labelTopicsInBackground: aFilePath]
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 12:00'
}
SWABitermTopicModel class >> generateWholeImageInBackgroundK: kTopics sweeps: nSweeps toFile: aFilePath [
	"Fit a whole-image BTM in the BACKGROUND behind a Stop window, exactly like the
	coverage runs (SWACoverage class>>generatePackages:tests:toFile:): opens a
	SWACoverageRunPanel, forks the heavy work at userBackgroundPriority so the UI
	stays live to deliver the Stop click, updates the status line per phase, and
	AUTO-CLOSES when done. Returns immediately (the fit + file write happen in the
	background). Headless (no World): runs inline and returns the path.

	Clicking STOP finishes the current sweep, then still writes the JSON from the
	partially-converged model (usable -- topics stabilise early).

	(SWABitermTopicModel generateWholeImageInBackgroundK: 40 sweeps: 250
		toFile: 'squeak-topics.json')"
	^ self generateInBackground: [self onAllMethods]
		label: 'Whole image'
		k: kTopics sweeps: nSweeps toFile: aFilePath
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:45'
}
SWABitermTopicModel class >> generateWholeImageK: kTopics sweeps: nSweeps toFile: aFilePath [
	"Fit a BTM over EVERY method in the image and write the SWATopicData JSON.
	This is a heavy batch job (hundreds of thousands of methods, millions of capped
	biterms). Run it FORKED via #generateWholeImageInBackgroundK:sweeps:toFile: so
	the UI stays responsive; this synchronous version is for CLI/Workspace use.

	Prunes rare vocabulary (minWordFreq 5) and caps biterms/method (50) by default
	to bound the corpus -- see the class comment. Returns the file path, or nil for
	an empty corpus.

	(SWABitermTopicModel generateWholeImageK: 40 sweeps: 250
		toFile: 'squeak-topics.json')"
	| model td result |
	model := self onAllMethods.
	model k: kTopics.
	result := nil.
	'Whole-image BTM (k=', kTopics printString, ')'
		displayProgressFrom: 0 to: nSweeps during: [:bar |
			bar value: 0.
			model buildCorpus = 0 ifTrue: [^ nil].
			model buildBiterms = 0 ifTrue: [^ nil].
			model progressBlock: [:frac | bar value: (frac * nSweeps) rounded].
			model runSweeps: nSweeps.
			td := model asTopicData.
			result := td writeToFile: aFilePath].
	^ result
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:50'
}
SWABitermTopicModel class >> labelTopicsInBackground: aFilePath [
	"STAGE 2 with the default local LLM endpoint/model. See
	#labelTopicsInBackground:endpoint:model:.

	(SWABitermTopicModel labelTopicsInBackground: 'squeakxr-topics.json')"
	^ self labelTopicsInBackground: aFilePath
		endpoint: SWATopicData defaultLlmEndpoint
		model: SWATopicData defaultLlmModel
]

{
	#category : #generation,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:50'
}
SWABitermTopicModel class >> labelTopicsInBackground: aFilePath endpoint: anEndpoint model: aModel [
	"STAGE 2 of the topic pipeline: load the topics JSON produced by
	#generatePackageInBackground:... , ask a local LLM to give each topic a one/two
	word label, and rewrite the file (now carrying 'topicLabels'). Progress is shown
	in a SWACoverageRunPanel Stop window just like stage 1, one line per topic, and
	STOP keeps whatever labels were produced so far. Headless: runs inline. Returns
	the file path immediately.

	(SWABitermTopicModel labelTopicsInBackground: 'squeakxr-topics.json'
		endpoint: SWATopicData defaultLlmEndpoint model: SWATopicData defaultLlmModel)"
	| panel work |
	panel := SWACoverageRunPanel new
		openInWindowTitled: 'BTM label (', aModel, ') -> ', aFilePath;
		yourself.
	work := [ | data n |
		panel status: 'Loading topics from ', aFilePath, '...'.
		data := SWATopicData new loadFromFile: aFilePath.
		n := data k.
		panel status: 'Labeling ', n printString, ' topics with ', aModel, '...'.
		data
			labelTopicsWithLlmEndpoint: anEndpoint
			model: aModel
			progress: [:frac :tid :lbl |
				panel status: aModel, ': topic ', (tid + 1) printString, '/', n printString,
					'  "', lbl, '"']
			untilStopped: [panel stopRequested].
		data writeToFile: aFilePath.
		panel finishAndClose: (panel stopRequested
			ifTrue: ['STOPPED; wrote partial labels -> ', aFilePath]
			ifFalse: ['Done. Labeled ', n printString, ' topics -> ', aFilePath])].
	(Smalltalk at: #World ifAbsent: [nil]) isNil
		ifTrue: [work value. ^ aFilePath].
	work forkAt: Processor userBackgroundPriority.
	^ aFilePath
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:40'
}
SWABitermTopicModel class >> onAllMethods [
	"Model over EVERY compiled method in the image, keyed by 'ClassName>>selector'
	('ClassName class>>selector' for class-side). Whole-image scope: expect a large
	corpus -- run forked behind a Stop panel and persist the JSON."
	| model |
	model := self new.
	Smalltalk allClassesAndTraits do: [:cls |
		#(instance class) do: [:side |
			| behavior prefix |
			behavior := side = #instance ifTrue: [cls] ifFalse: [cls class].
			prefix := side = #instance
				ifTrue: [cls name asString]
				ifFalse: [cls name asString, ' class'].
			behavior selectorsAndMethodsDo: [:sel :cm |
				| src |
				src := [behavior sourceCodeAt: sel] on: Error do: [:e | nil].
				(src notNil and: [src notEmpty])
					ifTrue: [model addMethodKey: prefix, '>>', sel source: src asString]]]].
	^ model
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:40'
}
SWABitermTopicModel class >> onMethodNodes: aCollectionOfMethodNodes [
	"Create a model with each SWACodeMethodNode registered as a document
	(crossRefKey -> source). Skips nodes with nil key or empty source."
	| model |
	model := self new.
	aCollectionOfMethodNodes do: [:node |
		| key src |
		key := node crossRefKey.
		src := node sourceString.
		(key notNil and: [src notNil and: [src notEmpty]])
			ifTrue: [model addMethodKey: key source: src]].
	^ model
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:40'
}
SWABitermTopicModel class >> onPackageNamed: aPackageName [
	"Model over all method leaves in one package (via the CodeMap node model)."
	^ self onMethodNodes: (SWACodeSimilarity new methodNodesInPackage: aPackageName)
]

{
	#category : #corpus,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> addMethodKey: aKey source: aSourceString [
	"Register one method document (crossRefKey + its source). Deferred tokenization
	happens in #buildCorpus so we can prune vocabulary across the whole corpus."
	self methodKeysAndSources add: aKey -> aSourceString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> alpha [
	"Default topic-Dirichlet hyperparameter 50/k if not set explicitly."
	^ alpha ifNil: [alpha := 50.0 / k]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> asTopicData [
	"Assemble the fitted model into an SWATopicData: top words per topic, hue-family
	map, and each method's sparse topic distribution keyed by crossRefKey."
	| topWordsArr hueArr methodTopics td |
	topWordsArr := (1 to: k) collect: [:t | self topWordsForTopic: t].
	hueArr := self hueFamiliesForTopWords: topWordsArr.
	methodTopics := Dictionary new.
	docWords doWithIndex: [:ids :di |
		| dist sparse |
		dist := self topicDistributionForDoc: di.
		sparse := self sparseDistribution: dist.
		methodTopics at: (methodKeys at: di) put: sparse].
	td := SWATopicData new.
	td setK: k
		topWords: topWordsArr asArray
		methodNames: methodKeys
		methodTopics: methodTopics
		topicHue: hueArr
		hueFamilyCount: hueFamilyCount.
	^ td
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> assignFamilies: activeGroups [
	"Turn the list of topic groups into a per-topic (1-based) family index array
	(0-based family ids)."
	| fam |
	fam := Array new: k withAll: 0.
	activeGroups doWithIndex: [:group :fi |
		group do: [:topic | fam at: topic put: fi - 1]].
	^ fam
]

{
	#category : #corpus,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> bitermPairsFor: idArray [
	"All unordered distinct-position word pairs in a document, capped at
	maxBitermsPerDoc. For short docs, enumerate all; for long docs, sample pairs
	by picking two distinct positions at random (with replacement across draws)."
	| n pairs total |
	n := idArray size.
	total := n * (n - 1) // 2.
	total <= maxBitermsPerDoc
		ifTrue: [
			pairs := OrderedCollection new: total.
			1 to: n - 1 do: [:i |
				i + 1 to: n do: [:j |
					pairs add: (Array with: (idArray at: i) with: (idArray at: j))]].
			^ pairs].
	pairs := OrderedCollection new: maxBitermsPerDoc.
	maxBitermsPerDoc timesRepeat: [
		| i j |
		i := random nextInt: n.
		j := random nextInt: n.
		[i = j] whileTrue: [j := random nextInt: n].
		pairs add: (Array with: (idArray at: i) with: (idArray at: j))].
	^ pairs
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> buildAndRun: nSweeps [
	"Full pipeline given already-registered method documents: build corpus, form
	biterms, run Gibbs, and answer the resulting SWATopicData. Answers nil if the
	corpus is empty after pruning."
	self buildCorpus = 0 ifTrue: [^ nil].
	self buildBiterms = 0 ifTrue: [^ nil].
	self runSweeps: nSweeps.
	^ self asTopicData
]

{
	#category : #corpus,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> buildBiterms [
	"Form the flat biterm bag from the pruned docs. Each biterm is an unordered
	word pair {w1id. w2id. topic} co-occurring in a method. If a method yields more
	than maxBitermsPerDoc pairs, sample that many at random (bound corpus size).
	docBiterms records, per document, the index range of its biterms (for post-hoc
	P(z|d) inference)."
	biterms := OrderedCollection new.
	docBiterms := OrderedCollection new.
	docWords doWithIndex: [:ids :di |
		| pairs start |
		start := biterms size + 1.
		pairs := self bitermPairsFor: ids.
		pairs do: [:pair |
			biterms add: (Array with: pair first with: pair last with: 0)].
		docBiterms add: (start to: biterms size)].
	^ biterms size
]

{
	#category : #corpus,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> buildCorpus [
	"Two-pass corpus build over the registered method documents:
	 pass 1: tokenise, count corpus word frequency;
	 prune: keep words with freq >= minWordFreq, assign 1-based wordIds;
	 pass 2: map each doc to an Array of kept wordIds (drop empty docs)."
	| freq tokenized |
	freq := Dictionary new.
	tokenized := OrderedCollection new.
	self methodKeysAndSources do: [:assoc |
		| ws |
		ws := self wordsFor: assoc value.
		tokenized add: (assoc key -> ws).
		ws do: [:w | freq at: w put: (freq at: w ifAbsent: [0]) + 1]].
	"Prune + assign ids."
	vocab := OrderedCollection new.
	wordId := Dictionary new.
	(freq associations asSortedCollection: [:a :b | a value >= b value]) do: [:a |
		a value >= minWordFreq ifTrue: [
			vocab add: a key.
			wordId at: a key put: vocab size]].
	"Pass 2: pruned docs as wordId arrays, keeping only docs with >= 2 kept words
	(a biterm needs two)."
	docWords := OrderedCollection new.
	methodKeys := OrderedCollection new.
	tokenized do: [:assoc |
		| ids |
		ids := OrderedCollection new.
		assoc value do: [:w |
			(wordId at: w ifAbsent: [nil]) ifNotNil: [:id | ids add: id]].
		ids size >= 2 ifTrue: [
			docWords add: ids asArray.
			methodKeys add: assoc key]].
	^ docWords size
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> groupSim: groupA with: groupB sets: sets [
	"Average pairwise Jaccard between the top-word sets of two topic groups."
	| total n |
	total := 0.0. n := 0.
	groupA do: [:ta |
		groupB do: [:tb |
			| sa sb inter uni |
			sa := sets at: ta. sb := sets at: tb.
			inter := (sa intersection: sb) size.
			uni := (sa size + sb size - inter) max: 1.
			total := total + (inter / uni).
			n := n + 1]].
	^ n = 0 ifTrue: [0.0] ifFalse: [total / n]
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> hueFamiliesForTopWords: topWordsArray [
	"Greedy agglomeration of the k topics into hueFamilyCount families by top-word
	overlap (Jaccard on top-word sets). Returns an Array (size k, 1-based) of family
	indices 0..hueFamilyCount-1. Simple greedy: start each topic its own family,
	repeatedly merge the closest pair until hueFamilyCount families remain."
	| sets families active |
	sets := topWordsArray collect: [:ws | Set withAll: ws].
	families := (1 to: k) collect: [:i | OrderedCollection with: i].
	active := families asOrderedCollection.
	[active size > hueFamilyCount] whileTrue: [
		| bestA bestB bestSim |
		bestSim := -1.0. bestA := nil. bestB := nil.
		1 to: active size - 1 do: [:ia |
			ia + 1 to: active size do: [:ib |
				| sim |
				sim := self groupSim: (active at: ia) with: (active at: ib) sets: sets.
				sim > bestSim ifTrue: [bestSim := sim. bestA := ia. bestB := ib]]].
		bestB ifNil: [^ self assignFamilies: active].
		(active at: bestA) addAll: (active at: bestB).
		active removeIndex: bestB].
	^ self assignFamilies: active
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> hueFamilyCount: anInt [
	hueFamilyCount := anInt
]

{
	#category : #tokenizing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> identifierRunsIn: aString [
	"Runs of letter/digit/underscore/colon = identifier or keyword-selector tokens.
	Mirrors SWACodeSimilarity>>tokensFor: but keeps only the identifier-like runs
	(operators and single punctuation are discarded for topic modeling)."
	| runs stream |
	runs := OrderedCollection new.
	stream := ReadStream on: aString.
	[stream atEnd] whileFalse: [
		| c |
		c := stream next.
		(c isLetter or: [c isDigit or: [c = $_ or: [c = $:]]])
			ifTrue: [
				| word |
				word := WriteStream on: String new.
				word nextPut: c.
				[stream atEnd not and: [
					(stream peek isLetter or: [stream peek isDigit
						or: [stream peek = $_ or: [stream peek = $:]]])]]
					whileTrue: [word nextPut: stream next].
				runs add: word contents]].
	^ runs
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 12:17'
}
SWABitermTopicModel >> initCounts [
	"Random topic init (1-based) for every biterm, building nWZ (word x topic),
	nZ (topic word-slot totals) and nB (biterms per topic).

	Counts are stored as FLOATS in FloatArrays. Integer counts <= 2^53 are exact in
	a double, so this is lossless, and it lets the hot sweep loop run PURE float
	arithmetic (no per-element SmallInteger->Float coercion, which was the real cost),
	fetching unboxed operands from primitive FloatArrays."
	| w |
	w := vocab size.
	nWZ := Array new: w.
	1 to: w do: [:i | nWZ at: i put: (FloatArray new: k)].
	nZ := FloatArray new: k.
	nB := FloatArray new: k.
	biterms do: [:bt |
		| z w1 w2 |
		z := random nextInt: k.
		bt at: 3 put: z.
		w1 := bt at: 1. w2 := bt at: 2.
		(nWZ at: w1) at: z put: ((nWZ at: w1) at: z) + 1.0.
		(nWZ at: w2) at: z put: ((nWZ at: w2) at: z) + 1.0.
		nZ at: z put: (nZ at: z) + 2.0.
		nB at: z put: (nB at: z) + 1.0]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> initialize [
	k := 40.
	beta := 0.01.
	maxBitermsPerDoc := 50.
	minWordFreq := 5.
	topWordCount := 10.
	hueFamilyCount := 12.
	docWords := OrderedCollection new.
	biterms := OrderedCollection new.
	vocab := OrderedCollection new.
	wordId := Dictionary new.
	random := Random new
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> k [
	^ k
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> k: anInt [
	k := anInt
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> maxBitermsPerDoc: anInt [
	maxBitermsPerDoc := anInt
]

{
	#category : #corpus,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> methodKeysAndSources [
	"Subclass/accessor hook: an OrderedCollection of Associations
	crossRefKey -> sourceString. Set by #buildFromMethodNodes:."
	^ methodKeysAndSources ifNil: [methodKeysAndSources := OrderedCollection new]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> minWordFreq: anInt [
	minWordFreq := anInt
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> phiForTopic: t [
	"P(w|z=t) as an Array over the vocabulary (1-based topic t)."
	| w wBeta denom phi |
	w := vocab size.
	wBeta := w * beta.
	denom := (nZ at: t) + wBeta.
	phi := Array new: w.
	1 to: w do: [:i |
		phi at: i put: (((nWZ at: i) at: t) + beta) / denom].
	^ phi
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:36'
}
SWABitermTopicModel >> progressBlock: aBlock [
	"A 1-arg block called with fraction 0..1 during sweeps (optional)."
	progressBlock := aBlock
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> runSweeps: nSweeps [
	"Initialise counts and run nSweeps Gibbs passes, reporting progress."
	self initCounts.
	1 to: nSweeps do: [:s |
		self sweep.
		progressBlock ifNotNil: [progressBlock value: s / nSweeps]]
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 12:00'
}
SWABitermTopicModel >> runSweeps: nSweeps untilStopped: aStopBlock [
	"Initialise counts and run up to nSweeps Gibbs passes, reporting progress and
	checking aStopBlock (a 0-arg block answering true to abort) BETWEEN sweeps so a
	Stop button can interrupt a long fit cleanly. Answers the number of sweeps
	actually run (< nSweeps if stopped early)."
	| done |
	self initCounts.
	done := 0.
	1 to: nSweeps do: [:s |
		(aStopBlock value) ifTrue: [^ done].
		self sweep.
		done := s.
		progressBlock ifNotNil: [progressBlock value: s / nSweeps]].
	^ done
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> sparseDistribution: distArray [
	"Convert a full topic distribution (1-based Array) into a sparse, weight-sorted
	Array of {topicId(0-based). weight} pairs, keeping topics with weight >= 0.05,
	always at least the argmax. Weights rounded to 4 places for compact JSON."
	| pairs |
	pairs := OrderedCollection new.
	distArray doWithIndex: [:wgt :t |
		wgt >= 0.05 ifTrue: [
			pairs add: (Array with: t - 1 with: ((wgt * 10000) rounded / 10000.0))]].
	pairs isEmpty ifTrue: [
		| maxT maxV |
		maxV := -1.0. maxT := 1.
		distArray doWithIndex: [:wgt :t | wgt > maxV ifTrue: [maxV := wgt. maxT := t]].
		pairs add: (Array with: maxT - 1 with: ((maxV * 10000) rounded / 10000.0))].
	^ (pairs asSortedCollection: [:a :b | a last >= b last]) asArray
]

{
	#category : #tokenizing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> splitCamelCase: aWord [
	"Split a camelCase / keyword identifier into lower-cased parts.
	'drawTileContent' -> ('draw' 'tile' 'content'); digits break runs too.
	Underscores and colons are treated as separators upstream, but be safe."
	| parts cur prev |
	parts := OrderedCollection new.
	cur := WriteStream on: String new.
	prev := nil.
	aWord do: [:ch |
		(ch = $_ or: [ch = $:])
			ifTrue: [
				cur contents isEmpty ifFalse: [parts add: cur contents].
				cur := WriteStream on: String new]
			ifFalse: [
				(prev notNil and: [prev isLowercase and: [ch isUppercase]])
					ifTrue: [
						cur contents isEmpty ifFalse: [parts add: cur contents].
						cur := WriteStream on: String new].
				cur nextPut: ch asLowercase].
		prev := ch].
	cur contents isEmpty ifFalse: [parts add: cur contents].
	^ parts
]

{
	#category : #tokenizing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> stopwords [
	"Smalltalk syntactic noise + generic English glue that carries no topic signal.
	Lower-cased; the word list is compared after down-casing camelCase parts."
	^ stopwordSet ifNil: [stopwordSet := Set withAll: #(
		'self' 'super' 'thiscontext' 'true' 'false' 'nil' 'yourself'
		'iftrue' 'iffalse' 'ifnil' 'ifnotnil' 'ifempty' 'ifnotempty'
		'ifabsent' 'ifpresent' 'and' 'or' 'not' 'whiletrue' 'whilefalse'
		'do' 'collect' 'select' 'reject' 'detect' 'inject' 'into' 'with'
		'at' 'put' 'add' 'new' 'value' 'size' 'is' 'as' 'to' 'of' 'the'
		'a' 'an' 'in' 'on' 'for' 'from' 'by' 'if' 'then' 'else' 'each'
		'i' 'j' 'n' 'x' 'y' 'z' 'e' 'c' 's' 'ablock' 'astring' 'anobject'
		'error' 'assert' 'should' 'return' 'get' 'set' )]
]

{
	#category : #sampling,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 12:17'
}
SWABitermTopicModel >> sweep [
	"One collapsed-Gibbs pass over all biterms. Topics are 1-based internally.
	For biterm (w1,w2): remove it, then draw z with
	  P(z) ~ (nB_z + alpha) * (nW1z + beta)(nW2z + beta) / (nZ_z + W*beta + 1)^2
	and re-add.

	Hot-loop optimizations:
	- ALL counts (nB/nZ/nWZ) and float scratch (invDenom/p) are FloatArrays, so the
	  inner loop is PURE double arithmetic on unboxed, primitive-backed slots -- no
	  per-element integer->float coercion (which dominated the boxed-Array version).
	- The per-topic denominator (nZ_t + W*beta)^-2 is cached in invDenom and updated
	  incrementally (only the two touched topics change per biterm)."
	| a p invDenom wBeta bt |
	wBeta := (vocab size * beta) asFloat.
	a := self alpha asFloat.
	p := FloatArray new: k.
	invDenom := FloatArray new: k.
	1 to: k do: [:t | | d | d := (nZ at: t) + wBeta. invDenom at: t put: 1.0 / (d * d)].
	1 to: biterms size do: [:bi |
		| z w1 w2 nw1 nw2 sum r cum pick d |
		bt := biterms at: bi.
		z := bt at: 3.
		w1 := bt at: 1. w2 := bt at: 2.
		nw1 := nWZ at: w1. nw2 := nWZ at: w2.
		"remove current assignment"
		nw1 at: z put: (nw1 at: z) - 1.0.
		nw2 at: z put: (nw2 at: z) - 1.0.
		nZ at: z put: (nZ at: z) - 2.0.
		nB at: z put: (nB at: z) - 1.0.
		d := (nZ at: z) + wBeta. invDenom at: z put: 1.0 / (d * d).
		"unnormalised cumulative P(z) -- pure float"
		sum := 0.0.
		1 to: k do: [:t |
			sum := sum + (((nB at: t) + a)
				* ((nw1 at: t) + beta) * ((nw2 at: t) + beta)
				* (invDenom at: t)).
			p at: t put: sum].
		"sample"
		r := random next * sum.
		cum := 1.
		[cum < k and: [(p at: cum) < r]] whileTrue: [cum := cum + 1].
		pick := cum.
		"re-add"
		bt at: 3 put: pick.
		nw1 at: pick put: (nw1 at: pick) + 1.0.
		nw2 at: pick put: (nw2 at: pick) + 1.0.
		nZ at: pick put: (nZ at: pick) + 2.0.
		nB at: pick put: (nB at: pick) + 1.0.
		d := (nZ at: pick) + wBeta. invDenom at: pick put: 1.0 / (d * d)]
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> thetaGlobal [
	"Corpus-level P(z) as an Array over topics (1-based), from biterm-topic counts."
	| totalB theta |
	totalB := biterms size.
	theta := Array new: k.
	1 to: k do: [:t |
		theta at: t put: ((nB at: t) + self alpha) / (totalB + (k * self alpha))].
	^ theta
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:39'
}
SWABitermTopicModel >> topWordsForTopic: t [
	"The topWordCount highest-phi words for topic t (1-based) as an Array of Strings."
	| phi idx |
	phi := self phiForTopic: t.
	idx := (1 to: vocab size) asOrderedCollection.
	idx := idx asSortedCollection: [:a :b | (phi at: a) >= (phi at: b)].
	^ ((idx first: (topWordCount min: idx size)) collect: [:i | vocab at: i]) asArray
]

{
	#category : #inference,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:38'
}
SWABitermTopicModel >> topicDistributionForDoc: di [
	"Post-hoc P(z|d) for document index di:
	  P(z|d) = sum over biterms b in d of P(z|b) * P(b|d),
	with P(b|d) uniform over the doc's biterms and
	  P(z|b) ~ theta_z * phi_{w1|z} * phi_{w2|z}.
	Returns a normalised Array over topics (1-based)."
	| range dist theta nb |
	range := docBiterms at: di.
	dist := Array new: k withAll: 0.0.
	range isEmpty ifTrue: [^ dist].
	theta := self thetaGlobal.
	nb := range size.
	range do: [:bi |
		| bt w1 w2 pz sum |
		bt := biterms at: bi.
		w1 := bt at: 1. w2 := bt at: 2.
		pz := Array new: k.
		sum := 0.0.
		1 to: k do: [:t |
			| denom v |
			denom := (nZ at: t) + (vocab size * beta).
			v := (theta at: t)
				* (((nWZ at: w1) at: t) + beta)
				* (((nWZ at: w2) at: t) + beta)
				/ (denom * denom).
			pz at: t put: v.
			sum := sum + v].
		1 to: k do: [:t |
			dist at: t put: (dist at: t) + ((pz at: t) / sum / nb)]].
	^ dist
]

{
	#category : #tokenizing,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:37'
}
SWABitermTopicModel >> wordsFor: aSourceString [
	"Full document tokenization: identifier tokens split on camelCase, lower-cased,
	stopwords and length<3 parts dropped. Binary operators / brackets are ignored
	(only letter/digit runs matter for topics). Returns an Array of word Strings."
	| words sep |
	words := OrderedCollection new.
	sep := self stopwords.
	(self identifierRunsIn: aSourceString) do: [:run |
		(self splitCamelCase: run) do: [:part |
			(part size >= 3 and: [(sep includes: part) not
				and: [part first isDigit not]])
					ifTrue: [words add: part]]].
	^ words asArray
]
