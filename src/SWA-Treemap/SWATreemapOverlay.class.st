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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWATreemapOverlay >> drawOn: aCanvas [
	"Draw a white border on the selected tile and fading cyan borders on all
	ancestor tiles. Domain-specific extras are added via the
	#drawExtraHighlightsFor:on:origin: hook (default no-op)."
	| origin screenR node r alpha parentColor selectedNode |
	hoveredTile ifNil: [^ self].
	origin := self position.
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
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:21'
}
SWATreemapOverlay >> setColorMode: aSymbol [
	treemapMorph colorMode: aSymbol
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWATreemapOverlay >> showMenuFor: aNode event: evt [
	"Show a context menu for the given node. Generic items (title, go back, color
	modes) plus domain items via the #addMenuItems:for: hook."
	| menu colorMenu current opts |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (aNode name ifNil: ['?']).
	menu add: 'go back' target: treemapMorph selector: #zoomOut.
	menu addLine.
	self addMenuItems: menu for: aNode.
	opts := self colorModeOptions.
	opts isEmpty ifFalse: [
		menu addLine.
		current := treemapMorph colorMode.
		colorMenu := MenuMorph new defaultTarget: self.
		opts do: [:pair | | mode label |
			mode := pair first.
			label := current == mode
				ifTrue: ['* ', pair second]
				ifFalse: ['   ', pair second].
			colorMenu add: label selector: #setColorMode: argument: mode].
		menu add: 'Color' subMenu: colorMenu].
	menu popUpEvent: evt in: self world
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
