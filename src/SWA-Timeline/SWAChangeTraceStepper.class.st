"
Invisible stepper that pushes a live SWAChangeTraceRecorder into its
SWAChangeTraceMorph as edits arrive.

A zero-extent morph parented on the view so it steps with it and dies with it. It
re-seats the view's rolling root only when the recorder's event count actually
changed, so a quiescent trace costs one integer compare per frame, not a relayout.

Mirrors SRGCRecorderStepper, the same trick the GC recorder uses.
"
Class {
	#name : #SWAChangeTraceStepper,
	#superclass : #Morph,
	#instVars : [
		'recorder',
		'lastCount'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:07'
}
SWAChangeTraceStepper >> initialize [
	super initialize.
	self extent: 0 @ 0.
	lastCount := -1.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:07'
}
SWAChangeTraceStepper >> recorder: aRecorder [
	recorder := aRecorder.
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:07'
}
SWAChangeTraceStepper >> step [
	| count |
	recorder ifNil: [^self delete].
	count := recorder root children size.
	count = lastCount ifTrue: [^self].
	lastCount := count.
	self owner
		refreshFromRoot: recorder root
		info: recorder infoString.
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:07'
}
SWAChangeTraceStepper >> stepTime [
	^250
]
