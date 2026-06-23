"
Interaction overlay for SWACodeTreemapMorph. Context menu offers browse, and (for method tiles) senders/implementors; no other-parent decorations since code nodes form a strict tree.
"
Class {
	#name : #SWACodeTreemapOverlay,
	#superclass : #SWATreemapOverlay,
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> addMenuItems: menu for: aNode [
	"Code context-menu items: browse the element; for method tiles also offer
	senders/implementors. Plus inspect/explore the node itself."
	menu add: 'browse' selector: #browseNode: argument: aNode.
	aNode kind = #method ifTrue: [
		menu add: 'senders' selector: #browseSenders: argument: aNode.
		menu add: 'implementors' selector: #browseImplementors: argument: aNode].
	menu addLine.
	menu add: 'inspect node' selector: #inspectObject: argument: aNode.
	menu add: 'explore node' selector: #exploreObject: argument: aNode
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseImplementors: aMethodNode [
	SystemNavigation default browseAllImplementorsOf: aMethodNode subject selector
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseNode: aNode [
	aNode browse
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:23'
}
SWACodeTreemapOverlay >> browseSenders: aMethodNode [
	SystemNavigation default browseAllCallsOn: aMethodNode subject selector
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:41'
}
SWACodeTreemapOverlay >> colorModeOptions [
	^ #(
		(#codeKind  'By kind (package/class/category/method)')
		(#loc       'By LOC (heat)')
		(#avgloc    'By avg LOC / method')
		(#versions  'By avg versions / method')
		(#recency   'By recency (last changed)')
		(#author    'By author (last changed)')
	)
]
