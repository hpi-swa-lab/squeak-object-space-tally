"
A single-line text input living in a SWANavPanel button bar. On EVERY keystroke it forwards its current text to the panel's #runSearch: so the view's name-filter updates live (matching entity tiles stay bright, the rest dim). Enter/Escape are handled too. Set the owning panel with #panel:.
"
Class {
	#name : #SWASearchFieldMorph,
	#superclass : #TextMorph,
	#instVars : [
		'panel'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:05'
}
SWASearchFieldMorph >> keyStroke: evt [
	"Edit as a normal text field, then push the new contents to the panel's live search
	on EVERY keystroke. Escape clears the field (and the filter) and drops focus."
	evt keyValue = 27 ifTrue: [   "Escape: clear + release focus"
		self contents: ''.
		panel ifNotNil: [panel runSearch: ''].
		evt hand newKeyboardFocus: nil.
		^ self].
	super keyStroke: evt.
	panel ifNotNil: [panel runSearch: self searchText]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWASearchFieldMorph >> panel: aNavPanel [
	"The SWAPane whose view I filter."
	panel := aNavPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:05'
}
SWASearchFieldMorph >> searchText [
	"My current contents as a plain String, blanks trimmed."
	^ self contents asString withBlanksTrimmed
]
