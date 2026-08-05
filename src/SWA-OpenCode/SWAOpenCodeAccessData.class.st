"
An agent's ACCESS LOG projected onto SWA's cross-reference keys: for each key,
how often it was read, how often written, in how many distinct sessions, and
when it was last touched.

This is the bridge that lets a pile of opencode conversations colour a Code Map.
It works without any translation layer because SWAOpenCodeToolCall already emits
SWA's own spelling -- 'Class>>selector' for a method, 'Class' for a class -- so
the keys land directly on Code Map tiles. File paths are carried in the same
table and are keyed by absolute path; they are meaningless to a Code Map and are
what SWAOpenCodeFileNode's treemap reads instead.

Feeds a #openCodeAccess SWADataset (see SWADataset>>buildMetrics). Five metrics,
and their ROLLUPS differ on purpose, for the same reason git churn's do:

	reads / writes / touches   #sum -- a class's accesses are its methods'
	                           accesses, so summing up the tree is the meaning.
	sessions                   #max -- summing would count one session once per
	                           method it touched, so a class edited ten times in
	                           a single sitting would read as ten sittings.
	recency                    #max -- most recent touch wins. Summing timestamps
	                           is arithmetic on the wrong kind of thing.

THE QUESTION IT ANSWERS that git cannot: git records what was COMMITTED, this
records what was LOOKED AT. Code an agent read repeatedly but never changed is
invisible to every other tool in the suite, and it is exactly where the agent
spent its context budget.
"
Class {
	#name : #SWAOpenCodeAccessData,
	#superclass : #Object,
	#instVars : [
		'name',
		'entries'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData class >> fromToolCalls: aCollection named: aName [
	"Build over any collection of SWAOpenCodeToolCalls -- a whole history, one
	session, one day. Restricting the collection is how you ask 'what did THIS
	session touch', which is the same dataset with a different domain."
	^ self new setName: aName; addAll: aCollection; yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> add: aToolCall [
	"Fold one tool call into the table. Calls that name no durable target (bash,
	grep, evaluate) are skipped -- they are real work but they decorate nothing."
	| key rec secs |
	key := aToolCall targetKey ifNil: [^ self].
	rec := entries at: key ifAbsentPut: [
		Dictionary new
			at: #reads put: 0;
			at: #writes put: 0;
			at: #sessions put: Set new;
			at: #first put: nil;
			at: #last put: nil;
			at: #kind put: aToolCall targetKind;
			yourself].
	aToolCall accessKind == #write
		ifTrue: [rec at: #writes put: (rec at: #writes) + 1]
		ifFalse: [rec at: #reads put: (rec at: #reads) + 1].
	aToolCall session ifNotNil: [:s | (rec at: #sessions) add: s id].
	aToolCall startMillis ifNotNil: [:ms |
		secs := ms // 1000.
		((rec at: #first) isNil or: [secs < (rec at: #first)])
			ifTrue: [rec at: #first put: secs].
		((rec at: #last) isNil or: [secs > (rec at: #last)])
			ifTrue: [rec at: #last put: secs]]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> addAll: aCollection [
	aCollection do: [:c | self add: c]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> initialize [
	super initialize.
	entries := Dictionary new.
	name := 'opencode'
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> keys [
	^ entries keys
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> keysOfKind: aSymbol [
	"#file / #method / #class."
	^ entries keys select: [:k | ((entries at: k) at: #kind) == aSymbol]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> lastTouchSecondsFor: aKey [
	"Unix seconds of the most recent access, for the recency ramp."
	^ (entries at: aKey ifAbsent: [^ nil]) at: #last
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> maxOf: aFieldSymbol [
	"Largest value of a numeric field over all keys (0 when empty) -- the dataset
	layer needs a real upper bound to build a colour ramp. #sessions is a Set, so
	it is measured by size; #touches is derived."
	| max |
	max := 0.
	entries valuesDo: [:r |
		| v |
		v := aFieldSymbol == #touches
			ifTrue: [(r at: #reads) + (r at: #writes)]
			ifFalse: [r at: aFieldSymbol ifAbsent: [0]].
		v isCollection ifTrue: [v := v size].
		(v notNil and: [v > max]) ifTrue: [max := v]].
	^ max
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> minLastTouchSeconds [
	"Oldest 'last touch' in the table -- the bottom of the recency ramp."
	| min |
	min := nil.
	entries valuesDo: [:r |
		(r at: #last) ifNotNil: [:v |
			(min isNil or: [v < min]) ifTrue: [min := v]]].
	^ min ifNil: [0]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> name [
	^ name
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> printOn: aStream [
	aStream nextPutAll: 'OpenCodeAccess('; nextPutAll: (name ifNil: ['?']).
	aStream nextPutAll: ', '; print: entries size; nextPutAll: ' keys)'
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> readsFor: aKey [
	"nil, not 0, for an untouched key: the dataset layer treats nil as 'no data'
	and leaves the tile intrinsic, while 0 would paint it as a measured zero."
	^ (entries at: aKey ifAbsent: [^ nil]) at: #reads
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> recordFor: aKey [
	^ entries at: aKey ifAbsent: [nil]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:54'
}
SWAOpenCodeAccessData >> sessionCountFor: aKey [
	"How many distinct sittings came back to this. High values mark the code you
	keep having to revisit."
	^ ((entries at: aKey ifAbsent: [^ nil]) at: #sessions) size
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> setName: aString [
	name := aString
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> touchesFor: aKey [
	| r |
	r := entries at: aKey ifAbsent: [^ nil].
	^ (r at: #reads) + (r at: #writes)
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:53'
}
SWAOpenCodeAccessData >> writesFor: aKey [
	^ (entries at: aKey ifAbsent: [^ nil]) at: #writes
]
