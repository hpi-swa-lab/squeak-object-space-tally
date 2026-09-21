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
		'lastCount',
		'ticker'
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
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:05'
}
SRGCChangesGraph >> ceilingFloor [
	"5 ms of change span fills the lane, and above that the ceiling moves. A burst of
	recompilation runs to hundreds of milliseconds, which on the fixed scale was a
	flat-topped bar indistinguishable from any other flat-topped bar."

	^ self class maxSpanMicros.
]

{
	#category : #'auto scale',
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:07'
}
SRGCChangesGraph >> drawRingColumnAt: x value: span flags: flagByte height: h [
	"A change frame keeps its 1px minimum through a rescale, so an isolated edit whose
	span rounds below a pixel does not vanish when the scale grows."

	| bar fired |
	fired := (flagByte bitAnd: 1) ~= 0.
	bar := (span * h // self ceiling) min: h.
	fired ifTrue: [bar := bar max: 1].
	graph form
		fill: (x @ 0 corner: (x + 2) @ h)
		rule: Form over
		fillColor: (fired ifTrue: [self class shallowOceanColor] ifFalse: [self class backgroundColor]).
	bar <= 0 ifTrue: [^ self].
	graph form
		fill: ((x + 1) @ (h - bar) corner: (x + 2) @ h)
		rule: Form over
		fillColor: self class coralColor.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:07'
}
SRGCChangesGraph >> labelString [
	| s |
	s := self labelStreamReset.
	s nextPutAll: 'changes '; print: (totalChanges ifNil: [0]).
	(lastCount notNil and: [lastCount > 0]) ifTrue: [
		s nextPutAll: '  (+'; print: lastCount; nextPutAll: ' this frame)'].
	self ceiling > self ceilingFloor ifTrue: [
		s nextPutAll: '  full '; print: self ceiling // 1000; nextPutAll: 'ms'].
	self ticker isArmed ifFalse: [s nextPutAll: '  [disarmed]'].
	^ s contents
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:16'
}
SRGCChangesGraph >> release [
	"SystemChangeNotifier keeps a strong reference to an armed ticker."

	super release.
	ticker ifNotNil: [:t | t stop. ticker := nil].
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:15'
}
SRGCChangesGraph >> ticker [
	"Started on first use rather than from an open hook: the desktop Morph and the XR
	panel have no hook in common, and the lane has data from its first frame either way."

	^ ticker ifNil: [ticker := SRChangeTicker new start; yourself].
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 9/21/2026 12:06'
}
SRGCChangesGraph >> updateGraph [
	"One frame: drain the ticker, plot the change span as the bar, colour the frame when
	any change fired. Cheap -- one drain, one addValue:, no allocation/GC probing."
	| ticker n span height scaled fired |
	ticker := self ticker.
	ticker frameCountAndSpanMicrosThenReset.
	n := ticker drainCount.
	span := ticker drainSpan.
	lastCount := n.
	totalChanges := (totalChanges ifNil: [0]) + n.
	height := self graph height.
	self noteCeilingValue: span.
	self updateCeiling ifTrue: [self repaintColumns].
	scaled := (span * height // self ceiling) min: height.
	fired := n > 0.
	"A change frame shows at least 1px even when its span rounds below a pixel, so a
	single isolated edit is never invisible."
	fired ifTrue: [scaled := scaled max: 1].
	self pushColumn: span flags: (fired ifTrue: [1] ifFalse: [0]).
	self graph
		addValue: scaled
		color: self class coralColor
		bgColor: (fired ifTrue: [self class shallowOceanColor] ifFalse: [self class backgroundColor])
]
