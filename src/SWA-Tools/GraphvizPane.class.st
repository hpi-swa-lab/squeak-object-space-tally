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
	#category : #examples,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 11:32'
}
GraphvizPane class >> exampleMorphTree [
	"Open a GraphvizPane showing the tree of all open morphs (World + 2 levels deep),
	laid out with the 'neato' force-directed engine. Clicking a node opens a halo on the
	corresponding live morph. Node ids are identity hashes; labels stay human-readable.

		GraphvizPane exampleMorphTree
	"
	| ws walk nodeId label gm pane win map |
	ws := WriteStream on: String new.
	map := IdentityDictionary new.
	ws nextPutAll: 'digraph Morphs {'; cr.
	ws nextPutAll: '  overlap=false;'; cr.
	ws nextPutAll: '  splines=true;'; cr.
	ws nextPutAll: '  node [shape=box, style="rounded,filled", fillcolor=lightyellow, fontname="Helvetica", fontsize=10];'; cr.
	nodeId := [:m | 'm', m identityHash printString].
	label := [:m | | s |
		s := m class name.
		(m isKindOf: SystemWindow) ifTrue: [s := s, '\n', ((m label ifNil: ['']) copyReplaceAll: '"' with: '')].
		s].
	walk := nil.
	walk := [:m :depth | | id |
		id := nodeId value: m.
		map at: id asSymbol put: m.
		ws nextPutAll: '  '; nextPutAll: id;
			nextPutAll: ' [label="'; nextPutAll: (label value: m); nextPutAll: '"];'; cr.
		depth < 2 ifTrue: [
			m submorphs do: [:c |
				ws nextPutAll: '  '; nextPutAll: id;
					nextPutAll: ' -> '; nextPutAll: (nodeId value: c); nextPutAll: ';'; cr.
				walk value: c value: depth + 1]]].
	ws nextPutAll: '  World [label="World", fillcolor=lightblue];'; cr.
	map at: #World put: World.
	World submorphs do: [:c |
		ws nextPutAll: '  World -> '; nextPutAll: (nodeId value: c); nextPutAll: ';'; cr.
		walk value: c value: 1].
	ws nextPutAll: '}'; cr.
	gm := GraphvizMorph new.
	gm engine: 'neato'.
	gm setDot: ws contents.
	pane := self new graph: gm.
	pane onNodeClick: [:nm | | morph |
		morph := map at: nm asSymbol ifAbsent: [nil].
		morph
			ifNil: [Transcript showln: 'No morph for: ', nm]
			ifNotNil: [
				Transcript showln: 'Halo on: ', morph class name.
				WorldState addDeferredUIMessage: [morph addHalo]]].
	pane extent: 800 @ 600.
	win := pane openInWindowLabeled: 'Open Morphs Tree (neato)  -  click a node for a halo'.
	win center: World center.
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:55'
}
GraphvizPane >> graph: aGraphvizMorph [
	"Place the given GraphvizMorph inside the scroller, resetting the view to the
	top-left at 100%."
	self graph: aGraphvizMorph keepView: false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:55'
}
GraphvizPane >> graph: aGraphvizMorph keepView: keepView [
	"Place the given GraphvizMorph inside the scroller (a TransformMorph). When
	keepView is true, preserve the current zoom (scroller scale) and pan (scroller
	offset) across the swap -- used when the graph is RE-rendered with the same
	layout (e.g. a color-mode change) so the user stays where they were. When false,
	reset to the top-left at 100%."
	| savedOffset savedScale |
	savedOffset := scroller offset.
	savedScale := scroller scale.
	graph ifNotNil: [graph delete].
	graph := aGraphvizMorph.
	graph position: 0 @ 0.
	graph panHandler: self.
	scroller removeAllMorphs.
	scroller addMorph: graph.
	keepView
		ifTrue: [scroller scale: savedScale. scroller offset: savedOffset]
		ifFalse: [zoom := 1.0. scroller scale: 1.0. scroller offset: 0 @ 0].
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:50'
}
GraphvizPane >> handlesMouseWheel: evt [
	"Always handle the wheel when zooming; otherwise defer to scrolling. The wheel
	EVENT does not carry keyboard modifiers on this platform, so read the live
	Ctrl/Cmd state from the Sensor instead of evt."
	self zoomModifierActiveFor: evt ifTrue: [^ true].
	^ super handlesMouseWheel: evt
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:46'
}
GraphvizPane >> initialize [
	super initialize.
	zoom := 1.0.
	self color: Color white.
	scroller color: Color transparent.
	"Anti-alias the scaled graph bitmap: smoothing 2 = bilinear (2x2 cell)
	sampling via WarpBlt, instead of the default nearest-neighbour (1).
	This softens the blockiness when zoomed in and the aliased edges when
	zoomed out."
	scroller smoothing: 2.
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:50'
}
GraphvizPane >> mouseWheel: evt [
	"Ctrl/Cmd + wheel zooms about the pointer; plain wheel scrolls. The wheel event
	does not carry keyboard modifiers on this platform, so the Ctrl/Cmd state is
	read live from the Sensor (see #zoomModifierActiveFor:ifTrue:)."
	self zoomModifierActiveFor: evt ifTrue: [
		evt isWheelUp ifTrue: [self zoom: zoom * 1.15 at: evt position].
		evt isWheelDown ifTrue: [self zoom: zoom / 1.15 at: evt position].
		^ self].
	super mouseWheel: evt
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
GraphvizPane >> onFieldClick: aBlock [
	"Forward record sub-field click handling to the wrapped GraphvizMorph."
	graph onFieldClick: aBlock
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:42'
}
GraphvizPane >> onMenuRequest: aBlock [
	"Forward right-click context-menu requests to the wrapped GraphvizMorph."
	graph onMenuRequest: aBlock
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
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:50'
}
GraphvizPane >> zoomModifierActiveFor: evt ifTrue: aBlock [
	"Answer (and, when true, run aBlock) whether the zoom modifier (Ctrl or Cmd) is
	held. Prefer the event's own modifier bits, but fall back to the live Sensor
	state because MouseWheelEvents arrive here WITHOUT modifier bits on this
	platform (verified: evt controlKeyPressed is always false under Ctrl+wheel)."
	| active |
	active := evt controlKeyPressed
		or: [evt commandKeyPressed
		or: [Sensor controlKeyPressed
		or: [Sensor commandKeyPressed]]].
	active ifTrue: [aBlock value].
	^ active
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 13:11'
}
GraphvizPane >> zoomOut [
	self zoom: zoom / 1.25
]
