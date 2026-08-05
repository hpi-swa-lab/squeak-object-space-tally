"
A node in one of the two trees built from an opencode history. Both are plain
SWANodes, so every SWA view works on them unchanged -- treemap, timeline and
calendar all read the same objects.

FILE TREE (SWAOpenCodeNode class>>fileTreeFor:)
	root -> directory... -> file
	Tile weight is the number of accesses. Single-child directory chains are
	COLLAPSED into one node ('home/jens/lively4/squeak'), because a treemap of a
	deep absolute path otherwise spends most of its area drawing frames around
	one child.

SESSION TREE (SWAOpenCodeNode class>>sessionTreeFor:)
	root -> session -> tool call
	Every leaf is one call with a real timestamp, which is what makes the
	temporal views work.

THE TEMPORAL CONTRACT is two messages, and both matter:

	#eventTimeStamp   when this happened. SWATemporalView collects only LEAVES,
	                  deliberately -- a container carries a timestamp too, and
	                  counting it as well would double-count every event against
	                  its own ancestors.
	#eventGroupKey    the atomic act this belonged to. Here that is the SESSION
	                  id, which makes the views' 'commits / saves' measure count
	                  distinct sittings. A day with 400 calls in one session and
	                  a day with 400 across twenty are different days, and this
	                  is the only field that can tell them apart.
