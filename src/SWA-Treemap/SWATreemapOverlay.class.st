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
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 12:06'
}
SWATreemapOverlay >> drawOn: aCanvas [
	"HOVER feedback (transient): a white border on the tile under the cursor + fading
	cyan ancestor borders, plus our OWN canvas-drawn tooltip for that tile (Morphic's
	balloon never worked here). A RED border marks any secondary-selection tile
	(hover-independent). Hover NEVER changes the selection -- the persistent CLICK
	selection + decorations are drawn by subclass #drawOn: overrides. Requires
	#wantsEveryMouseMove so button-up moves are delivered."
	| origin screenR node r alpha parentColor hoveredNode |
	origin := self position.
	"--- Secondary selection: red border (hover-independent) ---"
	self drawSecondarySelectionOn: aCanvas origin: origin.
	hoveredTile ifNil: [^ self].
	hoveredNode := hoveredTile key.
	"--- Hovered tile: white border ---"
	screenR := hoveredTile value translateBy: origin.
	aCanvas frameRectangle: screenR width: 2 color: Color white.
	"--- Walk parent chain upward, fading from bright cyan to dim ---"
	node := hoveredNode parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil "stop at synthetic root"]] whileTrue: [
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			parentColor := Color cyan alpha: alpha.
			screenR := r translateBy: origin.
			aCanvas frameRectangle: screenR width: 2 color: parentColor].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent].
	"--- Our own tooltip for the hovered tile ---"
	self drawTooltipFor: hoveredNode on: aCanvas origin: origin
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 13:01'
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
	aCanvas frameRectangle: (r translateBy: origin) width: 2 color: Color red
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:40'
}
SWATreemapOverlay >> drawSelectionBorderFor: aNode on: aCanvas origin: origin [
	"Draw the persistent CLICK-selection border for aNode: a distinct YELLOW 3px frame
	(deliberately different from the transient WHITE 2px hover border), plus fading
	cyan ancestor borders. Drawn every frame from the persistent selectedNode, so the
	selection stays visible -- and distinguishable from hover -- as the mouse moves
	over other tiles or leaves the canvas. Shared by all treemap overlays."
	| selRect node alpha r parentColor screenR |
	aNode ifNil: [^ self].
	selRect := treemapMorph rectForNode: aNode.
	selRect ifNil: [^ self].
	aCanvas frameRectangle: (selRect translateBy: origin) width: 3 color: Color yellow.
	node := aNode parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil]] whileTrue: [
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			parentColor := Color cyan alpha: alpha.
			screenR := r translateBy: origin.
			aCanvas frameRectangle: screenR width: 2 color: parentColor].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 12:11'
}
SWATreemapOverlay >> drawTooltipFor: aNode on: aCanvas origin: origin [
	"Draw a small hover label -- JUST the entity NAME -- near the mouse (canvas-drawn;
	Morphic's balloon never worked here). Enough to read a tiny tile; click for full
	details. Offset off the cursor and clamped to stay inside the overlay."
	| name font pad w h boxOrigin anchor maxRight maxBottom |
	aNode ifNil: [^ self].
	hoverPoint ifNil: [^ self].
	name := aNode name.
	(name isNil or: [name isEmpty]) ifTrue: [^ self].
	font := TextStyle default fontOfPointSize: 10.
	pad := 4.
	w := (font widthOfString: name) + (pad * 2).
	h := font height + (pad * 2).
	"anchor at the mouse (local coords), offset below-right of the cursor"
	anchor := (hoverPoint + origin) + (14 @ 18).
	"clamp inside the overlay's on-screen bounds"
	maxRight := origin x + self width.
	maxBottom := origin y + self height.
	boxOrigin := anchor.
	(boxOrigin x + w) > maxRight ifTrue: [boxOrigin := (maxRight - w - 2) @ boxOrigin y].
	(boxOrigin y + h) > maxBottom ifTrue: [boxOrigin := boxOrigin x @ ((hoverPoint + origin) y - h - 8)].
	boxOrigin := (boxOrigin x max: origin x + 2) @ (boxOrigin y max: origin y + 2).
	aCanvas
		frameAndFillRectangle: (boxOrigin extent: w @ h)
		fillColor: (Color black alpha: 0.82)
		borderWidth: 1
		borderColor: (Color gray: 0.6).
	aCanvas
		drawString: name
		at: (boxOrigin x + pad) @ (boxOrigin y + pad)
		font: font
		color: Color white
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
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:19'
}
SWATreemapOverlay >> mouseDown: evt [
	"Left-click a tile: select it. Click the ALREADY-SELECTED tile again: zoom in.
	 Right-click: context menu.  Shift+click: explore tally node."
	| local hit |
	treemapMorph takeKeyboardFocusFrom: evt.   "so Ctrl+F reaches the view"
	local := evt position - self position.
	hit := treemapMorph tileAtLocal: local.
	hit ifNil: [^ self].

	"Right-click: context menu"
	evt yellowButtonPressed ifTrue: [
		^ self showMenuFor: hit key event: evt].

	"Shift+click: explore tally node"
	evt shiftPressed ifTrue: [
		^ treemapMorph exploreNode: hit key].

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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWATreemapOverlay >> popUpColorMenu [
	"Pop up the Color menu standalone (header 'Color' button)."
	| menu |
	menu := self colorMenuMorph.
	menu ifNotNil: [menu popUpInWorld: self world]
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWATreemapOverlay >> popUpSizeMenu [
	"Pop up the Size menu standalone (header 'Size' button). Reachable even when the
	layout collapsed to nothing (e.g. a size metric with zero total weight left the
	canvas black), which the tile-based right-click menu cannot do."
	| menu |
	menu := self sizeMenuMorph.
	menu ifNotNil: [menu popUpInWorld: self world]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> setColorMode: aSymbol [
	treemapMorph colorMode: aSymbol
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWATreemapOverlay >> showMenuFor: aNode event: evt [
	"Show a context menu for the given node. Generic items (title, go back, then the
	Size and Color submenus, both built by the shared #sizeMenuMorph/#colorMenuMorph)
	plus domain items via the #addMenuItems:for: hook."
	| menu sizeMenu colorMenu |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (aNode name ifNil: ['?']).
	menu add: 'go back' target: treemapMorph selector: #zoomOut.
	menu addLine.
	self addMenuItems: menu for: aNode.
	sizeMenu := self sizeMenuMorph.
	sizeMenu ifNotNil: [menu addLine. menu add: 'Size' subMenu: sizeMenu].
	colorMenu := self colorMenuMorph.
	colorMenu ifNotNil: [menu addLine. menu add: 'Color' subMenu: colorMenu].
	menu popUpEvent: evt in: self world
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
