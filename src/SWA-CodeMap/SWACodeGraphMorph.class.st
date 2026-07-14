"
A SWAView that renders a SWACodeNode subtree as a Graphviz diagram (UML class diagram or containment tree) instead of a treemap/flamegraph, so it plugs into a SWANavPanel with the shared Back/Browse/Show/Deselect chrome, selection-path line, and source pane.

Clicking a graph node selects the matching SWACodeNode: the panel's breadcrumb, selection-path, and Show source pane update, and Browse opens it. Use #mode: to switch between #classDiagram (record boxes + inheritance) and #containment (package->class->category->method tree).

Open with: SWACodeGraphMorph openOnPackageNamed: 'SWAGame'
"
Class {
	#name : #SWACodeGraphMorph,
	#superclass : #SWAView,
	#instVars : [
		'graphMorph',
		'graphPane',
		'mode',
		'nodesByDotId',
		'fieldNodesByDotId',
		'rectKeyByNode',
		'colorMode',
		'leafKind'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph class >> on: aCodeNode mode: aSymbol [
	"A graph view of aCodeNode's subtree in the given mode (#classDiagram / #containment)."
	^ self new
		mode: aSymbol;
		rootNode: aCodeNode;
		yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:34'
}
SWACodeGraphMorph class >> openContainmentOnPackageNamed: aPackageGlob [
	"Open a containment tree (package -> class -> category -> method) of the matching
	packages in a SWANavPanel.

	SWACodeGraphMorph openContainmentOnPackageNamed: 'SWAGame'"
	| root |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		addPackages: aPackageGlob;
		yourself.
	^ self
		openOn: root
		mode: #containment
		label: 'Containment: ', aPackageGlob
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph class >> openOn: aCodeNode mode: aSymbol label: aLabel [
	"Wrap a graph view of aCodeNode in a SWANavPanel window (shared chrome:
	Back/Browse/Show/Deselect + breadcrumb + selection path + source pane)."
	| view panel window bounds |
	view := self on: aCodeNode mode: aSymbol.
	panel := SWANavPanel on: view.
	window := panel openInWindow.
	window setLabel: aLabel.
	bounds := SWANavPanel defaultWindowBounds intersect: (0 @ 0 corner: Display extent).
	window bounds: bounds.
	panel enforceMinimumWindowWidth.
	^ window
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:33'
}
SWACodeGraphMorph class >> openOnPackageNamed: aPackageGlob [
	"Open a UML class diagram of the matching packages in a SWANavPanel.

	SWACodeGraphMorph openOnPackageNamed: 'SWAGame'"
	| root |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		addPackages: aPackageGlob;
		yourself.
	^ self
		openOn: root
		mode: #classDiagram
		label: 'Class Diagram: ', aPackageGlob
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> breadcrumbString [
	"Top breadcrumb line: the graph's root plus current mode."
	| kind |
	rootNode ifNil: [^ ''].
	kind := mode = #containment ifTrue: ['containment'] ifFalse: ['class diagram'].
	^ rootNode name, '  (', kind, ')'
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> browseSelected [
	"Browse button: open a browser on the selected node."
	selectedNode
		ifNil: [Beeper beep]
		ifNotNil: [:n | n browse]
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:39'
}
SWACodeGraphMorph >> colorMode [
	"Active fill mode: #kind (pastel per node kind, the default) or #loc
	(green->yellow->red heat by method LOC)."
	^ colorMode ifNil: [#kind]
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:56'
}
SWACodeGraphMorph >> colorMode: aSymbol [
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
SWACodeGraphMorph >> colorModeOptions [
	"{ symbol. label } pairs for the shared Color menu/button. The graph recolors by
	re-rendering with per-row fill from the chosen mode."
	^ {
		{ #kind. 'Flat (by kind)' }.
		{ #loc. 'LOC heat (green->red)' } }
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:25'
}
SWACodeGraphMorph >> depthLabelString [
	"Friendly Depth-button text for this view's three granularities."
	^ 'Depth: ', (leafKind caseOf: {
		[#class]  -> ['Classes'].
		[#state]  -> ['+State'].
		[#method] -> ['+Methods'] }
		otherwise: ['Classes'])
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> deselect [
	"Clear the current selection."
	self selectedNode: nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:44'
}
SWACodeGraphMorph >> graphFieldClicked: anAssoc [
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:42'
}
SWACodeGraphMorph >> graphMenuRequest: evt [
	"Right-click on the graph: pop up a context menu with the shared Color submenu
	(same #colorMenuMorph the header Color button uses)."
	| menu colorMenu |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (mode = #containment ifTrue: ['Containment'] ifFalse: ['Class Diagram']).
	colorMenu := self colorMenuMorph.
	colorMenu ifNotNil: [menu add: 'Color' subMenu: colorMenu].
	menu popUpEvent: evt in: self world
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWACodeGraphMorph >> graphNodeClicked: aDotId [
	"A node in the embedded graph was clicked: select the matching SWACodeNode."
	self selectedNode: (nodesByDotId at: aDotId ifAbsent: [nil])
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:29'
}
SWACodeGraphMorph >> initialize [
	super initialize.
	mode := #classDiagram.
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:15'
}
SWACodeGraphMorph >> leafKind [
	"The render granularity: #class (boxes show name + state only) or #method (full
	boxes including one row per method). Drives the shared nav-panel Depth button."
	^ leafKind
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:23'
}
SWACodeGraphMorph >> leafKind: aSymbol [
	"Set the render granularity and rebuild. Three depths are meaningful for a UML
	class diagram: #class (name box only), #state (name + instance variables), and
	#method (name + state + methods). Anything else (the treemap's #package/#category)
	is normalized to the nearest of the three, so the shared Depth button never lands
	the graph on an unsupported depth. Rebuilds resetting the view, since the box
	layout changes."
	| normalized |
	normalized := (aSymbol = #class or: [aSymbol = #package])
		ifTrue: [#class]
		ifFalse: [(aSymbol = #state or: [aSymbol = #category])
			ifTrue: [#state]
			ifFalse: [#method]].
	leafKind = normalized ifTrue: [^ self].
	leafKind := normalized.
	rootNode ifNotNil: [self rebuildGraph]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:23'
}
SWACodeGraphMorph >> leafKindOrder [
	"The granularities the Depth button cycles through for THIS view (as opposed to
	the treemap's package->class->category->method). A class diagram has three
	meaningful depths: classes only, classes + state, and classes + state + methods."
	^ { #class. #state. #method }
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWACodeGraphMorph >> mode [
	"#classDiagram (UML record boxes + inheritance) or #containment
	(package -> class -> category -> method tree)."
	^ mode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWACodeGraphMorph >> mode: aSymbol [
	"Switch between #classDiagram and #containment, then rebuild if a root is set."
	mode := aSymbol.
	rootNode ifNotNil: [self rebuildGraph]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:39'
}
SWACodeGraphMorph >> overlayMorph [
	"The graph view draws its own selection frame and hosts its own menus (there is
	no separate transparent overlay morph as on the treemap), so it acts as its own
	overlay for the nav-panel chrome. Answering self lets the shared Color button
	light up and route #popUpColorMenu / #colorModeOptions here, without duplicating
	the button wiring."
	^ self
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:56'
}
SWACodeGraphMorph >> rebuildGraph [
	"Rebuild resetting the view to top-left/100% (initial build or a structural
	change such as a mode switch)."
	self rebuildGraphKeepView: false
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:24'
}
SWACodeGraphMorph >> rebuildGraphKeepView: keepView [
	"(Re)generate the DOT for the current mode and hand it to the embedded
	GraphvizMorph. Build nodesByDotId (dot-id -> SWACodeNode) for whole-node clicks;
	for the class diagram, fieldNodesByDotId (dot-id -> field node array) for
	per-row sub-field clicks; and rectKeyByNode (node -> dot-id -> fieldIndexOrNil)
	so a selection can be located as a highlight rectangle. The class diagram honors
	the active #colorMode (#kind / #loc) AND the active #leafKind granularity
	(#class = classes only, #state = classes + state, #method = classes + state +
	methods). Re-seat the morph in the pane, preserving the current zoom + pan when
	keepView is true (e.g. a color-mode recolor, which keeps the same layout) and
	resetting to top-left/100% otherwise."
	| tuple ids showState showMethods |
	rootNode ifNil: [^ self].
	showState := self showsState.
	showMethods := self showsMethods.
	tuple := mode = #containment
		ifTrue: [rootNode containmentGraph]
		ifFalse: [rootNode classDiagramGraphColorMode: self colorMode showState: showState showMethods: showMethods].
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
			class's own whole-box key (ivar rows resolve back to the class, and the
			class should highlight its whole box, not an ivar row)."
			fields doWithIndex: [:fnode :i |
				(i > 1 and: [fnode ~~ node])
					ifTrue: [rectKeyByNode at: fnode put: (dotId -> (i - 1))]]]].
	graphMorph setDot: tuple first.
	graphPane graph: graphMorph keepView: keepView.
	graphPane onNodeClick: [:dotId | self graphNodeClicked: dotId].
	graphPane onFieldClick: [:assoc | self graphFieldClicked: assoc].
	graphPane onMenuRequest: [:evt | self graphMenuRequest: evt].
	self updateSelectionHighlight.
	self refreshChrome
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> refreshChrome [
	"Refresh all chrome labels + source pane via the nav panel, if attached."
	navPanel ifNotNil: [:p | p refresh]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:31'
}
SWACodeGraphMorph >> rootNode: aCodeNode [
	"Set the SWACodeNode subtree to visualize and build the graph."
	rootNode := aCodeNode.
	self rebuildKeyIndex.
	self rebuildGraph
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> selectTileNode: aNodeOrNil [
	"Nav-panel Deselect button hook (parallels the treemap protocol)."
	self selectedNode: aNodeOrNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
SWACodeGraphMorph >> selectedNode: aNodeOrNil [
	"Record the selection, move the blue highlight frame to it, and refresh the
	nav-panel chrome (breadcrumb, selection path, Show source pane)."
	selectedNode := aNodeOrNil.
	self updateSelectionHighlight.
	self refreshChrome
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> selectedSourceString [
	"Source text for the Show pane: the selected node's source, or empty."
	(selectedNode notNil and: [selectedNode respondsTo: #sourceString])
		ifTrue: [^ selectedNode sourceString].
	^ ''
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> selectionInfoString [
	"Second info line: metrics about the current selection."
	selectedNode ifNil: [^ ''].
	^ selectedNode kind asString, ': ', selectedNode name,
		'   ', selectedNode loc printString, ' LOC'
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> selectionPathString [
	"Full path to the selected node, or empty."
	^ selectedNode
		ifNil: ['']
		ifNotNil: [:n | n pathString]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:24'
}
SWACodeGraphMorph >> showsMethods [
	"Whether the current granularity renders method rows inside class boxes."
	^ leafKind = #method
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:24'
}
SWACodeGraphMorph >> showsState [
	"Whether the current granularity renders the state (instance-variable) compartment
	inside class boxes. Off only at the coarsest #class granularity."
	^ leafKind ~= #class
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
SWACodeGraphMorph >> updateSelectionHighlight [
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWACodeGraphMorph >> zoomOut [
	"Back button: no hierarchical zoom in the graph view, so just deselect."
	self deselect
]
