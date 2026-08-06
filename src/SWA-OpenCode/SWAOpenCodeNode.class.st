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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:05'
}
SWAOpenCodeNode class >> calendarPartNodeKind: aKindPair facts: aFacts millis: millis size: aSize [
	"One part as a calendar event, built from the CHEAP scan rather than from a
	SWAOpenCodePart -- see SWAOpenCodeEventFacts for why there is no part object
	here.

	#eventGroupKey is the MESSAGE, not the session: it is what a per-group measure
	divides by, and cost is accounted per message. The session is on the facts, and
	that is what 'colour by session' reads."
	| type tool label kind |
	type := aKindPair first.
	tool := aKindPair second.
	kind := type == #text
		ifTrue: [aFacts role = 'user' ifTrue: [#user] ifFalse: [#assistant]]
		ifFalse: [type].
	label := type == #tool
		ifTrue: [tool ifNil: ['tool'] ifNotNil: [:t |
			aFacts className ifNil: [t] ifNotNil: [:c | t , ' ' , c]]]
		ifFalse: [kind asString , (type == #text ifTrue: [' text'] ifFalse: [''])].
	^ self new
		name: label;
		nodeKind: kind;
		eventTimeStamp: (DateAndTime fromUnixTime: millis // 1000) asLocal;
		eventGroupKey: aFacts messageId;
		payload: aFacts;
		weight: (aSize max: 1);
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:32'
}
SWAOpenCodeNode class >> calendarTreeFor: aHistory [
	"root -> session -> EVERY part, for the whole project, each part carrying the
	facts a view can colour by (SWAOpenCodeEventFacts: session, model, agent, cost,
	tokens, package) and the part id it can be resolved back through.

	Not #sessionTreeFor:, which carries only tool calls. A calendar asks 'which days
	were heavy', and answering it from a third of what happened made the quiet days
	look quieter than they were.

	Grouped by session rather than flat because the day-level selection reports its
	busiest children, and 'which sessions ran that day' is the answer worth having.

	COST AND TOKENS ARE SHARED OUT AFTERWARDS. They arrive per MESSAGE, repeated on
	each of that message's parts; the second pass divides by the part count so the
	totals add up to what the project actually spent instead of a multiple of it.

	FIVE SECONDS of scanning, so it runs under a progress bar. Not in a background
	process: the tree IS the view's model, so there would be nothing to show until
	it finished anyway, and a half-built calendar is worse than a bar that says how
	far along it is."
	| root bySession pkgCache allFacts perMessage total seen |
	root := self new
		name: 'sessions: ' , (aHistory worktree copyAfterLast: $/);
		nodeKind: #openCodeRoot;
		yourself.
	bySession := Dictionary new.
	pkgCache := Dictionary new.
	allFacts := OrderedCollection new.
	perMessage := Dictionary new.
	total := (aHistory db countPartsForProject: aHistory projectId) max: 1.
	seen := 0.
	'Reading opencode history...'
		displayProgressFrom: 0 to: total
		during: [:bar |
			aHistory db
				allPartsForProject: aHistory projectId
				do: [:pid :sid :mid :millis :prefix :len :fields |
					| kind |
					seen := seen + 1.
					"Every 500th row, not every row: updating the bar is a redraw, and
					80128 of them cost far more than the scan they are reporting on."
					seen \\ 500 = 0 ifTrue: [bar value: seen].
					kind := aHistory db partKindFromPrefix: prefix.
					(kind notNil and: [millis notNil]) ifTrue: [
						| facts sessionNode |
						sessionNode := bySession at: sid ifAbsentPut: [
							| s n |
							s := aHistory sessionsById at: sid ifAbsent: [nil].
							n := self new
								name: (s ifNil: [sid] ifNotNil: [:x | x title]);
								nodeKind: #openCodeSession;
								eventGroupKey: sid;
								payload: s;
								yourself.
							root addChild: n.
							n].
						facts := self
							factsFor: sid message: mid part: pid
							session: sessionNode payload fields: fields packages: pkgCache.
						allFacts add: facts.
						perMessage at: mid put: (perMessage at: mid ifAbsent: [0]) + 1.
						sessionNode addChild: (self
							calendarPartNodeKind: kind facts: facts millis: millis size: len)]]].
	allFacts do: [:f |
		| n |
		n := (perMessage at: f messageId ifAbsent: [1]) max: 1.
		f costShare: (f cost ifNil: [0]) / n.
		f tokenShare: (f tokens ifNil: [0]) / n].
	root rollUp.
	^ root
]

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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWAOpenCodeNode class >> factsFor: sid message: mid part: pid session: aSessionOrNil fields: fields packages: pkgCache [
	"Unpack one row of SWAOpenCodeDb>>allPartsForProject:do: into its facts.

	The session object and the part id are carried so that SELECTING a message can
	materialise the real SWAOpenCodePart on demand (SWAOpenCodeEventFacts>>part) and
	reuse everything the Flow view already does with one.

	The class -> package lookup goes through pkgCache: 24425 tool parts hit a few
	hundred distinct classes, and PackageOrganizer>>packageOfClass: is a scan."
	| m p cls |
	m := fields first.
	p := fields second.
	"squeak_write_class_code names its class `name`, every other squeak tool calls
	it `class` -- the same normalisation SWAOpenCodeToolCall makes."
	cls := (p at: 1 ifAbsent: [nil]) ifNil: [p at: 2 ifAbsent: [nil]].
	^ SWAOpenCodeEventFacts new
		sessionId: sid;
		session: aSessionOrNil;
		partId: pid;
		messageId: mid;
		role: (m at: 1 ifAbsent: [nil]);
		cost: (m at: 2 ifAbsent: [nil]);
		model: (m at: 3 ifAbsent: [nil]);
		agent: (m at: 4 ifAbsent: [nil]);
		tokens: (m at: 5 ifAbsent: [nil]);
		className: cls;
		packageName: (cls ifNotNil: [:c |
			pkgCache at: c ifAbsentPut: [self packageNameForClassName: c]]);
		yourself
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:21'
}
SWAOpenCodeNode class >> isTimelinePartType: aType [
	"Which part types are EVENTS on a timeline.

	step-start / step-finish are excluded. They are opencode's own framing of a
	message, not something that happened: they carry no content and no duration, and
	there are two of them per assistant turn -- 138 of the 351 parts in a typical
	session. Drawn as spans they become the largest lane on the chart, made entirely
	of identical zero-width ticks, and they push the actual work off the bottom.

	The message boundary they mark is not lost: every part still carries its
	messageId, which is what #eventGroupKey answers."
	^ (aType == #'step-start' or: [aType == #'step-finish']) not
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:04'
}
SWAOpenCodeNode class >> packageNameForClassName: aString [
	"Package of a class NAMED in a tool call, resolved through the live image, or nil
	when it no longer exists -- the session may have created and later deleted it."
	| name cls |
	name := aString withBlanksTrimmed.
	(name endsWith: ' class') ifTrue: [name := name copyFrom: 1 to: name size - 6].
	cls := Smalltalk at: name asSymbol ifAbsent: [nil].
	(cls isNil or: [cls isBehavior not]) ifTrue: [^ nil].
	^ (PackageOrganizer default packageOfClass: cls theNonMetaClass ifNone: [nil])
		ifNotNil: [:pkg | pkg packageName]
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
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:21'
}
SWAOpenCodeNode class >> timelineTreeFor: aSession [
	"EVERY part of the session as a timed event -- text, reasoning, tool calls, step
	markers -- flat under the session root.

	Not #nodeForSession:, which builds only the session's TOOL CALLS. That is the
	right tree for the whole-project timeline, where loading every part of every
	session would be gigabytes for a picture of a year; for ONE session it showed
	less than a third of what happened. In a typical session 107 of 351 parts are
	tool calls -- all the thinking and all the talking were simply missing from the
	timeline.

	FLAT, unlike #conversationTreeFor:: a temporal view collects LEAVES, so message
	containers would contribute nothing but a walk, and the grouping that matters
	when spans are drawn is the lane (#eventLaneKey), not the message."
	| root |
	root := self new
		name: (aSession title isEmpty ifTrue: [aSession id] ifFalse: [aSession title]);
		nodeKind: #openCodeSession;
		eventGroupKey: aSession id;
		eventTimeStamp: aSession timeStamp;
		payload: aSession;
		yourself.
	aSession parts do: [:p |
		(p timeStamp notNil and: [self isTimelinePartType: p type])
			ifTrue: [root addChild: (self nodeForPart: p)]].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWAOpenCodeNode >> details [
	"Everything known about this node, as a Dictionary for the inspector. May hit
	the database -- inspecting is an explicit act, unlike drawing."
	| d |
	"Facts first: they can resolve to a real part, whose #details is far richer than
	anything this node could assemble -- the raw JSON, the rendered content, the
	message's cost and token record."
	(payload isKindOf: SWAOpenCodeEventFacts) ifTrue: [
		payload part ifNotNil: [:p | ^ p details]].
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:06'
}
SWAOpenCodeNode >> eventCategoryFor: aSymbol [
	"Session, model, agent and the touched package -- read off the SWAOpenCodeEventFacts
	the project-wide scan attached (see SWAOpenCodeNode class>>calendarTreeFor:).

	#package is nil for anything that did not name a Smalltalk class, which is most
	events: a `read` of a markdown file belongs to no package, and inventing one for
	it would be a fabrication. The view paints a nil category as neutral grey, so
	'colour by package' reads as 'the Smalltalk work, by package, on a grey ground'."
	| f |
	f := payload.
	(f isKindOf: SWAOpenCodeEventFacts) ifFalse: [^ super eventCategoryFor: aSymbol].
	aSymbol == #session ifTrue: [^ f sessionId].
	aSymbol == #model ifTrue: [^ f model].
	aSymbol == #agent ifTrue: [^ f agent].
	aSymbol == #package ifTrue: [^ f packageName].
	aSymbol == #class ifTrue: [^ f className].
	^ super eventCategoryFor: aSymbol
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:06'
}
SWAOpenCodeNode >> eventColorModes [
	^ {
		{#kind.    'By kind (user / assistant / tool)'}.
		{#session. 'By session'}.
		{#model.   'By model'}.
		{#agent.   'By agent'}.
		{#package. 'By package touched'}.
		{#class.   'By class touched'}.
		{#cost.    'By cost (heat)'}.
		{#tokens.  'By tokens (heat)'}
	}
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:17'
}
SWAOpenCodeNode >> eventLaneKey [
	"user / assistant / reasoning / tool / step -- the same classification the flow
	views put in columns, so the timeline and the flow read the same way.

	A tool call gets its own band rather than sharing the assistant's: it is the
	assistant ACTING rather than speaking, and separating them is what makes a long
	grinding stretch visible as a solid bar."
	| p |
	p := payload.
	(p isKindOf: SWAOpenCodePart) ifFalse: [
		(p isKindOf: SWAOpenCodeToolCall) ifTrue: [^ #tool].
		^ self nodeKind].
	p type == #tool ifTrue: [^ #tool].
	p type == #reasoning ifTrue: [^ #reasoning].
	(p type == #'step-start' or: [p type == #'step-finish']) ifTrue: [^ #step].
	p role = 'user' ifTrue: [^ #user].
	^ #assistant
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:23'
}
SWAOpenCodeNode >> eventMicros [
	"Millisecond resolution, on the RIGHT EPOCH.

	The inherited default goes through #eventTimeStamp asSeconds, which rounds every
	event in a burst to the same instant -- fine for a histogram of a day's work,
	useless for drawing a 300 ms tool call as a box. opencode records its times as
	UNIX milliseconds, so the sub-second part comes from there.

	Anchored on #eventTimeStamp and NOT computed as `startMillis * 1000`: Unix
	counts from 1970 and Squeak's #asSeconds from 1901, and using the raw value
	directly dated the whole project timeline to April 1957. The two are combined
	instead -- whole seconds from the timestamp, remainder from the millis -- so the
	epoch comes from the one conversion that already gets it right."
	| t ms |
	t := self eventTimeStamp ifNil: [^ nil].
	ms := (payload notNil and: [payload respondsTo: #startMillis])
		ifTrue: [payload startMillis]
		ifFalse: [nil].
	^ (t asSeconds * 1000000) + (ms ifNil: [0] ifNotNil: [:m | m \\ 1000 * 1000])
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
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:10'
}
SWAOpenCodeNode >> eventValueFor: aSymbol [
	"Adds the money and the context budget, which is most of what anyone wants a
	session timeline to plot. Both are the owning MESSAGE's -- see
	#eventValueIsPerGroup:."
	| p m tk cache |
	(#(#cost #tokens #context) includes: aSymbol) ifFalse: [
		^ super eventValueFor: aSymbol].
	p := payload.
	"The cheap project-wide scan attaches facts instead of a part. Cost there is
	ALREADY the share of its message (see SWAOpenCodeEventFacts), so it needs no
	further division -- #eventValueIsPerGroup: answers false for it."
	(p isKindOf: SWAOpenCodeEventFacts) ifTrue: [
		aSymbol == #cost ifTrue: [^ p costShare].
		aSymbol == #tokens ifTrue: [^ p tokenShare].
		^ nil].
	(p isKindOf: SWAOpenCodePart) ifFalse: [^ nil].
	m := p messageData ifNil: [^ nil].
	aSymbol == #cost ifTrue: [^ m at: 'cost' ifAbsent: [nil]].
	tk := m at: 'tokens' ifAbsent: [nil].
	tk ifNil: [^ nil].
	aSymbol == #tokens ifTrue: [^ tk at: 'total' ifAbsent: [nil]].
	"CONTEXT is what was sent TO the model: input plus everything read from or
	written to the prompt cache. Distinct from #tokens, which includes the output
	and so answers a different question."
	cache := tk at: 'cache' ifAbsent: [Dictionary new].
	^ (tk at: 'input' ifAbsent: [0])
		+ (cache at: 'read' ifAbsent: [0])
		+ (cache at: 'write' ifAbsent: [0])
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:07'
}
SWAOpenCodeNode >> eventValueIsPerGroup: aSymbol [
	"Cost, tokens and context are the MESSAGE's, and #eventGroupKey is the message
	id -- so a view plotting them must share the number out across the message's
	parts rather than repeat it on each."
	(payload isKindOf: SWAOpenCodeEventFacts) ifTrue: [^ false].
	^ #(#cost #tokens #context) includes: aSymbol
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
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:33'
}
SWAOpenCodeNode >> sourceString [
	"Full text for the pane's Source flap. SWATreemapMorph>>selectedSourceString
	already delegates here when the node answers it, so implementing this is all a
	node needs to make its contents readable.

	For a conversation part this triggers the ON-DEMAND fetch of that one part's
	document -- the message text, or a tool call's input and complete output."
	payload ifNil: [^ ''].
	(payload isKindOf: SWAOpenCodePart) ifTrue: [^ payload fullContent].
	"A calendar event carries facts, not a part -- resolve to the real one and read
	it exactly as the Flow view does. Same rendered document, same on-demand fetch,
	no second implementation."
	(payload isKindOf: SWAOpenCodeEventFacts) ifTrue: [
		^ payload part
			ifNotNil: [:p | p fullContent]
			ifNil: ['(this part is no longer in the opencode store)']].
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
