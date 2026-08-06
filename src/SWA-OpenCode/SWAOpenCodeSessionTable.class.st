"
A sortable, per-session table -- the in-image equivalent of the CSV that
stats.py used to write, minus the export step.

Columns follow the CSV: when, title, agent, model, wall-clock minutes, user and
assistant message counts, tool calls, reads, writes, errors, cost, tokens, and
the subagent/compacted flags. Click a column heading to sort by it; click again
to reverse.

TWO NUMBERS THAT LOOK WRONG AND ARE NOT:

`min` is wall time from first to last activity, NOT time spent working. A
session left open over lunch and resumed reads as a three-hour session. It is
still the only duration the data contains.

`+lines`/`-lines` come from opencode's own diff summary of files changed on
disk, so they are ZERO for the many sessions here that only edited the Squeak
image. The git-visible diff of an image edit is nothing; `writes` is the column
that reflects that work.

Subagent sessions are listed in their own right (a `task` call spawns a real
session with its own row) and marked in the `sub` column, so the totals at the
bottom do not double-count them against their parents.
"
Class {
	#name : #SWAOpenCodeSessionTable,
	#superclass : #Model,
	#instVars : [
		'history',
		'rows',
		'sortKey',
		'sortAscending',
		'selectionIndex',
		'buttons'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:19'
}
SWAOpenCodeSessionTable class >> columns [
	"{ heading. sortKey. block answering the cell value } -- one place, so the list,
	the sorter and the CSV export can never drift apart."
	^ {
		{'when'.      #when.     [:s | s timeStamp ifNil: ['-'] ifNotNil: [:t |
			t asDate yyyymmdd , ' ' , t asTime print24]]}.
		{'title'.     #title.    [:s | s title truncateTo: 50]}.
		{'agent'.     #agent.    [:s | s agent ifNil: ['-']]}.
		{'model'.     #model.    [:s | (s modelId ifNil: ['-']) copyAfterLast: $/]}.
		{'min'.       #minutes.  [:s | s durationMinutes rounded printString]}.
		{'user'.      #user.     [:s | s messagesUser printString]}.
		{'asst'.      #asst.     [:s | s messagesAssistant printString]}.
		{'calls'.     #calls.    [:s | s toolCalls size printString]}.
		{'reads'.     #reads.    [:s | (s countOfAccessKind: #read) printString]}.
		{'writes'.    #writes.   [:s | (s countOfAccessKind: #write) printString]}.
		{'err'.       #errors.   [:s | s errorCount printString]}.
		{'cost $'.    #cost.     [:s | s cost printShowingDecimalPlaces: 2]}.
		{'tok in'.    #tokIn.    [:s | s tokensInput printString]}.
		{'tok out'.   #tokOut.   [:s | s tokensOutput printString]}.
		{'+lines'.    #added.    [:s | s linesAdded printString]}.
		{'-lines'.    #deleted.  [:s | s linesDeleted printString]}.
		{'sub'.       #sub.      [:s | s isSubagent ifTrue: ['yes'] ifFalse: ['']]}.
		{'compact'.   #compact.  [:s | s wasCompacted ifTrue: ['yes'] ifFalse: ['']]}
	}
]

{
	#category : #export,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> asCsvString [
	"The same table as CSV, in the current sort order -- for when it has to leave
	the image after all. Quotes are doubled and every field is quoted, because
	session titles contain commas and the occasional newline."
	^ String streamContents: [:s |
		| cols |
		cols := self class columns.
		(cols collect: [:c | c first]) do: [:h | s nextPut: $"; nextPutAll: h; nextPut: $"]
			separatedBy: [s nextPut: $,].
		s cr.
		rows do: [:row |
			(cols collect: [:c | (c third value: row) asString]) do: [:cell |
				s nextPut: $".
				cell do: [:ch |
					ch = $" ifTrue: [s nextPut: $"].
					s nextPut: (ch = Character cr ifTrue: [Character space] ifFalse: [ch])].
				s nextPut: $"]
				separatedBy: [s nextPut: $,].
			s cr]]
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> buttonColor [
	^ Color gray: 0.3
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> buttonLabelled: aString action: aSelector [
	"A bar button that sends aSelector to me. Same SimpleButtonMorph at the same
	grey as SWAPane>>buttonLabelled:action:."
	^ SimpleButtonMorph new
		label: aString;
		color: self buttonColor;
		target: self;
		actionSelector: aSelector;
		hResizing: #rigid; vResizing: #rigid;
		yourself
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> buttonSpecs [
	"{ label. selector. needsSelection. balloon }. Declared in one place so
	#newButtonBar can build them and #updateButtonStates can enable/disable them
	without the two drifting apart.

	FOUR VIEWS OF THE SELECTED SESSION, then the one project-wide view. The bar had
	thirteen buttons, seven of which nobody reached for: 'Session' and 'Treemap' are
	older takes on what the Flow and Flow Map now do better, the four 'All *'
	entries answered project-wide questions from a table whose every row is one
	session, and CSV is an export -- a thing you do once, not a thing you aim at.

	Nothing is deleted, only demoted: they are all on the BURGER menu at the far
	left of the bar (and on the list's right-click menu, which shows the same
	items), which is where a rarely-wanted command belongs."
	^ {
		{'Code Map'.   #openSelectedCodeMap.  true.
			'Code Map of the classes this session touched, coloured by what it did'}.
		{'Flow'.       #openSelectedFlow. true.
			'The conversation top to bottom, zoomable; wheel scrolls, CTRL-wheel zooms'}.
		{'Flow Map'.   #openSelectedFlowMap. true.
			'The same conversation as a 2D grid: your questions across the top, the work each one cost beneath it'}.
		{'Timeline'.   #openSelectedTimeline. true.
			'This session over time; width = duration, height = cost / tokens / size'}.
		{'-'. nil. false. nil}.
		{'Calendar'.   #openAllCalendar. false. 'Activity per day'}
	}
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:04'
}
SWAOpenCodeSessionTable >> columnHeadings [
	"Marks the active sort column, so the table says how it is ordered."
	^ self class columns collect: [:c |
		c second == sortKey
			ifTrue: [c first , (sortAscending ifTrue: [' ^'] ifFalse: [' v'])]
			ifFalse: [c first]]
]

{
	#category : #export,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:04'
}
SWAOpenCodeSessionTable >> copyCsvToClipboard [
	Clipboard clipboardText: self asCsvString.
	self inform: 'Session table copied as CSV (' , rows size printString , ' rows).'
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> detail [
	"What the selected session actually did: its tool mix, and the targets it
	touched most. This is the drill-down the CSV could never carry."
	| s |
	s := self selectedSession ifNil: [^ self summaryText].
	^ String streamContents: [:t |
		t nextPutAll: s title; cr.
		t nextPutAll: s id; cr; cr.
		t nextPutAll: 'agent '; nextPutAll: (s agent ifNil: ['-']).
		t nextPutAll: '   model '; nextPutAll: (s modelId ifNil: ['-']); cr.
		s isSubagent ifTrue: [t nextPutAll: 'subagent of '; nextPutAll: s parentId; cr].
		s children isEmpty ifFalse: [
			t nextPutAll: 'spawned '; print: s children size; nextPutAll: ' subagent session(s)'; cr].
		s wasCompacted ifTrue: [t nextPutAll: 'context was compacted'; cr].
		t cr; nextPutAll: 'tools:'; cr.
		(s toolCounts sortedCounts) do: [:assoc |
			t tab; print: assoc key; tab; nextPutAll: assoc value asString; cr].
		t cr; nextPutAll: 'most touched:'; cr.
		self topTargetsFor: s into: t]
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> disabledButtonColor [
	"SimpleButtonMorph has no #enabled: -- only PluggableButtonMorphPlus does, and
	that is the button this bar used to be built from. Standard buttons therefore
	show 'you cannot press this yet' the only way they can, by going darker. The
	actions guard themselves anyway (`self selectedSession ifNil: [^ self]`), so
	this is an affordance, not the enforcement."
	^ Color gray: 0.18
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:20'
}
SWAOpenCodeSessionTable >> list [
	"COLUMN-MAJOR: an Array of columns, each an Array of that column's cells.

	This is easy to get backwards, and getting it backwards fails in a way that
	looks like a rendering bug rather than a data-shape bug.
	PluggableMultiColumnListMorph reads a cell as
	`(getList at: columnIndex) at: rowIndex`, and takes `getFullList size` as its
	COLUMN COUNT -- so handing it an array of ROWS makes it believe there are 224
	columns of one character each, space-fill them across the pane, and shred every
	cell into a vertical sliver.

	Row 1 of each column is the HEADING, carried inside the list rather than as a
	separate morph: the widget has no column-label support (no
	getColumnLabelsSelector:, no columnLabelAction:), but it does size each column
	to its widest cell, so a heading travelling as an ordinary row is aligned for
	free. The offset that costs is confined to #selectionIndex / #selectionIndex:."
	| blocks headings |
	blocks := self class columns collect: [:c | c third].
	headings := self columnHeadings.
	^ (1 to: blocks size) collect: [:ci |
		(Array with: (headings at: ci))
			, (rows collect: [:s | ((blocks at: ci) value: s) asString]) asArray]
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:16'
}
SWAOpenCodeSessionTable >> listMenu: aMenu [
	"Sorting, then everything the button bar does NOT carry: the older per-session
	views and the four project-wide ones. See #buttonSpecs for why they are here
	rather than on the bar."
	| sortMenu |
	aMenu addTitle: 'sessions'.
	sortMenu := MenuMorph new.
	self class columns doWithIndex: [:c :i |
		sortMenu add: c first target: self selector: #sortByColumnIndex: argument: i].
	aMenu add: 'sort by...' subMenu: sortMenu.
	aMenu add: 'reverse sort order' target: self selector: #reverseSort.
	aMenu addLine.
	aMenu add: 'copy table as CSV' target: self selector: #copyCsvToClipboard.
	self selectedSession ifNotNil: [:s |
		aMenu addLine.
		aMenu add: 'conversation (boxes) of this session' target: self selector: #openSelectedConversation.
		aMenu add: 'treemap of this session' target: self selector: #openSelectedTreemap].
	aMenu addLine.
	aMenu add: 'ALL: files the project touched' target: self selector: #openAllFiles.
	aMenu add: 'ALL: tool calls by session' target: self selector: #openAllSessions.
	aMenu add: 'ALL: the project as one flow' target: self selector: #openAllFlow.
	aMenu add: 'ALL: the project over time' target: self selector: #openAllTimeline.
	^ aMenu
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> newButtonBar [
	"BURGER first at the far left -- the overflow home for everything rare, exactly
	as SWAPane>>buildHeaderRow does it -- then the four per-session views and the
	project Calendar."
	| bar menuButton |
	bar := self newChromeRow.
	menuButton := IconicButton new
		labelGraphic: MenuIcons smallJustifiedIcon;
		color: self buttonColor;
		borderWidth: 0;
		target: self;
		actionSelector: #openTableMenu;
		hResizing: #rigid; vResizing: #rigid;
		yourself.
	"Pad so the icon matches a text button's height and the row lines up."
	menuButton extent: (menuButton fullBounds extent
		max: (menuButton fullBounds width @ (self buttonLabelled: 'X' action: nil) fullBounds height)).
	menuButton setBalloonText: 'Table menu -- export, and the views that are not on the bar'.
	bar addMorphBack: menuButton.
	buttons := OrderedCollection new.
	self buttonSpecs do: [:spec |
		spec second
			ifNil: [bar addMorphBack: (Morph new
				extent: 10 @ 4; color: Color transparent; yourself)]
			ifNotNil: [:sel |
				| b |
				b := self buttonLabelled: spec first action: sel.
				b setBalloonText: spec fourth.
				b setProperty: #needsSelection toValue: spec third.
				buttons add: b.
				bar addMorphBack: b]].
	^ bar
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> newChromeRow [
	"The dark, width-filling button strip -- the same one SWAPane builds, so the two
	tools read as one application.

	A plain Morph with a TableLayout, NOT `AlignmentMorph newRow`: that answers a
	morph whose default colour is (Color r: 0.8 g: 1 b: 0.8), and THAT was the weird
	pale green behind the buttons. Nobody chose it; it was the default nobody
	overrode."
	^ Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		layoutInset: 4;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> on: aHistory [
	history := aHistory.
	sortKey := #when.
	sortAscending := false.
	selectionIndex := 0.
	self resort.
	^ self
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> open [
	"A multi-column list of sessions over a detail pane."
	| window list detail |
	window := SystemWindow labelled: 'opencode sessions -- ' , history worktree.
	window model: self.
	list := PluggableMultiColumnListMorph
		on: self
		list: #list
		selected: #selectionIndex
		changeSelected: #selectionIndex:
		menu: #listMenu:.
	"EVERY column defaults to #spaceFill at weight 1, so eighteen of them each get
	one eighteenth of the pane and the cells shred into unreadable slivers. Ask for
	the natural width instead and let the scroller be wider than the window --
	which is the whole reason the horizontal scrollbar has to be enabled too."
	list
		hResizingForColumns: (Array new: self class columns size withAll: #shrinkWrap);
		hScrollBarPolicy: #whenNeeded;
		vScrollBarPolicy: #whenNeeded.
	"#hResizingForColumns: only caches a property -- it does NOT re-run
	#updateColumns, and the column morphs were already built by #on:list:... above.
	Without this send the setting is silently ignored and the cells stay shredded."
	list updateColumns.
	detail := PluggableTextMorph on: self text: #detail accept: nil.
	"Fractional frames, so the bar keeps its height as the window is resized. The
	0.06 band is generous enough for the buttons at any theme font size."
	window addMorph: self newButtonBar frame: (0 @ 0 corner: 1 @ 0.06).
	window addMorph: list frame: (0 @ 0.06 corner: 1 @ 0.64).
	window addMorph: detail frame: (0 @ 0.64 corner: 1 @ 1).
	self updateButtonStates.
	window openInWorld.
	window extent: (1250 @ 750 min: Display extent - (40 @ 40)).
	^ window
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openAllCalendar [
	^ history openCalendar
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openAllFiles [
	^ history openFileTreemap
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:48'
}
SWAOpenCodeSessionTable >> openAllFlow [
	^ history openFlow
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openAllSessions [
	^ history openSessionTreemap
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openAllTimeline [
	^ history openTimeline
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openSelectedCodeMap [
	| s |
	s := self selectedSession ifNil: [^ self].
	^ history openCodeMapFor: s
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> openSelectedConversation [
	| s |
	s := self selectedSession ifNil: [^ self].
	^ history openConversation: s
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:47'
}
SWAOpenCodeSessionTable >> openSelectedFlow [
	| s |
	s := self selectedSession ifNil: [^ self].
	^ history openFlowFor: s
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:06'
}
SWAOpenCodeSessionTable >> openSelectedFlowMap [
	| s |
	s := self selectedSession ifNil: [^ self].
	^ history openFlowMapFor: s
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:23'
}
SWAOpenCodeSessionTable >> openSelectedTimeline [
	| s view |
	s := self selectedSession ifNil: [^ self].
	"#timelineTreeFor:, not #nodeForSession: -- the latter carries only the
	session's TOOL CALLS, which in a typical session is 107 of 351 parts. All the
	thinking and all the talking were missing from the picture."
	view := SWATimelineMorph on: (SWAOpenCodeNode timelineTreeFor: s).
	"SPANS, not the histogram: over one session the events last seconds and the
	window is minutes, so a box from start to end is legible and says what the
	bucketed peaks could not -- how long each thing took, and what overlapped."
	view layoutMode: #spans.
	view extent: (Display extent * 0.7) rounded - (0 @ 60).
	^ history openPane: (SWAPane on: view) labeled: 'opencode session timeline: ' , s title
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:13'
}
SWAOpenCodeSessionTable >> openSelectedTreemap [
	| s |
	s := self selectedSession ifNil: [^ self].
	^ history
		openTreemapOn: ((SWAOpenCodeNode nodeForSession: s) rollUp; yourself)
		labeled: 'opencode session: ' , s title
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> openTableMenu [
	"The burger. Deliberately the SAME menu the list's right-click builds
	(#listMenu:) rather than a second one: two menus over one table drift apart, and
	there is nothing here that belongs to only one of the two ways in."
	| menu |
	menu := MenuMorph new defaultTarget: self.
	self listMenu: menu.
	^ menu popUpInWorld: self currentWorld
]

{
	#category : #sorting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> resort [
	| sorted |
	sorted := history sessions asSortedCollection: [:a :b |
		| va vb |
		va := self sortValueFor: a key: sortKey.
		vb := self sortValueFor: b key: sortKey.
		va = vb
			ifTrue: [a timeCreated <= b timeCreated]
			ifFalse: [sortAscending ifTrue: [va <= vb] ifFalse: [va >= vb]]].
	rows := sorted asOrderedCollection.
	self changed: #list
]

{
	#category : #sorting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:05'
}
SWAOpenCodeSessionTable >> reverseSort [
	sortAscending := sortAscending not.
	self resort
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> selectedSession [
	^ (selectionIndex between: 1 and: rows size)
		ifTrue: [rows at: selectionIndex]
		ifFalse: [nil]
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:04'
}
SWAOpenCodeSessionTable >> selectionIndex [
	"List indices are shifted by the heading row (see #list)."
	^ selectionIndex = 0 ifTrue: [0] ifFalse: [selectionIndex + 1]
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:31'
}
SWAOpenCodeSessionTable >> selectionIndex: anInteger [
	"Clicking the heading row deselects rather than selecting a phantom session."
	selectionIndex := anInteger <= 1 ifTrue: [0] ifFalse: [anInteger - 1].
	self changed: #selectionIndex.
	self changed: #detail.
	self updateButtonStates
]

{
	#category : #sorting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> sortBy: aKey [
	"Same column twice reverses; a new column starts descending, which is what you
	want for every numeric column and harmless for the rest."
	sortKey = aKey
		ifTrue: [sortAscending := sortAscending not]
		ifFalse: [sortKey := aKey. sortAscending := false].
	self resort
]

{
	#category : #sorting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:04'
}
SWAOpenCodeSessionTable >> sortByColumnIndex: anInteger [
	(anInteger between: 1 and: self class columns size) ifFalse: [^ self].
	self sortBy: ((self class columns at: anInteger) second).
	self changed: #columnHeadings
]

{
	#category : #sorting,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> sortValueFor: aSession key: aKey [
	"Sorting must use the UNDERLYING value, never the formatted cell. Cells are
	Strings, and sorting '9' against '113' as text puts 9 last."
	aKey == #when ifTrue: [^ aSession timeCreated ifNil: [0]].
	aKey == #title ifTrue: [^ aSession title asLowercase].
	aKey == #agent ifTrue: [^ (aSession agent ifNil: ['']) asLowercase].
	aKey == #model ifTrue: [^ (aSession modelId ifNil: ['']) asLowercase].
	aKey == #minutes ifTrue: [^ aSession durationMinutes].
	aKey == #user ifTrue: [^ aSession messagesUser].
	aKey == #asst ifTrue: [^ aSession messagesAssistant].
	aKey == #calls ifTrue: [^ aSession toolCalls size].
	aKey == #reads ifTrue: [^ aSession countOfAccessKind: #read].
	aKey == #writes ifTrue: [^ aSession countOfAccessKind: #write].
	aKey == #errors ifTrue: [^ aSession errorCount].
	aKey == #cost ifTrue: [^ aSession cost].
	aKey == #tokIn ifTrue: [^ aSession tokensInput].
	aKey == #tokOut ifTrue: [^ aSession tokensOutput].
	aKey == #added ifTrue: [^ aSession linesAdded].
	aKey == #deleted ifTrue: [^ aSession linesDeleted].
	aKey == #sub ifTrue: [^ aSession isSubagent ifTrue: [1] ifFalse: [0]].
	aKey == #compact ifTrue: [^ aSession wasCompacted ifTrue: [1] ifFalse: [0]].
	^ 0
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> summaryText [
	"Shown when nothing is selected: the totals across every row."
	^ String streamContents: [:t |
		t nextPutAll: history summaryString; cr; cr.
		t nextPutAll: 'Click a row for its tool mix and the targets it touched.'; cr.
		t nextPutAll: 'Click a column heading to sort; click it again to reverse.']
]

{
	#category : #list,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:03'
}
SWAOpenCodeSessionTable >> topTargetsFor: aSession into: t [
	| data keys |
	data := SWAOpenCodeAccessData fromToolCalls: aSession allToolCalls named: 'sel'.
	keys := data keys asArray asSortedCollection: [:a :b |
		(data touchesFor: a) >= (data touchesFor: b)].
	keys isEmpty ifTrue: [^ t tab; nextPutAll: '(nothing with a durable target)'; cr].
	(keys first: (keys size min: 25)) do: [:k |
		t tab; nextPutAll: (data touchesFor: k) printString.
		t nextPutAll: ' ('; nextPutAll: (data readsFor: k) printString; nextPut: $r.
		t nextPut: $/; nextPutAll: (data writesFor: k) printString; nextPut: $w.
		t nextPutAll: ')  '; nextPutAll: k; cr]
]

{
	#category : #buttons,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 15:19'
}
SWAOpenCodeSessionTable >> updateButtonStates [
	"Dim the per-session buttons while nothing is selected, rather than letting them
	look pressable and silently do nothing. Colour rather than #enabled:, because
	these are now standard SimpleButtonMorphs -- see #disabledButtonColor."
	| c |
	buttons ifNil: [^ self].
	c := self selectedSession notNil
		ifTrue: [self buttonColor]
		ifFalse: [self disabledButtonColor].
	buttons do: [:b |
		(b valueOfProperty: #needsSelection ifAbsent: [false])
			ifTrue: [b color: c]]
]