"
Class {
	#name : #SWAOpenCodeNode,
	#superclass : #SWANode,
	#instVars : [
		'name',
		'kind',
		'key',
		'reads',
		'writes',
		'others',
		'weight',
		'timeStamp',
		'groupKey',
		'payload'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:29'
}
SWAOpenCodeNode class >> conversationTreeFor: aSession [
	"session -> message -> part, every part a box.

	Tile weight is the SIZE OF THE PART's text where that is already known, else 1.
	Sizing by content is what makes the view legible: the long user prompt and the
	800-line file the agent read become big boxes, and the step markers between them
	shrink to slivers -- which is the actual shape of the conversation."
	| root |
	root := self new
		name: (aSession title isEmpty ifTrue: [aSession id] ifFalse: [aSession title]);
		nodeKind: #openCodeSession;
		eventGroupKey: aSession id;
		eventTimeStamp: aSession timeStamp;
		payload: aSession;
		yourself.
	aSession partsByMessage do: [:entry |
		| msgNode |
		msgNode := self new
			name: (entry at: 2) asString , ' message';
			nodeKind: #openCodeMessage;
			eventGroupKey: (entry at: 1);
			yourself.
		root addChild: msgNode.
		(entry at: 3) do: [:p | msgNode addChild: (self nodeForPart: p)]].
	root rollUp.
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode class >> fileTreeFor: aHistory [
	"root -> directory... -> file, weighted by accesses. Only calls that named a
	FILE take part; the Smalltalk ones have no path and belong on a Code Map."
	| root byPath |
	root := self new
		name: 'files: ' , (aHistory worktree copyAfterLast: $/);
		nodeKind: #openCodeRoot;
		yourself.
	byPath := Dictionary new.
	aHistory toolCalls do: [:c |
		c targetKind == #file ifTrue: [
			| leaf |
			leaf := byPath at: c targetKey ifAbsentPut: [
				self leafForPath: c targetKey under: root].
			leaf
				countRead: (c accessKind == #read ifTrue: [1] ifFalse: [0])
				write: (c accessKind == #write ifTrue: [1] ifFalse: [0])
				other: (c accessKind == #other ifTrue: [1] ifFalse: [0]).
			c timeStamp ifNotNil: [:ts |
				(leaf eventTimeStamp isNil or: [leaf eventTimeStamp < ts])
					ifTrue: [leaf eventTimeStamp: ts].
				leaf eventGroupKey ifNil: [leaf eventGroupKey: c session id]]]].
	root collapseSingleChildChains.
	root rollUp.
	^ root
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode class >> leafForPath: aPath under: aRoot [
	"Find or create the directory chain for an absolute path and answer its file
	leaf. Empty components (a leading slash, a doubled one) are dropped."
	"A filePath that is not absolute is not a path at all -- it is the agent having
	passed something else to the read tool, and the log is full of Code Map keys
	('SWANavPanel>>setView:') and bare words ('crossRefKey', 'nonexistent') sitting
	where a filename belongs. Bucketing them under one node keeps them visible as
	the mistakes they are, instead of scattering fake directories over the treemap."
	| node comps |
	node := (aPath beginsWith: '/')
		ifTrue: [aRoot]
		ifFalse: [aRoot children
			detect: [:ch | ch name = '<not a path>']
			ifNone: [aRoot addChild: (self new
				name: '<not a path>'; nodeKind: #openCodeDir; yourself)]].
	comps := (aPath findTokens: '/') reject: [:t | t isEmpty].
	(aPath beginsWith: '/') ifFalse: [comps := Array with: aPath].
	comps doWithIndex: [:comp :i |
		| isLast existing |
		isLast := i = comps size.
		existing := node children
			detect: [:ch | ch name = comp]
			ifNone: [nil].
		existing ifNil: [
			existing := self new
				name: comp;
				nodeKind: (isLast ifTrue: [#openCodeFile] ifFalse: [#openCodeDir]);
				yourself.
			isLast ifTrue: [existing crossRefKey: aPath].
			node addChild: existing].
		node := existing].
	^ node
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode class >> nodeForCall: aToolCall [
	"One tool call as a leaf. Weight 1 per call, split into the read/write columns
	so the same tree can be coloured by what kind of access it was."
	^ self new
		name: aToolCall label;
		nodeKind: #openCodeCall;
		crossRefKey: aToolCall targetKey;
		eventTimeStamp: aToolCall timeStamp;
		eventGroupKey: aToolCall session id;
		payload: aToolCall;
		countRead: (aToolCall accessKind == #read ifTrue: [1] ifFalse: [0])
			write: (aToolCall accessKind == #write ifTrue: [1] ifFalse: [0])
			other: (aToolCall accessKind == #other ifTrue: [1] ifFalse: [0]);
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeNode class >> nodeForPart: aPart [
	"A tool part is counted as a read or a write so the read/write colouring works
	here too; text, reasoning and step markers are neither."
	| n isWrite isRead |
	isWrite := aPart type == #tool
		and: [SWAOpenCodeToolCall writingTools includes: aPart tool].
	isRead := aPart type == #tool
		and: [SWAOpenCodeToolCall readingTools includes: aPart tool].
	n := self new
		name: aPart label;
		nodeKind: #openCodePart;
		eventTimeStamp: aPart timeStamp;
		eventGroupKey: aPart messageId;
		payload: aPart;
		weight: (aPart byteSize max: 1);
		yourself.
	n countRead: (isRead ifTrue: [1] ifFalse: [0])
		write: (isWrite ifTrue: [1] ifFalse: [0])
		other: ((isRead or: [isWrite]) ifTrue: [0] ifFalse: [1]).
	^ n
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:57'
}
SWAOpenCodeNode class >> nodeForSession: aSession [
	| n |
	n := self new
		name: (aSession title isEmpty
			ifTrue: [aSession id]
			ifFalse: [aSession title first: (aSession title size min: 60)]);
		nodeKind: #openCodeSession;
		eventGroupKey: aSession id;
		eventTimeStamp: aSession timeStamp;
		payload: aSession;
		yourself.
	aSession toolCalls do: [:c | n addChild: (self nodeForCall: c)].
	aSession children do: [:sub | n addChild: (self nodeForSession: sub)].
	^ n
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:57'
}
SWAOpenCodeNode class >> sessionTreeFor: aHistory [
	"root -> session -> tool call. Every leaf carries a timestamp and a session
	group key, which is what the timeline and calendar consume.

	Subagent sessions are nested under the session that spawned them, so a `task`
	delegation reads as what it is -- work done inside the parent conversation --
	rather than as an unrelated sibling."
	| root |
	root := self new
		name: 'sessions: ' , (aHistory worktree copyAfterLast: $/);
		nodeKind: #openCodeRoot;
		yourself.
	aHistory rootSessions do: [:s | root addChild: (self nodeForSession: s)].
	root rollUp.
	^ root
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> accesses [
	^ reads + writes + others
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:57'
}
SWAOpenCodeNode >> addChild: aNode [
	"SWANode declares the `children` ivar but leaves mutation to subclasses, since
	most node families build their children lazily. These are built eagerly."
	children ifNil: [children := OrderedCollection new].
	children add: aNode.
	aNode parent: self.
	^ aNode
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:57'
}
SWAOpenCodeNode >> children: aCollection [
	children := aCollection.
	aCollection do: [:c | c parent: self]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:57'
}
SWAOpenCodeNode >> collapseSingleChildChains [
	"Fuse a directory that has exactly one subdirectory into its child, so that
	'/home/jens/lively4/squeak/notes' is ONE tile and not five nested frames around
	the same rectangle. Purely cosmetic, but on absolute paths it is the difference
	between a readable treemap and a set of borders.

	A directory with one FILE in it is left alone -- that is a real branching point
	with a real leaf, not a pass-through."
	self children do: [:c | c collapseSingleChildChains].
	[self children size = 1
		and: [self children first nodeKind == #openCodeDir
		and: [kind == #openCodeDir]]] whileTrue: [
			| only |
			only := self children first.
			name := name , '/' , only name.
			children := only children asOrderedCollection.
			children do: [:c | c parent: self]]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:28'
}
SWAOpenCodeNode >> contentLineCount [
	"Lines this node's content would occupy. Never touches the database -- see
	SWAOpenCodePart>>lineCount for where the number is exact and where estimated."
	payload ifNil: [^ 1].
	^ (payload isKindOf: SWAOpenCodePart)
		ifTrue: [payload lineCount]
		ifFalse: [1]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> countRead: r write: w [
	^ self countRead: r write: w other: 0
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> countRead: r write: w other: o [
	reads := reads + r.
	writes := writes + w.
	others := others + o
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> crossRefKey [
	"A file path, or 'Class>>selector' for a call that touched Smalltalk -- the
	latter is a Code Map key, so marking a node here lights it up over there.
	Containers and sessions answer nil: they are not cross-referenceable things."
	^ key
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> crossRefKey: aString [
	key := aString
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:37'
}
SWAOpenCodeNode >> details [
	"Everything known about this node, as a Dictionary for the inspector. May hit
	the database -- inspecting is an explicit act, unlike drawing."
	| d |
	payload ifNotNil: [
		(payload respondsTo: #details) ifTrue: [^ payload details]].
	d := Dictionary new.
	d at: #name put: self name.
	d at: #nodeKind put: kind.
	d at: #crossRefKey put: key.
	d at: #reads put: reads.
	d at: #writes put: writes.
	d at: #others put: others.
	d at: #weight put: weight.
	d at: #totalSize put: self totalSize.
	d at: #eventTimeStamp put: timeStamp.
	d at: #eventGroupKey put: groupKey.
	d at: #childCount put: self children size.
	payload ifNotNil: [d at: #payload put: payload].
	^ d
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:45'
}
SWAOpenCodeNode >> eventDurationMicros [
	"Microseconds this node lasted, completing the temporal contract SWANode
	defines. Without it every node answered the inherited nil, which made the
	flow's #duration height mode silently uniform.

	Also what would let these nodes be drawn as SPANS rather than instants -- see
	the comment on SWANode>>eventDurationMicros."
	| ms |
	payload ifNil: [^ nil].
	ms := (payload respondsTo: #durationMillis)
		ifTrue: [payload durationMillis]
		ifFalse: [nil].
	^ ms ifNotNil: [:m | m * 1000]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> eventGroupKey [
	"The SESSION this event belonged to -- the opencode equivalent of a commit.
	Makes the temporal views' distinct-acts measure count sittings rather than
	individual tool calls."
	^ groupKey
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> eventGroupKey: aString [
	groupKey := aString
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> eventTimeStamp [
	"Local DateAndTime. On a leaf this is when the call ran; on a container it is
	the latest thing inside it (see #rollUp)."
	^ timeStamp
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> eventTimeStamp: aDateAndTime [
	timeStamp := aDateAndTime
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> initialize [
	super initialize.
	reads := 0.
	writes := 0.
	others := 0.
	kind := #openCodeOther
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAOpenCodeNode >> isContentLoaded [
	"True when #sourceString will not hit the database. Only conversation parts can
	answer no; everything else builds its text from what is already in memory."
	payload ifNil: [^ true].
	^ (payload isKindOf: SWAOpenCodePart)
		ifTrue: [payload isContentLoaded]
		ifFalse: [true]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> name [
	^ name ifNil: ['?']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> name: aString [
	name := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> nodeKind [
	"#openCodeRoot / #openCodeDir / #openCodeFile / #openCodeSession /
	#openCodeCall. Recorded in mark provenance and used by #leafKind cutoffs."
	^ kind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> nodeKind: aSymbol [
	kind := aSymbol
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> others [
	"Calls that named no durable target -- bash, grep, glob, evaluate, todowrite.
	Counted SEPARATELY from reads on purpose: lumping them in made the session tree
	claim 17888 reads where the history knows of 7918, because every shell command
	was being filed as a read of something."
	^ others
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> payload [
	"The SWAOpenCodeSession or SWAOpenCodeToolCall this node stands for, or nil for
	a synthetic container."
	^ payload
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> payload: anObject [
	payload := anObject
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:46'
}
SWAOpenCodeNode >> previewString: nChars [
	"A CHEAP preview -- the flow calls this for every visible row on every repaint,
	so it must never touch the database. Answers from what the metadata scan
	already loaded; #sourceString is the expensive one."
	payload ifNil: [^ self name].
	(payload isKindOf: SWAOpenCodePart) ifTrue: [
		^ payload previewString: nChars].
	^ self name truncateTo: nChars
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:59'
}
SWAOpenCodeNode >> printOn: aStream [
	aStream nextPutAll: self name; nextPutAll: ' ('; print: self accesses.
	aStream nextPutAll: ' acc, '; print: reads; nextPutAll: 'r/'; print: writes.
	aStream nextPutAll: 'w'.
	others > 0 ifTrue: [aStream nextPutAll: '/'; print: others; nextPutAll: 'o'].
	aStream nextPut: $)
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> reads [
	^ reads
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeNode >> rollUp [
	"Sum leaf counts into containers, and carry the LATEST timestamp upward. A
	container's time is the most recent thing inside it, never the sum -- summing
	timestamps is arithmetic on the wrong kind of thing."
	self children isEmpty ifTrue: [^ self].
	self children do: [:c | c rollUp].
	reads := self children inject: 0 into: [:a :c | a + c reads].
	writes := self children inject: 0 into: [:a :c | a + c writes].
	others := self children inject: 0 into: [:a :c | a + c others].
	"Only roll an explicit weight up where the children carry one, so a container
	in an access-weighted tree keeps answering accesses."
	(self children anySatisfy: [:c | c weight notNil]) ifTrue: [
		weight := self children inject: 0 into: [:a :c | a + (c weight ifNil: [0])]].
	self children do: [:c |
		c eventTimeStamp ifNotNil: [:ts |
			(timeStamp isNil or: [timeStamp < ts]) ifTrue: [timeStamp := ts]]]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:29'
}
SWAOpenCodeNode >> sourceString [
	"Full text for the pane's Source flap. SWATreemapMorph>>selectedSourceString
	already delegates here when the node answers it, so implementing this is all a
	node needs to make its contents readable.

	For a conversation part this triggers the ON-DEMAND fetch of that one part's
	document -- the message text, or a tool call's input and complete output."
	payload ifNil: [^ ''].
	(payload isKindOf: SWAOpenCodePart) ifTrue: [^ payload fullContent].
	(payload isKindOf: SWAOpenCodeToolCall) ifTrue: [
		^ String streamContents: [:s |
			s nextPutAll: payload label; cr; cr.
			s nextPutAll: 'tool:    '; nextPutAll: payload tool asString; cr.
			s nextPutAll: 'status:  '; nextPutAll: (payload status ifNil: ['-']) asString; cr.
			s nextPutAll: 'access:  '; nextPutAll: payload accessKind asString; cr.
			payload targetKey ifNotNil: [:k | s nextPutAll: 'target:  '; nextPutAll: k; cr].
			payload command ifNotNil: [:c | s cr; nextPutAll: c; cr].
			s cr; nextPutAll: 'Open the session view for this call''s full output.']].
	(payload isKindOf: SWAOpenCodeSession) ifTrue: [
		^ payload title , String cr , payload id].
	^ ''
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeNode >> totalSize [
	"Tile weight. Normally the number of accesses -- but the conversation view sets
	an explicit weight (the part's byte size), because there every part is a single
	event and counting them would make all boxes identical, hiding exactly the
	thing worth seeing: which parts of the conversation were BIG.

	Rolled up by #rollUp at build time rather than computed here, because the
	treemap asks for this once per tile per layout."
	weight ifNotNil: [^ weight max: 0].
	^ self accesses max: 0
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeNode >> weight [
	^ weight
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeNode >> weight: aNumber [
	weight := aNumber
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:56'
}
SWAOpenCodeNode >> writes [
	^ writes
]
