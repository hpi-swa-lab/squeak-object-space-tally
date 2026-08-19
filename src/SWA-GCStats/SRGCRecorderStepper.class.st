"
Invisible desktop driver for SRGCRecorder: a zero-extent stepping Morph that sends #sampleNow to its recorder once per Morphic cycle while a recording is running, then removes itself when the recorder stops.

A stepping Morph rather than a Delay loop, because the requested granularity is one sample per Morphic cycle -- the same clock the live GC panels advance on -- so the recording lines up with what the desktop actually rendered. On the XR side the render loop calls #sampleNow directly and this morph is not used.
"
Class {
	#name : #SRGCRecorderStepper,
	#superclass : #Morph,
	#instVars : [
		'recorder'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorderStepper >> initialize [
	super initialize.
	self extent: 0 @ 0.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorderStepper >> recorder: aRecorder [
	recorder := aRecorder
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorderStepper >> step [
	(recorder isNil or: [recorder isRecording not])
		ifTrue: [^ self delete].
	recorder sampleNow
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:41'
}
SRGCRecorderStepper >> stepTime [
	"Every cycle. Morphic clamps to the world's frame rate, which is the point --
	one sample per rendered desktop frame."
	^ 0
]
