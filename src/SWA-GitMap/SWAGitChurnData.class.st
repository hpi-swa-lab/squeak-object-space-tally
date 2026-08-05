"
Per-method GIT CHURN, keyed by crossRefKey ('Class>>selector', 'Class class>>selector'),
so a repository's history can be projected onto ANY other SWA view -- above all the
Code Map.

This is the point of the whole exercise. The Git Map answers ""what did these commits
change?"" laid out by TIME. Fold that same scan down to one record per method and you
can answer it laid out by CODE STRUCTURE instead: which classes are churning, which
have not been touched in months, how many hands each method has been through -- drawn
on the structural map you already read, and mixable with coverage, duplication and
space data through the ordinary SWADataset algebra.

Each entry is a Dictionary with
	#commits  -- how many commits in the scanned window touched this method
	#churn    -- total changed lines across those commits
	#last     -- seconds (TimeStamp asSeconds) of the most recent change
	#first    -- seconds of the earliest change in the window
	#authors  -- Set of author names
	#lastOp   -- #added / #modified / #removed, from the most recent commit

Build one from an already-built git tree (cheap -- it is a fold, no new git work):

	| root data |
	root := (SWAGitHistory onWorkingCopyNamed: 'squeak-object-space-tally')
		treeForLastCommits: 60.
	data := SWAGitChurnData fromGitTree: root.

or in one step with SWAGitChurnData class>>onWorkingCopyNamed:lastCommits:.

Everything is image-independent (names and numbers only), so it round-trips through
JSON like the coverage and topic data sets: #writeToFile: / #fromFile:.

