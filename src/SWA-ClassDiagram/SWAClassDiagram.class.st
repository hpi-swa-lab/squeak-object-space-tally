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
		'syncedMarkSet'
	],
	#category : #'SWA-ClassDiagram',
	#'squeak_changestamp' : '<historical>'
}

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
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:45'
}
SWAClassDiagram >> ivarFilterForBuild [
	"The ivar-filter block to install on class nodes for the current granularity, or nil to
	show all instance variables. For #selected, only ivars whose crossRefKey
	('Class>>#ivar') is in the mark set are shown. Uses the synced mark set if any, else the
	global singleton."
	| ms |
	leafKind = #selected ifFalse: [^ nil].
	ms := syncedMarkSet ifNil: [SWAMarkSet default].
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
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:45'
}
SWAClassDiagram >> methodFilterForBuild [
	"The method-filter block to install on class nodes for the current granularity, or nil
	to show all methods. For #selected, only methods whose crossRefKey ('Class>>sel') is in
	the mark set are shown. Uses the synced mark set if any, else the global singleton."
	| ms |
	leafKind = #selected ifFalse: [^ nil].
	ms := syncedMarkSet ifNil: [SWAMarkSet default].
	^ [:methodNode | ms includes: methodNode crossRefKey]
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:45'
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
	tuple := rootNode classDiagramGraphColorMode: self colorMode showState: showState showMethods: showMethods.
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
	self updateSelectionHighlight.
	self refreshChrome
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:32'
}
SWAClassDiagram >> selectedSourceString [
	"Source text for the Show pane: the selected node's source, or empty."
	(selectedNode notNil and: [selectedNode respondsTo: #sourceString])
		ifTrue: [^ selectedNode sourceString].
	^ ''
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
