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
		'priorSources',
		'reviewScope',
		'repositoryName',
		'fromCommit',
		'toCommit'
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
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:21'
}
SWAClassDiagram class >> addRemoval: aString static: isStatic isIvar: isIvar forClassNamed: aClassName into: aRemovalDictionary [
	| list entry |
	list := aRemovalDictionary at: aClassName ifAbsentPut: [OrderedCollection new].
	entry := Array with: aString with: isStatic with: isIvar.
	(list anySatisfy: [:each | each = entry]) ifFalse: [list add: entry]
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:36'
}
SWAClassDiagram class >> behaviorNamed: aString [
	"The class or metaclass aString names, or nil. Monticello spells the class side
	'SRAvatar class', which is also how a crossRefKey does."

	| behaviorName |
	behaviorName := aString asString.
	(behaviorName endsWith: ' class') ifTrue: [
		^ (Smalltalk at: (behaviorName copyFrom: 1 to: behaviorName size - 6) asSymbol ifAbsent: [nil])
			ifNotNil: [:cls | cls class]].
	^ Smalltalk at: behaviorName asSymbol ifAbsent: [nil]
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:32'
}
SWAClassDiagram class >> changesForRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"Everything the diagram needs about a commit range, from ONE diff -- the diff costs a
	tree materialisation and must not be run more than once. Answers a Dictionary:

		#marks         a SWAMarkSet, for the #selected granularity
		#kinds         crossRefKey -> #added / #modified, to colour the rows
		#removals      class name -> { displayText. isStatic. isIvar }, drawn struck through
		#priorSources  crossRefKey -> the source as it was, for the diff in the source pane

	Prior source comes off the obsoletion definition, which already carries it, so this
	costs nothing beyond the diff itself."

	| history base head changes result |
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
	result := Dictionary new.
	result at: #marks put: SWAMarkSet new.
	result at: #kinds put: Dictionary new.
	result at: #removals put: Dictionary new.
	result at: #priorSources put: Dictionary new.
	changes do: [:change | self record: change into: result].
	^ result
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
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:31'
}
SWAClassDiagram class >> openOnGitRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"A class diagram of what changed between two commits -- the range under review, with
	nothing else in the way. A nil second argument means the head commit.

	SWAClassDiagram openOnGitRepository: 'SqueakXRNative' from: '94b68b4' to: nil.
	SWAClassDiagram openOnGitRepository: 'SqueakXRNative' from: '94b68b4' to: 'a82eb22'.

	Both ends are named because head is not always the end you mean: a later commit that
	reformats or strips comments will otherwise swamp the feature work it follows.

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
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:33'
}
SWAClassDiagram class >> record: aCodeChange into: aResult [
	"One change: mark it and note its kind if the member still exists, record it as a
	removal if it does not. An MCModification carries the definition as it was, which is
	both how a modification is told from an addition and where the diff text comes from."

	| op defn prior clsName sel behavior key |
	op := [aCodeChange operation] on: Error do: [:e | nil].
	op ifNil: [^ self].
	defn := [op definition] on: Error do: [:e | nil].
	defn ifNil: [^ self].
	prior := (op respondsTo: #obsoletion) ifTrue: [[op obsoletion] on: Error do: [:e | nil]] ifFalse: [nil].
	(defn isKindOf: MCMethodDefinition) ifTrue: [
		clsName := [defn fullClassName asString] on: Error do: [:e | nil].
		sel := [defn selector] on: Error do: [:e | nil].
		(clsName isNil or: [sel isNil]) ifTrue: [^ self].
		behavior := self behaviorNamed: clsName.
		behavior ifNil: [^ self].
		(([op isRemoval] on: Error do: [:e | false])
			or: [(behavior includesSelector: sel asSymbol) not])
				ifTrue: [^ self
					addRemoval: sel asString
					static: behavior isMeta
					isIvar: false
					forClassNamed: behavior theNonMetaClass name asString
					into: (aResult at: #removals)].
		key := clsName, '>>', sel asString.
		(aResult at: #marks) add: key.
		(aResult at: #kinds) at: key put: (prior isNil ifTrue: [#added] ifFalse: [#modified]).
		prior ifNotNil: [
			([prior source] on: Error do: [:e | nil])
				ifNotNil: [:src | (aResult at: #priorSources) at: key put: src asString]].
		^ self].
	(defn isKindOf: MCClassDefinition) ifTrue: [
		clsName := [defn className asString] on: Error do: [:e | nil].
		clsName ifNil: [^ self].
		behavior := self behaviorNamed: clsName.
		behavior ifNil: [^ self].
		(aResult at: #marks) add: behavior theNonMetaClass name asString.
		self recordIvarsOf: op definition: defn into: aResult]
]

{
	#category : #git,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:33'
}
SWAClassDiagram class >> recordIvarsOf: anOperation definition: aClassDefinition into: aResult [
	"Added instance variables get marked as #added, dropped ones recorded as removals.
	Only an MCModification carries an #obsoletion, so a newly added class has nothing to
	compare against and every ivar of it is new."

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
		((oldNames includes: each) not and: [behavior allInstVarNames includes: each]) ifTrue: [
			(aResult at: #marks) add: clsName, '>>#', each.
			(aResult at: #kinds) at: clsName, '>>#', each put: #added]].
	oldNames do: [:each |
		(newNames includes: each) ifFalse: [
			self
				addRemoval: each static: false isIvar: true
				forClassNamed: behavior theNonMetaClass name asString
				into: (aResult at: #removals)]]
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:57'
}
SWAClassDiagram >> breadcrumbString [
	"Top breadcrumb line: the graph's root."
	rootNode ifNil: [^ ''].
	^ rootNode name, '  (class diagram)'
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
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:39'
}
SWAClassDiagram >> colorModeOptions [
	"{ symbol. label } pairs for the shared Color menu/button. The graph recolors by
	re-rendering with per-row fill from the chosen mode."
	^ {
		{ #kind. 'Flat (by kind)' }.
		{ #loc. 'LOC heat (green->red)' } }
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> commitLabelFor: aHexPrefix [
	"'aae5930  the subject line', short enough to sit in a field."
	| repoHistory commit |
	aHexPrefix ifNil: [^ ''].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ aHexPrefix].
	commit := repoHistory commitWithHexPrefix: aHexPrefix.
	commit ifNil: [^ aHexPrefix].
	^ aHexPrefix, '  ', ((repoHistory summaryOf: commit) truncateWithElipsisTo: 30)
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:24'
}
SWAClassDiagram >> dataPanelFor: aPane [
	"The Data flap's contents: the commit range this diagram is a picture of. Each
	field is typeable as well as pickable -- a hash under review is usually pasted
	from a mail or a pull request, not one of the recent ones -- and each shows the
	commit's subject line, so the range reads as what it is rather than as two hashes.

	From also takes PARENT: with that set, stepping To down the log walks the history
	one commit at a time. Accepting any field re-diffs (see #reloadFromGit); Reload
	re-runs the same range, for after a commit.

	Wraps like the header bar, so a narrow pane stacks the fields instead of
	overflowing its window."
	| row reload |
	row := Morph new
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		wrapDirection: #topToBottom;
		cellPositioning: #leftCenter;
		cellInset: 8;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	reload := (aPane buttonLabelled: 'Reload' action: #reloadFromGit)
		target: self;
		yourself.
	reload setBalloonText: 'Diff this range again, picking up new commits'.
	row
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #repositoryName set: #repositoryName:
			choices: #repositoryChoices label: 'Repository' width: 170);
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #fromCommitLabel set: #fromCommit:
			choices: #fromCommitChoices label: 'From' width: 210);
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #toCommitLabel set: #toCommit:
			choices: #toCommitChoices label: 'To' width: 210);
		addMorphBack: reload.
	^ row
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWAClassDiagram >> depthLabelString [
	"Friendly Depth-button text for this view's granularities."
	^ 'Depth: ', (leafKind caseOf: {
		[#class]  -> ['Classes'].
		[#state]  -> ['+State'].
		[#method] -> ['+Methods'].
		[#selected] -> ['+Selected'] }
		otherwise: ['Classes'])
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:29'
}
SWAClassDiagram >> fromCommit [
	^ fromCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:22'
}
SWAClassDiagram >> fromCommit: aString [
	| value |
	value := self normalizeCommitInput: aString.
	value = fromCommit ifTrue: [^ self].
	self tryRange: [fromCommit := value]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> fromCommitChoices [
	"PARENT leads the list: with From on PARENT, stepping To down the log shows what
	each commit changed, one at a time."
	^ (OrderedCollection with: 'PARENT' -> 'PARENT (just what To changed)') , self recentCommits
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> fromCommitLabel [
	"What the From field shows: the keyword as chosen, or the commit's subject line so
	the field says what it points at rather than just where."
	self isParentFrom ifTrue: [^ 'PARENT'].
	^ self commitLabelFor: fromCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:29'
}
SWAClassDiagram >> gitHistory [
	"A history on the named repository, or nil when there is no such working copy."
	repositoryName isNil ifTrue: [^ nil].
	^ [SWAGitHistory onWorkingCopyNamed: repositoryName] on: Error do: [:e | nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:22'
}
SWAClassDiagram >> gitRangeLabel [
	"'mysqueak aae5930..a1f8091' -- names the range for the window title and, more
	importantly, for the review marks: a sign-off is only meaningful together with the
	version it was given to, so both ends are the RESOLVED hashes. PARENT and HEAD
	would each mean something different tomorrow."
	| from to |
	repositoryName ifNil: [^ 'Class Diagram'].
	from := self resolvedFromCommit.
	from ifNil: [^ repositoryName].
	to := self resolvedToCommit ifNil: ['HEAD'].
	^ repositoryName, ' ',
		(from first: (from size min: 7)), '..', (to first: (to size min: 7))
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:44'
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
		ifTrue: [self selectedNode: (fieldNodes at: idx)]
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
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:39'
}
SWAClassDiagram >> graphMenuRequest: evt [
	"Right-click on the graph: pop up a context menu with the shared Color submenu
	(same #colorMenuMorph the header Color button uses)."
	| menu colorMenu |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: 'Class Diagram'.
	colorMenu := self colorMenuMorph.
	colorMenu ifNotNil: [menu add: 'Color' subMenu: colorMenu].
	self popUpMenu: menu at: (evt ifNil: [self currentHand] ifNotNil: [evt hand]) position truncated
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWAClassDiagram >> graphNodeClicked: aDotId [
	"A node in the embedded graph was clicked: select the matching SWACodeNode."
	self selectedNode: (nodesByDotId at: aDotId ifAbsent: [nil])
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
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> isNodeReviewed: aNode [
	| key |
	key := self reviewKeyFor: aNode.
	key ifNil: [^ false].
	^ SWAMarkSet reviewed includes: key
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> isParentFrom [
	"Whether the From end is the symbolic PARENT rather than a hash."
	^ fromCommit notNil and: [fromCommit asUppercase = 'PARENT']
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:26'
}
SWAClassDiagram >> loadGitRange [
	"Diff the range and rebuild everything the diagram shows from that ONE diff.
	Answers whether it loaded.

	Works on the RESOLVED ends: the fields may say PARENT or HEAD, which are positions
	rather than commits, and a review sign-off has to name the commit it was given to.
	An end that will not resolve is REPORTED -- answering false quietly would look
	exactly like a range that changed nothing.

	Order matters: priorSources and reviewScope must be in place before #rootNode:,
	which rebuilds the graph and reads both."
	| from to result root |
	(repositoryName isNil or: [fromCommit isNil]) ifTrue: [^ false].
	to := self resolvedToCommit.
	from := self resolvedFromCommit.
	from ifNil: [
		self reportProblem: (self isParentFrom
			ifTrue: ['no commit starting ', (toCommit ifNil: ['HEAD']), ' to take the parent of']
			ifFalse: ['no commit starting ', fromCommit, ' in ', repositoryName]).
		^ false].
	result := [self class changesForRepository: repositoryName from: from to: to]
		on: Error
		do: [:e | self reportProblem: e messageText. nil].
	result ifNil: [^ false].
	root := SWACodeMarkSetRootNode new markSet: (result at: #marks); yourself.
	root withAllChildrenDo: [:node |
		(node isKindOf: SWACodeClassNode) ifTrue: [
			node memberKinds: (result at: #kinds).
			((result at: #removals) at: node name ifAbsent: [nil])
				ifNotNil: [:list | node removedMembers: list]]].
	"A diagram opened on the live mark set filters against THAT set (see
	#markSetForBuild); leaving the sync up would hide everything the range found."
	self syncToMarkSet: nil.
	self priorSources: (result at: #priorSources).
	self reviewScope: self gitRangeLabel.
	self rootNode: root.
	^ true
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> normalizeCommitInput: aString [
	"The fields show 'aae5930  the subject line', so an accepted value may be a whole
	label, a bare hash, or a keyword. Everything up to the first blank is the value."
	| text |
	text := aString ifNil: [''] ifNotNil: [:s | s asString withBlanksTrimmed].
	text isEmpty ifTrue: [^ nil].
	text := (text findTokens: ' ') first.
	text asUppercase = 'PARENT' ifTrue: [^ 'PARENT'].
	text asUppercase = 'HEAD' ifTrue: [^ 'HEAD'].
	^ text
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
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:46'
}
SWAClassDiagram >> priorSourceForSelection [
	"The selected member's source as it was before the range being shown, or nil."

	| key |
	(priorSources isNil or: [selectedNode isNil]) ifTrue: [^ nil].
	key := [selectedNode crossRefKey] on: Error do: [:e | nil].
	key ifNil: [^ nil].
	^ priorSources at: key ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:37'
}
SWAClassDiagram >> priorSources: aDictionary [
	"crossRefKey -> the source as it was before the range being shown. Makes the Show
	pane display a diff rather than just the current source."

	priorSources := aDictionary
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
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
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
	| tuple ids showState showMethods methodFilter ivarFilter |
	rootNode ifNil: [^ self].
	showState := self showsState.
	showMethods := self showsMethods.
	"Install the per-granularity ivar/method filters on every class node before building,
	so #recordIvarNodes / #recordMethodNodes (DOT label, field-click map, compartments)
	all agree."
	methodFilter := self methodFilterForBuild.
	ivarFilter := self ivarFilterForBuild.
	rootNode withAllChildrenDo: [:node |
		(node isKindOf: SWACodeClassNode) ifTrue: [
			node methodFilter: methodFilter.
			node ivarFilter: ivarFilter]].
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
	self refreshChrome
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:35'
}
SWAClassDiagram >> recentCommits [
	"The newest commits of the current repository as value -> menu label: short hash
	-> the git log --oneline line. Capped, since this feeds a pop-up menu."
	| repoHistory ancestry |
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ #()].
	ancestry := [repoHistory workingCopy headCommit ancestors] on: Error do: [:e | #()].
	ancestry ifNil: [^ #()].
	ancestry := ancestry first: (SWAGitHistory defaultMaxCommits min: ancestry size).
	^ ancestry collect: [:commit |
		([commit hexHash first: 7] on: Error do: [:e | '???????'])
			-> (repoHistory commitLabelFor: commit)]
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:34'
}
SWAClassDiagram >> refreshDataPanel [
	"Reload the Data flap's fields from me, after I changed them myself."
	navPanel ifNotNil: [:panel | panel refreshDataPanel]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:34'
}
SWAClassDiagram >> reloadFromGit [
	"Re-diff and rebuild, answering whether it loaded. A range that does not resolve
	leaves the current diagram standing: the fields are edited live, so a half-typed
	hash must not wipe the screen."
	self loadGitRange ifFalse: [^ false].
	self updateWindowLabel.
	^ true
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:26'
}
SWAClassDiagram >> reportProblem: aString [
	"Say why the range did not load, without a modal dialog -- the fields are edited
	live, and a dialog would block the pane that owns them."
	navPanel
		ifNil: [Transcript cr; show: 'class diagram: ', aString]
		ifNotNil: [:panel | panel showMessage: aString]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:29'
}
SWAClassDiagram >> repositoryChoices [
	"value -> menu label for the Repository drop-down: every git working copy the
	image has open."
	^ SWAGitHistory workingCopies collect: [:wc |
		| name |
		name := [wc name] on: Error do: [:e | '?'].
		name -> name]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:29'
}
SWAClassDiagram >> repositoryName [
	^ repositoryName
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:34'
}
SWAClassDiagram >> repositoryName: aString [
	"Switching repository invalidates the range: hashes are repository-local, so the
	old ones would not resolve. The new range defaults to what the newest commit
	changed."
	| name |
	name := aString ifNil: [''] ifNotNil: [:s | s asString withBlanksTrimmed].
	name = repositoryName ifTrue: [^ self].
	self tryRange: [
		repositoryName := name.
		self resetRangeToNewestCommit]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:22'
}
SWAClassDiagram >> resetRangeToNewestCommit [
	"Point the range at what the newest commit changed. Said symbolically, so it needs
	no git walk here and stays right as the branch grows."
	fromCommit := 'PARENT'.
	toCommit := nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> resolvedFromCommit [
	"The hash the range starts at. PARENT means the first parent of the TO end, which
	is what makes stepping To down the log show one commit at a time."
	| repoHistory target |
	fromCommit ifNil: [^ nil].
	self isParentFrom ifFalse: [^ fromCommit].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ nil].
	target := toCommit
		ifNil: [[repoHistory workingCopy headCommit] on: Error do: [:e | nil]]
		ifNotNil: [:hex | repoHistory commitWithHexPrefix: hex].
	target ifNil: [^ nil].
	^ [target firstParent hexHash first: 7] on: Error do: [:e | nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> resolvedToCommit [
	"The hash the range ends at. The field may say HEAD, which moves."
	| repoHistory |
	toCommit ifNotNil: [^ toCommit].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ nil].
	^ [repoHistory workingCopy headCommit hexHash first: 7] on: Error do: [:e | nil]
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
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> reviewKeyFor: aNode [
	"The key under which aNode is signed off in SWAMarkSet reviewed, or nil when there
	is nothing to sign off: no commit range, or a node with no mark key."
	| key |
	reviewScope ifNil: [^ nil].
	aNode ifNil: [^ nil].
	key := aNode markKey.
	key ifNil: [^ nil].
	^ reviewScope, ' ', key
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> reviewScope [
	^ reviewScope
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> reviewScope: aStringOrNil [
	"Names the commit range this diagram shows, e.g. 'SqueakXRNative 2269a69..399beef'.
	A review mark is only meaningful together with the version reviewed, so the scope
	becomes part of the reviewed key. nil switches the review badges off."
	reviewScope := aStringOrNil.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWAClassDiagram >> rootNode: aCodeNode [
	"Set the SWACodeNode subtree to visualize and build the graph."
	rootNode := aCodeNode.
	self rebuildKeyIndex.
	self rebuildGraph
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
SWAClassDiagram >> selectedNode: aNodeOrNil [
	"Record the selection, move the blue highlight frame to it, and refresh the
	nav-panel chrome (breadcrumb, selection path, Show source pane)."
	selectedNode := aNodeOrNil.
	self updateSelectionHighlight.
	self refreshChrome
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:46'
}
SWAClassDiagram >> selectedSourceString [
	"Source text for the Show pane: the selected node's source, or empty."
	| prior |
	(selectedNode notNil and: [selectedNode respondsTo: #sourceString]) ifFalse: [^ ''].
	prior := self priorSourceForSelection.
	prior ifNil: [^ selectedNode sourceString].
	^ [TextDiffBuilder
		buildDisplayPatchFrom: prior
		to: selectedNode sourceString asString
		inClass: ([selectedNode parent theClass] on: Error do: [:e | nil])
		prettyDiffs: false]
			on: Error do: [:e | selectedNode sourceString]
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:30'
}
SWAClassDiagram >> setRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"Install the range WITHOUT loading -- the individual setters each reload, which is
	right when a field is edited and wrong while all three are being installed."
	repositoryName := aRepositoryName.
	fromCommit := aHexPrefix.
	toCommit := aHexPrefixOrNil
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
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 17:46'
}
SWAClassDiagram >> styleClassForSelection [
	"No styling class while a diff is on show: Shout restyles the whole pane from the
	source text and would overwrite the insert/remove attributes TextDiffBuilder put
	there, leaving the diff looking exactly like ordinary source."

	self priorSourceForSelection ifNotNil: [^ nil].
	^ super styleClassForSelection
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
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:29'
}
SWAClassDiagram >> toCommit [
	"nil means the head commit."
	^ toCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:22'
}
SWAClassDiagram >> toCommit: aString [
	"HEAD is a position, not a commit: the diff API spells it nil."
	| value |
	value := self normalizeCommitInput: aString.
	(value notNil and: [value = 'HEAD']) ifTrue: [value := nil].
	value = toCommit ifTrue: [^ self].
	self tryRange: [toCommit := value]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> toCommitChoices [
	"HEAD leads the list: reviewing up to the tip is the common case, and it stays
	right as the branch grows."
	^ (OrderedCollection with: 'HEAD' -> 'HEAD (branch tip)') , self recentCommits
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 14:21'
}
SWAClassDiagram >> toCommitLabel [
	"What the To field shows. The head commit has a name rather than a blank."
	toCommit ifNil: [^ 'HEAD'].
	^ self commitLabelFor: toCommit
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> toggleReviewed: aNode [
	"Sign aNode off, or take the sign-off back."
	| key prov |
	key := self reviewKeyFor: aNode.
	key ifNil: [^ self].
	prov := self markProvenance.
	prov at: 'nodeKind' put: aNode nodeKind asString.
	prov at: 'reviewScope' put: reviewScope.
	SWAMarkSet reviewed toggle: key from: prov.
	self updateReviewMarkers.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:34'
}
SWAClassDiagram >> tryRange: aBlock [
	"Apply a range change, undoing it when the new range does not load. The fields have
	to describe the picture on screen, and a hash that resolves to nothing would
	otherwise leave them claiming a range the diagram is not of."
	| snapshot |
	snapshot := { repositoryName. fromCommit. toCommit }.
	aBlock value.
	self reloadFromGit ifFalse: [
		repositoryName := snapshot first.
		fromCommit := snapshot second.
		toCommit := snapshot third].
	self refreshDataPanel
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
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/21/2026 18:18'
}
SWAClassDiagram >> updateReviewMarkers [
	"Hand the GraphvizMorph one badge per method row, keyed by the node so a click
	resolves back without a second hit test."
	| list |
	graphMorph ifNil: [^ self].
	(reviewScope isNil or: [rectKeyByNode isNil])
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
SWAClassDiagram >> updateSelectionHighlight [
	"Set the embedded GraphvizMorph's selection rectangle to frame the currently
	selected node: a method uses its record field rect, a class/other node uses its
	whole-node rect. Clears the frame when nothing is selected or not laid out."
	| key rect |
	graphMorph ifNil: [^ self].
	(selectedNode isNil or: [rectKeyByNode isNil])
		ifTrue: [^ graphMorph selectionRect: nil].
	key := rectKeyByNode at: selectedNode ifAbsent: [nil].
	rect := key isNil
		ifTrue: [nil]
		ifFalse: [key value isNil
			ifTrue: [graphMorph rectForNode: key key]
			ifFalse: [graphMorph rectForNode: key key field: key value]].
	graphMorph selectionRect: rect
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:30'
}
SWAClassDiagram >> updateWindowLabel [
	"Keep the window title on the range actually shown."
	navPanel ifNil: [^ self].
	navPanel enclosingWindow ifNotNil: [:window | window setLabel: self gitRangeLabel]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:01'
}
SWAClassDiagram >> viewKind [
	^ #classDiagram
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> zoomOut [
	"Back button: no hierarchical zoom in the graph view, so just deselect."
	self deselect
]
