"
The zoomed-in old-space lane of the GC Stats panel, split out as its own toggleable
graph: used old space at the SAME kB/pixel as the young lane (eden per lane height) over
a whole-span floor that tracks so used stays in view. The resolution never changes; a red
vertical mark is drawn in the newest column whenever the floor rebases (a lane movement).
"
Class {
	#name : #SRGCOldZoomGraph,
	#superclass : #GcFullGraph,
	#instVars : [
		'oldWindowMin',
		'oldWindowSpan',
		'lastZoomFloor'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:27'
}
SRGCOldZoomGraph >> labelString [
	| s |
	s := self labelStreamReset.
	s nextPutAll: 'old-zoom '. self mbPrint: self usedOldSpace on: s.
	s nextPutAll: ' ['. self mbPrint: (oldWindowMin ifNil: [0]) on: s.
	s nextPut: $-. self mbPrint: (oldWindowMin ifNil: [0]) + (oldWindowSpan ifNil: [0]) on: s.
	s nextPut: $].
	^ s contents
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:00'
}
SRGCOldZoomGraph >> updateGraph [
	"Zoomed-in old space, full height, at the young lane's resolution (eden per lane
	height). The span never changes; the floor tracks in whole spans so used stays in view.
	A red vertical mark in the newest column whenever the floor rebases (a lane movement)."
	| height used span zoomFill |
	height := graph height.
	used := self usedOldSpace.

	"Resolution = eden spread over this lane's height (same kB/pixel as the young lane)."
	span := (self youngSpace max: 1) max: 1.
	oldWindowSpan := span.
	oldWindowMin ifNil: [oldWindowMin := used // span * span].
	[used >= (oldWindowMin + span)] whileTrue: [oldWindowMin := oldWindowMin + span].
	[used < oldWindowMin] whileTrue: [oldWindowMin := oldWindowMin - span].

	self graph shiftBy: 2.
	self graph drawFrom: 0 to: height color: self class backgroundColor width: 2.
	zoomFill := (((used - oldWindowMin) max: 0) * height // span) min: height.
	self graph drawFrom: 0 to: zoomFill color: self class deepOceanColor width: 2.
	(lastZoomFloor notNil and: [lastZoomFloor ~= oldWindowMin]) ifTrue: [
		self graph drawFrom: 0 to: height color: self class zoomMarkColor width: 2].
	lastZoomFloor := oldWindowMin
]
