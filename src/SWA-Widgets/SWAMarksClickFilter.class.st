"
A GLOBAL mouse event filter (registered on the World's hand) that lets Ctrl+click work as a multi-select toggle inside a SWAMarksListMorph, despite this VM's single-button emulation.

Background (measured on this VM): a modified left-click is remapped by the VM to a different BUTTON while keeping the true modifier flag:
  - Ctrl+Left  -> YELLOW button (+ ctrl flag)  -> would pop the context menu
  - Cmd/Alt+Left -> BLUE button (+ cmd flag)   -> would pop the halo
So Ctrl/Cmd/Alt clicks never reach a list's selection logic.

This filter runs during the mouse CAPTURE phase (before halo/menu dispatch). Scoped tightly: it only acts on a mouseDown whose position is over a SWAMarksListMorph. There it rewrites an emulated Ctrl+click (yellow button, control pressed) back into a normal RED left-click that KEEPS the control modifier, so AlternatePluggableListMorphOfMany receives it as a real Ctrl+click and toggles the row. Every other morph, and every other gesture, is left untouched -- halo and menus keep working everywhere else.

Registered once (idempotent) via #install; the Marks panel calls #ensureInstalled when shown."">

"
Class {
	#name : #SWAMarksClickFilter,
	#superclass : #Object,
	#classVars : [
		'Default'
	],
	#category : #'SWA-Widgets',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #install,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter class >> activeHand [
	^ World ifNotNil: [:w | w activeHand]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter class >> default [
	^ Default ifNil: [Default := self new]
]

{
	#category : #install,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter class >> ensureInstalled [
	"Register the singleton filter on the active World's hand, idempotently."
	| hand |
	hand := self activeHand.
	hand ifNil: [^ self].
	(hand mouseCaptureFilters notNil and: [hand mouseCaptureFilters includes: self default])
		ifTrue: [^ self].
	hand addMouseCaptureFilter: self default
]

{
	#category : #install,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter class >> uninstall [
	"Remove the filter from the hand (e.g. for cleanup)."
	| hand |
	hand := self activeHand.
	hand ifNil: [^ self].
	Default ifNotNil: [hand removeMouseCaptureFilter: Default]
]

{
	#category : #filtering,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:47'
}
SWAMarksClickFilter >> filterEvent: anEvent for: aTargetOrNil [
	"Global mouse-capture filter. Only touch a mouseDown that is (a) an emulated
	Ctrl+click -- yellow button with the control modifier still set -- and (b)
	positioned over a SWAMarksListMorph. Rewrite it into a normal Ctrl+RED left-click
	so the list's multi-select machinery toggles the row. Everything else passes
	through unchanged, so halo/menu behaviour is preserved everywhere else.

	NOTE: this only reaches selection when the 'Offer Meta Menu for All Morphs'
	preference (Morph metaMenuForAll) is OFF; otherwise the World consumes every
	control+mouseDown for its meta menu before dispatch (regardless of button)."
	(anEvent isMouse and: [anEvent isMouseDown]) ifFalse: [^ anEvent].
	(anEvent yellowButtonPressed and: [anEvent controlKeyPressed]) ifFalse: [^ anEvent].
	(self isOverMarksList: anEvent) ifFalse: [^ anEvent].
	^ self rewriteToControlRedClick: anEvent
]

{
	#category : #filtering,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter >> isOverMarksList: anEvent [
	"Is the event position over a SWAMarksListMorph (or a submorph of one)? Walk the
	front-most morph under the point up its owner chain."
	| target |
	World ifNil: [^ false].
	target := (World morphsAt: anEvent position unlocked: true) 
		ifEmpty: [^ false] ifNotEmpty: [:morphs | morphs first].
	[target notNil] whileTrue: [
		(target isKindOf: SWAMarksListMorph) ifTrue: [^ true].
		target := target owner].
	^ false
]

{
	#category : #filtering,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAMarksClickFilter >> rewriteToControlRedClick: anEvent [
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
