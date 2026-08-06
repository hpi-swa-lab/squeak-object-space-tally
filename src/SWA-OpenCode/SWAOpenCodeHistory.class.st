"
Scans one opencode project out of an opencode.db into an in-image model:
SWAOpenCodeSessions holding SWAOpenCodeToolCalls. Everything downstream -- the
Code Map dataset, the file treemap, the timeline, the calendar, the session
table -- reads this object and never touches SQLite again.

	| h |
	h := SWAOpenCodeHistory onWorktree: '/home/jens/lively4/squeak'.
	h scan.            ""~30 s, see below""
	h openSessionTable.
	h openFileTreemap.
	h openTimeline.
	h openCalendar.
	h asDatasetNamed: 'opencode'.   ""-> drop on a Code Map""

WHY ONE BIG SCAN. The `part` table is 1.4 GB of JSON, most of it tool OUTPUT, and
it carries no index that helps here. So a project scan is an unavoidable ~30 s
sequential read (see SWAOpenCodeDb for the two tricks that got it down from 55 s)
-- and therefore something to do ONCE and keep. Hence #scan builds the whole
model eagerly, and #default caches the result per worktree in a class variable so
that a second `SWAOpenCodeHistory default` in the same image is instant.

WHAT AN AGENT SESSION LOOKS LIKE, from this project's 223 sessions / 24425 tool
calls: file access is a minority activity. The agent reads 765 files and writes
494, but reads 7100 and writes 6100 Smalltalk methods and classes -- because in
Squeak the program is the image, not a directory of text. That is the reason the
Code Map projection (#asDatasetNamed:) is the interesting output and the file
treemap is the sanity check.
"
Class {
	#name : #SWAOpenCodeHistory,
	#superclass : #Object,
	#instVars : [
		'db',
		'worktree',
		'projectId',
		'sessions',
		'sessionsById',
		'toolCalls',
		'scanSeconds'
	],
	#classVars : [
		'Cache'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> default [
	^ self forWorktree: self defaultWorktree
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> defaultWorktree [
	^ '/home/jens/lively4/squeak'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> flushCache [
	"Forget every scanned history, so the next #forWorktree: re-reads the store."
	Cache := nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> forWorktree: aString [
	"A SCANNED history, cached per worktree. The scan is a ~30 s sequential read of
	a 1.4 GB table, so paying it twice in one image would be a bug, not a slowdown.
	Send #flushCache after copying in a newer store."
	Cache ifNil: [Cache := Dictionary new].
	^ Cache at: aString ifAbsentPut: [(self onWorktree: aString) scan]
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> onWorktree: aString [
	"An UNSCANNED history over the default (Dropbox copy) store. Send #scan."
	^ self onWorktree: aString db: SWAOpenCodeDb default
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:33'
}
SWAOpenCodeHistory class >> onWorktree: aString db: aDb [
	^ self new setWorktree: aString db: aDb
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:55'
}
SWAOpenCodeHistory >> accessData [
	"The whole history as one access table."
	^ SWAOpenCodeAccessData
		fromToolCalls: toolCalls
		named: 'opencode ' , (worktree copyAfterLast: $/)
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:55'
}
SWAOpenCodeHistory >> asDataset [
	"A #openCodeAccess SWADataset ready to be dropped on any open SWAPane:

		SWAPane openPanes first view addDataset: SWAOpenCodeHistory default asDataset

	then pick it from the Data menu."
	| d |
	d := self accessData.
	^ SWADataset openCodeAccessFrom: d named: d name
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> codeKeys [
	"Every distinct Smalltalk class or 'Class>>selector' touched -- these are Code
	Map crossRefKeys already."
	^ (toolCalls inject: Set new into: [:acc :c |
		(c targetKind == #method or: [c targetKind == #class])
			ifTrue: [acc add: c targetKey]. acc])
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:55'
}
SWAOpenCodeHistory >> datasetForSession: aSession [
	"What ONE session touched, subagents included. This is the 'what did that
	conversation actually do' view -- the same metrics, a one-session domain."
	| d |
	d := SWAOpenCodeAccessData
		fromToolCalls: aSession allToolCalls
		named: 'opencode: ' , (aSession title first: (aSession title size min: 40)).
	^ SWADataset openCodeAccessFrom: d named: d name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> db [
	^ db
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> fileKeys [
	"Every distinct file path touched."
	^ (toolCalls inject: Set new into: [:acc :c |
		c targetKind == #file ifTrue: [acc add: c targetKey]. acc])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> linkSubagents [
	"Turn parent_id references into a forest. A parent outside this project (or
	already deleted) simply leaves the child as another root."
	sessions do: [:s |
		s parentId ifNotNil: [:pid |
			(sessionsById at: pid ifAbsent: [nil]) ifNotNil: [:p | p addChild: s]]]
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:29'
}
SWAOpenCodeHistory >> openCalendar [
	"Activity per calendar day; click a day to drill into its hours."
	| view |
	"#calendarTreeFor:, not #sessionTreeFor: -- the latter carries only tool calls,
	so a day of long conversations with little tooling read as almost empty."
	view := SWACalendarMorph on: (SWAOpenCodeNode calendarTreeFor: self).
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	^ self openPane: (SWAPane on: view) labeled: 'opencode calendar: ' , worktree
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:32'
}
SWAOpenCodeHistory >> openCodeMapFor: aSession [
	"A Code Map of the CLASSES this session actually worked in, coloured by what
	the session did to them.

	The baseline is deliberately class-grained. Scoping by PACKAGE was still far
	too coarse: one edited method dragged in its whole package, so a typical
	session showed a dozen coloured tiles adrift in fifteen hundred grey ones and
	the reading you came for was invisible. Scoping by METHOD would be too tight
	in the other direction -- an edit means nothing without the siblings it sits
	among. So a touched class comes in WHOLE, untouched methods included: those
	are the context. Classes nobody touched are left out."
	| names root view ds overlay classes |
	classes := aSession touchedClasses.
	names := aSession touchedPackageNames.
	"Answer nil, not the result of #inform: -- a session that only ran shell
	commands and greps has no Code Map, and callers need to be able to tell that
	from a window."
	names isEmpty ifTrue: [
		self inform: 'This session touched no Smalltalk class that still exists here.'.
		^ nil].
	root := SWACodeRootNode new name: aSession title; yourself.
	names do: [:n | root addPackages: n].
	root classFilter: classes.
	view := SWACodeTreemapMorph on: root.
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	ds := self datasetForSession: aSession.
	view addDataset: ds; selectDataset: ds.
	view ensureLayout.
	overlay := view overlayClass new.
	overlay treemapMorph: view.
	overlay extent: view extent.
	view overlayMorph: overlay.
	view addMorph: overlay.
	^ self openPane: (SWAPane on: view)
		labeled: 'Code Map of session: ' , aSession title
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:30'
}
SWAOpenCodeHistory >> openConversation: aSession [
	"The session as boxes: every message, every text, reasoning and tool part,
	sized by content. Selecting a box loads that part's full text into the Source
	flap -- which is opened here, because a view whose entire purpose is reading
	contents should not require finding the flap tab first."
	| pane |
	pane := self
		openTreemapOn: (SWAOpenCodeNode conversationTreeFor: aSession)
		labeled: 'opencode session: ' , aSession title.
	[pane model openSource] on: Error do: [:e | "flap is optional" nil].
	^ pane
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:12'
}
SWAOpenCodeHistory >> openFileTreemap [
	"What the agent read and wrote ON DISK, as a directory treemap."
	^ self
		openTreemapOn: (SWAOpenCodeNode fileTreeFor: self)
		labeled: 'opencode files: ' , worktree
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:48'
}
SWAOpenCodeHistory >> openFlow [
	"The WHOLE project as one flow: every tool call of every session, in order.

	Built from the session tree, not from conversation trees -- the latter would
	mean one query per session and would load the text of the entire store. So the
	items here are tool calls rather than message parts, which is also why the
	#cost and #tokens colour modes are worth having: across 223 sessions they
	actually vary."
	| view pane |
	view := SWAOpenCodeFlowMorph new.
	view setRoot: (SWAOpenCodeNode sessionTreeFor: self).
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	pane := self openPane: (SWAPane on: view) labeled: 'opencode flow: ' , worktree.
	[pane model openSource] on: Error do: [:e | nil].
	^ pane
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:46'
}
SWAOpenCodeHistory >> openFlowFor: aSession [
	"The conversation as a zoomable flow: top to bottom in reading order, lanes for
	user / assistant / reasoning / tool, height by content size. Wheel scrolls,
	CTRL-wheel zooms, right-click rebinds the axes."
	| view pane |
	view := SWAOpenCodeFlowMorph new.
	view setRoot: (SWAOpenCodeNode conversationTreeFor: aSession).
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	pane := self openPane: (SWAPane on: view) labeled: 'opencode flow: ' , aSession title.
	[pane model openSource] on: Error do: [:e | nil].
	^ pane
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:05'
}
SWAOpenCodeHistory >> openFlowMapFor: aSession [
	"The conversation as a 2D map of TURNS: your questions across the top, the work
	each one cost hanging beneath it. See SWAOpenCodeFlowMapMorph -- the sibling of
	#openFlowFor:, same items, a layout that uses the width of the window instead of
	spending it on four lanes."
	| view pane |
	view := SWAOpenCodeFlowMapMorph new.
	view setRoot: (SWAOpenCodeNode conversationTreeFor: aSession).
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	pane := self openPane: (SWAPane on: view) labeled: 'flow map: ' , aSession title.
	[pane model openSource] on: Error do: [:e | nil].
	^ pane
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:12'
}
SWAOpenCodeHistory >> openPane: aPane labeled: aLabel [
	"Open with the pane's own #openInWindowLabeled:bounds: rather than the
	inherited Morph>>openInWindow. The latter guesses an extent from #fullBounds
	and adds the window to the world before the caller can correct it, which in XR
	leaves the surrounding SRMorphPanel built around the wrong aspect.

	Bounds are clipped to the display so a pane opened on a smaller screen than the
	one the default was computed for is still fully reachable."
	| bounds |
	bounds := SWAPane defaultWindowBounds intersect: (0 @ 0 corner: Display extent).
	^ aPane openInWindowLabeled: aLabel bounds: bounds
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:04'
}
SWAOpenCodeHistory >> openSessionTable [
	^ (SWAOpenCodeSessionTable new on: self) open
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:12'
}
SWAOpenCodeHistory >> openSessionTreemap [
	"Every tool call, grouped by conversation. Use the Tree menu to switch this
	same tree to the Timeline or the Calendar."
	^ self
		openTreemapOn: (SWAOpenCodeNode sessionTreeFor: self)
		labeled: 'opencode sessions: ' , worktree
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:13'
}
SWAOpenCodeHistory >> openTimeline [
	"Tool calls on a time axis, stacked per bar by session."
	"The temporal views need no overlay -- unlike the treemap they handle their own
	mouseDown:/mouseMove:/showMenuAt: directly."
	| view |
	view := SWATimelineMorph on: (SWAOpenCodeNode sessionTreeFor: self).
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	^ self openPane: (SWAPane on: view) labeled: 'opencode timeline: ' , worktree
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:12'
}
SWAOpenCodeHistory >> openTreemapOn: aRootNode labeled: aLabel [
	"A treemap needs THREE things beyond its root, and leaving any of them out
	produces a pane that silently never appears or appears inert:

	  1. an EXTENT -- the layout is computed against it,
	  2. an OVERLAY morph -- all clicking, zooming, tooltips and the context menu
	     live there, not in the treemap,
	  3. an actual window -- `SWAPane on:` only BUILDS the pane."
	| view overlay |
	view := SWAOpenCodeTreemapMorph on: aRootNode.
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	view ensureLayout.
	overlay := view overlayClass new.
	overlay treemapMorph: view.
	overlay extent: view extent.
	view overlayMorph: overlay.
	view addMorph: overlay.
	^ self openPane: (SWAPane on: view) labeled: aLabel
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> printOn: aStream [
	aStream nextPutAll: 'OpenCodeHistory('; nextPutAll: (worktree ifNil: ['?']).
	aStream nextPutAll: ', '; print: sessions size; nextPutAll: ' sessions, '.
	aStream print: toolCalls size; nextPutAll: ' calls)'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:28'
}
SWAOpenCodeHistory >> projectId [
	"opencode's id for this worktree, which is what every project-wide query keys on."
	^ projectId
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> rootSessions [
	"Sessions the user actually started (subagent sessions hang off these)."
	^ sessions reject: [:s | s isSubagent]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> scan [
	"Read the whole project into memory. ~30 s; see the class comment for why that
	is inherent and why it is done exactly once."
	| t |
	t := [
		projectId := db projectIdForWorktree: worktree.
		self scanSessions.
		self scanToolCalls.
		self linkSubagents.
		sessions do: [:s | s sortToolCalls]] timeToRun.
	scanSeconds := t / 1000.0.
	^ self
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> scanSessions [
	| counts |
	sessions := OrderedCollection new.
	sessionsById := Dictionary new.
	db sessionRowsForProject: projectId do: [:rec |
		| s |
		s := SWAOpenCodeSession new setHistory: self record: rec; yourself.
		sessions add: s.
		sessionsById at: s id put: s].
	counts := db messageCountsForProject: projectId.
	sessions do: [:s |
		(counts at: s id ifAbsent: [nil]) ifNotNil: [:pair |
			s messagesUser: (pair at: 1) assistant: (pair at: 2)]]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> scanToolCalls [
	"The expensive pass. A part whose session we do not know is skipped rather than
	dropped silently into a phantom session -- it can only mean the session row was
	deleted while its parts survived."
	toolCalls := OrderedCollection new.
	db toolPartsForProject: projectId do: [:sid :fields |
		(sessionsById at: sid ifAbsent: [nil]) ifNotNil: [:s |
			| call |
			call := SWAOpenCodeToolCall session: s fields: fields.
			s addToolCall: call.
			toolCalls add: call]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> sessions [
	"All sessions, subagents included, oldest first."
	^ sessions
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:28'
}
SWAOpenCodeHistory >> sessionsById [
	"Session id -> SWAOpenCodeSession, for joining a raw scan back to its sessions.
	Populated by the same scan that fills #sessions."
	self sessions.
	^ sessionsById ifNil: [sessionsById := Dictionary new]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> setWorktree: aString db: aDb [
	worktree := aString.
	db := aDb.
	sessions := OrderedCollection new.
	sessionsById := Dictionary new.
	toolCalls := OrderedCollection new
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> summaryString [
	| s |
	s := WriteStream on: String new.
	s nextPutAll: worktree; cr.
	s print: sessions size; nextPutAll: ' sessions ('.
	s print: (sessions count: [:x | x isSubagent]); nextPutAll: ' subagent), '.
	s print: toolCalls size; nextPutAll: ' tool calls'; cr.
	s nextPutAll: 'reads: '; print: (toolCalls count: [:c | c accessKind == #read]).
	s nextPutAll: '   writes: '; print: (toolCalls count: [:c | c accessKind == #write]).
	s nextPutAll: '   other: '; print: (toolCalls count: [:c | c accessKind == #other]); cr.
	s nextPutAll: 'files touched: '; print: self fileKeys size.
	s nextPutAll: '   methods/classes touched: '; print: self codeKeys size; cr.
	s nextPutAll: 'cost: $'; nextPutAll: ((sessions inject: 0 into: [:a :x | a + x cost]) printShowingDecimalPlaces: 2).
	scanSeconds ifNotNil: [s nextPutAll: '   (scan '; nextPutAll: (scanSeconds printShowingDecimalPlaces: 1); nextPutAll: ' s)'].
	^ s contents
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> toolCalls [
	^ toolCalls
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> toolCounts [
	| b |
	b := Bag new.
	toolCalls do: [:c | c tool ifNotNil: [:t | b add: t]].
	^ b
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 14:34'
}
SWAOpenCodeHistory >> worktree [
	^ worktree
]
