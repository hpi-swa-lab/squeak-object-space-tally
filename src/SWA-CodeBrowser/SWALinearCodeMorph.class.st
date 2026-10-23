"
One member's source in the linear view. A TextMorph rather than a PluggableTextMorph: it has no scroll pane of its own to swallow the mouse wheel, and it grows to fit its text.
"
Class {
	#name : #SWALinearCodeMorph,
	#superclass : #TextMorph,
	#instVars : [
		'view',
		'node',
		'shownText'
	],
	#category : #'SWA-CodeBrowser',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWALinearCodeMorph >> acceptContents [
	"Cmd+S."
	(view acceptSource: self contents of: node shown: shownText notifying: self editor)
		ifTrue: [shownText := self contents asString].
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWALinearCodeMorph >> mouseDown: anEvent [
	view selectFromLinear: node.
	super mouseDown: anEvent.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWALinearCodeMorph >> node [
	^ node
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWALinearCodeMorph >> view: aView node: aNode shown: aString [
	view := aView.
	node := aNode.
	shownText := aString.
]
