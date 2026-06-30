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
		'hoveredTile'
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> clearHover [
	hoveredTile := nil.
	self setBalloonText: nil.
	treemapMorph updateSelectionPath: nil.
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWATreemapOverlay >> drawExtraHighlightsFor: selectedNode on: aCanvas origin: origin [
	"Hook: draw extra highlights for the selected node after the ancestor chain.
	Default no-op. Subclasses may override (e.g. SpaceTally other-parent lines)."
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 13:01'
}
SWATreemapOverlay >> drawOn: aCanvas [
	"Draw a white border on the selected (hovered) tile and fading cyan borders on
	all ancestor tiles, plus a RED border on any secondary-selection tile (drawn
	first so it always shows even when nothing is hovered). Domain-specific extras
	are added via the #drawExtraHighlightsFor:on:origin: hook (default no-op)."
	| origin screenR node r alpha parentColor selectedNode |
	origin := self position.
	"--- Secondary selection: red border (hover-independent) ---"
	self drawSecondarySelectionOn: aCanvas origin: origin.
	hoveredTile ifNil: [^ self].
	selectedNode := hoveredTile key.
	"--- Selected tile: white border ---"
	screenR := hoveredTile value translateBy: origin.
	aCanvas frameRectangle: screenR width: 2 color: Color white.
	"--- Walk parent chain upward, fading from bright cyan to dim ---"
	node := selectedNode parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil "stop at synthetic root"]] whileTrue: [
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			parentColor := Color cyan alpha: alpha.
			screenR := r translateBy: origin.
			aCanvas frameRectangle: screenR width: 2 color: parentColor].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent].
	"--- Domain extras (e.g. SpaceTally other-parent lines) ---"
	self drawExtraHighlightsFor: selectedNode on: aCanvas origin: origin
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:44'
}
SWATreemapOverlay >> mouseDown: evt [
	"Left-click: select tile. Click again on same tile: zoom in.
	 Right-click: context menu.
	 Shift+click: explore tally node."

	| local hit |
	local := evt position - self position.
	hit := treemapMorph tileAtLocal: local.
	hit ifNil: [^ self].

	"Right-click: context menu"
	evt yellowButtonPressed ifTrue: [
		^ self showMenuFor: hit key event: evt].

	"Shift+click: explore tally node"
	evt shiftPressed ifTrue: [
		^ treemapMorph exploreNode: hit key].

	"Same tile clicked twice -> zoom in"
	(hoveredTile notNil and: [hoveredTile key == hit key])
		ifTrue: [^ treemapMorph zoomInto: hit key].

	"Otherwise select this tile"
	hoveredTile := hit.
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> mouseMove: evt [
	"Update hover highlight and tooltip as the mouse moves."

	| local hit |
	local := evt position - self position.
	hit := treemapMorph tileAtLocal: local.

	"Same tile or both nil -- nothing to do"
	(hoveredTile == hit or: [
		hoveredTile notNil and: [hit notNil and: [hoveredTile key == hit key]]])
		ifTrue: [^ self].

	hoveredTile := hit.
	"Invalidate entire overlay because parent highlights can span the full area."
	self changed.
	hit ifNotNil: [
		self setBalloonText: (treemapMorph balloonStringFor: hit key).
		treemapMorph updateSelectionPath: hit key]
	ifNil: [
		self setBalloonText: nil.
		treemapMorph updateSelectionPath: nil]
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
