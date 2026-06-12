"
ObjectExplorer subclass customized for SWASpaceTally. Adds Treemap and Diff buttons via the ToolBuilder spec system.
"
Class {
	#name : #SWASpaceTallyExplorer,
	#superclass : #ObjectExplorer,
	#instVars : [
		'tallyRoot',
		'compactThreshold',
		'trackOtherParents'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:11'
}
SWASpaceTallyExplorer >> buildDiffButtonWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: 'Diff from this';
		action: #openDiff;
		help: 'Walk the heap again and show only new objects since this tally';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 16:09'
}
SWASpaceTallyExplorer >> buildOtherParentsCheckboxWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: #otherParentsLabel;
		action: #toggleTrackOtherParents;
		changeLabelWhen: #otherParentsChanged;
		help: 'Track alternate parents for shared objects (slower walk, enables "By shared references" color mode)';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:35'
}
SWASpaceTallyExplorer >> buildTallyButtonWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: 'Tally (compact)';
		action: #runTally;
		help: 'Run a new tally, pruning children below the threshold';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:35'
}
SWASpaceTallyExplorer >> buildTallyFullButtonWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: 'Tally (full)';
		action: #runTallyFull;
		help: 'Run a new tally without pruning';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:35'
}
SWASpaceTallyExplorer >> buildThresholdFieldWith: builder [
	^ builder pluggableInputFieldSpec new
		model: self;
		getText: #compactThresholdText;
		setText: #compactThresholdText:;
		help: 'Compact threshold in bytes (prune children below this size)';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:10'
}
SWASpaceTallyExplorer >> buildTreemapButtonWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: 'Treemap';
		action: #openTreemap;
		help: 'Open a treemap visualization of this tally';
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:59'
}
SWASpaceTallyExplorer >> buildWith: builder [
	"Like ObjectExplorer>>buildWith: but adds action buttons, a
	compact-threshold field, and an other-parents toggle above the tree."

	| windowSpec buttonHeight tool w |
	buttonHeight := Preferences standardButtonFont height * 2.
	w := 1/6.  "6 items in the button row"

	windowSpec := self buildWindowWith: builder specs: {
		"Button row at the top"
		(LayoutFrame fractions: (0@0 corner: w@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildTallyFullButtonWith: builder].
		(LayoutFrame fractions: (w@0 corner: (w*2)@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildTallyButtonWith: builder].
		(LayoutFrame fractions: ((w*2)@0 corner: (w*3)@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildThresholdFieldWith: builder].
		(LayoutFrame fractions: ((w*3)@0 corner: (w*4)@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildOtherParentsCheckboxWith: builder].
		(LayoutFrame fractions: ((w*4)@0 corner: (w*5)@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildTreemapButtonWith: builder].
		(LayoutFrame fractions: ((w*5)@0 corner: 1@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildDiffButtonWith: builder].

		"Tree below the buttons"
		(LayoutFrame fractions: (0@0 corner: 1@0.71) offsets: (0@buttonHeight corner: 0@0))
			-> [self buildTreeWith: builder].

		"Code pane and inspect button at the bottom"
		(LayoutFrame fractions: (0@0.71 corner: 0.85@1) offsets: (0@0 corner: 0@0))
			-> [self buildCodePaneWith: builder].
		(LayoutFrame fractions: (0.85@0.71 corner: 1@1) offsets: (0@0 corner: 0@0))
			-> [self buildInspectButtonWith: builder].
	}.

	tool := builder build: windowSpec.
	self changed: #expandRootsRequested.
	^ tool
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:35'
}
SWASpaceTallyExplorer >> compactThresholdText [
	"For the input field: return the current threshold as a string."
	^ compactThreshold printString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:35'
}
SWASpaceTallyExplorer >> compactThresholdText: aStringOrText [
	"For the input field: accept a new threshold value."
	| str val |
	str := aStringOrText asString withBlanksTrimmed.
	val := [str asInteger] ifError: [nil].
	(val notNil and: [val >= 0])
		ifTrue: [compactThreshold := val]
		ifFalse: [self inform: 'Enter a positive integer (bytes)'].
	self changed: #compactThresholdText.
	^ true
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:58'
}
SWASpaceTallyExplorer >> initialize [
	super initialize.
	compactThreshold := 100000.
	trackOtherParents := false
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:58'
}
SWASpaceTallyExplorer >> newWalk [
	"Create and run a new tally with the current settings."
	| t |
	t := SWASpaceTally new.
	trackOtherParents ifTrue: [t trackOtherParents: true].
	t walk.
	^ t
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:59'
}
SWASpaceTallyExplorer >> openDiff [
	| after diff |
	after := self newWalk compact.
	diff := after diffFrom: tallyRoot.
	diff compact.
	diff openExplorer
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:11'
}
SWASpaceTallyExplorer >> openTreemap [
	tallyRoot openTreemap
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 16:04'
}
SWASpaceTallyExplorer >> otherParentsLabel [
	^ trackOtherParents
		ifTrue: ['[x] Other parents']
		ifFalse: ['[ ] Other parents']
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:59'
}
SWASpaceTallyExplorer >> runTally [
	"Run a fresh space tally with compaction at the current threshold."
	| t |
	t := self newWalk.
	t compact: compactThreshold.
	t openExplorer
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:59'
}
SWASpaceTallyExplorer >> runTallyFull [
	"Run a fresh space tally without pruning (compact only, no threshold)."
	| t |
	t := self newWalk compact.
	t openExplorer
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:10'
}
SWASpaceTallyExplorer >> tallyRoot [
	^ tallyRoot
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:10'
}
SWASpaceTallyExplorer >> tallyRoot: aTallyNode [
	tallyRoot := aTallyNode.
	self rootObject: aTallyNode
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 16:09'
}
SWASpaceTallyExplorer >> toggleTrackOtherParents [
	trackOtherParents := trackOtherParents not.
	self changed: #otherParentsChanged
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:58'
}
SWASpaceTallyExplorer >> trackOtherParents [
	^ trackOtherParents ifNil: [false]
]
