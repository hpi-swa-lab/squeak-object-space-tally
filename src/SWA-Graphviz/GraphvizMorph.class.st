"
A Morph that renders a Graphviz DOT graph to a PNG (via the external 'dot' command) and displays it as an image. It also parses Graphviz '-Tplain' output to recover node bounding boxes, so mouse clicks can be hit-tested against individual nodes.

Usage:
    (GraphvizMorph fromDot: 'digraph G { A -> B; B -> C; }') openInWorld

Set a per-node click handler:
    morph onNodeClick: [:nodeName | Transcript showln: 'clicked ', nodeName].

Instance variables:
    dotSource  - the DOT graph string
    nodeRects  - Dictionary mapping node name (String) -> Rectangle (in morph-local pixels)
    graphScale - scale factor reported by 'dot -Tplain'
    graphSize  - graph size in inches (Point) from 'dot -Tplain'
    nodeAction - a one-arg block evaluated with the clicked node name
"
Class {
	#name : #GraphvizMorph,
	#superclass : #ImageMorph,
	#instVars : [
		'dotSource',
		'nodeRects',
		'graphScale',
		'graphSize',
		'nodeAction',
		'panHandler',
		'engine',
		'fieldRects',
		'fieldAction',
		'selectionRect',
		'selectionColor',
		'menuAction'
	],
	#category : #'SWA-Graphviz',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph class >> fromDot: aDotString [
	"Create a GraphvizMorph rendering the given DOT source string."
	^ self new setDot: aDotString
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> addCustomMenuItems: aCustomMenu hand: aHandMorph [
	"Add Graphviz-specific items to the halo / control menu."
	super addCustomMenuItems: aCustomMenu hand: aHandMorph.
	aCustomMenu addLine.
	aCustomMenu add: 'choose engine... (' , self engine , ')'
		target: self selector: #chooseEngine.
	aCustomMenu add: 'show DOT source' target: self selector: #showDotSource.
	aCustomMenu add: 'edit DOT source...' target: self selector: #editDotSource.
	aCustomMenu add: 'rerender' target: self selector: #render
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> availableEngines [
	"The Graphviz layout engines offered in the halo menu."
	^ #('dot' 'neato' 'fdp' 'sfdp' 'circo' 'twopi' 'osage' 'patchwork')
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> chooseEngine [
	"Let the user pick a layout engine, then re-render."
	| choice |
	choice := UIManager default
		chooseFrom: self availableEngines
		values: self availableEngines
		title: 'Layout engine (current: ' , self engine , ')'.
	choice ifNil: [^ self].
	self engine: choice.
	self render
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> dotSource [
	"The current DOT source string."
	^ dotSource
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
GraphvizMorph >> drawOn: aCanvas [
	"Draw the layout image (super), then, if an element is selected, frame it with a
	blue selection border via the shared SWASelectionPainter (same feedback the
	treemap uses). The enclosing scroll/zoom pane transforms this canvas, so the
	frame tracks the graph as it pans and zooms."
	super drawOn: aCanvas.
	selectionRect ifNotNil: [:r |
		SWASelectionPainter
			selectionFrameOn: aCanvas
			rect: (r translateBy: self bounds origin)
			color: self selectionColor]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> editDotSource [
	"Open an editor on the DOT source; accepting (cmd-s) re-renders the graph."
	UIManager default
		edit: (self dotSource ifNil: [''])
		label: 'Edit DOT source - accept (cmd-s) to rerender'
		accept: [:newText | self setDot: newText asString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:21'
}
GraphvizMorph >> engine [
	"The Graphviz layout engine to use (e.g. 'dot', 'neato', 'fdp', 'sfdp', 'circo', 'twopi'). Defaults to 'dot'."
	^ engine ifNil: [engine := 'dot']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:21'
}
GraphvizMorph >> engine: aString [
	"Set the Graphviz layout engine (e.g. 'dot', 'neato', 'fdp', 'sfdp', 'circo', 'twopi')."
	engine := aString
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
GraphvizMorph >> fieldAt: aWorldPoint [
	"Answer the record sub-field hit by aWorldPoint as an Association
	nodeName -> fieldIndex (0-based, top-to-bottom), or nil. fieldRects are in
	morph-local pixel coordinates, so subtract our origin. Fields are contiguous
	within a node, so first containment wins."
	| local |
	fieldRects isNil ifTrue: [^ nil].
	local := aWorldPoint - self bounds origin.
	fieldRects do: [:assoc |
		((assoc value second) containsPoint: local)
			ifTrue: [^ assoc key -> (assoc value first)]].
	^ nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:42'
}
GraphvizMorph >> mouseDown: evt [
	"Right-click (yellow button) with a menuAction set -> fire the context menu.
	Otherwise hit-test the click: if a fieldAction is set and the click lands in a
	record sub-field, fire it with nodeName -> fieldIndex; else if a node is hit and
	a nodeAction is set, fire that with the node name; else pan (if a panHandler is
	set) or fall back to default behavior (e.g. dragging via halo)."
	| field node |
	(evt yellowButtonPressed and: [menuAction notNil])
		ifTrue: [^ menuAction value: evt].
	fieldAction ifNotNil: [
		field := self fieldAt: evt cursorPoint.
		field ifNotNil: [^ fieldAction value: field]].
	node := self nodeAt: evt cursorPoint.
	(node notNil and: [nodeAction notNil])
		ifTrue: [^ nodeAction value: node].
	panHandler ifNotNil: [^ panHandler panBackgroundDown: evt from: self].
	super mouseDown: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizMorph >> mouseMove: evt [
	"Forward drags to the panHandler (for background panning)."
	panHandler ifNotNil: [^ panHandler panBackgroundMove: evt from: self].
	super mouseMove: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizMorph >> mouseUp: evt [
	"Forward drag end to the panHandler (for background panning)."
	panHandler ifNotNil: [^ panHandler panBackgroundUp: evt from: self].
	super mouseUp: evt
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph >> nodeAt: aWorldPoint [
	"Answer the name of the node whose rectangle contains aWorldPoint, or nil.
	nodeRects are in morph-local pixel coordinates, so subtract our origin."
	| local |
	nodeRects isNil ifTrue: [^ nil].
	local := aWorldPoint - self bounds origin.
	nodeRects keysAndValuesDo: [:name :rect |
		(rect containsPoint: local) ifTrue: [^ name]].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizMorph >> nodeRectsAvailable [
	"Answer whether node rectangles have been parsed (a graph is loaded)."
	^ nodeRects notNil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
GraphvizMorph >> onFieldClick: aBlock [
	"Set a one-argument block evaluated with the clicked record sub-field as an
	Association nodeName -> fieldIndex (0-based). Takes precedence over the plain
	node action when the click lands inside a record field."
	fieldAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:42'
}
GraphvizMorph >> onMenuRequest: aBlock [
	"Set a one-argument block evaluated with the triggering event when the user
	right-clicks (yellow button) the graph background, so an owner can pop up a
	context menu."
	menuAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'SqueakXR 6/18/2026 10:54'
}
GraphvizMorph >> onNodeClick: aBlock [
	"Set a one-argument block to be evaluated with the clicked node's name (a String)."
	nodeAction := aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:22'
}
GraphvizMorph >> panHandler: anObject [
	"Optional object notified of background (non-node) mouse drags so an
	enclosing pane can implement panning. It must understand
	#panBackgroundDown:from:, #panBackgroundMove:from:, #panBackgroundUp:from:.
	When nil, background clicks fall back to default Morph behavior."
	panHandler := anObject
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:38'
}
GraphvizMorph >> parsePlain: plainText withForm: form [
	"Delegate to GraphvizPlainParser to turn 'dot -Tplain' output into node
	rectangles in pixel coordinates matching the rendered form."
	| parser |
	parser := GraphvizPlainParser parse: plainText pixelExtent: form extent.
	graphScale := parser scale.
	graphSize := parser graphSize.
	nodeRects := parser nodeRects
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> rectForNode: aDotId [
	"The whole-node pixel rectangle for the node with the given dot id, or nil."
	nodeRects ifNil: [^ nil].
	^ nodeRects at: aDotId ifAbsent: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> rectForNode: aDotId field: aFieldIndex [
	"The pixel rectangle of record sub-field aFieldIndex (0-based) of the node with
	the given dot id, or nil if there is no such field."
	fieldRects ifNil: [^ nil].
	fieldRects do: [:assoc |
		(assoc key = aDotId and: [assoc value first = aFieldIndex])
			ifTrue: [^ assoc value second]].
	^ nil
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:42'
}
GraphvizMorph >> render [
	"Run the external layout engine (self engine, e.g. 'dot') to produce a PNG plus
	a -Tjson layout. Load the PNG as our image and parse the JSON into node
	rectangles AND per-field (record compartment) rectangles via GraphvizJsonParser.
	JSON is used instead of -Tplain: it is properly structured (no whitespace-token
	fragility) and carries record sub-field geometry, enabling sub-node clicks.
	The .dot file is written with LF line endings since the engine rejects bare CRs."
	| dir dotFile pngFile jsonFile form jsonText eng parser |
	eng := self engine.
	dir := FileDirectory default fullNameFor: 'graphvizmorph'.
	dotFile := dir, '.dot'.
	pngFile := dir, '.png'.
	jsonFile := dir, '.json'.
	(FileStream forceNewFileNamed: dotFile) nextPutAll: dotSource withUnixLineEndings; close.
	(OSProcess waitForCommand: eng, ' -Tpng ', dotFile, ' -o ', pngFile) exitStatus = 0
		ifFalse: [^ self error: eng, ' -Tpng failed'].
	(OSProcess waitForCommand: eng, ' -Tjson ', dotFile, ' -o ', jsonFile) exitStatus = 0
		ifFalse: [^ self error: eng, ' -Tjson failed'].
	form := PNGReadWriter formFromFileNamed: pngFile.
	self image: form.
	jsonText := (FileStream fileNamed: jsonFile) contentsOfEntireFile.
	parser := GraphvizJsonParser parse: jsonText pixelExtent: form extent.
	graphScale := parser scale.
	graphSize := parser graphSize.
	nodeRects := parser nodeRects.
	fieldRects := parser fieldRects
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionColor [
	^ selectionColor ifNil: [Color blue]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionColor: aColor [
	"The color of the selection frame (default blue)."
	selectionColor := aColor.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:58'
}
GraphvizMorph >> selectionRect: aRectangleOrNil [
	"Set the morph-local pixel rectangle to frame as the persistent selection
	(or nil to clear), and redraw. Coordinates are in the same local pixel space
	as nodeRects / fieldRects."
	selectionRect = aRectangleOrNil ifTrue: [^ self].
	selectionRect := aRectangleOrNil.
	self changed
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 10:50'
}
GraphvizMorph >> setDot: aDotString [
	"Set the DOT source and (re)render the graph."
	dotSource := aDotString.
	self render.
	^ self
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:36'
}
GraphvizMorph >> showDotSource [
	"Open a read-only-ish editor window displaying the current DOT source."
	UIManager default
		edit: (self dotSource ifNil: [''])
		label: 'DOT source (', self engine, ')'
]
