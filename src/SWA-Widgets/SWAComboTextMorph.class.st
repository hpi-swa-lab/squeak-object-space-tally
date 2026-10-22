"
The editable half of a SWAComboFieldMorph.

A plain TextMorph, not a PluggableTextMorph: that one is a scrolling pane, so it reserves a scrollbar gutter and clips a single line to less than the field's own height. SWASearchFieldMorph is the same pattern for the same reason.
"
Class {
	#name : #SWAComboTextMorph,
	#superclass : #TextMorph,
	#instVars : [
		'combo'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboTextMorph >> combo: aComboFieldMorph [
	combo := aComboFieldMorph
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 13:40'
}
SWAComboTextMorph >> keyStroke: evt [
	"Enter accepts what was typed, Escape puts the old value back. Both then drop
	focus, so the next click lands where it looks like it will."
	evt keyValue = 13 ifTrue: [
		evt hand newKeyboardFocus: nil.
		combo ifNotNil: [combo acceptFieldText: self contents].
		^ self].
	evt keyValue = 27 ifTrue: [
		evt hand newKeyboardFocus: nil.
		combo ifNotNil: [combo refresh].
		^ self].
	super keyStroke: evt
]
