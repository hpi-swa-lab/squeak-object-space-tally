"
Transparent overlay on SWASpaceTallyTreemapMorph. Handles mouse events (hover, click, zoom) and draws the hover highlight. Keeps the treemap itself as a pure renderer that never redraws for interaction.
"
Class {
	#name : #SWASpaceTallyTreemapOverlay,
	#superclass : #SWATreemapOverlay,
	#category : #'SWA-SpaceTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWASpaceTallyTreemapOverlay >> addMenuItems: menu for: aNode [
	"SpaceTally context-menu items: explorer, subtree copy, retention graph,
	inspect/explore the live object and the tally node."
	| obj |
	menu add: 'open in SpaceTally Explorer' selector: #openExplorerOn: argument: aNode.
	menu add: 'copy subtree to clipboard' selector: #copySubtreeToClipboard: argument: aNode.
	menu add: 'graph parents to roots' selector: #graphParentsToRoots: argument: aNode.
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
	menu add: 'explore tally node' selector: #exploreObject: argument: aNode
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWASpaceTallyTreemapOverlay >> colorModeOptions [
	^ #(
		(#class          'By class name')
		(#children       'By number of children')
		(#otherParents   'By shared references')
		(#type           'By type (Morphic/Collection/Value/Other)')
		(#bitmap         'Bitmap (render Forms)')
	)
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:22'
}
SWASpaceTallyTreemapOverlay >> drawExtraHighlightsFor: selectedNode on: aCanvas origin: origin [
	"Draw lines pointing to other-parent tiles: gray if the other parent is a
	descendant of the selected node, red otherwise. If an other-parent tile is too
	small to be rendered, draw the line to the nearest visible ancestor instead."
	| screenR r selectedCenter otherParentSeen lineColor anc target |
	selectedCenter := (hoveredTile value translateBy: origin) center.
	otherParentSeen := IdentitySet new.
	selectedNode otherParents ifNotNil: [:ops |
		ops do: [:otherNode |
			(otherParentSeen includes: otherNode) ifFalse: [
				otherParentSeen add: otherNode.
				target := otherNode.
				r := treemapMorph rectForNode: target.
				[r isNil and: [target notNil and: [target parent notNil]]] whileTrue: [
					target := target parent.
					r := treemapMorph rectForNode: target].
				(r notNil and: [target ~~ selectedNode]) ifTrue: [
					anc := target.
					[anc notNil and: [anc ~~ selectedNode]] whileTrue: [anc := anc parent].
					lineColor := anc == selectedNode
						ifTrue: [Color gray alpha: 0.8]
						ifFalse: [Color red alpha: 0.8].
					screenR := r translateBy: origin.
					aCanvas
						line: selectedCenter
						to: screenR center
						width: 2
						color: lineColor]]]]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/18/2026 12:30'
}
SWASpaceTallyTreemapOverlay >> graphParentsToRoots: aNode [
	"Open a Graphviz view of aNode's ancestry up to the roots (capped at 100
	nodes). Same as the explorer's menu item; delegates to the node."

	aNode openParentsGraph
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/11/2026 12:00'
}
SWASpaceTallyTreemapOverlay >> openExplorerOn: aNode [
	"Open a SpaceTally Explorer on the root, expanded and selected to aNode."

	treemapMorph rootNode openExplorerSelecting: aNode
]
