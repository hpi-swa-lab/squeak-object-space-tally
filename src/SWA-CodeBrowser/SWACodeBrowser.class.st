"
The four-pane System Browser layout over the same SWACodeNode tree the Code Map and the class diagram draw, so a commit range, its review sign-offs and the selection carry over when the pane switches views. The code pane is SWAPane's Source flap.
"
Class {
	#name : #SWACodeBrowser,
	#superclass : #SWAView,
	#instVars : [
		'selectedPackage',
		'selectedClass',
		'selectedCategory',
		'selectedMethod',
		'side',
		'columnNodes',
		'sideButtons',
		'refreshPending',
		'allCategories'
	],
	#category : #'SWA-CodeBrowser',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> aboutToStyle: aStyler [
	"A class definition is styled as a doit, a comment or a diff not at all."
	(selectedNode isKindOf: SWACodeClassNode) ifTrue: [
		self priorSourceForSelection ifNotNil: [^ false].
		aStyler classOrMetaClass: nil; parseAMethod: false.
		^ true].
	((selectedNode isKindOf: SWACodeMethodNode) and: [(selectedNode isKindOf: SWACodeCommentNode) not])
		ifFalse: [^ false].
	aStyler parseAMethod: true.
	^ super aboutToStyle: aStyler
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> breadcrumbString [
	rootNode ifNil: [^ ''].
	^ rootNode name, '  (browser)'
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> browseSelected [
	selectedNode
		ifNil: [Beeper beep]
		ifNotNil: [:node | node browse]
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> canZoomOut [
	^ selectedNode notNil
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> categoryIndex [
	^ self indexIn: #category
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> categoryIndex: anInteger [
	self select: anInteger in: #category.
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> categoryList [
	^ self labelsIn: #category
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> categoryNodesOf: aClassNode [
	side == #comment ifTrue: [^ #()].
	^ ((self visibleChildrenOf: aClassNode) select: [:each |
		(each isKindOf: SWACodeCategoryNode) and: [each isStatic = (side == #class)]]) asArray
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> classIndex [
	^ self indexIn: #class
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> classIndex: anInteger [
	self select: anInteger in: #class.
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> classList [
	^ self labelsIn: #class
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> classNodesUnder: aNode [
	| nodes |
	nodes := OrderedCollection new.
	self classesUnder: aNode into: nodes.
	^ (nodes asSortedCollection: [:a :b | a name <= b name]) asArray
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> classesUnder: aNode into: aCollection [
	(self visibleChildrenOf: aNode) do: [:each |
		(each isKindOf: SWACodeClassNode)
			ifTrue: [aCollection add: each]
			ifFalse: [(self isPackageNode: each) ifTrue: [self classesUnder: each into: aCollection]]].
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWACodeBrowser >> codeChanged [
	super codeChanged.
	self refreshLists.
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> codeViewKey [
	^ #browser
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:00'
}
SWACodeBrowser >> commentNodeOf: aClassNode [
	"A class without a comment gets a node anyway, so ? can write the first one."
	^ aClassNode children
		detect: [:each | each isKindOf: SWACodeCommentNode]
		ifNone: [SWACodeCommentNode on: aClassNode subject parent: aClassNode]
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> computeNodesIn: aColumn [
	rootNode ifNil: [^ #()].
	aColumn == #package ifTrue: [^ self packageNodes].
	aColumn == #class ifTrue: [^ self classNodesUnder: (selectedPackage ifNil: [rootNode])].
	aColumn == #category ifTrue: [
		(selectedClass isNil or: [side == #comment]) ifTrue: [^ #()].
		^ {#all}, (self categoryNodesOf: selectedClass)].
	^ self methodNodes
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> currentFocus [
	^ self focusForNode: (selectedClass ifNil: [selectedPackage])
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> dataPanelExtrasFor: aPane [
	^ self rangeViewButtonsFor: aPane
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> focusOn: aFocus [
	aFocus ifNil: [^ self].
	(self nodeForFocus: aFocus) ifNotNil: [:node | self selectedNode: node].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:38'
}
SWACodeBrowser >> hasRangeViews [
	^ true
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> indexIn: aColumn [
	^ (self nodesIn: aColumn) indexOf: (self selectionIn: aColumn)
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> initialize [
	super initialize.
	side := #instance.
	self
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellInset: 2;
		hResizing: #spaceFill;
		vResizing: #spaceFill.
	self
		addMorphBack: (self newColumn: {self newListFor: #package});
		addMorphBack: (self newColumn: {self newListFor: #class. self newSideButtonRow});
		addMorphBack: (self newColumn: {self newListFor: #category});
		addMorphBack: (self newColumn: {self newListFor: #method}).
]

{
	#category : #labels,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWACodeBrowser >> labelFor: aNode in: aColumn [
	aNode == #all ifTrue: [^ '-- all --'].
	^ self changeLabel: (self nameOf: aNode in: aColumn) for: aNode
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> labelsIn: aColumn [
	^ (self nodesIn: aColumn) collect: [:each | self labelFor: each in: aColumn]
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> listKeystroke: anEvent [
	"r signs off the selection, R everything under it. This takes the two letters away
	from the lists' type-ahead."
	| char |
	selectedNode ifNil: [^ false].
	char := anEvent keyCharacter.
	(self isReviewKey: char event: anEvent) ifTrue: [
		self toggleReviewedUnder: selectedNode.
		^ true].
	(char = $R and: [(anEvent commandKeyPressed or: [anEvent controlKeyPressed]) not]) ifTrue: [
		self toggleReviewedAllUnder: selectedNode.
		^ true].
	^ false
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> listMenu: aMenu [
	selectedNode ifNil: [^ aMenu].
	aMenu add: 'browse' target: self selector: #browseSelected.
	self showsGitRange ifTrue: [
		aMenu
			add: 'sign off / take back (r)' target: self selector: #toggleReviewedUnder: argument: selectedNode;
			add: 'sign off everything under it (R)' target: self selector: #toggleReviewedAllUnder: argument: selectedNode].
	^ aMenu
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> methodIndex [
	^ self indexIn: #method
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> methodIndex: anInteger [
	self select: anInteger in: #method.
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> methodList [
	^ self labelsIn: #method
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> methodNodes [
	| methods |
	selectedCategory ifNotNil: [:node | ^ (self visibleChildrenOf: node) asArray].
	(allCategories == true and: [selectedClass notNil]) ifFalse: [^ #()].
	methods := OrderedCollection new.
	(self categoryNodesOf: selectedClass) do: [:each | methods addAll: (self visibleChildrenOf: each)].
	^ (methods asSortedCollection: [:a :b | a name <= b name]) asArray
]

{
	#category : #labels,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> nameOf: aNode in: aColumn [
	(aNode isKindOf: SWACodeSubpackageNode) ifTrue: [^ aNode fullCategory].
	aColumn == #category ifTrue: [^ aNode subject asString].
	^ aNode name
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> newColumn: aCollection [
	| column |
	column := Morph new
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellInset: 2;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		yourself.
	aCollection do: [:each | column addMorphBack: each].
	^ column
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> newListFor: aColumn [
	| list |
	list := PluggableListMorph
		on: self
		list: (aColumn, 'List') asSymbol
		selected: (aColumn, 'Index') asSymbol
		changeSelected: (aColumn, 'Index:') asSymbol
		menu: #listMenu:
		keystroke: nil.
	list
		keystrokePreviewSelector: #listKeystroke:;
		hResizing: #spaceFill;
		vResizing: #spaceFill.
	^ list
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> newSideButtonRow [
	| row |
	row := Morph new
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellInset: 2;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	sideButtons := Dictionary new.
	#(#(#instance 'instance') #(#comment '?') #(#class 'class')) do: [:pair | | button |
		button := SimpleButtonMorph new
			label: pair second;
			target: self;
			actionSelector: #side:;
			arguments: {pair first};
			hResizing: #spaceFill;
			vResizing: #rigid;
			yourself.
		sideButtons at: pair first put: button.
		row addMorphBack: button].
	self updateSideButtons.
	^ row
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> nodesIn: aColumn [
	columnNodes ifNil: [columnNodes := Dictionary new].
	^ columnNodes at: aColumn ifAbsentPut: [self computeNodesIn: aColumn]
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> opensSourceFlap [
	^ true
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> packageIndex [
	^ self indexIn: #package
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> packageIndex: anInteger [
	self select: anInteger in: #package.
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> packageList [
	^ self labelsIn: #package
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> packageNodes [
	| nodes |
	nodes := OrderedCollection new.
	self packagesUnder: rootNode into: nodes.
	^ nodes asArray
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> packagesUnder: aNode into: aCollection [
	(self visibleChildrenOf: aNode) do: [:each |
		(self isPackageNode: each) ifTrue: [
			aCollection add: each.
			self packagesUnder: each into: aCollection]].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 18:05'
}
SWACodeBrowser >> rangeViewChanged [
	super rangeViewChanged.
	self refreshLists.
	self refreshChrome.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> refreshChrome [
	navPanel ifNotNil: [:panel | panel refresh]
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> refreshLists [
	columnNodes := nil.
	#(#package #class #category #method) do: [:each |
		self changed: (each, 'List') asSymbol.
		self changed: (each, 'Index') asSymbol].
	self updateSideButtons.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> revealNode: aNode [
	"Point every column at aNode's ancestors, the way the System Browser shows where a
	method lives. A broader package that is already selected and contains aNode stays
	selected, and so does -- all -- for the methods of its class."
	| node previousPackage previousClass |
	previousPackage := selectedPackage.
	previousClass := selectedClass.
	selectedPackage := selectedClass := selectedCategory := selectedMethod := nil.
	columnNodes := nil.
	node := aNode.
	[node notNil] whileTrue: [
		(node isKindOf: SWACodeCommentNode)
			ifTrue: [side := #comment]
			ifFalse: [
				(node isKindOf: SWACodeMethodNode) ifTrue: [
					selectedMethod := node.
					side := node isStatic ifTrue: [#class] ifFalse: [#instance]].
				(node isKindOf: SWACodeCategoryNode) ifTrue: [
					selectedCategory := node.
					side := node isStatic ifTrue: [#class] ifFalse: [#instance]]].
		(node isKindOf: SWACodeClassNode) ifTrue: [selectedClass := node].
		((self isPackageNode: node) and: [selectedPackage isNil]) ifTrue: [selectedPackage := node].
		(node == previousPackage and: [(self isPackageNode: aNode) not])
			ifTrue: [selectedPackage := previousPackage].
		node := node parent].
	allCategories := allCategories == true
		and: [selectedClass notNil
		and: [selectedClass == previousClass
		and: [(aNode isKindOf: SWACodeCategoryNode) not]]].
	allCategories ifTrue: [selectedCategory := nil].
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:41'
}
SWACodeBrowser >> runInfoString [
	^ self codeRunInfoString
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> searchFor: aStringOrNil [
	super searchFor: aStringOrNil.
	self refreshLists.
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> select: anIndex in: aColumn [
	"Clicking the selected item again deselects it, as in the System Browser."
	| node |
	node := (self nodesIn: aColumn) at: anIndex ifAbsent: [nil].
	aColumn == #category ifTrue: [allCategories := node == #all].
	node ifNil: [^ self selectedNode: (self selectionAbove: aColumn)].
	node == #all ifTrue: [^ self selectedNode: selectedClass].
	(aColumn == #class and: [side == #comment]) ifTrue: [
		^ self selectedNode: (self commentNodeOf: node)].
	self selectedNode: node.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectNodeForKey: aCrossRefKey [
	"An instance variable picked in the diagram has no row here; its class does."
	| node |
	aCrossRefKey ifNil: [^ self].
	node := self keyIndex at: aCrossRefKey ifAbsent: [
		self keyIndex at: (aCrossRefKey copyUpTo: $>) ifAbsent: [^ self]].
	self selectedNode: node.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectTileNode: aNodeOrNil [
	self selectedNode: aNodeOrNil.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectedNode: aNodeOrNil [
	self revealNode: aNodeOrNil.
	super selectedNode: aNodeOrNil.
	self refreshLists.
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectedSourceString [
	selectedNode ifNil: [^ ''].
	^ self gitDiffForSelection ifNil: [self currentTextFor: selectedNode]
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectionAbove: aColumn [
	aColumn == #method ifTrue: [^ selectedCategory ifNil: [selectedClass]].
	aColumn == #category ifTrue: [^ selectedClass].
	aColumn == #class ifTrue: [^ selectedPackage].
	^ nil
]

{
	#category : #columns,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> selectionIn: aColumn [
	^ aColumn caseOf: {
		[#package] -> [selectedPackage].
		[#class] -> [selectedClass].
		[#category] -> [allCategories == true ifTrue: [#all] ifFalse: [selectedCategory]].
		[#method] -> [selectedMethod] }
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWACodeBrowser >> selectionInfoString [
	^ self codeSelectionInfoString
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> selectionPathString [
	^ selectedNode ifNil: [''] ifNotNil: [:node | node pathString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> setRoot: aNode [
	"A new tree, e.g. the range's after the live one: keep pointing at the same member."
	| previous |
	previous := selectedNode.
	rootNode := aNode.
	selectedNode := nil.
	columnNodes := nil.
	self flushMarksCache.
	self rebuildKeyIndex.
	searchQuery ifNotNil: [self rebuildSearchMatches].
	self selectedNode: (previous ifNotNil: [:node | self equivalentOf: node]).
	^ self
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> showGitChanges: aDictionary [
	self showRangeTree: aDictionary.
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:46'
}
SWACodeBrowser >> side [
	^ side
]

{
	#category : #'list access',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:00'
}
SWACodeBrowser >> side: aSymbol [
	self okToChange ifFalse: [^ self].
	side := aSymbol.
	selectedClass ifNil: [^ self refreshLists].
	self selectedNode: (aSymbol == #comment
		ifTrue: [self commentNodeOf: selectedClass]
		ifFalse: [selectedClass]).
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> supportsGitRange [
	^ true
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> takeOverRootFrom: aView [
	self takeOverRangeRootsFrom: aView.
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWACodeBrowser >> toggleReviewedUnder: aNode [
	self toggleReviewedShownUnder: aNode.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> updateReviewMarkers [
	"Signing off a whole package arrives here once per member."
	super updateReviewMarkers.
	refreshPending == true ifTrue: [^ self].
	refreshPending := true.
	Project current addDeferredUIMessage: [
		refreshPending := false.
		self refreshLists.
		self refreshChrome].
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> updateSideButtons [
	sideButtons ifNil: [^ self].
	sideButtons keysAndValuesDo: [:key :button |
		button color: (key == side
			ifTrue: [Color h: 210 s: 0.6 v: 0.7]
			ifFalse: [Color gray: 0.3])].
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:45'
}
SWACodeBrowser >> updateWindowLabel [
	navPanel ifNotNil: [:panel | panel view == self ifTrue: [panel updateCodeViewWindowLabel]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWACodeBrowser >> viewKind [
	^ #codeBrowser
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:12'
}
SWACodeBrowser >> zoomOut [
	"Back: one column to the left."
	(selectedNode isKindOf: SWACodeCommentNode) ifTrue: [
		side := #instance.
		^ self selectedNode: selectedClass].
	selectedMethod ifNotNil: [^ self selectedNode: (selectedCategory ifNil: [selectedClass])].
	allCategories := false.
	self selectedNode: (selectedCategory
		ifNotNil: [selectedClass]
		ifNil: [selectedClass ifNotNil: [selectedPackage]]).
]
