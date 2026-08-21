"
The system-changes lane of the GC-stats panel.

Sits alongside the fps / memory / survivor graphs and scrolls at frame rate through the
same FormGraph mechanism. Each frame it drains SRChangeTicker: the bar height is the
first-to-last change span this frame (microseconds, scaled), and a frame in which any
change fired is coloured so a burst of edits stands out as a coloured cluster.

Deliberately does NOT read the allocation counter or trigger any GC -- the whole point
of this lane, versus the live SWAChangeTraceRecorder, is to mark and time system changes
without perturbing the frame it is measuring. Magnitude/subscriber/byte detail is the
prerecord-then-display SWAChangeTrace timeline's job, not this overlay's.
"
Class {
	#name : #SRGCChangesGraph,
	#superclass : #GcGraph,
	#instVars : [
		'totalChanges',
		'lastCount'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:00'
}
SRGCChangesGraph class >> maxSpanMicros [
	"Full-height span. A frame whose changes take longer than this pins the bar; edits
	rarely exceed a few ms of first-to-last span within one frame."
	^ 5000
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:27'
}
SRGCChangesGraph >> labelString [
	| s |
	s := self labelStreamReset.
	s nextPutAll: 'changes '; print: (totalChanges ifNil: [0]).
	(lastCount notNil and: [lastCount > 0]) ifTrue: [
		s nextPutAll: '  (+'; print: lastCount; nextPutAll: ' this frame)'].
	SRChangeTicker current isArmed ifFalse: [s nextPutAll: '  [disarmed]'].
	^ s contents
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 14:09'
}
SRGCChangesGraph >> updateGraph [
	"One frame: drain the ticker, plot the change span as the bar, colour the frame when
	any change fired. Cheap -- one drain, one addValue:, no allocation/GC probing."
	| ticker n span height scaled fired |
	ticker := SRChangeTicker current.
	ticker frameCountAndSpanMicrosThenReset.
	n := ticker drainCount.
	span := ticker drainSpan.
	lastCount := n.
	totalChanges := (totalChanges ifNil: [0]) + n.
	height := self graph height.
	scaled := (span * height // self class maxSpanMicros) min: height.
	fired := n > 0.
	"A change frame shows at least 1px even when its span rounds below a pixel, so a
	single isolated edit is never invisible."
	fired ifTrue: [scaled := scaled max: 1].
	self graph
		addValue: scaled
		color: self class coralColor
		bgColor: (fired ifTrue: [self class shallowOceanColor] ifFalse: [self class backgroundColor])
]
