"
ObjectExplorer subclass customized for SWASpaceTally. Adds Treemap and Diff buttons via the ToolBuilder spec system.
"
Class {
	#name : #SWASpaceTallyExplorer,
	#superclass : #ObjectExplorer,
	#instVars : [
		'tallyRoot',
		'compactThreshold',
		'trackOtherParents',
		'highlightMorph',
		'allHighlights'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:57'
}
SWASpaceTallyExplorer >> allHighlightsLabel [
	^ allHighlights isNil
		ifTrue: ['Show morphs']
		ifFalse: ['Hide morphs']
]

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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:58'
}
SWASpaceTallyExplorer >> buildShowAllButtonWith: builder [
	^ builder pluggableButtonSpec new
		model: self;
		label: #allHighlightsLabel;
		action: #toggleAllHighlights;
		changeLabelWhen: #allHighlightsChanged;
		help: 'Overlay every on-screen morph found in this tally with its calculated size; click again to hide';
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:55'
}
SWASpaceTallyExplorer >> buildWith: builder [
	"Like ObjectExplorer>>buildWith: but adds action buttons, a
	compact-threshold field, and an other-parents toggle above the tree."

	| windowSpec buttonHeight tool w |
	buttonHeight := Preferences standardButtonFont height * 2.
	w := 1/7.  "7 items in the button row"

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
		(LayoutFrame fractions: ((w*5)@0 corner: (w*6)@0) offsets: (0@0 corner: 0@buttonHeight))
			-> [self buildShowAllButtonWith: builder].
		(LayoutFrame fractions: ((w*6)@0 corner: 1@0) offsets: (0@0 corner: 0@buttonHeight))
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
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyExplorer >> clearHighlight [
	"Remove the current highlight overlay, if any."

	highlightMorph ifNotNil: [:m | m delete. highlightMorph := nil]
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
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 13:59'
}
SWASpaceTallyExplorer >> copySelectedSubtree [
	"Pretty-print the SELECTED node's subtree as a nested bullet list and put it
	on the clipboard, for sharing in chat / issues. No-op if nothing is selected
	(the menu item is only offered when there is a selection)."

	| node text |
	node := self selectedNode ifNil: [^ self].
	text := node asBulletListString.
	Clipboard clipboardText: text.
	Transcript show: 'SWASpaceTally: copied subtree (';
		show: text lineCount printString;
		show: ' lines) to clipboard.'; cr
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:48'
}
SWASpaceTallyExplorer >> currentSelection: anObject [
	"Besides the normal selection behaviour, when the freshly selected object
	is a Morph that is currently on screen, drop a half-transparent overlay on
	it showing the size we calculated for that node."

	super currentSelection: anObject.
	self updateHighlight
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 12:29'
}
SWASpaceTallyExplorer >> graphParentsToRoots [
	"Open a Graphviz view of the selected node's ancestry up to the roots
	(capped at 100 nodes). Delegates to SWASpaceTallyNode>>openParentsGraph."

	| node |
	node := self selectedNode.
	node ifNil: [^ self inform: 'No node selected.'].
	node openParentsGraph
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:57'
}
SWASpaceTallyExplorer >> hideAllHighlights [
	"Remove all the 'show all morphs' overlays, if any."

	allHighlights ifNotNil: [:c | c do: [:m | m delete]].
	allHighlights := nil
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:51'
}
SWASpaceTallyExplorer >> ignoreSelectedClassToLabel [
	"Add a diff-ignore pattern for the selected node, constrained to its
	parent's class: parentClassName -> edgeLabel (e.g. #Morph -> #fullBounds)."

	| node parentNode parentToken childToken |
	node := self selectedNode.
	node ifNil: [^ self].
	parentNode := node parent.
	parentToken := parentNode ifNotNil: [parentNode className].
	childToken := node edgeLabel ifNil: [node className].
	(parentToken isNil or: [childToken isNil]) ifTrue: [^ self].
	SWASpaceTally addDiffIgnore: parentToken asSymbol -> childToken asSymbol
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:51'
}
SWASpaceTallyExplorer >> ignoreSelectedLabel [
	"Add a diff-ignore pattern for the selected node's edge label, matching
	that label under any parent (nil -> label)."

	| node token |
	node := self selectedNode.
	node ifNil: [^ self].
	token := node edgeLabel ifNil: [node className].
	token ifNil: [^ self].
	SWASpaceTally addDiffIgnore: nil -> token asSymbol
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
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:04'
}
SWASpaceTallyExplorer >> isHighlightableMorph: aMorph [
	"True when aMorph is worth covering with a 'show all' overlay: a real,
	on-screen content morph. Excludes the world/desktop and hands (full-screen
	or pointer overlays are noise), and our own highlight overlays."

	aMorph world ifNil: [^ false].
	(aMorph isKindOf: SWASpaceTallyHighlight) ifTrue: [^ false].
	(aMorph isKindOf: HandMorph) ifTrue: [^ false].
	(aMorph isKindOf: PasteUpMorph) ifTrue: [^ false].
	^ true
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 16:06'
}
SWASpaceTallyExplorer >> jumpToOriginal [
	"Open the baseline tally this diff was derived from, expanded to and
	selecting the node corresponding to the current selection (matched by
	object identity). Falls back to opening the baseline root if the object
	is gone or can't be located. Returns the opened window."

	| base obj node |
	base := tallyRoot baseTally.
	base ifNil: [^ self].
	obj := self object.
	node := base nodeForObject: obj.
	^ node
		ifNil: [base openExplorerWindow first]
		ifNotNil: [base openExplorerSelecting: node]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 11:37'
}
SWASpaceTallyExplorer >> mainTreeListMenu: aMenu [
	"Add diff-related items: jump back to the baseline (diff trees only) and
	two 'ignore in diffs' commands for the selected node, with labels showing
	the concrete tokens they will add to the ignore preference. Plus a
	'copy subtree to clipboard' item (selection only) that pretty-prints the
	selected subtree as a nested bullet list, and a 'graph parents to roots'
	item that opens a Graphviz view of the selected node's ancestry."

	<treeListMenu>
	| node child parent |
	super mainTreeListMenu: aMenu.
	(tallyRoot notNil and: [tallyRoot baseTally notNil]) ifTrue: [
		aMenu addLine.
		aMenu
			add: 'jump to original'
			target: self
			selector: #jumpToOriginal
			argument: nil].

	node := self selectedNode.
	node ifNotNil: [
		aMenu addLine.
		aMenu
			add: 'copy subtree to clipboard'
			target: self
			selector: #copySelectedSubtree
			argument: nil.
		aMenu
			add: 'graph parents to roots'
			target: self
			selector: #graphParentsToRoots
			argument: nil.

		child := node edgeLabel ifNil: [node className].
		parent := node parent ifNotNil: [:p | p className].
		child ifNotNil: [
			aMenu addLine.
			aMenu
				add: 'ignore label (', child asString, ')'
				target: self
				selector: #ignoreSelectedLabel
				argument: nil.
			parent ifNotNil: [
				aMenu
					add: 'ignore ', parent asString, ' -> ', child asString
					target: self
					selector: #ignoreSelectedClassToLabel
					argument: nil]]].
	^ aMenu
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:57'
}
SWASpaceTallyExplorer >> rootTallyNode [
	"The lean SWASpaceTallyNode the tree is rooted at (the group's rootNode,
	or a bare node if that's what we were handed)."

	^ (tallyRoot isKindOf: SWASpaceTally)
		ifTrue: [tallyRoot rootNode]
		ifFalse: [tallyRoot]
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:52'
}
SWASpaceTallyExplorer >> selectedNode [
	"Return the SWASpaceTally node for the current tree selection, or nil.
	Child rows use SWASpaceTallyWrapper, whose item is (name -> realObject);
	we find the matching visible wrapper -- preferring identity, falling back
	to equal key and identical value -- and ask it for its tally node. The
	root row is a plain ObjectExplorerWrapper whose value is the node itself,
	so we recognise that directly."

	| sel match |
	sel := self currentSelection.
	(sel isKindOf: Association) ifFalse: [^ nil].
	(sel value isKindOf: SWASpaceTallyNode) ifTrue: [^ sel value].
	match := nil.
	self visibleObjectExplorerWrappers do: [:w |
		(w isKindOf: SWASpaceTallyWrapper) ifTrue: [
			w item == sel ifTrue: [^ w tallyNode].
			(match isNil
				and: [w item key = sel key
				and: [w item value == sel value]])
					ifTrue: [match := w]]].
	^ match ifNotNil: [match tallyNode]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 18:15'
}
SWASpaceTallyExplorer >> showAllHighlights [
	"Drop a half-transparent overlay on the topmost on-screen morphs discovered
	in this tally, each labelled with the size we calculated for its node. Skips
	the World and hands (full-screen / pointer overlays are noise), and skips
	submorphs whose owner is already overlaid."

	| node |
	self hideAllHighlights.
	allHighlights := OrderedCollection new.
	node := self rootTallyNode.
	node ifNil: [^ self].
	node
		morphNodesDo: [:n |
			allHighlights add:
				(SWASpaceTallyHighlight on: n object bytes: n totalSize)]
		select: [:m | self isHighlightableMorph: m]
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
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:13'
}
SWASpaceTallyExplorer >> tallyRoot: aTallyGroupOrNode [
	"Accept the SWASpaceTally group (preferred) or a bare node. Keep the group
	as tallyRoot for title/diff metadata, but point the tree at the lean node."

	tallyRoot := aTallyGroupOrNode.
	self rootObject: ((aTallyGroupOrNode isKindOf: SWASpaceTally)
		ifTrue: [aTallyGroupOrNode rootNode]
		ifFalse: [aTallyGroupOrNode])
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:57'
}
SWASpaceTallyExplorer >> toggleAllHighlights [
	"Toggle overlays on every discovered on-screen morph on/off."

	allHighlights isNil
		ifTrue: [self showAllHighlights]
		ifFalse: [self hideAllHighlights].
	self changed: #allHighlightsChanged
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

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:52'
}
SWASpaceTallyExplorer >> updateHighlight [
	"Remove any previous overlay and, if the current selection corresponds to
	an on-screen Morph, place a fresh half-transparent highlight on it labelled
	with the tally size we computed for the selected node.

	The selected object is taken from the tally node when we can resolve one
	(its `object` is the real analyzed object), falling back to the explorer's
	own `object` for the root row, whose wrapper carries the node itself."

	| node obj bytes |
	self clearHighlight.
	node := self selectedNode.
	obj := node ifNotNil: [node object] ifNil: [self object].
	((obj isKindOf: Morph) and: [obj world notNil]) ifFalse: [^ self].
	bytes := node ifNil: [0] ifNotNil: [node totalSize].
	highlightMorph := SWASpaceTallyHighlight on: obj bytes: bytes
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer 6/16/2026 17:58'
}
SWASpaceTallyExplorer >> windowIsClosing [
	"Tidy up our on-screen overlays when the explorer window closes."

	self clearHighlight.
	self hideAllHighlights.
	super windowIsClosing
]
