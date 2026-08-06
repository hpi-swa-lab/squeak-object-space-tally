"
A STRICTLY READ-ONLY window onto an opencode store (the `opencode.db` SQLite
file under `~/.local/share/opencode`).

Read-only is not politeness, it is a requirement: this database belongs to a
live process that may be running right now, and SQLite's default
`sqlite3_open` would happily create/rewrite the `-wal` and `-shm` sidecars.
So the connection is opened through `sqlite3_open_v2` with
SQLITE_OPEN_READONLY (see `SqliteLibrary>>openReadOnly:`, an extension method
of this package); any statement that would write fails with
'attempt to write a readonly database'.

DEFAULT PATH points at a COPY in Dropbox on purpose, so that experiments cannot
disturb the live store. `SWAOpenCodeDb liveStorePath` names the real one for
when that is wanted deliberately.

SCHEMA, the parts that matter:
	project   id, worktree            -- one row per checked-out working tree
	session   id, project_id, parent_id, title, agent, model, directory,
	          time_created, time_updated, cost, tokens_*, summary_*
	message   id, session_id, time_created, data (JSON)
	part      id, message_id, session_id, time_created, data (JSON)

Everything interesting about a tool call lives inside `part.data`, a JSON
document that also carries the tool's ENTIRE output -- a single `read` part can
be hundreds of kilobytes. Two consequences shape every query here:

1. NEVER `select p.data`. Pull individual fields with `json_extract` so SQLite
   does the projection and only small strings cross the FFI boundary.
2. Prefilter with `p.data like '{""type"":""tool""%'`. `type` is always the first
   key, so this is a cheap string compare that skips parsing the text and
   step-finish parts entirely. It takes a full scan of the 24k tool parts in
   this project from ~55 s down to ~16 s.

