"
A scrollable, zoomable container for a GraphvizMorph.

The inherited ScrollPane already uses a TransformMorph as its 'scroller', which gives me free zoom (via scale) and pan (via offset + scroll bars). I place a GraphvizMorph inside the scroller and let the scroll bars handle panning.

Usage:
    (GraphvizPane fromDot: 'digraph { a -> b }')
        openInWindowLabeled: 'Graph'.

Interaction:
    - Scroll bars and mouse wheel: pan.
    - Ctrl + mouse wheel: zoom in/out around the pointer.
    - Node clicks are forwarded to the wrapped GraphvizMorph's onNodeClick: block.

Instance variables:
    graph - the wrapped GraphvizMorph
    zoom  - current zoom factor (1.0 = 100%)
"
Class {
	#name : #GraphvizPane,
	#superclass : #ScrollPane,
	#instVars : [
		'graph',
		'zoom',
		'panLast',
		'buttons'
	],
	#category : #'SWA-Tools',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #examples,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:24'
}
GraphvizPane class >> example [
	"Open a scrollable, zoomable Graphviz example in a window.
	Use the +/-/= buttons (top-left) to zoom; drag the background to pan;
	the mouse wheel also pans. Node clicks print to the Transcript.

		GraphvizPane example
	"
	| dot pane win |
	dot := 'digraph G {
  rankdir=LR;
  node [shape=box, style="rounded,filled", fillcolor=lightyellow, fontname="Helvetica"];
  Start -> Parse;
  Parse -> Render;
  Render -> Display;
  Display -> Start [label="loop"];
  Parse -> Error [style=dashed, color=red];
  Render -> Cache;
  Cache -> Display;
  Cache -> Parse [label="invalidate", style=dotted];
}'.
	pane := self fromDot: dot.
	pane onNodeClick: [:name | Transcript showln: 'Clicked node: ', name].
	pane extent: 500 @ 360.
	win := pane openInWindowLabeled: 'GraphvizPane  -  +/- zoom, drag bg to pan'.
	"Start zoomed in a little so content overflows and panning is obvious."
	pane zoom: 1.8.
	^ win
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane class >> fromDot: aDotString [
	"Create a scrollable, zoomable pane rendering the given DOT source."
	^ self new graph: (GraphvizMorph fromDot: aDotString)
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane class >> on: aGraphvizMorph [
	"Wrap an existing GraphvizMorph in a scrollable, zoomable pane."
	^ self new graph: aGraphvizMorph
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:17'
}
GraphvizPane >> addZoomButtons [
	"Add small +, -, and reset (=) buttons overlaid in the top-left corner.
	They are submorphs of the pane itself (not the scroller) so they stay
	fixed in place and on top of the scrolled content."
	buttons := OrderedCollection new.
	buttons add: (self makeButton: '+' action: #zoomIn).
	buttons add: (self makeButton: '-' action: #zoomOut).
	buttons add: (self makeButton: '=' action: #resetZoom).
	buttons do: [:b | self addMorphFront: b].
	self positionButtons.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizPane >> buttons [
	"The overlay zoom buttons."
	^ buttons
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizPane >> doLayoutIn: layoutBounds [
	"Keep the overlay buttons pinned to the corner after any layout."
	super doLayoutIn: layoutBounds.
	self positionButtons.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane >> graph [
	"The wrapped GraphvizMorph."
	^ graph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizPane >> graph: aGraphvizMorph [
	"Place the given GraphvizMorph inside the scroller (a TransformMorph)."
	graph ifNotNil: [graph delete].
	graph := aGraphvizMorph.
	graph position: 0 @ 0.
	graph panHandler: self.
	scroller removeAllMorphs.
	scroller addMorph: graph.
	scroller offset: 0 @ 0.
	buttons ifNil: [self addZoomButtons].
	self setScrollDeltas.
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:27'
}
GraphvizPane >> hScrollBarValue: scrollValue [
	"Scroll bar value and scroller offset share local (pre-scale) coordinates."
	scroller hasSubmorphs ifFalse: [^ self].
	scroller offset: (scrollValue max: 0) @ scroller offset y
]

{
	#category : #'geometry ranges',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:28'
}
GraphvizPane >> hUnadjustedScrollRange [
	"Content width in displayed (zoomed) pixels. The scroller's
	localSubmorphBounds are pre-scale, and the scroller offset is applied
	*after* scaling (i.e. in displayed pixels), so the whole scroll system
	works in displayed units once we multiply the content size by zoom."
	scroller hasSubmorphs ifFalse: [^ 0].
	^ (scroller localSubmorphBounds width * zoom) ceiling
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> handlesMouseWheel: evt [
	"Always handle the wheel when zooming; otherwise defer to scrolling."
	(evt controlKeyPressed or: [evt commandKeyPressed]) ifTrue: [^ true].
	^ super handlesMouseWheel: evt
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:34'
}
GraphvizPane >> initialize [
	super initialize.
	zoom := 1.0.
	self color: Color white.
	scroller color: Color transparent.
	"Always show scroll bars. The #whenNeeded policy makes the bars hide/show
	as the offset nears an edge during a drag, which thrashes the layout and
	flickers the viewport. A stable layout keeps panning smooth."
	self
		hScrollBarPolicy: #always;
		vScrollBarPolicy: #always.
	self extent: 600 @ 400.
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizPane >> makeButton: aLabel action: aSelector [
	"Build one small square zoom button."
	| b |
	b := SimpleButtonMorph new.
	b
		label: aLabel font: TextStyle defaultFont;
		target: self;
		actionSelector: aSelector;
		actWhen: #buttonUp;
		color: (Color gray: 0.9);
		borderColor: (Color gray: 0.5);
		borderWidth: 1;
		extent: 22 @ 22.
	^ b
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane >> maxZoom [
	^ 8.0
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane >> minZoom [
	^ 0.1
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> mouseWheel: evt [
	"Ctrl/Cmd + wheel zooms about the pointer; plain wheel scrolls."
	(evt controlKeyPressed or: [evt commandKeyPressed])
		ifTrue: [
			evt isWheelUp ifTrue: [self zoom: zoom * 1.15 at: evt position].
			evt isWheelDown ifTrue: [self zoom: zoom / 1.15 at: evt position].
			^ self].
	super mouseWheel: evt
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> onNodeClick: aBlock [
	"Forward node-click handling to the wrapped GraphvizMorph."
	graph onNodeClick: aBlock
]

{
	#category : #panning,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:33'
}
GraphvizPane >> panBackgroundDown: evt from: aMorph [
	"Begin a background pan-drag. Use the hand's world position: the event's
	own position is in the graph morph's *local* (zoom-scaled) coordinates,
	which would make drags track at the wrong speed when zoomed."
	panLast := evt hand position
]

{
	#category : #panning,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:33'
}
GraphvizPane >> panBackgroundMove: evt from: aMorph [
	"Pan the content as the background is dragged. The hand position is in
	world (displayed) pixels, and the scroller offset is also in displayed
	pixels, so the delta applies 1:1 at every zoom level."
	| here delta |
	panLast ifNil: [^ self].
	here := evt hand position.
	delta := here - panLast.
	panLast := here.
	self scrollBy: delta
]

{
	#category : #panning,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:23'
}
GraphvizPane >> panBackgroundUp: evt from: aMorph [
	"End the background pan-drag."
	panLast := nil
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:18'
}
GraphvizPane >> positionButtons [
	"Stack the zoom buttons vertically just inside the top-left corner."
	| p gap |
	buttons ifNil: [^ self].
	p := self topLeft + (6 @ 6).
	gap := 4.
	buttons do: [:b |
		b position: p.
		p := p + (0 @ (b height + gap))].
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> resetZoom [
	"Reset to 100% and scroll back to the top-left."
	zoom := 1.0.
	scroller scale: 1.0.
	scroller offset: 0 @ 0.
	self setScrollDeltas.
	self changed.
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:27'
}
GraphvizPane >> vScrollBarValue: scrollValue [
	"Scroll bar value and scroller offset share local (pre-scale) coordinates."
	scroller hasSubmorphs ifFalse: [^ self].
	scroller offset: scroller offset x @ (scrollValue max: 0)
]

{
	#category : #'geometry ranges',
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:28'
}
GraphvizPane >> vUnadjustedScrollRange [
	"Content height in displayed (zoomed) pixels. See #hUnadjustedScrollRange."
	scroller hasSubmorphs ifFalse: [^ 0].
	^ (scroller localSubmorphBounds height * zoom) ceiling
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane >> zoom [
	"Current zoom factor (1.0 = 100%)."
	^ zoom
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:10'
}
GraphvizPane >> zoom: aFactor [
	"Set the zoom factor, scaling the content about the view's top-left."
	self zoom: aFactor at: scroller topLeft
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:28'
}
GraphvizPane >> zoom: aFactor at: aGlobalPoint [
	"Set the zoom factor, keeping the content point currently under
	aGlobalPoint (in world coordinates) fixed under that point.
	The scroller maps a pre-scale local point c to the world as
		world = scroller topLeft + (c * scale) - offset
	so to pin c under aGlobalPoint after rescaling:
		offset = scroller topLeft + (c * newScale) - aGlobalPoint."
	| newZoom localPt |
	newZoom := (aFactor min: self maxZoom) max: self minZoom.
	localPt := scroller transformFromWorld globalPointToLocal: aGlobalPoint.
	zoom := newZoom.
	scroller scale: newZoom.
	scroller offset: scroller topLeft + (localPt * newZoom) - aGlobalPoint.
	self setScrollDeltas.
	self changed.
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> zoomIn [
	self zoom: zoom * 1.25
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> zoomOut [
	self zoom: zoom / 1.25
]
