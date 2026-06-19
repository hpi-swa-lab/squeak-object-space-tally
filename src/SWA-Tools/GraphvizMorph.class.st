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
		'engine'
	],
	#category : #'SWA-Tools',
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
	#'squeak_changestamp' : 'MCPServer 6/17/2026 15:28'
}
GraphvizMorph >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:22'
}
GraphvizMorph >> mouseDown: evt [
	"Hit-test the click against node rectangles; if a node is hit, fire the
	node action. Otherwise, if a panHandler is set, let it pan; else fall
	back to default behavior (e.g. dragging via halo)."
	| node |

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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:21'
}
GraphvizMorph >> render [
	"Run the external layout command (self engine, e.g. 'dot' or 'neato') to produce a PNG
	and a -Tplain layout. Load the PNG as our image and parse the plain output into node
	rectangles. The .dot file is written with LF line endings since the engine rejects bare CRs."
	| dir dotFile pngFile plainFile form plainText eng |
	eng := self engine.
	dir := FileDirectory default fullNameFor: 'graphvizmorph'.
	dotFile := dir, '.dot'.
	pngFile := dir, '.png'.
	plainFile := dir, '.plain'.
	(FileStream forceNewFileNamed: dotFile) nextPutAll: dotSource withUnixLineEndings; close.
	(OSProcess waitForCommand: eng, ' -Tpng ', dotFile, ' -o ', pngFile) exitStatus = 0
		ifFalse: [^ self error: eng, ' -Tpng failed'].
	(OSProcess waitForCommand: eng, ' -Tplain ', dotFile, ' -o ', plainFile) exitStatus = 0
		ifFalse: [^ self error: eng, ' -Tplain failed'].
	form := PNGReadWriter formFromFileNamed: pngFile.
	self image: form.
	plainText := (FileStream fileNamed: plainFile) contentsOfEntireFile.
	self parsePlain: plainText withForm: form
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
