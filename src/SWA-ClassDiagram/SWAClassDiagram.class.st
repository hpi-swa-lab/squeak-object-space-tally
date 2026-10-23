"
A SWAView rendering a SWACodeNode subtree as a Graphviz diagram (UML class diagram or containment tree) instead of a treemap/flamegraph, plugging into a SWAPane with the shared chrome. Clicking a node selects the matching SWACodeNode. #mode: switches between #classDiagram and #containment.

Open with: SWACodeGraphMorph openOnPackageNamed: 'SWAGame'
See squeak-object-space-tally/doc/ for details.
"
Class {
	#name : #SWAClassDiagram,
	#superclass : #SWAView,
	#instVars : [
		'graphMorph',
		'graphPane',
		'nodesByDotId',
		'fieldNodesByDotId',
		'rectKeyByNode',
		'colorMode',
		'leafKind',
		'syncedMarkSet',
		'suppressedSuperclassNames',
		'clustered',
		'showsComposition',
		'displayedKeys',
		'fullRoot',
		'focus'
	],
	#category : #'SWA-ClassDiagram',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:13'
}
SWAClassDiagram class >> addIvarMarksFor: anOperation definition: aClassDefinition into: aMarkSet [
	"Mark the instance variables this class definition ADDED. Only MCModification carries
	an #obsoletion -- the definition as it was -- so for a newly added class there is
	nothing to compare against and every ivar counts as new.

	An ivar that no longer exists in the image is skipped, the same as a removed method:
	there would be no node to mark."

	| clsName behavior oldNames newNames |
	clsName := [aClassDefinition className asString] on: Error do: [:e | nil].
	clsName ifNil: [^ self].
	behavior := self behaviorNamed: clsName.
	behavior ifNil: [^ self].
	newNames := [aClassDefinition instVarNames] on: Error do: [:e | #()].
	oldNames := (anOperation respondsTo: #obsoletion)
		ifTrue: [[anOperation obsoletion instVarNames] on: Error do: [:e | #()]]
		ifFalse: [#()].
	newNames do: [:each |
		((oldNames includes: each) not
			and: [behavior allInstVarNames includes: each])
				ifTrue: [aMarkSet add: clsName, '>>#', each]]
]

{
	#category : #defaults,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:04'
}
SWAClassDiagram class >> defaultSuppressedSuperclassNames [
	"Superclasses whose inheritance edge carries no information, so it is not drawn and
	the class gets no placeholder box. Every class inherits from Object; a name ending
	in Test inheriting from TestCase is not news; and a framework base class is already
	announced by the prefix its subclasses share. Edit this, or set the list per
	diagram with #suppressedSuperclassNames:."

	^ #('Object' 'TestCase' 'SRObject')
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:45'
}
SWAClassDiagram class >> initialize [
	"Register the Apps-menu entries, alongside the other SWA tools. The 'SWA Code: '
	label prefix groups them in the (alphabetically sorted) Apps menu. Idempotent:
	removes any prior entry for this receiver first.

	  SWAClassDiagram initialize"
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Code: Class Diagram'.
		{self. #open}.
		'Open a UML class diagram of your working-set packages' }.
	TheWorldMenu registerOpenCommand: {
		'SWA Code: Class Diagram (commit range)'.
		{self. #openOnGitRange}.
		'Open a class diagram of what a range of commits changed, for review' }
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:54'
}
SWAClassDiagram class >> markSetForRepository: aRepositoryName from: aHexPrefix [
	^ self markSetForRepository: aRepositoryName from: aHexPrefix to: nil
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:13'
}
SWAClassDiagram class >> markSetForRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"A SWAMarkSet of what changed between two commits, keyed the way every SWA view keys
	members, so it can drive the #selected granularity. A nil second argument means the
	head commit.

	ONE diff, not a walk over the commits between the two. Each changesFromCommit:toCommit:
	materialises both trees through the code mapper, so doing it per commit costs that many
	times over -- and answers a different question: the accumulated churn, in which a
	method changed and then reverted still counts. A range wants its net effect.

	Deletions are left out: a removed method is in the history but not in the image, so
	there is no node to mark. A class-definition change marks the class itself."

	| history base head changes marks |
	history := SWAGitHistory onWorkingCopyNamed: aRepositoryName.
	base := history commitWithHexPrefix: aHexPrefix.
	base ifNil: [^ self error: 'no commit starting ', aHexPrefix, ' on this branch'].
	head := aHexPrefixOrNil
		ifNil: [history workingCopy headCommit]
		ifNotNil: [:prefix |
			(history commitWithHexPrefix: prefix)
				ifNil: [^ self error: 'no commit starting ', prefix, ' on this branch']].
	changes := #().
	UIManager default
		informUser: 'Diffing ', aHexPrefix, ' .. ', (aHexPrefixOrNil ifNil: ['HEAD'])
		during: [
			changes := [history workingCopy changesFromCommit: base toCommit: head]
				on: Error do: [:e | #()]].
	marks := SWAMarkSet new.
	changes do: [:change |
		| defn clsName sel behavior |
		defn := [change operation definition] on: Error do: [:e | nil].
		defn ifNotNil: [
			clsName := nil.
			sel := nil.
			(defn isKindOf: MCMethodDefinition)
				ifTrue: [
					clsName := [defn fullClassName asString] on: Error do: [:e | nil].
					sel := [defn selector] on: Error do: [:e | nil]]
				ifFalse: [
					(defn isKindOf: MCClassDefinition) ifTrue: [
						clsName := [defn className asString] on: Error do: [:e | nil].
						self
							addIvarMarksFor: change operation
							definition: defn
							into: marks]].
			clsName ifNotNil: [
				behavior := self behaviorNamed: clsName.
				behavior ifNotNil: [
					sel isNil
						ifTrue: [marks add: behavior theNonMetaClass name asString]
						ifFalse: [
							(behavior includesSelector: sel asSymbol)
								ifTrue: [marks add: clsName, '>>', sel asString]]]]]].
	^ marks
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:58'
}
SWAClassDiagram class >> on: aCodeNode [
	"A class-diagram view of aCodeNode's subtree."
	^ self new
		rootNode: aCodeNode;
		yourself
]

{
	#category : #opening,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 15:05'
}
SWAClassDiagram class >> open [
	"Apps-menu action: diagram the current working set, the same scope SWAPane>>open
	uses, so the Code Map and the diagram always show the same packages."
	^ self openOnPackageNamed: SWAPane codeMapWorkingSet
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAClassDiagram class >> openOn: aCodeNode label: aLabel [
	"Wrap a class-diagram view of aCodeNode in a SWAPane window (shared chrome:
	Back/Browse/Show/Deselect + breadcrumb + selection path + source pane)."
	| view panel window bounds |
	view := self on: aCodeNode.
	panel := SWAPane on: view.
	window := panel openInWindow.
	window setLabel: aLabel.
	bounds := SWAPane defaultWindowBounds intersect: (0 @ 0 corner: Display extent).
	window bounds: bounds.
	panel enforceMinimumWindowWidth.
	^ window
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:45'
}
SWAClassDiagram class >> openOnGitRange [
	"Apps-menu action: a diagram of what a commit changed, ready to browse. Opens on
	the chosen repository at PARENT..HEAD -- the newest commit alone -- with the Data
	flap already out, since choosing the range IS the point of this entry and the
	fields should not have to be found first.

	  SWAClassDiagram openOnGitRange"
	| workingCopy repoName window |
	workingCopy := SWAGitHistory chooseWorkingCopy.
	workingCopy ifNil: [^ nil].
	repoName := [workingCopy name] on: Error do: [:e | nil].
	repoName ifNil: [^ nil].
	window := self openOnGitRepository: repoName from: 'PARENT' to: nil.
	(window submorphs detect: [:each | each isKindOf: SWAPane] ifNone: [nil])
		ifNotNil: [:pane | pane openData].
	^ window
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:54'
}
SWAClassDiagram class >> openOnGitRepository: aRepositoryName from: aHexPrefix [
	"A class diagram of what the commits after aHexPrefix changed -- the branch under
	review, with nothing else in the way.

	SWAClassDiagram openOnGitRepository: 'SqueakXRNative' from: '94b68b4'

	Opens at the #selected granularity, so each class shows only its touched members."

	^ self openOnGitRepository: aRepositoryName from: aHexPrefix to: nil
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:46'
}
SWAClassDiagram class >> openOnGitRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"A class diagram of what changed between two commits -- the range under review, with
	nothing else in the way. A nil second argument means the head commit.

	SWAClassDiagram openOnGitRepository: 'SqueakXRNative' from: '94b68b4' to: nil.
	SWAClassDiagram openOnGitRepository: 'SqueakXRNative' from: '94b68b4' to: 'a82eb22'.

	Both ends are named because head is not always the end you mean: a later commit that
	reformats or strips comments will otherwise swamp the feature work it follows.

	Either end takes a hash prefix; From also takes 'PARENT' and To 'HEAD', the two
	positions that make the range follow the branch rather than pin it.

	Opens at the #selected granularity, so each class shows only its touched members.
	The range stays editable afterwards, in the pane's Data flap."

	| view |
	view := self new.
	view setRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil.
	"Before the load: #leafKind: rebuilds, and with no root yet that rebuild is free."
	view leafKind: #selected.
	view loadGitRange.
	^ (SWAPane on: view) openInWindow setLabel: view gitRangeLabel
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:52'
}
SWAClassDiagram class >> openOnMarkSet: aMarkSet [
	"Open a LIVE class diagram of the classes currently marked in aMarkSet (marks whose
	nodeKind is #class, plus the owning class of any method/ivar marks). Opens directly in
	the '+Selected' depth, so each class box shows ONLY its bookmarked ivars and methods.
	The diagram stays synced: marking/unmarking a member ANYWHERE updates it. Wrapped in
	the usual SWAPane chrome.

	SWAClassDiagram openOnMarkSet: SWAMarkSet default"
	| root view panel window bounds |
	root := SWACodeMarkSetRootNode new markSet: aMarkSet; yourself.
	view := self on: root.
	view syncToMarkSet: aMarkSet.
	view leafKind: #selected.
	panel := SWAPane on: view.
	window := panel openInWindow.
	window setLabel: 'Class Diagram: marked members (live)'.
	bounds := SWAPane defaultWindowBounds intersect: (0 @ 0 corner: Display extent).
	window bounds: bounds.
	panel enforceMinimumWindowWidth.
	^ window
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:13'
}
SWAClassDiagram class >> openOnMarks [
	"Open a live class diagram of the classes in the GLOBAL mark set.

	SWAClassDiagram openOnMarks"
	^ self openOnMarkSet: SWAMarkSet default
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:00'
}
SWAClassDiagram class >> openOnPackageNamed: aPackageGlob [
	"Open a UML class diagram of the matching packages in a SWAPane.

	SWAClassDiagram openOnPackageNamed: 'SWAGame'"
	| root |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		addPackages: aPackageGlob;
		yourself.
	^ self
		openOn: root
		label: 'Class Diagram: ', aPackageGlob
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:45'
}
SWAClassDiagram class >> unload [
	"Remove the Apps-menu entries."
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWAClassDiagram >> boxFillFor: aClassNode [
	"Pale enough to keep the box's black text readable."
	| metric |
	metric := self metricForMode: colorMode.
	metric ifNil: [^ nil].
	^ (metric colorForNode: aClassNode)
		ifNil: ['#f4f4f4']
		ifNotNil: [:color | SWACodeNode hexColor: (color alphaMixed: 0.45 with: Color white)]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> breadcrumbString [
	fullRoot ifNil: [^ ''].
	^ fullRoot name,
		(focus ifNil: [''] ifNotNil: [:each | '  >  ', each value]),
		'  (class diagram)'
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> browseSelected [
	"Browse button: open a browser on the selected node."
	selectedNode
		ifNil: [Beeper beep]
		ifNotNil: [:n | n browse]
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> canZoomOut [
	^ focus notNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:14'
}
SWAClassDiagram >> clustered [
	"Draw each system subcategory as a labelled subgraph."

	^ clustered ifNil: [true]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:14'
}
SWAClassDiagram >> clustered: aBoolean [
	clustered := aBoolean.
	self rebuildGraph
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAClassDiagram >> codeViewKey [
	^ #classDiagram
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:39'
}
SWAClassDiagram >> colorMode [
	"Active fill mode: #kind (pastel per node kind, the default) or #loc
	(green->yellow->red heat by method LOC)."
	^ colorMode ifNil: [#kind]
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:56'
}
SWAClassDiagram >> colorMode: aSymbol [
	"Set the fill mode and re-render the graph (Graphviz lays out fast; per-row
	fills are baked into the DOT). Keeps the current selection highlight AND the
	current zoom + pan, since only the colors change, not the layout."
	colorMode = aSymbol ifTrue: [^ self].
	colorMode := aSymbol.
	rootNode ifNotNil: [self rebuildGraphKeepView: true]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWAClassDiagram >> colorModeOptions [
	"{ symbol. label } pairs for the shared Color menu/button. Kind and LOC fill per row;
	the composition metrics fill each class box."
	^ { { #kind. 'Flat (by kind)' }. { #loc. 'LOC heat (green->red)' } },
		((self compositionDataset metrics select: [:each | each supportsColor])
			collect: [:each | { each modeSymbol. each label }]) asArray
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> compositionDataset [
	"The newest #composition dataset, analysed from the shown classes when there is none."
	^ (self datasets reverse detect: [:each | each kind == #composition] ifNone: [nil])
		ifNil: [self addDataset: (SWADataset
			compositionFrom: (SWACompositionData fromClasses: self shownClasses named: self compositionLabel)
			named: self compositionLabel)]
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> compositionLabel [
	^ 'Composition of ', (repositoryName ifNil: [rootNode name] ifNotNil: [self gitRangeLabel])
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> currentFocus [
	^ focus
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> deselect [
	"Clear the current selection."
	self selectedNode: nil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAClassDiagram >> displayedCrossRefKeys [
	"The keys the diagram actually DRAWS: the class boxes plus the member rows the
	current granularity leaves visible. Under #selected that is the marked members
	only, while the node tree still carries every member of a touched class as
	context -- 83 keys drawn out of 865 held, on the range open as I write this."

	| keys |
	displayedKeys ifNotNil: [^ displayedKeys].
	keys := Set new.
	nodesByDotId ifNotNil: [
		nodesByDotId valuesDo: [:node |
			(node respondsTo: #crossRefKey) ifTrue: [
				node crossRefKey ifNotNil: [:k | keys add: k]]]].
	fieldNodesByDotId ifNotNil: [
		fieldNodesByDotId valuesDo: [:fields |
			fields do: [:fieldNode |
				(fieldNode respondsTo: #crossRefKey) ifTrue: [
					fieldNode crossRefKey ifNotNil: [:k | keys add: k]]]]].
	^ displayedKeys := keys
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> focusIncludesClass: aClass [
	| category |
	focus ifNil: [^ true].
	focus key == #class ifTrue: [^ aClass name asString = focus value].
	category := aClass category ifNil: [^ false].
	^ category asString = focus value or: [category asString beginsWith: focus value, '-']
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> focusOn: aFocus [
	focus = aFocus ifTrue: [^ self].
	focus := aFocus.
	fullRoot ifNotNil: [self showFocus].
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> focusedCopyOf: aRoot [
	"A root of its own rather than a filter on aRoot, which the Code Map may be showing."
	| filter |
	(focus isNil or: [aRoot isNil]) ifTrue: [^ aRoot].
	filter := [:class | self focusIncludesClass: class].
	(aRoot isKindOf: SWACodeMarkSetRootNode) ifTrue: [
		^ SWACodeMarkSetRootNode new
			markSet: aRoot markSet;
			snapshot: aRoot snapshot;
			classFilter: filter;
			yourself].
	(aRoot isKindOf: SWACodeSnapshotRootNode) ifTrue: [
		^ SWACodeSnapshotRootNode new
			snapshot: aRoot snapshot;
			name: aRoot displayName;
			addPackages: aRoot packageNames;
			classFilter: filter;
			yourself].
	(aRoot isKindOf: SWACodeRootNode) ifTrue: [
		^ SWACodeRootNode new
			name: aRoot displayName;
			addPackages: aRoot packageNames;
			classFilter: filter;
			yourself].
	^ aRoot
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAClassDiagram >> forgetGeneratedComposition [
	"An analysis belongs to the classes it was made of. A loaded one is kept."
	(self datasets select: [:each | each kind == #composition and: [each source isGenerated]])
		do: [:each | self forgetDataset: each].
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 16:16'
}
SWAClassDiagram >> graphFieldClicked: anAssoc [
	"A record sub-field was clicked: anAssoc is dotId -> fieldIndex (0-based, where
	field 0 is the class-name compartment and 1..N are methods). Resolve to the
	matching SWACodeNode and select it. Falls back to the whole-node selection if
	the class or field index is unknown."
	| fieldNodes idx |
	fieldNodes := fieldNodesByDotId at: anAssoc key ifAbsent: [nil].
	fieldNodes ifNil: [^ self graphNodeClicked: anAssoc key].
	idx := anAssoc value + 1.
	(idx between: 1 and: fieldNodes size)
		ifTrue: [self selectOrDeselectNode: (fieldNodes at: idx)]
		ifFalse: [self graphNodeClicked: anAssoc key]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> graphMarkerClicked: aNode [
	"Select the row the badge belongs to, then toggle its review sign-off."
	self selectedNode: aNode.
	self toggleReviewed: aNode.
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> graphMenuRequest: evt [
	"Right-click on the graph: pop up a context menu with the shared Color submenu
	(same #colorMenuMorph the header Color button uses)."
	| menu colorMenu |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: 'Class Diagram'.
	colorMenu := self colorMenuMorph.
	colorMenu ifNotNil: [menu add: 'Color' subMenu: colorMenu].
	self zoomTargetsForSelection ifNotEmpty: [:targets | | zoomMenu |
		zoomMenu := MenuMorph new defaultTarget: self.
		targets do: [:each | zoomMenu add: each value selector: #focusOn: argument: each].
		menu add: 'Zoom into' subMenu: zoomMenu].
	menu add: 'Composition' subMenu: ((MenuMorph new defaultTarget: self)
		add: 're-analyse' action: #reanalyseComposition;
		add: 'save data...' action: #saveCompositionData;
		add: 'load data...' action: #loadCompositionData;
		yourself).
	menu addLine.
	menu add: 'export DOT...' target: graphMorph selector: #exportDot.
	menu add: 'export PDF...' target: graphMorph selector: #exportPdf.
	self popUpMenu: menu at: (evt ifNil: [self currentHand] ifNotNil: [evt hand]) position truncated
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 16:16'
}
SWAClassDiagram >> graphNodeClicked: aDotId [
	"A node in the embedded graph was clicked: select the matching SWACodeNode."
	self selectOrDeselectNode: (nodesByDotId at: aDotId ifAbsent: [nil])
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:41'
}
SWAClassDiagram >> graphRectForNode: aNode [
	"The graph-local rect framing aNode: a member uses its record row, anything else
	its whole box. nil when the current granularity does not draw it."

	| key |
	(aNode isNil or: [rectKeyByNode isNil or: [graphMorph isNil]]) ifTrue: [^ nil].
	key := rectKeyByNode at: aNode ifAbsent: [^ nil].
	^ key value isNil
		ifTrue: [graphMorph rectForNode: key key]
		ifFalse: [graphMorph rectForNode: key key field: key value]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:59'
}
SWAClassDiagram >> initialize [
	super initialize.
	leafKind := #class.
	nodesByDotId := Dictionary new.
	self
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		color: (Color gray: 0.1).
	graphMorph := GraphvizMorph new.
	graphMorph engine: 'dot'.
	"Host the (potentially huge) graph in a scroll/zoom pane so this view stays
	window-sized and pans, rather than expanding to the full image extent."
	graphPane := GraphvizPane new graph: graphMorph.
	graphPane onNodeClick: [:dotId | self graphNodeClicked: dotId].
	graphPane hResizing: #spaceFill; vResizing: #spaceFill.
	self addMorphBack: graphPane
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:22'
}
SWAClassDiagram >> ivarFilterForBuild [
	"The ivar-filter block to install on class nodes for the current granularity, or nil to
	show all instance variables. For #selected, only ivars whose crossRefKey
	('Class>>#ivar') is in the mark set are shown. Uses the synced mark set if any, else the
	global singleton."
	| ms |
	leafKind = #selected ifFalse: [^ nil].
	ms := self markSetForBuild.
	^ [:ivarNode | ms includes: ivarNode crossRefKey]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:15'
}
SWAClassDiagram >> leafKind [
	"The render granularity: #class (boxes show name + state only) or #method (full
	boxes including one row per method). Drives the shared nav-panel Depth button."
	^ leafKind
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWAClassDiagram >> leafKind: aSymbol [
	"Set the render granularity and rebuild. Four depths are meaningful for a UML class
	diagram: #class (name box only), #state (name + all instance variables), #method
	(name + all state + all methods), and #selected (name + only the MARKED ivars +
	only the MARKED methods). Anything else (the treemap's #package/#category) is
	normalized to the nearest, so the shared Depth button never lands the graph on an
	unsupported depth. Rebuilds resetting the view, since the box layout changes."
	| normalized |
	normalized := (aSymbol = #class or: [aSymbol = #package])
		ifTrue: [#class]
		ifFalse: [(aSymbol = #state or: [aSymbol = #category])
			ifTrue: [#state]
			ifFalse: [(aSymbol = #selected or: [aSymbol = #markedMethods])
				ifTrue: [#selected]
				ifFalse: [#method]]].
	leafKind = normalized ifTrue: [^ self].
	leafKind := normalized.
	rootNode ifNotNil: [self rebuildGraph]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWAClassDiagram >> leafKindOrder [
	"The granularities the Depth button cycles through for THIS view (as opposed to
	the treemap's package->class->category->method). A class diagram has four
	meaningful depths: classes only, classes + all state, classes + all state + all
	methods, and #selected -- classes + only the MARKED instance variables and MARKED
	methods (bookmarked in the mark set)."
	^ { #class. #state. #method. #selected }
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> loadCompositionData [
	| path data |
	navPanel ifNil: [^ self].
	path := navPanel chooseJsonFilePrompt: 'Load composition JSON from:'.
	path ifNil: [^ self].
	data := [SWACompositionData fromFile: path]
		on: Error do: [:e | ^ self reportProblem: 'Load failed: ', e messageText].
	self addDataset: (SWADataset compositionFrom: data named: (FileDirectory localNameFor: path)).
	self showsComposition ifTrue: [self rebuildGraphKeepView: true] ifFalse: [self showsComposition: true].
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:22'
}
SWAClassDiagram >> markSetForBuild [
	"The mark set the #selected granularity filters against. A root node built on its own
	private SWAMarkSet -- SWACodeMarkSetRootNode -- must be filtered by THAT set, or the
	diagram silently shows nothing: it would be matching against the global working set,
	which knows nothing about the keys the root was built from."

	syncedMarkSet ifNotNil: [^ syncedMarkSet].
	(rootNode notNil and: [rootNode respondsTo: #markSet])
		ifTrue: [rootNode markSet ifNotNil: [:ms | ^ ms]].
	^ SWAMarkSet default
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:22'
}
SWAClassDiagram >> methodFilterForBuild [
	"The method-filter block to install on class nodes for the current granularity, or nil
	to show all methods. For #selected, only methods whose crossRefKey ('Class>>sel') is in
	the mark set are shown. Uses the synced mark set if any, else the global singleton."
	| ms |
	leafKind = #selected ifFalse: [^ nil].
	ms := self markSetForBuild.
	^ [:methodNode | ms includes: methodNode crossRefKey]
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAClassDiagram >> newCounterpart [
	^ SWACodeTreemapMorph new
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:39'
}
SWAClassDiagram >> overlayMorph [
	"The graph view draws its own selection frame and hosts its own menus (there is
	no separate transparent overlay morph as on the treemap), so it acts as its own
	overlay for the nav-panel chrome. Answering self lets the shared Color button
	light up and route #popUpColorMenu / #colorModeOptions here, without duplicating
	the button wiring."
	^ self
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAClassDiagram >> peerWeightForKey: aCrossRefKey [
	"Only what the diagram draws is data a peer may colour by. Reading the whole key
	index lights up every method of a class the range merely touched."

	(self displayedCrossRefKeys includes: aCrossRefKey) ifFalse: [^ nil].
	^ super peerWeightForKey: aCrossRefKey
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAClassDiagram >> peerWeightKeys [
	^ self displayedCrossRefKeys
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> reanalyseComposition [
	self forgetGeneratedComposition.
	self addDataset: (SWADataset
		compositionFrom: (SWACompositionData fromClasses: self shownClasses named: self compositionLabel)
		named: self compositionLabel).
	self rebuildGraphKeepView: true.
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:56'
}
SWAClassDiagram >> rebuildGraph [
	"Rebuild resetting the view to top-left/100% (initial build or a structural
	change such as a mode switch)."
	self rebuildGraphKeepView: false
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> rebuildGraphKeepView: keepView [
	"(Re)generate the DOT for the class diagram and hand it to the embedded
	GraphvizMorph. Build nodesByDotId (dot-id -> SWACodeNode) for whole-node clicks;
	fieldNodesByDotId (dot-id -> field node array) for per-row sub-field clicks; and
	rectKeyByNode (node -> dot-id -> fieldIndexOrNil) so a selection can be located
	as a highlight rectangle. The class diagram honors the active #colorMode (#kind /
	#loc) AND the active #leafKind granularity (#class = classes only, #state =
	classes + all state, #method = classes + all state + all methods, #selected =
	classes + only the MARKED ivars and MARKED methods). Re-seat the morph in the pane,
	preserving the current zoom + pan when keepView is true (e.g. a color-mode recolor,
	which keeps the same layout) and resetting to top-left/100% otherwise."
	| tuple ids showState showMethods methodFilter ivarFilter composition |
	rootNode ifNil: [^ self].
	showState := self showsState.
	showMethods := self showsMethods.
	"Install the per-granularity ivar/method filters on every class node before building,
	so #recordIvarNodes / #recordMethodNodes (DOT label, field-click map, compartments)
	all agree."
	methodFilter := self methodFilterForBuild.
	ivarFilter := self ivarFilterForBuild.
	composition := ((self showsComposition and: [showState]) or: [self showsCompositionColor])
		ifTrue: [self compositionDataset source]
		ifFalse: [nil].
	rootNode withAllChildrenDo: [:node |
		(node isKindOf: SWACodeClassNode) ifTrue: [
			node methodFilter: methodFilter.
			node ivarFilter: ivarFilter.
			node compositionData: composition.
			node memberKinds: (self showsGitRange ifTrue: [gitChanges at: #kinds] ifFalse: [nil]).
			node boxFill: (self showsCompositionColor ifTrue: [self boxFillFor: node] ifFalse: [nil])]].
	tuple := rootNode
		classDiagramGraphColorMode: self colorMode
		showState: showState
		showMethods: showMethods
		suppressingSuperclasses: self suppressedSuperclassNames
		clustered: self clustered
		composition: (self showsComposition and: [showState]).
	nodesByDotId := Dictionary new.
	fieldNodesByDotId := Dictionary new.
	rectKeyByNode := IdentityDictionary new.
	displayedKeys := nil.
	ids := tuple second.
	ids keysAndValuesDo: [:node :dotId |
		nodesByDotId at: dotId put: node.
		rectKeyByNode at: node put: (dotId -> nil).
		(node isKindOf: SWACodeClassNode) ifTrue: [ | fields |
			fields := node recordFieldNodesShowState: showState showMethods: showMethods.
			fieldNodesByDotId at: dotId put: fields.
			"Field 0 is the class name (whole node). Rows 1..N are ivar/method rows;
			map each DISTINCT row node to its field rect -- but never overwrite the
			class's own whole-box key (the class should highlight its whole box)."
			fields doWithIndex: [:fnode :i |
				(i > 1 and: [fnode ~~ node])
					ifTrue: [rectKeyByNode at: fnode put: (dotId -> (i - 1))]]]].
	graphMorph setDot: tuple first.
	graphPane graph: graphMorph keepView: keepView.
	graphPane onNodeClick: [:dotId | self graphNodeClicked: dotId].
	graphPane onFieldClick: [:assoc | self graphFieldClicked: assoc].
	graphPane onMenuRequest: [:evt | self graphMenuRequest: evt].
	graphPane onMarkerClick: [:node | self graphMarkerClicked: node].
	self updateReviewMarkers.
	self updateSelectionHighlight.
	self refreshChrome.
	"Granularity decides which keys are data, so a peer colouring by me is now stale."
	self notifyCrossReferenceDependents.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> refreshChrome [
	"Refresh all chrome labels + source pane via the nav panel, if attached."
	navPanel ifNotNil: [:p | p refresh]
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:19'
}
SWAClassDiagram >> reviewBadgeRectFor: aFieldRect [
	"A circle at the trailing edge of a method row. Rows are left-aligned and dot sizes
	the box to the widest one, so this is free space on every row but that one."
	| d |
	d := ((aFieldRect height - 4) min: 11) max: 7.
	^ ((aFieldRect right - d - 3) @ (aFieldRect center y - (d // 2))) rounded
		extent: d @ d
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> rootNode: aCodeNode [
	"The tree to draw; #focus narrows it to one category or class."
	fullRoot := aCodeNode.
	self showFocus.
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> saveCompositionData [
	navPanel ifNotNil: [:panel | panel saveDataset: self compositionDataset].
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:41'
}
SWAClassDiagram >> secondarySelection: aNodeOrNil [
	"The graph draws its own frames, so a foreign selection is a rect to set rather
	than a repaint to trigger."

	super secondarySelection: aNodeOrNil.
	graphMorph ifNil: [^ self].
	graphMorph foreignSelectionRect: (self graphRectForNode: aNodeOrNil)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 16:16'
}
SWAClassDiagram >> selectOrDeselectNode: aNodeOrNil [
	"Click to select, click the same row again to clear: one gesture both ways. Not
	used by the review badge -- clicking that must keep its row selected."
	self selectedNode: (selectedNode == aNodeOrNil
		ifTrue: [nil]
		ifFalse: [aNodeOrNil])
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> selectTileNode: aNodeOrNil [
	"Nav-panel Deselect button hook (parallels the treemap protocol)."
	self selectedNode: aNodeOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:42'
}
SWAClassDiagram >> selectedNode: aNodeOrNil [
	"Record the selection, move the blue highlight frame to it, and refresh the
	nav-panel chrome (breadcrumb, selection path, Show source pane)."
	selectedNode := aNodeOrNil.
	self updateSelectionHighlight.
	self refreshChrome.
	self notifyCrossReferenceSelection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAClassDiagram >> selectedSourceString [
	(selectedNode notNil and: [selectedNode respondsTo: #sourceString]) ifFalse: [^ ''].
	^ self gitDiffForSelection ifNil: [selectedNode sourceString]
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> selectionInfoString [
	"Second info line: metrics about the current selection."
	selectedNode ifNil: [^ ''].
	^ selectedNode kind asString, ': ', selectedNode name,
		'   ', selectedNode loc printString, ' LOC'
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> selectionPathString [
	"Full path to the selected node, or empty."
	^ selectedNode
		ifNil: ['']
		ifNotNil: [:n | n pathString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 15:15'
}
SWAClassDiagram >> setRoot: aNode [
	"SWAPane>>rebuildCodeMap drives every code view through #setRoot:, so the diagram
	has to answer it too -- Add / Remove / Reset package all went to
	doesNotUnderstand: without it."
	self flushMarksCache.
	self rootNode: aNode.
	^ self
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> showFocus [
	rootNode := self focusedCopyOf: fullRoot.
	self forgetGeneratedComposition.
	self rebuildKeyIndex.
	self rebuildGraph.
	self refreshChrome.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> showGitChanges: aDictionary [
	"A diagram opened on the live mark set filters against THAT set (see
	#markSetForBuild); leaving the sync up would hide everything the range found."
	self syncToMarkSet: nil.
	self rootNode: (SWACodeMarkSetRootNode new
		markSet: (aDictionary at: #marks);
		snapshot: (aDictionary at: #snapshot);
		yourself).
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:18'
}
SWAClassDiagram >> shownClasses [
	| classes |
	classes := OrderedCollection new.
	rootNode ifNotNil: [
		rootNode withAllChildrenDo: [:node |
			(node isKindOf: SWACodeClassNode) ifTrue: [classes add: node theClass]]].
	^ classes
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:14'
}
SWAClassDiagram >> showsComposition [
	"Draw association edges for ivars holding other domain objects. Only meaningful at a
	granularity that shows state, since an ivar drawn as an edge leaves the compartment."

	^ showsComposition ifNil: [true]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:14'
}
SWAClassDiagram >> showsComposition: aBoolean [
	showsComposition := aBoolean.
	self rebuildGraph
]

{
	#category : #composition,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:26'
}
SWAClassDiagram >> showsCompositionColor [
	^ colorMode notNil and: [colorMode asString beginsWith: 'composition_']
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAClassDiagram >> showsGitRange [
	^ gitChanges notNil
		and: [(rootNode isKindOf: SWACodeMarkSetRootNode) and: [rootNode snapshot notNil]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWAClassDiagram >> showsMethods [
	"Whether the current granularity renders method rows inside class boxes. True for the
	all-methods (#method) and selected (#selected) depths; which methods are shown is
	decided by #methodFilterForBuild (#selected shows only marked methods)."
	^ leafKind = #method or: [leafKind = #selected]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWAClassDiagram >> showsState [
	"Whether the current granularity renders the state (instance-variable) compartment
	inside class boxes. Off only at the coarsest #class granularity. For #selected the
	compartment is rendered but FILTERED to marked ivars (see #ivarFilterForBuild)."
	^ leafKind ~= #class
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAClassDiagram >> supportsGitRange [
	^ true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:05'
}
SWAClassDiagram >> suppressedSuperclassNames [
	^ suppressedSuperclassNames ifNil: [self class defaultSuppressedSuperclassNames]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 16:05'
}
SWAClassDiagram >> suppressedSuperclassNames: aCollectionOfStrings [
	suppressedSuperclassNames := aCollectionOfStrings.
	self rebuildGraph
]

{
	#category : #'marks-sync',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:13'
}
SWAClassDiagram >> syncToMarkSet: aMarkSet [
	"Keep this diagram LIVE-synced to aMarkSet: register as a dependent so that whenever the
	mark set changes (a mark added/removed elsewhere) we rebuild from the current marks.
	Only meaningful when rootNode is a SWACodeMarkSetRootNode over the same set. Safe to
	call once; re-registration is idempotent."
	syncedMarkSet == aMarkSet ifTrue: [^ self].
	syncedMarkSet ifNotNil: [syncedMarkSet removeDependent: self].
	syncedMarkSet := aMarkSet.
	aMarkSet ifNotNil: [aMarkSet addDependent: self]
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> takeOverRootFrom: aView [
	"Root and focus together: drawing the whole tree first would cost a layout of
	every class only to be thrown away."
	| newFocus |
	newFocus := aView currentFocus.
	aView showsGitRange ifFalse: [
		(aView unfocusedRoot == fullRoot and: [newFocus = focus]) ifTrue: [^ self].
		focus := newFocus.
		^ self rootNode: aView unfocusedRoot].
	"A range reads best showing only what changed, but a depth chosen here is kept."
	fullRoot ifNil: [leafKind := #selected].
	(self showsGitRange and: [rootNode snapshot == (gitChanges at: #snapshot)])
		ifTrue: [^ self focusOn: newFocus].
	focus := newFocus.
	self showGitChanges: gitChanges.
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> unfocusedRoot [
	^ fullRoot ifNil: [rootNode]
]

{
	#category : #'marks-sync',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:13'
}
SWAClassDiagram >> update: anAspect [
	"Dependent hook: the synced mark set changed. Invalidate the marks-scoped root so it
	re-reads the live marks, then rebuild the graph keeping the current zoom/pan. Guard
	against re-entrancy and non-marks roots."
	syncedMarkSet ifNil: [^ self].
	(rootNode isKindOf: SWACodeMarkSetRootNode) ifFalse: [^ self].
	self world ifNil: [^ self syncToMarkSet: nil].	"detached: unsubscribe"
	rootNode invalidate.
	self rebuildKeyIndex.
	self rebuildGraphKeepView: true
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAClassDiagram >> updateReviewMarkers [
	"Hand the GraphvizMorph one badge per method row, keyed by the node so a click
	resolves back without a second hit test."
	| list |
	graphMorph ifNil: [^ self].
	(self reviewScope isNil or: [rectKeyByNode isNil])
		ifTrue: [^ graphMorph markers: nil].
	list := OrderedCollection new.
	rectKeyByNode keysAndValuesDo: [:node :key |
		(key value notNil and: [node isKindOf: SWACodeMethodNode]) ifTrue: [
			(graphMorph rectForNode: key key field: key value) ifNotNil: [:fieldRect |
				list add: node -> {
					self reviewBadgeRectFor: fieldRect.
					self isNodeReviewed: node.
					Color green darker }]]].
	graphMorph markers: list
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:41'
}
SWAClassDiagram >> updateSelectionHighlight [
	"Set the embedded GraphvizMorph's selection rectangle to frame the currently
	selected node: a method uses its record field rect, a class/other node uses its
	whole-node rect. Clears the frame when nothing is selected or not laid out."
	graphMorph ifNil: [^ self].
	graphMorph selectionRect: (self graphRectForNode: selectedNode)
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:01'
}
SWAClassDiagram >> viewKind [
	^ #classDiagram
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> widerFocus [
	"One level up: a class to its category, a category to its parent, the top to all."
	| category |
	focus ifNil: [^ nil].
	focus key == #class ifTrue: [
		category := (self keyIndex at: focus value ifAbsent: [nil])
			ifNotNil: [:node | node theClass category].
		^ category ifNotNil: [#category -> category asString]].
	(focus value includes: $-) ifFalse: [^ nil].
	^ #category -> (focus value copyUpToLast: $-)
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> zoomOut [
	"Back: widen the focus, and deselect once there is nothing left to widen."
	focus ifNil: [^ self deselect].
	self focusOn: self widerFocus.
]

{
	#category : #focus,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAClassDiagram >> zoomTargetsForSelection [
	"Every category prefix of the selected class narrower than the focus, then the class."
	| classNode category prefixes targets |
	(selectedNode notNil and: [selectedNode respondsTo: #classNode]) ifFalse: [^ #()].
	classNode := selectedNode classNode ifNil: [^ #()].
	targets := OrderedCollection new.
	category := classNode theClass category.
	(category notNil and: [focus isNil or: [focus key == #category]]) ifTrue: [
		prefixes := OrderedCollection new.
		(category asString findTokens: '-') inject: '' into: [:prefix :segment | | next |
			next := prefix isEmpty ifTrue: [segment] ifFalse: [prefix, '-', segment].
			prefixes add: next.
			next].
		prefixes do: [:each |
			(focus isNil or: [each size > focus value size and: [each beginsWith: focus value]])
				ifTrue: [targets add: #category -> each]]].
	(focus isNil or: [focus value ~= classNode name]) ifTrue: [targets add: #class -> classNode name].
	^ targets
]