CAVEAT: the window is what you scanned. A method with 0 commits here was not
necessarily untouched -- it may simply predate the oldest commit in the scan. Scan
deeper, or read the absence as ""quiet lately"" rather than ""never written"".
"
Class {
	#name : #SWAGitChurnData,
	#superclass : #Object,
	#instVars : [
		'entries',
		'repositoryName',
		'branchName',
		'commitCount',
		'fromDate',
		'toDate'
	],
	#category : #'SWA-GitMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData class >> fromFile: aFileName [
	| contents |
	contents := (FileStream readOnlyFileNamed: aFileName) contentsOfEntireFile.
	^ self fromJson: (Json readFrom: contents readStream)
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitChurnData class >> fromGitTree: aSWAGitRootNode [
	"Fold an already-built git history tree into one record per method. Pure
	traversal -- no further git access, so this is free once the map exists."
	^ self new loadFromGitTree: aSWAGitRootNode; yourself
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData class >> fromJson: aJsonObject [
	^ self new loadFromJson: aJsonObject; yourself
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData class >> isGitChurnJson: aJsonObject [
	^ ((aJsonObject at: 'format' ifAbsent: ['']) asString beginsWith: 'SWAGitChurnData')
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData class >> on: aSWAGitHistory lastCommits: n [
	| data |
	data := self fromGitTree: (aSWAGitHistory maxCommits: n; buildTree).
	data repositoryName: aSWAGitHistory rootLabel.
	^ data
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitChurnData class >> onWorkingCopyNamed: aString lastCommits: n [
	"	(SWAGitChurnData onWorkingCopyNamed: 'squeak-object-space-tally' lastCommits: 60)
			writeToFile: 'swa-git-churn.json'	"
	^ self on: (SWAGitHistory onWorkingCopyNamed: aString) lastCommits: n
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> addLeaf: aGitNode [
	"Accumulate one change leaf into its method's record. Leaves arrive in tree
	order, which is chronological, so #last / #lastOp simply keep being overwritten
	-- but we guard with a max anyway so the fold does not depend on that."
	| key rec secs |
	key := aGitNode crossRefKey ifNil: [^ self].
	rec := entries at: key ifAbsentPut: [
		Dictionary new
			at: #commits put: 0;
			at: #churn put: 0;
			at: #last put: 0;
			at: #first put: SmallInteger maxVal;
			at: #authors put: Set new;
			at: #lastOp put: nil;
			yourself].
	rec at: #commits put: (rec at: #commits) + 1.
	rec at: #churn put: (rec at: #churn) + aGitNode diffLines.
	aGitNode author ifNotNil: [:a | (rec at: #authors) add: a].
	secs := aGitNode timeStamp ifNil: [0] ifNotNil: [:t | t asSeconds].
	secs >= (rec at: #last) ifTrue: [
		rec at: #last put: secs.
		rec at: #lastOp put: aGitNode operationKind].
	secs < (rec at: #first) ifTrue: [rec at: #first put: secs]
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> asJsonObject [
	"Image-independent representation: names and numbers only, keyed by crossRefKey.
	The 'format' marker is what SWAPane>>loadJsonFile: dispatches on."
	| methods |
	methods := Dictionary new.
	entries keysAndValuesDo: [:k :r |
		methods at: k put: (Dictionary new
			at: 'commits' put: (r at: #commits);
			at: 'churn' put: (r at: #churn);
			at: 'last' put: (r at: #last);
			at: 'first' put: (r at: #first);
			at: 'authors' put: (r at: #authors) asArray asSortedCollection asArray;
			at: 'lastOp' put: ((r at: #lastOp) ifNil: ['']) asString;
			yourself)].
	^ Dictionary new
		at: 'format' put: 'SWAGitChurnData/1';
		at: 'repository' put: (repositoryName ifNil: ['']);
		at: 'branch' put: (branchName ifNil: ['']);
		at: 'commitCount' put: self commitCount;
		at: 'from' put: (fromDate ifNil: [''] ifNotNil: [:d | d printString]);
		at: 'to' put: (toDate ifNil: [''] ifNotNil: [:d | d printString]);
		at: 'methods' put: methods;
		yourself
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> authorCountFor: aCrossRefKey [
	"How many distinct people touched this method in the window. High values are
	the classic 'shared, hot, and probably worth reviewing' signal."
	^ (self recordFor: aCrossRefKey) ifNotNil: [:r | (r at: #authors) size]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> authorsFor: aCrossRefKey [
	^ (self recordFor: aCrossRefKey) ifNotNil: [:r | r at: #authors]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> churnFor: aCrossRefKey [
	"Total changed lines this method accumulated over the window."
	^ (self recordFor: aCrossRefKey) ifNotNil: [:r | r at: #churn]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> commitCount [
	"Distinct commits that contributed to this data set."
	^ commitCount ifNil: [0]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> commitCountFor: aCrossRefKey [
	"How many commits in the scanned window touched this method. nil (not 0) when
	the method is unknown here, so the dataset layer can tell 'no data' from
	'genuinely quiet' and roll containers up instead of painting them cold."
	^ (self recordFor: aCrossRefKey) ifNotNil: [:r | r at: #commits]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:00'
}
SWAGitChurnData >> initialize [
	super initialize.
	entries := Dictionary new.
	commitCount := 0
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> keys [
	^ entries keys
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> lastChangeSecondsFor: aCrossRefKey [
	"Seconds (TimeStamp asSeconds) of the most recent change -- a bigger number is
	more recent, which is what the recency ramp wants."
	^ (self recordFor: aCrossRefKey) ifNotNil: [:r | r at: #last]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> loadFromGitTree: aRootNode [
	"Walk a SWAGitNode tree and accumulate one record per crossRefKey. Class-level
	and organization changes carry a key too (the class name), so a Code Map class
	tile lights up when its DEFINITION changed even if no method did."
	| hashes |
	entries := Dictionary new.
	hashes := Set new.
	aRootNode withAllChildrenDo: [:n |
		n kind == #commit ifTrue: [n hexHash ifNotNil: [:h | hashes add: h]].
		(n isLeaf and: [n crossRefKey notNil]) ifTrue: [
			self addLeaf: n]].
	commitCount := hashes size.
	aRootNode timeStamp ifNotNil: [:t | fromDate := t asDate].
	toDate := Date today.
	^ self
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData >> loadFromJson: aJsonObject [
	| methods |
	entries := Dictionary new.
	repositoryName := (aJsonObject at: 'repository' ifAbsent: ['']) ifEmpty: [nil] ifNotEmpty: [:s | s asString].
	branchName := (aJsonObject at: 'branch' ifAbsent: ['']) ifEmpty: [nil] ifNotEmpty: [:s | s asString].
	commitCount := aJsonObject at: 'commitCount' ifAbsent: [0].
	methods := aJsonObject at: 'methods' ifAbsent: [Dictionary new].
	methods keysAndValuesDo: [:k :v |
		entries at: k asString put: (Dictionary new
			at: #commits put: (v at: 'commits' ifAbsent: [0]);
			at: #churn put: (v at: 'churn' ifAbsent: [0]);
			at: #last put: (v at: 'last' ifAbsent: [0]);
			at: #first put: (v at: 'first' ifAbsent: [0]);
			at: #authors put: ((v at: 'authors' ifAbsent: [#()]) asSet);
			at: #lastOp put: ((v at: 'lastOp' ifAbsent: ['']) ifEmpty: [nil] ifNotEmpty: [:s | s asSymbol]);
			yourself)].
	^ self
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData >> maxAuthorCount [
	"Largest number of distinct authors on any single method."
	| max |
	max := 0.
	entries valuesDo: [:r | | v | v := (r at: #authors) size. v > max ifTrue: [max := v]].
	^ max
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> maxOf: aFieldSymbol [
	"Largest value of a numeric field across all records (0 when empty) -- the
	dataset layer needs it to build a colour ramp with a real upper bound."
	| max |
	max := 0.
	entries valuesDo: [:r | | v | v := r at: aFieldSymbol ifAbsent: [0]. v > max ifTrue: [max := v]].
	^ max
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> methodCount [
	^ entries size
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> minLastChangeSeconds [
	"Oldest 'last touched' moment in the data -- the cold end of the recency ramp."
	| min |
	min := nil.
	entries valuesDo: [:r | | v |
		v := r at: #last ifAbsent: [0].
		(min isNil or: [v < min]) ifTrue: [min := v]].
	^ min ifNil: [0]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> printOn: aStream [
	aStream nextPutAll: 'SWAGitChurnData('; nextPutAll: self summaryString; nextPut: $)
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> recordFor: aCrossRefKey [
	aCrossRefKey ifNil: [^ nil].
	^ entries at: aCrossRefKey asString ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> repositoryName [
	^ repositoryName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> repositoryName: aString [
	repositoryName := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:01'
}
SWAGitChurnData >> summaryString [
	^ String streamContents: [:s |
		repositoryName ifNotNil: [:r | s nextPutAll: r; nextPutAll: ': '].
		s print: self methodCount; nextPutAll: ' methods touched by ';
			print: self commitCount; nextPutAll: ' commits, ';
			print: (self maxOf: #churn); nextPutAll: ' max changed lines'.
		fromDate ifNotNil: [:d | s nextPutAll: ', since '; nextPutAll: d printString]]
]

{
	#category : #json,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWAGitChurnData >> writeToFile: aFileName [
	"	(SWAGitChurnData onWorkingCopyNamed: 'squeak-object-space-tally' lastCommits: 60)
			writeToFile: 'swa-git-churn.json'	"
	| stream |
	stream := FileStream forceNewFileNamed: aFileName.
	[stream nextPutAll: (Json render: self asJsonObject)] ensure: [stream close].
	^ aFileName
]
