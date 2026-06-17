"
Transparent overlay on SWASpaceTallyTreemapMorph. Handles mouse events (hover, click, zoom) and draws the hover highlight. Keeps the treemap itself as a pure renderer that never redraws for interaction.
"
Class {
	#name : #SWASpaceTallyTreemapOverlay,
	#superclass : #Morph,
	#instVars : [
		'treemapMorph',
		'hoveredTile'
	],
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 12:04'
}
SWASpaceTallyTreemapOverlay >> clearHover [
	hoveredTile := nil.
	self setBalloonText: nil.
	treemapMorph updateSelectionPath: nil.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:04'
}
SWASpaceTallyTreemapOverlay >> copySubtreeToClipboard: aNode [
	"Pretty-print aNode's subtree as a nested bullet list and put it on the
	clipboard, for sharing in chat / issues. Mirrors the explorer's
	#copySelectedSubtree; confirms on the Transcript, no popup."

	| text |
	text := aNode asBulletListString.
	Clipboard clipboardText: text.
	Transcript show: 'SWASpaceTally: copied subtree (';
		show: text lineCount printString;
		show: ' lines) to clipboard.'; cr
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 6/12/2026 14:37'
}
SWASpaceTallyTreemapOverlay >> drawOn: aCanvas [
	"Draw a white border on the selected tile, fading borders on all
	 ancestor tiles, and colored borders on other-parent tiles."

	| origin screenR node r alpha parentColor otherParentSeen |
	hoveredTile ifNil: [^ self].
	origin := self position.

	"--- Selected tile: white border ---"
	screenR := hoveredTile value translateBy: origin.
	aCanvas frameRectangle: screenR width: 2 color: Color white.

	"--- Walk parent chain upward, fading from bright cyan to dim ---"
	node := hoveredTile key parent.
	alpha := 0.7.
	[node notNil and: [node parent notNil "stop at synthetic root"]] whileTrue: [
		r := treemapMorph rectForNode: node.
		r ifNotNil: [
			parentColor := Color cyan alpha: alpha.
			screenR := r translateBy: origin.
			aCanvas frameRectangle: screenR width: 2 color: parentColor].
		alpha := (alpha - 0.15) max: 0.15.
		node := node parent].

	"--- Other parents: orange borders ---"
	otherParentSeen := IdentitySet new.
	hoveredTile key otherParents ifNotNil: [:ops |
		ops do: [:otherNode |
			"Highlight the other parent node itself"
			(otherParentSeen includes: otherNode) ifFalse: [
				otherParentSeen add: otherNode.
				r := treemapMorph rectForNode: otherNode.
				r ifNotNil: [
					screenR := r translateBy: origin.
					aCanvas frameRectangle: screenR width: 2 color: (Color orange alpha: 0.8)]].
			"Walk up that other parent's ancestor chain too"
			node := otherNode parent.
			alpha := 0.5.
			[node notNil and: [node parent notNil]] whileTrue: [
				(otherParentSeen includes: node) ifFalse: [
					otherParentSeen add: node.
					r := treemapMorph rectForNode: node.
					r ifNotNil: [
						parentColor := Color orange alpha: alpha.
						screenR := r translateBy: origin.
						aCanvas frameRectangle: screenR width: 2 color: parentColor]].
				alpha := (alpha - 0.12) max: 0.1.
				node := node parent]]]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:37'
}
SWASpaceTallyTreemapOverlay >> exploreObject: anObject [
	ToolSet explore: anObject
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:25'
}
SWASpaceTallyTreemapOverlay >> handlesMouseDown: evt [
	^ true
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:57'
}
SWASpaceTallyTreemapOverlay >> handlesMouseOver: evt [
	^ true
]

{
	#category : #initialize,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:25'
}
SWASpaceTallyTreemapOverlay >> initialize [
	super initialize.
	self color: Color transparent.
	hoveredTile := nil
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:37'
}
SWASpaceTallyTreemapOverlay >> inspectObject: anObject [
	anObject inspect
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/12/2026 14:37'
}
SWASpaceTallyTreemapOverlay >> mouseDown: evt [
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
	treemapMorph updateSelectionPath: hit key
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 14:57'
}
SWASpaceTallyTreemapOverlay >> mouseLeave: evt [
	self clearHover
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/12/2026 14:37'
}
SWASpaceTallyTreemapOverlay >> mouseMove: evt [
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
	#'squeak_changestamp' : 'MCPServer 6/11/2026 12:00'
}
SWASpaceTallyTreemapOverlay >> openExplorerOn: aNode [
	"Open a SpaceTally Explorer on the root, expanded and selected to aNode."

	treemapMorph rootNode openExplorerSelecting: aNode
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 15:53'
}
SWASpaceTallyTreemapOverlay >> setColorMode: aSymbol [
	treemapMorph colorMode: aSymbol
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/17/2026 14:04'
}
SWASpaceTallyTreemapOverlay >> showMenuFor: aNode event: evt [
	"Show a context menu for the given tally node."

	| menu obj colorMenu current |
	menu := MenuMorph new defaultTarget: self.
	menu addTitle: (aNode name ifNil: ['?']).
	menu add: 'go back' target: treemapMorph selector: #zoomOut.
	menu addLine.
	menu add: 'open in SpaceTally Explorer' selector: #openExplorerOn: argument: aNode.
	menu add: 'copy subtree to clipboard' selector: #copySubtreeToClipboard: argument: aNode.
	menu addLine.
	obj := aNode object.
	obj
		ifNotNil: [
			menu add: 'inspect object' selector: #inspectObject: argument: obj.
			menu add: 'explore object' selector: #exploreObject: argument: obj]
		ifNil: [
			menu add: '(object was GC''d)' target: self selector: #yourself].
	menu addLine.
	menu add: 'inspect tally node' selector: #inspectObject: argument: aNode.
	menu add: 'explore tally node' selector: #exploreObject: argument: aNode.
	menu addLine.

	"Color mode submenu"
	current := treemapMorph colorMode.
	colorMenu := MenuMorph new defaultTarget: self.
	#(
		(#class          'By class name')
		(#children       'By number of children')
		(#otherParents   'By shared references')
		(#type           'By type (Morphic/Collection/Value/Other)')
		(#bitmap         'Bitmap (render Forms)')
	) do: [:pair |
		| mode label |
		mode := pair first.
		label := current == mode
			ifTrue: ['* ' , pair second]
			ifFalse: ['   ' , pair second].
		colorMenu add: label selector: #setColorMode: argument: mode].
	menu add: 'Color' subMenu: colorMenu.

	menu popUpEvent: evt in: self world
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:25'
}
SWASpaceTallyTreemapOverlay >> treemapMorph [
	^ treemapMorph
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 11:25'
}
SWASpaceTallyTreemapOverlay >> treemapMorph: aMorph [
	treemapMorph := aMorph
]