Use one `json_extract(data, path1, path2, ...)` call with MANY paths rather than
many calls with one path each: multiple paths parse the document once and answer
a JSON array, N calls parse it N times.
"
Class {
	#name : #SWAOpenCodeDb,
	#superclass : #Object,
	#instVars : [
		'path',
		'connection',
		'mutex'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb class >> default [
	^ self onPath: self defaultPath
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:27'
}
SWAOpenCodeDb class >> defaultPath [
	"A COPY of the store, taken 2026-07-29. Deliberately the default: analysing the
	live database of a tool that may be running is how you find out the hard way
	that 'read-only' had a loophole."
	^ '/home/jens/Dropbox/tmp/opencode_alto_2026-07-29/opencode/opencode.db'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb class >> liveStorePath [
	"The real store, written by every running opencode. We only ever open it
	read-only, and only when that is meant deliberately:

		SWAOpenCodeDb onPath: SWAOpenCodeDb liveStorePath"
	| home |
	home := [OSProcess thisOSProcess environment at: 'HOME']
		on: Error do: [:e | '~'].
	^ home , '/.local/share/opencode/opencode.db'
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb class >> onPath: aFileName [
	^ self new setPath: aFileName
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:34'
}
SWAOpenCodeDb >> allPartsForProject: aProjectId do: aSevenArgBlock [
	"Evaluate aSevenArgBlock with (partId, sessionId, messageId, timeCreated,
	docPrefix, byteSize, fields) for EVERY part of a project -- not just the tool calls
	#toolPartsForProject:do: returns. `fields` is { messageFields . partFields }:
	{ role . cost . modelID . agent . tokens.total } and { input.class . input.name }.

	NO json_extract OF THE PART DOCUMENT for the type. The document is what makes
	this expensive (a tool part carries whole files), and `type` is always its FIRST
	key -- so a 64-character SUBSTR carries the type and, for a tool part, the tool
	name, read out by #partKindFromPrefix: without parsing anything.

	Everything else IS extracted, and measured before it was written:

		role only                       4417 ms
		+ cost, model, agent             4455 ms   (same message parse)
		+ the tool call's target class   4969 ms

	80128 rows either way. A shallow json_extract short-circuits, which is why the
	target class costs 500 ms here and not the 16 s the eleven-path tool scan takes.
	There is nothing here worth caching or loading in the background."
	| sql |
	sql := 'select p.id, p.session_id, p.message_id, p.time_created, substr(p.data, 1, 64), length(p.data),'
		, ' json_extract(m.data, ''$.role'', ''$.cost'', ''$.modelID'', ''$.agent'', ''$.tokens.total''),'
		, ' json_extract(p.data, ''$.state.input.class'', ''$.state.input.name'')'
		, ' from part p join message m on m.id = p.message_id'
		, ' where p.session_id in (select id from session where project_id = ?)'
		, ' order by p.time_created'.
	^ self query: sql args: (Array with: aProjectId) do: [:pid :sid :mid :tc :prefix :len :mjson :pjson |
		"A brace array, not Array with:...: the class-side constructor stops at SIX
		arguments and this needs seven."
		aSevenArgBlock valueWithArguments: {
			pid. sid. mid. tc. prefix. len.
			{(mjson ifNil: [Array new: 5] ifNotNil: [Json readFrom: mjson readStream]).
			 (pjson ifNil: [Array new: 2] ifNotNil: [Json readFrom: pjson readStream])}}]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> connection [
	"Opened lazily, and opened READ-ONLY (see the class comment). Kept open for the
	life of this object because a full-scan analysis issues several statements."
	connection ifNotNil: [^ connection].
	(FileDirectory default fileExists: path)
		ifFalse: [self error: 'No opencode store at ' , path].
	^ connection := SQLiteConnection readOnlyFileNamed: path
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:32'
}
SWAOpenCodeDb >> countPartsForProject: aProjectId [
	"How many parts the project has. ~300 ms, which is worth paying to give
	#allPartsForProject:do: a real progress bar instead of a spinner that cannot say
	how far along it is."
	| n |
	n := 0.
	self query: 'select count(*) from part p where p.session_id in (select id from session where project_id = ?)'
		args: (Array with: aProjectId)
		do: [:c | n := c].
	^ n
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:29'
}
SWAOpenCodeDb >> messageCountsForProject: aProjectId [
	"sessionId -> {userCount. assistantCount}. Roles are only 'user' and
	'assistant': opencode keeps the system prompt as a `system` array INSIDE each
	assistant message, so there is no system role to count.

	`message.data` is small compared with `part.data`, but still worth extracting
	rather than fetching -- and grouping in SQL beats grouping in the image."
	| d |
	d := Dictionary new.
	self query: 'select session_id, json_extract(data, ''$.role'') as role, count(*) as n
		 from message where session_id in (select id from session where project_id = ?)
		 group by 1, 2'
		args: (Array with: aProjectId)
		do: [:sid :role :n |
			| pair |
			pair := d at: sid ifAbsentPut: [Array with: 0 with: 0].
			role = 'user'
				ifTrue: [pair at: 1 put: n]
				ifFalse: [pair at: 2 put: (pair at: 2) + n]].
	^ d
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:37'
}
SWAOpenCodeDb >> messagesForSession: aSessionId do: aTwoArgBlock [
	"Evaluate with (messageId, parsedData) for each message of one session.

	The WHOLE document is fetched here, unlike parts -- a message row is under a
	kilobyte (it holds cost, tokens, model, timing and finish reason, but no
	content; the content lives in the parts). Cheap for one session, and the only
	place per-message cost and token counts exist."
	^ self query: 'select id, data from message where session_id = ? order by time_created'
		args: (Array with: aSessionId)
		do: [:mid :d |
			aTwoArgBlock value: mid value: (d
				ifNil: [Dictionary new]
				ifNotNil: [[Json readFrom: d readStream] on: Error do: [:e | Dictionary new]])]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:03'
}
SWAOpenCodeDb >> mutex [
	^ mutex ifNil: [mutex := Mutex new]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:27'
}
SWAOpenCodeDb >> partDataAt: aPartId [
	"The complete JSON document of ONE part, fetched on demand -- this is the only
	place the tool output is ever loaded, and only for the part being looked at."
	| out |
	out := nil.
	self query: 'select data from part where id = ?' args: (Array with: aPartId)
		do: [:d | out := d].
	^ out
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:28'
}
SWAOpenCodeDb >> partKindFromPrefix: aString [
	"{ type . tool } read straight out of the opening characters of a part document,
	without a JSON parse -- see #allPartsForProject:do: for why.

	Answers nil for a STEP MARKER. Those documents open with `snapshot` or `reason`
	rather than `type`, which makes them free to identify and free to drop: they are
	opencode's framing of a message, not something that happened, and there are two
	per assistant turn."
	| type tool |
	aString ifNil: [^ nil].
	type := self valueAfter: '"type":"' in: aString.
	type ifNil: [^ nil].
	tool := self valueAfter: '"tool":"' in: aString.
	^ {type asSymbol. tool}
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 12:35'
}
SWAOpenCodeDb >> partsForSession: aSessionId do: aBlock [
	"Metadata for EVERY part of one session -- text, reasoning, tool, step markers --
	in conversation order, with the role of the owning message.

	The whole-project scan cannot afford this (it json_extracts the big documents
	and pulls `$.text` whole), but one session is a few hundred parts, so here it is
	the right trade: it buys the conversation view its labels and previews in a
	single query. The tool OUTPUT is still not fetched -- that stays on demand in
	#partDataAt:, because a single read part can be hundreds of kilobytes."
	| sql |
	sql := 'select p.id, p.message_id, p.time_created, json_extract(p.data, '
		, '''$.type'', ''$.tool'', ''$.state.status'', ''$.state.title'','
		, ' ''$.state.time.start'', ''$.text'','
		"End times, and BOTH spellings: a tool part carries its interval under
		$.state.time, a reasoning part carries it at the top level under $.time.
		Pulling only one of them is why duration was blank for half the parts."
		, ' ''$.state.time.end'', ''$.time.start'', ''$.time.end'','
		"WHAT the call was about. The squeak_* MCP tools leave $.state.title
		EMPTY, so without these a whole conversation of method edits reads as
		twenty identical rows saying 'squeak_get_source_code'. All three are
		short identifiers -- unlike $.state.input.source, which is a method
		body and stays out."
		, ' ''$.state.input.class'', ''$.state.input.method'', ''$.state.input.name''),'
		, ' json_extract(m.data, ''$.role''),'
		, ' length(p.data)'
		, ' from part p join message m on m.id = p.message_id'
		, ' where p.session_id = ? order by p.time_created, p.id'.
	"length(p.data) is the one honest size we can have for a part without loading
	it: it needs no JSON parse and it counts the tool output we deliberately do not
	fetch. It is the raw document length, so it overstates a part by its JSON
	scaffolding -- fine for sizing a box, wrong for anything quantitative."
	"valueWithArguments:, not a chain of value: -- BlockClosure only implements
	#value: up to FOUR arguments, and this block takes six."
	^ self query: sql args: (Array with: aSessionId) do: [:pid :mid :tc :json :role :len |
		aBlock valueWithArguments: (Array
			with: pid with: mid with: tc
			with: (json ifNil: [Array new: 12] ifNotNil: [Json readFrom: json readStream])
			with: role with: len)]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> path [
	^ path
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> printOn: aStream [
	super printOn: aStream.
	aStream nextPutAll: ' on '; nextPutAll: (path ifNil: ['<no path>'])
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> projectIdForWorktree: aString [
	"Exact match first, then unique substring -- so 'squeak' resolves while
	'/home/jens/lively4/squeak' still wins over '.../squeak-object-space-tally'."
	| all hits |
	all := self projects.
	(all detect: [:p | (p at: 2) = aString] ifNone: [nil])
		ifNotNil: [:p | ^ p first].
	hits := all select: [:p | (p at: 2) includesSubstring: aString caseSensitive: false].
	hits size = 1 ifTrue: [^ hits first first].
	hits isEmpty
		ifTrue: [self error: 'No opencode project matching ' , aString printString]
		ifFalse: [self error: 'Ambiguous worktree ' , aString printString , ': '
			, ((hits collect: [:p | p at: 2]) asArray) printString]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> projects [
	"{ id. worktree } pairs, alphabetically by worktree."
	| out |
	out := OrderedCollection new.
	self query: 'select id, worktree from project order by worktree' args: #()
		do: [:id :wt | out add: {id. wt}].
	^ out asArray
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:03'
}
SWAOpenCodeDb >> query: aSqlString args: anArray do: aBlock [
	"Stream the rows of a prepared statement. Note the block-arity rule inherited
	from SqliteLibrary: a block whose numArgs EQUALS the column count receives the
	columns as separate arguments, any other arity receives one SQLiteRecord. So a
	one-column query with a one-argument block gets the raw value, NOT a record --
	the source of a puzzling 'Only integers should be used as indices'."
	"SERIALISED. Once content is fetched on a background process while the UI
	queries too, two processes share one sqlite3*. A statement here is a
	prepare/step*/finalize SEQUENCE in Smalltalk, and Squeak can preempt between
	any two of those sends -- so without this, an interleaving is a matter of
	timing, not of luck. The lock is per connection, which is the granularity
	SQLite itself cares about."
	^ self mutex critical: [
		self connection execute: aSqlString args: anArray do: aBlock]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> sessionRowsForProject: aProjectId do: aBlock [
	"One SQLiteRecord per session. `model` is a JSON blob {id, providerID, variant},
	not a name -- SWAOpenCodeSession unpacks it."
	^ self
		query: 'select id, parent_id, title, directory, agent, model,
			time_created, time_updated, time_compacting,
			cost, tokens_input, tokens_output, tokens_reasoning,
			tokens_cache_read, tokens_cache_write,
			summary_files, summary_additions, summary_deletions
		 from session where project_id = ? order by time_created'
		args: (Array with: aProjectId)
		do: aBlock
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:28'
}
SWAOpenCodeDb >> setPath: aFileName [
	path := aFileName.
	connection := nil
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:29'
}
SWAOpenCodeDb >> toolPartFieldPaths [
	"The `$.`-paths pulled out of every tool part, IN ORDER. They are handed to a
	single json_extract with many paths, which parses the (often huge) document
	ONCE and answers a JSON array -- N single-path calls would parse it N times.

	Deliberately absent: `$.state.output`, `$.state.input.source`,
	`$.state.input.content`, `$.state.metadata.preview`. Those hold whole files and
	whole method bodies; pulling them would move gigabytes across FFI to compute
	nothing. `command` is kept because bash commands are short and naming the
	program run is most of what a bash call means."
	^ #('$.tool' '$.state.status' '$.state.time.start' '$.state.time.end'
		'$.state.input.filePath' '$.state.input.class' '$.state.input.method'
		'$.state.input.name' '$.state.input.action' '$.state.input.pattern'
		'$.state.input.command')
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:29'
}
SWAOpenCodeDb >> toolPartLikePattern [
	"A single-quoted SQL literal matching the opening of a tool part document.
	Built from Character doubleQuote rather than written inline, because a literal
	double quote inside a Smalltalk method comment would close the comment."
	| q |
	q := String with: $".
	^ '''{' , q , 'type' , q , ':' , q , 'tool' , q , '%'''
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:29'
}
SWAOpenCodeDb >> toolPartsForProject: aProjectId do: aTwoArgBlock [
	"Evaluate aTwoArgBlock with (sessionId, fieldArray) for every tool part of a
	project, where fieldArray holds #toolPartFieldPaths in order (nil for absent).

	The LIKE prefilter on the literal prefix of a tool document is the whole
	performance story: `type` is always the FIRST key of a part document, so this is
	a string compare that skips PARSING every text and step-finish part. Measured on
	the squeak project (24425 tool parts in a 1.4 GB store): 55 s without it, 16 s
	with it."
	| sql |
	sql := 'select p.session_id, json_extract(p.data, '
		, ((self toolPartFieldPaths collect: [:p | '''' , p , '''']) inject: nil into: [:a :b |
			a ifNil: [b] ifNotNil: [a , ', ' , b]])
		, ') from part p where p.session_id in (select id from session where project_id = ?)'
		, ' and p.data like ' , self toolPartLikePattern.
	^ self query: sql args: (Array with: aProjectId) do: [:sid :json |
		aTwoArgBlock value: sid value: (json
			ifNil: [Array new: self toolPartFieldPaths size]
			ifNotNil: [Json readFrom: json readStream])]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:28'
}
SWAOpenCodeDb >> valueAfter: aKey in: aString [
	"The JSON string value following aKey, or nil. Deliberately naive: it is applied
	only to the first 64 characters of a document whose shape we know, where the
	value cannot contain an escaped quote. Anything more would be a JSON parser,
	which is exactly the cost this avoids."
	| i j |
	i := aString indexOfSubCollection: aKey startingAt: 1.
	i = 0 ifTrue: [^ nil].
	i := i + aKey size.
	j := aString indexOf: $" startingAt: i ifAbsent: [0].
	j = 0 ifTrue: [^ nil].
	^ aString copyFrom: i to: j - 1
]
