"
Click/hover overlay for a SWAChangeTreemapMorph.

Inherits all the generic behavior (select / zoom-into-selected / shift-explore /
right-click menu / hover tooltip) from SWATreemapOverlay; adds the change-map's
own Color submenu options and a Browse item for method changes.
"
Class {
	#name : #SWAChangeTreemapOverlay,
	#superclass : #SWATreemapOverlay,
	#category : #'SWA-ChangeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:55'
}
SWAChangeTreemapOverlay >> addMenuItems: aMenu for: aNode [
	"Add a Browse item for method changes that still exist in the image."
	(aNode notNil and: [aNode kind == #change and: [aNode crossRefKey notNil]])
		ifTrue: [
			aMenu add: 'browse current version' target: self
				selector: #browseNode: argument: aNode]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:55'
}
SWAChangeTreemapOverlay >> browseNode: aNode [
	"Open a browser on the change's class/selector as it exists NOW in the image
	(may differ from, or no longer match, the archived change)."
	| clsName cls sel |
	clsName := aNode methodClassName.
	clsName ifNil: [^ self].
	cls := Smalltalk at: clsName asSymbol ifAbsent: [^ self inform: clsName, ' no longer exists'].
	sel := aNode methodSelector.
	(sel notNil and: [aNode changeType == #method])
		ifTrue: [ToolSet browse: cls selector: sel asSymbol]
		ifFalse: [ToolSet browse: cls selector: nil]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapOverlay >> colorModeOptions [
	^ #(
		(#changeKind 'By change kind (method/doIt/class/comment/removal)')
		(#status     'By status (current/superseded/in-history/gone)')
		(#author     'By author')
		(#recency    'By recency (blue old -> red new)')
	)
]
