"
One opencode session (a conversation) of one project, with its metadata, its
rolled-up cost/token totals and its list of SWAOpenCodeToolCalls.

`parentId` is not decoration: a `task` tool call spawns a SUBAGENT, which gets
its very own session row whose parent is the caller's. So the session list is a
forest, not a list, and any per-session total that ignores children
under-reports the work done -- #children and #allToolCalls exist for that.

`model` arrives from SQLite as a JSON blob {id, providerID, variant}, not a
name; #setFromRecord: unpacks it.

Costs and token counts are taken from the SESSION ROW rather than re-summed
from messages. opencode maintains them there, and re-summing would mean loading
21k message documents to reproduce a number the database already has.
"
Class {
	#name : #SWAOpenCodeSession,
	#superclass : #Object,
	#instVars : [
		'history',
		'id',
		'parentId',
		'title',
		'directory',
		'agent',
		'modelId',
		'modelVariant',
		'timeCreated',
		'timeUpdated',
		'timeCompacting',
		'cost',
		'tokensInput',
		'tokensOutput',
		'tokensReasoning',
		'tokensCacheRead',
		'tokensCacheWrite',
		'summaryFiles',
		'summaryAdditions',
		'summaryDeletions',
		'messagesUser',
		'messagesAssistant',
		'toolCalls',
		'children',
		'parts',
		'messageData'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> addChild: aSession [
	children add: aSession
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> addToolCall: aCall [
	toolCalls add: aCall
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> agent [
	^ agent
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> allToolCalls [
	"This session's calls plus every subagent's, chronological. A `task` call
	delegates work to a child session, so a parent's own list systematically
	under-reports what the conversation actually did."
	| out |
	out := OrderedCollection withAll: toolCalls.
	children do: [:c | out addAll: c allToolCalls].
	^ (out asSortedCollection: [:a :b |
		(a startMillis ifNil: [0]) <= (b startMillis ifNil: [0])]) asOrderedCollection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> children [
	"Subagent sessions spawned by a `task` call in this one."
	^ children
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> cost [
	"US dollars, as opencode accounted them on the session row."
	^ cost
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> countOfAccessKind: aSymbol [
	^ toolCalls count: [:c | c accessKind == aSymbol]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> durationMinutes [
	"Wall time from first to last activity. This is NOT time spent working: a
	session left open overnight and resumed reads as a 14-hour session."
	(timeCreated isNil or: [timeUpdated isNil]) ifTrue: [^ 0].
	^ (timeUpdated - timeCreated) / 60000.0
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> errorCount [
	^ toolCalls count: [:c | c status == #error]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> filesChanged [
	^ summaryFiles
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:28'
}
SWAOpenCodeSession >> history [
	^ history
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> id [
	^ id
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> isSubagent [
	^ parentId notNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> linesAdded [
	"From opencode's own diff summary of the session (files it changed on disk).
	Zero for a session that only edited the Squeak image -- the git-visible diff of
	an image edit is nothing."
	^ summaryAdditions
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> linesDeleted [
	^ summaryDeletions
]

{
	#category : #parts,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 16:37'
}
SWAOpenCodeSession >> messageData [
	"messageId -> the message's parsed record (cost, tokens, model, timing).
	Loaded once per session, on first ask."
	^ messageData ifNil: [
		messageData := Dictionary new.
		history db messagesForSession: id do: [:mid :d | messageData at: mid put: d].
		messageData]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> messagesAssistant [
	^ messagesAssistant
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> messagesUser [
	^ messagesUser
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> messagesUser: u assistant: a [
	messagesUser := u.
	messagesAssistant := a
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> modelId [
	^ modelId
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> parentId [
	^ parentId
]

{
	#category : #parts,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeSession >> parts [
	"Every part of this conversation in order, loaded ON FIRST ASK and cached.

	Not loaded during the project scan: multiplied by 223 sessions this would pull
	the text of every message in the store, and the whole point of the scan's
	`like` prefilter is to avoid exactly that. One session at a time is cheap."
	parts ifNotNil: [^ parts].
	parts := OrderedCollection new.
	history db partsForSession: id do: [:pid :mid :tc :fields :aRole :len |
		parts add: (SWAOpenCodePart new
			setSession: self id: pid message: mid time: tc
				fields: fields role: aRole size: len;
			yourself)].
	^ parts
]

{
	#category : #parts,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:28'
}
SWAOpenCodeSession >> partsByMessage [
	"OrderedCollection of {messageId. role. parts} in conversation order."
	| out index |
	out := OrderedCollection new.
	index := Dictionary new.
	self parts do: [:p |
		| entry |
		entry := index at: p messageId ifAbsent: [nil].
		entry ifNil: [
			entry := Array with: p messageId with: p role with: OrderedCollection new.
			index at: p messageId put: entry.
			out add: entry].
		(entry at: 3) add: p].
	^ out
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> printOn: aStream [
	aStream nextPutAll: 'Session('.
	aStream nextPutAll: (title ifEmpty: [id] ifNotEmpty: [title first: (title size min: 40)]).
	aStream nextPutAll: ', '; print: toolCalls size; nextPutAll: ' calls)'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> setHistory: aHistory record: rec [
	"rec is a SQLiteRecord from SWAOpenCodeDb>>sessionRowsForProject:do:."
	| m |
	history := aHistory.
	toolCalls := OrderedCollection new.
	children := OrderedCollection new.
	id := rec at: #id.
	parentId := rec at: #parent_id.
	title := (rec at: #title) ifNil: [''].
	directory := rec at: #directory.
	agent := rec at: #agent.
	timeCreated := rec at: #time_created.
	timeUpdated := rec at: #time_updated.
	timeCompacting := rec at: #time_compacting.
	cost := (rec at: #cost) ifNil: [0].
	tokensInput := (rec at: #tokens_input) ifNil: [0].
	tokensOutput := (rec at: #tokens_output) ifNil: [0].
	tokensReasoning := (rec at: #tokens_reasoning) ifNil: [0].
	tokensCacheRead := (rec at: #tokens_cache_read) ifNil: [0].
	tokensCacheWrite := (rec at: #tokens_cache_write) ifNil: [0].
	summaryFiles := (rec at: #summary_files) ifNil: [0].
	summaryAdditions := (rec at: #summary_additions) ifNil: [0].
	summaryDeletions := (rec at: #summary_deletions) ifNil: [0].
	messagesUser := 0.
	messagesAssistant := 0.
	"`model` is a JSON object, not a string. A malformed one must not abort a scan
	of 223 sessions, so failure degrades to 'unknown model'."
	m := [(rec at: #model) ifNotNil: [:s | Json readFrom: s readStream]]
		on: Error do: [:e | nil].
	m ifNotNil: [
		modelId := m at: 'id' ifAbsent: [nil].
		modelVariant := m at: 'variant' ifAbsent: [nil]]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> sortToolCalls [
	"Chronological by start. Calls with no recorded start sort first (they carry no
	information about where they belong, and dropping them would lose the count)."
	toolCalls := (toolCalls asSortedCollection: [:a :b |
		(a startMillis ifNil: [0]) <= (b startMillis ifNil: [0])]) asOrderedCollection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> timeCreated [
	"Unix milliseconds."
	^ timeCreated
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> timeStamp [
	"Session start in LOCAL time."
	timeCreated ifNil: [^ nil].
	^ (DateAndTime fromUnixTime: timeCreated // 1000) asLocal
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> timeUpdated [
	"Unix milliseconds."
	^ timeUpdated
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> title [
	^ title
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> tokensCacheRead [
	^ tokensCacheRead
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> tokensCacheWrite [
	^ tokensCacheWrite
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> tokensInput [
	^ tokensInput
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> tokensOutput [
	^ tokensOutput
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> toolCalls [
	"This session's own calls, chronological. See #allToolCalls for the subtree."
	^ toolCalls
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeSession >> toolCounts [
	"tool symbol -> number of calls, this session only."
	| b |
	b := Bag new.
	toolCalls do: [:c | c tool ifNotNil: [:t | b add: t]].
	^ b
]

{
	#category : #'code map',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:31'
}
SWAOpenCodeSession >> touchedClasses [
	"The live classes this session's Smalltalk edits landed in -- the INSTANCE side,
	since a metaclass and its class share one tile in the Code Map. Read/write of a
	class-side method counts as touching the class.

	This is the Code Map's real subject; #touchedPackageNames only says which
	packages to walk. Keys naming classes that no longer exist are skipped: the
	session may have created and later deleted them."
	| classes |
	classes := Set new.
	self allToolCalls do: [:c |
		(c targetKind == #method or: [c targetKind == #class]) ifTrue: [
			| clsName cls |
			clsName := (c targetKey findTokens: '>>') first.
			(clsName endsWith: ' class')
				ifTrue: [clsName := clsName copyFrom: 1 to: clsName size - 6].
			cls := Smalltalk at: clsName withBlanksTrimmed asSymbol ifAbsent: [nil].
			(cls notNil and: [cls isBehavior]) ifTrue: [classes add: cls theNonMetaClass]]].
	^ classes
]

{
	#category : #'code map',
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:32'
}
SWAOpenCodeSession >> touchedPackageNames [
	"Names of the packages this session's Smalltalk edits landed in, resolved
	through the live image. These are the packages the Code Map WALKS; which
	classes inside them it actually TILES is #touchedClasses.

	Classes that no longer exist are already dropped by #touchedClasses: the
	session may have created and later deleted them, and there is no package
	to ask."
	| names |
	names := Set new.
	self touchedClasses do: [:cls |
		(PackageOrganizer default packageOfClass: cls ifNone: [nil])
			ifNotNil: [:pkg | names add: pkg packageName]].
	^ names
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:32'
}
SWAOpenCodeSession >> wasCompacted [
	"True when the context window filled up and opencode summarised the history --
	the machine-visible trace of a conversation that outgrew its window."
	^ timeCompacting notNil
]
