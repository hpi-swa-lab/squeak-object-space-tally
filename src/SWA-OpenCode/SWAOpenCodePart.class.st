"
One part of one message: a chunk of assistant text, a reasoning block, a tool
call, or a step marker. This is the unit the conversation view draws as a box.

LAZY BY CONSTRUCTION. The metadata (type, role, tool, status, title, a text
preview) arrives with every other part of the session in one query; the
CONTENT -- which for a `read` or a `bash` part is the tool's entire output and
can be hundreds of kilobytes -- is fetched only when #fullContent is asked for,
and then cached. That is the whole reason a 1.4 GB store can be browsed
interactively: nothing large is ever loaded speculatively.

#fullContent renders whatever the part actually holds: the message text, the
tool's input arguments AND its output, or the reasoning block. Reasoning is
usually empty here because OpenAI returns it encrypted
(`reasoningEncryptedContent`), which is worth knowing before concluding the
extraction is broken.
"
Class {
	#name : #SWAOpenCodePart,
	#superclass : #Object,
	#instVars : [
		'session',
		'id',
		'messageId',
		'role',
		'type',
		'tool',
		'status',
		'title',
		'startMillis',
		'endMillis',
		'timeCreated',
		'text',
		'byteSize',
		'fullContent',
		'className',
		'selector'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodePart >> byteSize [
	"Length of the stored JSON document. Includes the JSON scaffolding, so it
	overstates the content -- honest enough to size a box, not a measurement."
	^ byteSize
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:37'
}
SWAOpenCodePart >> contentBodyOrNil [
	"The rendered content WITHOUT the banner #renderDocument: puts on top of it, or
	nil when nothing has been loaded. Fetches nothing.

	The banner repeats the label, the part id and the timestamp -- all of which the
	surrounding view already shows. In a 400-character preview that header is most
	of the budget, so the row ends up spelling out an id nobody reads instead of the
	call's input."
	| i body |
	fullContent ifNil: [^ nil].
	i := fullContent indexOfSubCollection: (String new: 70 withAll: $-) startingAt: 1.
	i = 0 ifTrue: [^ fullContent].
	body := (fullContent copyFrom: i + 70 to: fullContent size) withBlanksTrimmed.
	"'STATUS: completed' too: the headline already carries any status worth
	reporting, and spending a preview line on the word 'completed' is how a
	whole column of rows ends up saying the same thing."
	(body beginsWith: 'STATUS:') ifTrue: [
		body := (body copyAfter: Character cr) withBlanksTrimmed].
	^ body
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:37'
}
SWAOpenCodePart >> details [
	"EVERYTHING known or reachable about this part, as a Dictionary for the
	inspector: the part's own fields, the owning message's cost/token/model record,
	the session it belongs to, and -- fetched here, because an inspect is an
	explicit request -- the raw JSON document and the rendered content.

	Costs and tokens are the MESSAGE's, and are repeated for every part of that
	message. That is how opencode accounts them; dividing them among parts would
	be a fabrication."
	| d m raw |
	d := Dictionary new.
	d at: #partId put: id.
	d at: #messageId put: messageId.
	d at: #type put: type.
	d at: #role put: role.
	d at: #tool put: tool.
	d at: #status put: status.
	d at: #title put: title.
	d at: #timeStamp put: self timeStamp.
	d at: #startMillis put: startMillis.
	d at: #byteSize put: byteSize.
	d at: #lineCount put: self lineCount.
	d at: #lineCountIsEstimate put: (fullContent isNil and: [text isNil or: [text isEmpty]]).
	d at: #textPreview put: text.
	m := self messageData.
	m ifNotNil: [
		d at: #messageCost put: (m at: 'cost' ifAbsent: [nil]).
		d at: #messageTokens put: (m at: 'tokens' ifAbsent: [nil]).
		d at: #messageModel put: (m at: 'modelID' ifAbsent: [nil]).
		d at: #messageProvider put: (m at: 'providerID' ifAbsent: [nil]).
		d at: #messageAgent put: (m at: 'agent' ifAbsent: [nil]).
		d at: #messageFinish put: (m at: 'finish' ifAbsent: [nil]).
		d at: #messageTime put: (m at: 'time' ifAbsent: [nil]).
		d at: #messageRaw put: m].
	d at: #session put: session.
	d at: #sessionTitle put: session title.
	d at: #sessionCost put: session cost.
	raw := [session history db partDataAt: id] on: Error do: [:e | nil].
	d at: #rawJson put: raw.
	d at: #rawParsed put: (raw ifNotNil: [[Json readFrom: raw readStream] on: Error do: [:e | nil]]).
	d at: #renderedContent put: self fullContent.
	^ d
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:45'
}
SWAOpenCodePart >> durationMillis [
	"How long this part took, or nil where it is an instant (text parts and step
	markers carry no interval). nil rather than 0, so a view can tell 'took no
	time' from 'we do not know'."
	(startMillis isNil or: [endMillis isNil]) ifTrue: [^ nil].
	^ (endMillis - startMillis) max: 0
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> fullContent [
	"The complete contents of this part, fetched from the database ON DEMAND and
	then cached. This is the only code path that loads a tool's output."
	| raw doc |
	fullContent ifNotNil: [^ fullContent].
	raw := [session history db partDataAt: id]
		on: Error do: [:e | ^ 'could not load part ' , id , ': ' , e messageText].
	raw ifNil: [^ fullContent := '(part ' , id , ' is no longer in the database)'].
	doc := [Json readFrom: raw readStream]
		on: Error do: [:e | ^ fullContent := raw].
	^ fullContent := self renderDocument: doc
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> id [
	^ id
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:02'
}
SWAOpenCodePart >> isContentLoaded [
	"Whether #fullContent can answer without going to the database. Lets a view
	decide between rendering now and scheduling a fetch."
	^ fullContent notNil
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:36'
}
SWAOpenCodePart >> label [
	"Short label for the box. Falls back through what is actually available: a tool
	part has a title, a text part has its opening words, a step marker has neither."
	type == #tool ifTrue: [
		"Prefer the Smalltalk target over $.state.title: the squeak_* MCP tools
		leave the title empty, so 'squeak_get_source_code' alone was all a row
		could say. 'squeak_get_source_code SWASpaceTally>>captureDeepUniverse'
		is the same width and actually names the subject."
		^ (tool ifNil: ['tool']) asString
			, (self targetKey
				ifNotNil: [:k | ' ' , k]
				ifNil: [title
					ifNil: ['']
					ifNotNil: [:t | t isEmpty ifTrue: [''] ifFalse: [' ' , (t truncateTo: 40)]]])].
	(type == #text or: [type == #reasoning]) ifTrue: [
		| p |
		p := (text ifNil: ['']) copyReplaceAll: (String with: Character cr) with: ' '.
		p := p copyReplaceAll: (String with: Character lf) with: ' '.
		p := p withBlanksTrimmed.
		^ p isEmpty
			ifTrue: [type == #reasoning ifTrue: ['(reasoning, encrypted)'] ifFalse: ['(empty text)']]
			ifFalse: [(role = 'user' ifTrue: ['USER: '] ifFalse: ['']) , (p truncateTo: 60)]].
	^ type asString
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:29'
}
SWAOpenCodePart >> lineCount [
	"Lines of content -- EXACT where the text is already in memory, ESTIMATED where
	it is not.

	The estimate matters and is not hidden: a tool part's output is deliberately
	never loaded during the session scan, so for those all we have is the stored
	document length. 64 characters per line is a guess; it puts a 300 kB file read
	at roughly 4700 lines, the right order of magnitude but not a measurement. Once
	the part has been selected and its content fetched the count becomes exact and
	the row resizes accordingly."
	fullContent ifNotNil: [^ (fullContent occurrencesOf: Character lf) + 1].
	(text notNil and: [text notEmpty])
		ifTrue: [^ (text occurrencesOf: Character lf) + 1].
	^ ((byteSize ifNil: [1]) // 64) max: 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:37'
}
SWAOpenCodePart >> messageData [
	"The owning message's record: cost, tokens, model, timing. Note that this is
	PER MESSAGE, not per part -- a message that made three tool calls reports one
	cost covering all of them, so attributing cost to an individual part would be
	inventing a number."
	^ session messageData at: messageId ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> messageId [
	^ messageId
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:37'
}
SWAOpenCodePart >> previewString: nChars [
	"Preview from the ALREADY LOADED metadata only -- nothing is fetched, because
	this runs per visible row per repaint.

	A TOOL part always leads with its own headline: the tool, what it was aimed at
	(#targetKey -- 'SWASpaceTally>>captureDeepUniverse'), and an error marker. Only
	then, and only if the content happens to be cached, does the body follow.
	Dumping the raw rendered document instead -- which is what this did -- spent the
	preview on '=== squeak_get_source_code / part prt_ed4a4c0e... / STATUS:
	completed', so every squeak call in the flow looked identical."
	type == #tool ifTrue: [
		^ String streamContents: [:s |
			s nextPutAll: self label.
			(status notNil and: [status ~~ #completed])
				ifTrue: [s nextPutAll: '  ['; nextPutAll: status asString; nextPutAll: ']'].
			self contentBodyOrNil
				ifNil: [s cr; nextPutAll: '(select to load the full call)']
				ifNotNil: [:b | s cr; nextPutAll: (b truncateTo: (nChars - self label size max: 0))]]].
	fullContent ifNotNil: [^ fullContent truncateTo: nChars].
	(text notNil and: [text notEmpty]) ifTrue: [^ text truncateTo: nChars].
	^ self label
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:28'
}
SWAOpenCodePart >> renderDocument: doc [
	"Turn one part's JSON into something readable. A tool part gets INPUT and
	OUTPUT as separate sections -- the input is what the agent asked for and the
	output is what it got back, and reading a tool call without both is guesswork."
	^ String streamContents: [:s |
		| st |
		s nextPutAll: '=== '; nextPutAll: self label; cr.
		s nextPutAll: 'part '; nextPutAll: id.
		self timeStamp ifNotNil: [:t | s nextPutAll: '   '; print: t].
		s cr; nextPutAll: (String new: 70 withAll: $-); cr; cr.
		st := doc at: 'state' ifAbsent: [nil].
		st ifNil: [
			s nextPutAll: ((doc at: 'text' ifAbsent: ['']) ifEmpty: [
				'(no text -- reasoning blocks are returned encrypted by the provider)'])]
		ifNotNil: [
			s nextPutAll: 'STATUS: '; nextPutAll: (st at: 'status' ifAbsent: ['?']) asString; cr; cr.
			s nextPutAll: '--- INPUT ---'; cr.
			self writeValue: (st at: 'input' ifAbsent: [nil]) on: s indent: 0.
			s cr; cr; nextPutAll: '--- OUTPUT ---'; cr.
			s nextPutAll: ((st at: 'output' ifAbsent: [nil]) ifNil: ['(none)'] ifNotNil: [:o | o asString]).
			(st at: 'error' ifAbsent: [nil]) ifNotNil: [:e |
				s cr; cr; nextPutAll: '--- ERROR ---'; cr; nextPutAll: e asString]]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> role [
	"'user' or 'assistant' -- opencode has no system role; the system prompt is an
	array inside each assistant message, not a message of its own."
	^ role
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:43'
}
SWAOpenCodePart >> session [
	^ session
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:36'
}
SWAOpenCodePart >> setSession: aSession id: aPartId message: aMessageId time: aTime fields: f role: aRole size: aSize [
	"Positional unpacking of the multi-path json_extract in
	SWAOpenCodeDb>>partsForSession:do:: type, tool, state.status, state.title,
	state.time.start, text, state.time.end, time.start, time.end,
	state.input.class, state.input.method, state.input.name."
	session := aSession.
	id := aPartId.
	messageId := aMessageId.
	timeCreated := aTime.
	role := aRole.
	byteSize := aSize ifNil: [1].
	type := (f at: 1) ifNotNil: [:x | x asSymbol].
	tool := (f at: 2) ifNotNil: [:x | x asSymbol].
	status := (f at: 3) ifNotNil: [:x | x asSymbol].
	title := f at: 4.
	"Interval, from whichever spelling this part uses: $.state.time for a tool call,
	$.time for a reasoning block."
	startMillis := (f at: 5) ifNil: [f at: 8].
	text := f at: 6.
	endMillis := (f at: 7) ifNil: [f at: 9].
	"What a squeak_* call was aimed at. squeak_write_class_code names its class
	`name`, every other squeak tool calls it `class` -- normalised here so
	#targetKey has one rule, the same normalisation SWAOpenCodeToolCall makes."
	className := (f at: 10 ifAbsent: [nil]) ifNil: [f at: 12 ifAbsent: [nil]].
	selector := f at: 11 ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:23'
}
SWAOpenCodePart >> startMillis [
	"UNIX milliseconds at which this part began, or nil. Raw: see
	SWAOpenCodeNode>>eventMicros for why this must not be treated as a Squeak time."
	^ startMillis
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> status [
	^ status
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:36'
}
SWAOpenCodePart >> targetKey [
	"The Smalltalk thing this tool call was aimed at, in SWA's own crossRefKey
	spelling -- 'Class>>selector' for a method, 'Class' for a class -- or nil for a
	part that names none (a text block, or a tool that works on files).

	Same spelling as SWAOpenCodeToolCall>>targetKey on purpose: these keys are what
	a Code Map tile is called, so they cross-reference with no translation."
	className ifNil: [^ nil].
	className isEmpty ifTrue: [^ nil].
	^ (selector isNil or: [selector isEmpty])
		ifTrue: [className]
		ifFalse: [className , '>>' , selector]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> timeStamp [
	| ms |
	ms := startMillis ifNil: [timeCreated].
	ms ifNil: [^ nil].
	^ (DateAndTime fromUnixTime: ms // 1000) asLocal
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> tool [
	^ tool
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodePart >> type [
	"#text / #reasoning / #tool / #'step-start' / #'step-finish'."
	^ type
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:28'
}
SWAOpenCodePart >> writeValue: aValue on: s indent: n [
	"Pretty-print a decoded JSON value. Multi-line strings (a method body, a file's
	contents) are written out in full on their own lines rather than inlined, since
	reading them is the entire point of opening this pane."
	| pad |
	pad := String new: n * 2 withAll: $ .
	aValue isNil ifTrue: [^ s nextPutAll: pad; nextPutAll: '(none)'].
	(aValue isKindOf: Dictionary) ifTrue: [
		aValue keys asSortedCollection do: [:k |
			| v |
			v := aValue at: k.
			s nextPutAll: pad; nextPutAll: k asString; nextPutAll: ': '.
			((v isString and: [v includesSubstring: (String with: Character lf)])
				or: [v isKindOf: Dictionary])
				ifTrue: [s cr. self writeValue: v on: s indent: n + 1]
				ifFalse: [self writeValue: v on: s indent: 0].
			s cr].
		^ self].
	(aValue isArray or: [aValue isKindOf: OrderedCollection]) ifTrue: [
		aValue do: [:v | self writeValue: v on: s indent: n + 1. s cr].
		^ self].
	aValue isString ifTrue: [
		(aValue includesSubstring: (String with: Character lf))
			ifTrue: [aValue linesDo: [:ln | s nextPutAll: pad; nextPutAll: ln; cr]]
			ifFalse: [s nextPutAll: pad; nextPutAll: aValue].
		^ self].
	s nextPutAll: pad; nextPutAll: aValue printString
]
