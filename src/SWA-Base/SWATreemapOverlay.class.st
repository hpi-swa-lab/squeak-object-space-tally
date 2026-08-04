"
Abstract transparent overlay for a SWATreemapMorph. Handles generic interaction:
hover highlight + balloon, click-to-select, click-again-to-zoom, shift-to-explore,
right-click context menu, and selection/ancestor border highlighting.

Domain-specific bits are hooks:
  - drawExtraHighlightsFor:on:origin:   extra decorations after the ancestor chain
  - addMenuItems:for:                   domain menu items
  - colorModeOptions                    {symbol. label} pairs for the Color submenu

Subclasses: SWASpaceTallyTreemapOverlay (other-parent lines + object menu),
SWACodeTreemapOverlay (browse/senders/implementors menu + code color modes).
"
Class {
	#name : #SWATreemapOverlay,
	#superclass : #Morph,
	#instVars : [
		'treemapMorph',
		'hoveredTile',
		'hoverPoint'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:32'
}
SWATreemapOverlay >> addContainerTintItemsTo: aMenu [
	"Below a separator, how CONTAINER tiles are tinted while a dataset metric drives
	colour. Only shown when a dataset metric is actually active -- it says nothing
	about the intrinsic modes, which colour containers on purpose (by kind, by
	author, ...)."
	| current |
	((treemapMorph respondsTo: #metricForMode:) and: [treemapMorph respondsTo: #colorMode])
		ifFalse: [^ self].
	(treemapMorph metricForMode: treemapMorph colorMode) ifNil: [^ self].
	current := SWAView datasetContainerTint.
	aMenu addLine.
	SWAView datasetContainerTintOptions do: [:pair |
		aMenu
			add: (current == pair first ifTrue: ['* '] ifFalse: ['   ']), pair second
			selector: #setContainerTint:
			argument: pair first]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:58'
}
SWATreemapOverlay >> addMarkMenuItems: aMenu for: aNode [
	"Add the mark/bookmark context-menu items for aNode: a toggle (Mark / Unmark)
	when the node is markable, an object-explore of the tally node (previously
	shift-click), and a shortcut to show the Marks panel. Kept out of the
	domain-specific #addMenuItems:for: hook so every view gets them."
	aMenu addLine.
	aNode markKey ifNotNil: [
		(treemapMorph isNodeMarked: aNode)
			ifTrue: [aMenu add: 'Unmark' target: treemapMorph selector: #toggleMark: argument: aNode]
			ifFalse: [aMenu add: 'Mark' target: treemapMorph selector: #toggleMark: argument: aNode]].
	aMenu add: 'explore tally node' target: treemapMorph selector: #exploreNode: argument: aNode
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWATreemapOverlay >> addMenuItems: aMenu for: aNode [
	"Hook: add domain-specific context-menu items. Default none."
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 12:06'
}
SWATreemapOverlay >> clearHover [
	"Mouse left the overlay: drop the transient hover state (tile + point) so the
	border and tooltip disappear. Does NOT touch the selection or its path label --
	those are click-driven and must persist while the mouse is away."
	hoveredTile := nil.
	hoverPoint := nil.
	self changed
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:32'
}
SWATreemapOverlay >> colorMenuMorph [
	"Build the Color (instant recolor) menu from #colorModeOptions, ticking the
	current mode. Single source of truth shared by the context menu and the header
	'Color' button. Answers nil when the view offers no color options."
	| opts current menu |
	opts := self colorModeOptions.
	opts isEmpty ifTrue: [^ nil].
	current := treemapMorph colorMode.
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode
			ifTrue: ['* ', pair second]
			ifFalse: ['   ', pair second].
		menu add: label selector: #setColorMode: argument: mode].
	self addContainerTintItemsTo: menu.
	^ menu
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWATreemapOverlay >> colorModeOptions [
	"Hook: { colorModeSymbol. menuLabel } pairs for the Color submenu.
	Default: empty (no Color submenu). Subclasses override."
	^ #()
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:58'
}
SWATreemapOverlay >> drawMarksOn: aCanvas origin: origin [
	"Draw a GREEN border around every tile currently in the global mark set
	(SWAMarkSet), resolved to this view's nodes via #markedNodes. Hover-independent
	and persistent: marks stay visible as the mouse moves. Only currently-laid-out
	tiles have a rectangle (rectForNode: answers nil otherwise), so marks off-screen
	under a zoom are simply not drawn."
	(treemapMorph respondsTo: #markedNodes) ifFalse: [^ self].
	treemapMorph markedNodes do: [:node | | r |
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			SWASelectionPainter
				frame: (r translateBy: origin) on: aCanvas width: 3 color: Color green]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:58'
}
SWATreemapOverlay >> drawOn: aCanvas [
	"HOVER feedback (transient): a white border on the tile under the cursor + fading
	cyan ancestor borders, plus our OWN canvas-drawn tooltip for that tile (Morphic's
	balloon never worked here). A RED border marks any secondary-selection tile
	(hover-independent). GREEN borders mark every bookmarked tile (the global
	SWAMarkSet, hover-independent). Hover NEVER changes the selection -- the
	persistent CLICK selection + decorations are drawn by subclass #drawOn: overrides.
	Requires #wantsEveryMouseMove so button-up moves are delivered. Border/tooltip
	drawing is delegated to the shared SWASelectionPainter."
	| origin hoveredNode |
	origin := self position.
	"--- Marks: green borders (hover-independent, every marked tile) ---"
	self drawMarksOn: aCanvas origin: origin.
	"--- Secondary selection: red border (hover-independent) ---"
	self drawSecondarySelectionOn: aCanvas origin: origin.
	hoveredTile ifNil: [^ self].
	hoveredNode := hoveredTile key.
	"--- Hovered tile: white border ---"
	SWASelectionPainter
		hoverFrameOn: aCanvas
		rect: (hoveredTile value translateBy: origin).
	"--- Fading cyan ancestor borders ---"
	SWASelectionPainter
		ancestorFramesOn: aCanvas
		from: hoveredNode
		rectBlock: [:node | | r | r := treemapMorph rectForNode: node.
			r ifNotNil: [r translateBy: origin]].
	"--- Our own tooltip for the hovered tile ---"
	self drawTooltipFor: hoveredNode on: aCanvas origin: origin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:01'
}
SWATreemapOverlay >> drawSecondarySelectionOn: aCanvas origin: origin [
	"Draw a RED border around the view's secondary-selection tile, if any. Unlike
	the white primary-selection/hover border this is driven by #secondarySelection
	(not hover), so it persists while the mouse is elsewhere. General mechanism: any
	view can set a secondary selection; the duplication view sets it to the
	near-duplicate being diffed against the primary selection."
	| sec r |
	(treemapMorph respondsTo: #secondarySelection) ifFalse: [^ self].
	sec := treemapMorph secondarySelection.
	sec ifNil: [^ self].
	r := treemapMorph rectForNode: sec.
	r ifNil: [^ self].
	SWASelectionPainter
		frame: (r translateBy: origin) on: aCanvas width: 2 color: Color red
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWATreemapOverlay >> drawSelectionBorderFor: aNode on: aCanvas origin: origin [
	"Draw the persistent CLICK-selection border for aNode: a distinct YELLOW 3px
	frame (deliberately different from the transient WHITE 2px hover border), plus
	fading cyan ancestor borders. Drawn every frame from the persistent selectedNode,
	so the selection stays visible -- and distinguishable from hover -- as the mouse
	moves over other tiles or leaves the canvas. Delegates the actual drawing to the
	shared SWASelectionPainter so all views stay visually consistent."
	| selRect |
	aNode ifNil: [^ self].
	selRect := treemapMorph rectForNode: aNode.
	selRect ifNil: [^ self].
	SWASelectionPainter
		selectionFrameOn: aCanvas
		rect: (selRect translateBy: origin)
		color: Color yellow.
	SWASelectionPainter
		ancestorFramesOn: aCanvas
		from: aNode
		rectBlock: [:node | | r | r := treemapMorph rectForNode: node.
			r ifNotNil: [r translateBy: origin]]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:00'
}
SWATreemapOverlay >> drawTooltipFor: aNode on: aCanvas origin: origin [
	"Draw a small hover label -- JUST the entity NAME -- near the mouse. Delegates to
	the shared SWASelectionPainter (canvas-drawn; Morphic's balloon never worked
	here). Enough to read a tiny tile; click for full details."
	aNode ifNil: [^ self].
	hoverPoint ifNil: [^ self].
	SWASelectionPainter
		tooltipOn: aCanvas
		string: aNode name
		at: (hoverPoint + origin) + (14 @ 18)
		bounds: (origin extent: self extent)
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWATreemapOverlay >> exploreObject: anObject [
	ToolSet explore: anObject
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> handlesMouseOver: evt [
	^ true
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> initialize [
	super initialize.
	self color: Color transparent.
	hoveredTile := nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWATreemapOverlay >> inspectObject: anObject [
	anObject inspect
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:57'
}
SWATreemapOverlay >> mouseDown: evt [
	"Left-click a tile: select it. Click the ALREADY-SELECTED tile again: zoom in.
	 Right-click: context menu.  Shift+click: toggle the tile in/out of the global
	 mark set (bookmark). (Object-explore of the tally node moved to the context
	 menu.)"
	| local hit |
	treemapMorph takeKeyboardFocusFrom: evt.   "so Ctrl+F reaches the view"
	local := evt position - self position.
	hit := treemapMorph tileAtLocal: local.
	hit ifNil: [^ self].

	"Right-click: context menu"
	evt yellowButtonPressed ifTrue: [
		^ self showMenuFor: hit key event: evt].

	"Shift+click: toggle bookmark/mark"
	evt shiftPressed ifTrue: [
		treemapMorph toggleMark: hit key.
		^ self changed].

	"Click on the already-selected tile -> zoom in"
	(treemapMorph selectedNode notNil
		and: [treemapMorph selectedNode == hit key])
		ifTrue: [^ treemapMorph zoomInto: hit key].

	"Otherwise select this tile"
	self changed.
	treemapMorph selectTileNode: hit key
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> mouseLeave: evt [
	self clearHover
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 12:05'
}
SWATreemapOverlay >> mouseMove: evt [
	"Track ONLY hover state -- the tile under the cursor + the mouse point -- so
	#drawOn: can draw the hover border and our own tooltip. Hover must NOT affect the
	SELECTION (that is click-only, in #mouseDown:), so we do NOT touch selectedNode or
	the selection-path label here. Fires on every move now (#wantsEveryMouseMove)."
	| local hit |
	local := evt position - self position.
	hit := treemapMorph tileAtLocal: local.
	hoverPoint := local.
	"Same tile -- still repaint so the tooltip tracks the moving cursor."
	(hoveredTile == hit or: [
		hoveredTile notNil and: [hit notNil and: [hoveredTile key == hit key]]])
		ifTrue: [^ self changed].
	hoveredTile := hit.
	self changed
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWATreemapOverlay >> popUpColorMenu [
	"Pop up the Color menu standalone (header 'Color' button)."
	| menu |
	menu := self colorMenuMorph.
	self popUpMenu: menu
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWATreemapOverlay >> popUpMenu: aMenu [
	"Pop up aMenu at the hand position, as a CHILD -- never in the world.
	See SWAPane class>>popUp:at:in: for why."
	^ self popUpMenu: aMenu at: self currentHand position
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWATreemapOverlay >> popUpMenu: aMenu at: aPoint [
	"Hand the pop-up to the treemap I decorate, which hands it on to its pane.
	Falls back to this overlay (it covers the whole map) when there is no view."
	^ (treemapMorph notNil and: [treemapMorph respondsTo: #popUpMenu:at:])
		ifTrue: [treemapMorph popUpMenu: aMenu at: aPoint]
		ifFalse: [SWAPane popUp: aMenu at: aPoint in: self]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWATreemapOverlay >> popUpSizeMenu [
	"Pop up the Size menu standalone (header 'Size' button). Reachable even when the
	layout collapsed to nothing (e.g. a size metric with zero total weight left the
	canvas black), which the tile-based right-click menu cannot do."
	| menu |
	menu := self sizeMenuMorph.
	self popUpMenu: menu
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> setColorMode: aSymbol [
	treemapMorph colorMode: aSymbol
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:32'
}
SWATreemapOverlay >> setContainerTint: aSymbol [
	"Switch how container tiles are tinted, everywhere. Colour-only, so every open
	view just drops its cached Form -- no relayout."
	SWAView datasetContainerTint: aSymbol.
	SWAView allSubInstances do: [:v |
		(v respondsTo: #flushCache) ifTrue: [v flushCache].
		v changed]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:03'
}
SWATreemapOverlay >> setSizeMode: aSymbol [
	"Switch the tile size (weight) metric and relayout. Only meaningful for views
	whose morph understands #weightMetric: (the Code Map); a no-op otherwise."
	(treemapMorph respondsTo: #weightMetric:) ifTrue: [
		treemapMorph weightMetric: aSymbol]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWATreemapOverlay >> showMenuFor: aNode event: evt [
	"Show a context menu for the given node. Generic items (title, go back, the
	mark/unmark toggle, then the Size and Color submenus, both built by the shared
	#sizeMenuMorph/#colorMenuMorph) plus domain items via the #addMenuItems:for:
	hook."
	| menu sizeMenu colorMenu |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (aNode name ifNil: ['?']).
	menu add: 'go back' target: treemapMorph selector: #zoomOut.
	self addMarkMenuItems: menu for: aNode.
	menu addLine.
	self addMenuItems: menu for: aNode.
	sizeMenu := self sizeMenuMorph.
	sizeMenu ifNotNil: [menu addLine. menu add: 'Size' subMenu: sizeMenu].
	colorMenu := self colorMenuMorph.
	colorMenu ifNotNil: [menu addLine. menu add: 'Color' subMenu: colorMenu].
	self popUpMenu: menu at: (evt ifNil: [self currentHand] ifNotNil: [evt hand]) position truncated
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWATreemapOverlay >> sizeMenuMorph [
	"Build the Size (tile-WEIGHT metric) menu from #sizeModeOptions, ticking the
	current metric. Single source of truth shared by the context menu and the
	header 'Size' button. Answers nil when the view offers no size options."
	| opts current menu |
	opts := self sizeModeOptions.
	opts isEmpty ifTrue: [^ nil].
	current := (treemapMorph respondsTo: #weightMetric)
		ifTrue: [treemapMorph weightMetric] ifFalse: [nil].
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode
			ifTrue: ['* ', pair second]
			ifFalse: ['   ', pair second].
		menu add: label selector: #setSizeMode: argument: mode].
	^ menu
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:03'
}
SWATreemapOverlay >> sizeModeOptions [
	"Hook: { sizeModeSymbol. menuLabel } pairs for the Size submenu (the live tile
	WEIGHT metric). Default: empty (no Size submenu). Subclasses override."
	^ #()
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> treemapMorph [
	^ treemapMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> treemapMorph: aMorph [
	treemapMorph := aMorph
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 12:04'
}
SWATreemapOverlay >> wantsEveryMouseMove [
	"YES -- deliver mouseMove: even with NO button pressed. By default Morphic drops
	button-up moves (see #handlesMouseMove:), which is why our hover tooltip only fired
	while click-dragging. To Morphic we are one flat morph doing our own tile hit-test
	in #mouseMove:, so we need every move to track the cursor over tiles on plain hover."
	^ true
]
