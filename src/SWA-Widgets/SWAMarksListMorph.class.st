"
A plain multi-select list used in the SWAPane Marks panel. It carries NO event overrides -- it exists only as a MARKER type so the global SWAMarksClickFilter can recognise 'a click over a marks list' and rewrite the VM's emulated Ctrl+click (yellow button) back into a normal Ctrl+Red left-click that reaches selection. See SWAMarksClickFilter.
"
Class {
	#name : #SWAMarksListMorph,
	#superclass : #AlternatePluggableListMorphOfMany,
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 17:40'
}
SWAMarksListMorph >> filterEvent: anEvent for: aTargetOrNil [
	"Global mouse-capture filter (I register myself on the hand while on screen). Only
	touch a mouseDown that is (a) an emulated Ctrl+click -- yellow button with the
	control modifier still set -- and (b) positioned over ME. Rewrite it into a normal
	Ctrl+RED left-click so my multi-select machinery toggles the row. Everything else
	passes through unchanged, so halo/menu behaviour is preserved everywhere else.

	NOTE: this only reaches selection when the 'Offer Meta Menu for All Morphs'
	preference (Morph metaMenuForAll) is OFF; otherwise the World consumes every
	control+mouseDown for its meta menu before dispatch (regardless of button)."
	(anEvent isMouse and: [anEvent isMouseDown]) ifFalse: [^ anEvent].
	(anEvent yellowButtonPressed and: [anEvent controlKeyPressed]) ifFalse: [^ anEvent].
	(self fullBounds containsPoint: anEvent position) ifFalse: [^ anEvent].
	^ self rewriteToControlRedClick: anEvent
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 17:40'
}
SWAMarksListMorph >> intoWorld: aWorld [
	"When I appear in the world, register MYSELF as a global mouse capture filter on
	that world's hand, so #filterEvent:for: can rewrite this VM's emulated Ctrl+click
	(yellow button) over me back into a real Ctrl+Red click (a per-morph capture
	filter never sees that emulated down; only a hand-level one does). Removed again
	in #outOfWorld:, so the registration lives exactly as long as I am on screen."
	super intoWorld: aWorld.
	aWorld ifNil: [^ self].
	aWorld activeHand ifNotNil: [:hand | hand addMouseCaptureFilter: self]
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 17:40'
}
SWAMarksListMorph >> outOfWorld: aWorld [
	"When I leave the world, remove my hand mouse-capture filter registration."
	super outOfWorld: aWorld.
	aWorld ifNil: [^ self].
	aWorld activeHand ifNotNil: [:hand | hand removeMouseCaptureFilter: self]
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/16/2026 17:40'
}
SWAMarksListMorph >> rewriteToControlRedClick: anEvent [
	"Return a copy of anEvent (an emulated Ctrl+Yellow mouseDown) with the yellow
	button bit cleared and the red button bit set, keeping every modifier bit (so
	control stays pressed)."
	| newButtons clicks |
	newButtons := (anEvent buttons bitClear: MouseButtonEvent yellowButton)
		bitOr: MouseButtonEvent redButton.
	clicks := (anEvent respondsTo: #nClicks) ifTrue: [anEvent nClicks] ifFalse: [1].
	^ MouseButtonEvent new
		setType: anEvent type
		position: anEvent position
		which: MouseButtonEvent redButton
		buttons: newButtons
		nClicks: clicks
		hand: anEvent hand
		stamp: anEvent timeStamp
]
