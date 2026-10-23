"
The zoomed part of the code tree as one scrolling document: a row per package, class and category, and the source of every method at depth S. Expansion is remembered by path, so it survives the switch between the live tree and the one built from git.
"
Class {
	#name : #SWACodeLinearView,
	#superclass : #SWAView,
	#instVars : [
		'scrollPane',
		'content',
		'rows',
		'currentNode',
		'leafKind',
		'expansion',
		'selectedRow',
		'refreshPending',
		'revealing'
	],
	#category : #'SWA-CodeBrowser',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:43'
}
SWACodeLinearView >> addCodeRowFor: aNode depth: anInteger [
	| row code shown |
	row := self newRowIndented: anInteger.
	shown := self currentTextFor: aNode.
	code := SWALinearCodeMorph new.
	code
		view: self node: aNode shown: shown;
		contentsWrapped: ((self gitDiffFor: aNode) ifNil: [self styled: shown for: aNode]);
		margins: 4;
		backgroundColor: (Color gray: 0.95);
		hResizing: #spaceFill;
		vResizing: #shrinkWrap.
	(self showsGitRange and: [(self gitKindOf: aNode) notNil]) ifTrue: [
		code
			borderWidth: 2;
			borderColor: (self colorForChange: (self gitKindOf: aNode) reviewed: (self isReviewedChange: aNode))].
	row addMorphBack: code.
	(aNode isKindOf: SWACodeClassNode)
		ifFalse: [rows at: aNode ifAbsentPut: [row]].
	content addMorphBack: row.
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> addHeaderFor: aNode depth: anInteger [
	| row toggle label |
	row := self newRowIndented: anInteger.
	toggle := StringMorph contents: ((self canExpand: aNode)
		ifTrue: [(self isExpanded: aNode) ifTrue: ['-'] ifFalse: ['+']]
		ifFalse: [' ']).
	toggle on: #mouseDown send: #toggle:event:from: to: self withValue: aNode.
	label := StringMorph contents: (self labelFor: aNode).
	(self emphasisFor: aNode) ifNotNil: [:code | label emphasis: code].
	label color: (self labelColorFor: aNode).
	label on: #mouseDown send: #header:event:from: to: self withValue: aNode.
	row addMorphBack: toggle; addMorphBack: label.
	rows at: aNode ifAbsentPut: [row].
	content addMorphBack: row.
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 18:08'
}
SWACodeLinearView >> addRowsFor: aNode depth: anInteger [
	(self showsAsCode: aNode) ifTrue: [^ self addCodeRowFor: aNode depth: anInteger].
	self addHeaderFor: aNode depth: anInteger.
	(self isExpanded: aNode) ifFalse: [^ self].
	(self showsDefinitionOf: aNode) ifTrue: [self addCodeRowFor: aNode depth: anInteger + 1].
	(self visibleChildrenOf: aNode) do: [:each | self addRowsFor: each depth: anInteger + 1].
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> breadcrumbString [
	^ currentNode ifNil: [''] ifNotNil: [:node | node pathString, '  (linear)']
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> browseSelected [
	selectedNode
		ifNil: [Beeper beep]
		ifNotNil: [:node | node browse]
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> canExpand: aNode [
	^ (aNode isKindOf: SWACodeMethodNode) not and: [(self visibleChildrenOf: aNode) notEmpty]
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> canZoomOut [
	^ currentNode notNil and: [currentNode ~~ rootNode]
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> codeChanged [
	super codeChanged.
	self rebuild.
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> codeViewKey [
	^ #linear
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> currentFocus [
	^ (currentNode isNil or: [currentNode == rootNode]) ifTrue: [nil] ifFalse: [self focusForNode: currentNode]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> dataPanelExtrasFor: aPane [
	^ self rangeViewButtonsFor: aPane
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> depthIndexOf: aNodeOrKind [
	| kind |
	kind := aNodeOrKind isSymbol ifTrue: [aNodeOrKind] ifFalse: [aNodeOrKind kind].
	kind == #comment ifTrue: [kind := #method].
	^ #(#root #package #class #category #method #source) indexOf: kind ifAbsent: [0]
]

{
	#category : #labels,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> emphasisFor: aNode [
	| code |
	code := ((aNode isKindOf: SWACodeClassNode) or: [self isPackageNode: aNode])
		ifTrue: [TextEmphasis bold emphasisCode]
		ifFalse: [0].
	(aNode isKindOf: SWACodeCategoryNode) ifTrue: [code := code bitOr: TextEmphasis italic emphasisCode].
	self showsGitRange ifTrue: [
		(self gitKindOf: aNode) == #removed ifTrue: [code := code bitOr: TextEmphasis struckOut emphasisCode].
		((self gitStatusOf: aNode) notNil and: [self isReviewedChange: aNode])
			ifTrue: [code := code bitOr: TextEmphasis italic emphasisCode]].
	^ code
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> expandTo: aNode [
	| node |
	node := aNode parent.
	[node notNil and: [node ~~ currentNode]] whileTrue: [
		expansion at: node pathString put: true.
		node := node parent].
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> fitContent [
	content width: (scrollPane scroller width max: 100).
	content fullBounds.
	scrollPane setScrollDeltas.
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> focusOn: aFocus [
	| node |
	node := (aFocus ifNotNil: [self nodeForFocus: aFocus]) ifNil: [rootNode].
	node == currentNode ifTrue: [^ self].
	currentNode := node.
	self rebuild.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> hasRangeViews [
	^ true
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> header: aNode event: anEvent from: aMorph [
	anEvent yellowButtonPressed ifTrue: [^ self headerMenuFor: aNode].
	anEvent hand newKeyboardFocus: self.
	aNode == selectedNode
		ifTrue: [self toggle: aNode event: anEvent from: aMorph]
		ifFalse: [self selectFromLinear: aNode].
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> headerMenuFor: aNode [
	| menu |
	menu := MenuMorph new defaultTarget: self.
	menu add: 'zoom into' target: self selector: #zoomInto: argument: aNode.
	menu add: 'browse' target: aNode selector: #browse.
	self showsGitRange ifTrue: [
		menu
			add: 'sign off / take back (r)' target: self selector: #toggleReviewedUnder: argument: aNode;
			add: 'sign off everything under it' target: self selector: #toggleReviewedAllUnder: argument: aNode].
	menu popUpInWorld.
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:45'
}
SWACodeLinearView >> initialize [
	super initialize.
	leafKind := #source.
	expansion := Dictionary new.
	rows := IdentityDictionary new.
	self
		color: Color white;
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		hResizing: #spaceFill;
		vResizing: #spaceFill.
	content := self newContent.
	scrollPane := ScrollPane new
		color: Color white;
		hResizing: #spaceFill;
		vResizing: #spaceFill;
		yourself.
	scrollPane scroller addMorph: content.
	self addMorphBack: scrollPane.
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> isExpanded: aNode [
	aNode == currentNode ifTrue: [^ true].
	^ expansion at: aNode pathString ifAbsent: [
		(self depthIndexOf: aNode) < (self depthIndexOf: leafKind)]
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:30'
}
SWACodeLinearView >> isReachable: aNode [
	"Whether aNode can get a row: it hangs below the zoom through children that are shown."
	| node |
	node := aNode.
	[node == currentNode] whileFalse: [
		(node isNil or: [node parent isNil]) ifTrue: [^ false].
		((self visibleChildrenOf: node parent) includes: node) ifFalse: [^ false].
		node := node parent].
	^ true
]

{
	#category : #labels,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> labelColorFor: aNode [
	(self showsGitRange and: [(self gitStatusOf: aNode) notNil]) ifTrue: [
		^ self colorForChange: (self gitStatusOf: aNode) reviewed: (self isReviewedChange: aNode)].
	(aNode isKindOf: SWACodeCategoryNode) ifTrue: [^ Color gray: 0.45].
	^ Color black
]

{
	#category : #labels,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> labelFor: aNode [
	(aNode isKindOf: SWACodeSubpackageNode) ifTrue: [^ aNode fullCategory].
	(aNode isKindOf: SWACodeCategoryNode) ifTrue: [
		^ aNode isStatic ifTrue: ['class side: ', aNode subject asString] ifFalse: [aNode subject asString]].
	^ aNode name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> leafKind [
	^ leafKind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> leafKind: aKind [
	leafKind := aKind.
	expansion removeAll.
	self rebuild.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> leafKindOrder [
	^ #(#package #class #category #method #source)
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:45'
}
SWACodeLinearView >> newContent [
	^ Morph new
		color: Color white;
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #rigid;
		vResizing: #shrinkWrap;
		yourself
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> newRowIndented: anInteger [
	| row |
	row := Morph new
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #topLeft;
		cellInset: 4;
		layoutInset: 2;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	row addMorphBack: (Morph new
		color: Color transparent;
		extent: (anInteger * 16) @ 1;
		yourself).
	^ row
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 18:05'
}
SWACodeLinearView >> rangeViewChanged [
	super rangeViewChanged.
	self rebuild.
	self refreshChrome.
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:45'
}
SWACodeLinearView >> rebuild [
	"Rows go into a detached morph: added one by one to the scroller, each would lay out
	everything before it again."
	| offset |
	offset := scrollPane scroller offset.
	content := self newContent.
	rows := IdentityDictionary new.
	selectedRow := nil.
	currentNode ifNotNil: [self addRowsFor: currentNode depth: 0].
	scrollPane scroller removeAllMorphs; addMorph: content.
	self fitContent.
	scrollPane scroller offset: offset.
	self showSelectionRow.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> refreshChrome [
	navPanel ifNotNil: [:panel | panel refresh]
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> runInfoString [
	^ self codeRunInfoString
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:43'
}
SWACodeLinearView >> scrollToShow: aRow [
	scrollPane scrollToShow: (aRow bounds translateBy: content topLeft negated).
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> searchFor: aStringOrNil [
	super searchFor: aStringOrNil.
	self rebuild.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectFromLinear: aNode [
	aNode == selectedNode ifFalse: [self selectedNode: aNode].
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectTileNode: aNodeOrNil [
	self selectedNode: aNodeOrNil.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectedNode: aNodeOrNil [
	super selectedNode: aNodeOrNil.
	self showSelectionRow.
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectedSourceString [
	selectedNode ifNil: [^ ''].
	^ self gitDiffForSelection ifNil: [self currentTextFor: selectedNode]
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectionInfoString [
	^ self codeSelectionInfoString
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> selectionPathString [
	^ selectedNode ifNil: [''] ifNotNil: [:node | node pathString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> setRoot: aNode [
	"A new tree, e.g. the range's after the live one: keep the zoom and the selection."
	| focus previous |
	focus := self currentFocus.
	previous := selectedNode.
	rootNode := aNode.
	selectedNode := nil.
	self flushMarksCache.
	self rebuildKeyIndex.
	searchQuery ifNotNil: [self rebuildSearchMatches].
	currentNode := (focus ifNotNil: [self nodeForFocus: focus]) ifNil: [rootNode].
	selectedNode := previous ifNotNil: [:node | self equivalentOf: node].
	self rebuild.
	^ self
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> showGitChanges: aDictionary [
	self showRangeTree: aDictionary.
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 17:30'
}
SWACodeLinearView >> showSelectionRow [
	"Mark the selection's row. A selection inside a collapsed node is expanded to, with
	one rebuild; a node the tree no longer holds, e.g. the one just saved over, gets none."
	| row |
	selectedRow ifNotNil: [selectedRow color: Color transparent].
	selectedRow := nil.
	selectedNode ifNil: [^ self].
	row := rows at: selectedNode ifAbsent: [nil].
	row ifNil: [
		(revealing ~~ true and: [self isReachable: selectedNode]) ifFalse: [^ self].
		self expandTo: selectedNode.
		revealing := true.
		^ [self rebuild] ensure: [revealing := false]].
	selectedRow := row.
	row color: (Color h: 210 s: 0.2 v: 1.0).
	self scrollToShow: row.
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> showsAsCode: aNode [
	^ leafKind == #source and: [aNode isKindOf: SWACodeMethodNode]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 18:08'
}
SWACodeLinearView >> showsDefinitionOf: aNode [
	"Changes only leaves out a definition the range did not touch."
	(aNode isKindOf: SWACodeClassNode) ifFalse: [^ false].
	leafKind == #source ifFalse: [^ false].
	^ self showsChangesOnly not or: [(self gitKindOf: aNode) notNil]
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:43'
}
SWACodeLinearView >> step [
	"The scroll pane gives no notice when it is resized."
	content width = scrollPane scroller width ifTrue: [^ self].
	self fitContent.
	selectedRow ifNotNil: [:row | self scrollToShow: row].
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> stepTime [
	^ 250
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> styled: aString for: aNode [
	"Shout, without a running styler: a method in its class, a definition as a doit, a
	comment as prose."
	| class |
	(aNode isKindOf: SWACodeCommentNode) ifTrue: [^ aString asText].
	class := self styleClassForDiffOf: aNode.
	^ [SHTextStylerST80 new
		classOrMetaClass: ((aNode isKindOf: SWACodeClassNode) ifFalse: [class]);
		parseAMethod: (aNode isKindOf: SWACodeClassNode) not;
		styledTextFor: aString asText]
			on: Error do: [:e | aString asText]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> supportsGitRange [
	^ true
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> takeOverRootFrom: aView [
	self takeOverRangeRootsFrom: aView.
]

{
	#category : #expanding,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> toggle: aNode event: anEvent from: aMorph [
	(self canExpand: aNode) ifFalse: [^ self].
	expansion at: aNode pathString put: (self isExpanded: aNode) not.
	self rebuild.
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> toggleReviewedUnder: aNode [
	self toggleReviewedShownUnder: aNode.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> updateReviewMarkers [
	"Signing off a whole package arrives here once per member."
	super updateReviewMarkers.
	refreshPending == true ifTrue: [^ self].
	refreshPending := true.
	Project current addDeferredUIMessage: [
		refreshPending := false.
		self rebuild.
		self refreshChrome].
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> updateWindowLabel [
	navPanel ifNotNil: [:panel | panel view == self ifTrue: [panel updateCodeViewWindowLabel]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> viewKind [
	^ #codeLinear
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> wantsSteps [
	^ true
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> zoomInto: aNode [
	"Zoom positions are packages and classes, the ones every code view understands."
	| node |
	node := aNode.
	[node notNil and: [(self isPackageNode: node) not and: [(node isKindOf: SWACodeClassNode) not]]]
		whileTrue: [node := node parent].
	node ifNil: [^ self].
	currentNode := node.
	self rebuild.
	self refreshChrome.
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWACodeLinearView >> zoomOut [
	| node |
	node := currentNode parent.
	[node notNil and: [node ~~ rootNode and: [(self isPackageNode: node) not]]]
		whileTrue: [node := node parent].
	currentNode := node ifNil: [rootNode].
	self rebuild.
]
