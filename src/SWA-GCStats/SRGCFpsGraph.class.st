"
GcGraph whose FPS bars are scaled so maxFps maps to the full graph height, instead of the stock 1 fps = 1 pixel (which saturates any graph shorter than the frame rate). Only the plotted bar is scaled; the label still prints the true fps. Used by SRGCStats so its short (50px) FPS strip shows a meaningful curve up to maxFps rather than a solid block.
"
Class {
	#name : #SRGCFpsGraph,
	#superclass : #GcGraph,
	#instVars : [
		'emaFps',
		'lastScavengeMs',
		'lastScavengeCount'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph class >> emaAlpha [
	"Smoothing factor for the label's exponential moving average of fps.
	~0.1 is about a 10-frame time constant: stable to read, still tracks changes."

	^ 0.1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:36'
}
SRGCFpsGraph class >> maxFps [
	"Full graph height corresponds to this frame rate."

	^ 120
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 14:57'
}
SRGCFpsGraph class >> maxFrameMs [
	"Frame time in ms that fills the graph height. 33ms (a 30fps floor) means a smooth
	frame is a short bar and a hitch spikes toward the top."
	^ 33
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph class >> scavengeColor [
	"Coral fills the portion of a frame's bar taken by that frame's scavenge time, so
	the young-space GC hitch is visible inside the frame-time bar."
	^ self coralColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph class >> scavengeTimeColor [
	"Darker coral for the portion of a scavenge-frame bar that was the actual scavenge
	time, drawn over the coral whole-bar."
	^ self coralColor muchDarker
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph >> drawScavengePortion: pixels [
	"Fill the bottom `pixels` of the newest bar (the rightmost 1px column, as drawn by
	FormGraph>>addValue:color:bgColor:) with the darker scavenge colour."

	| form w h |
	form := self graph form.
	w := form width.
	h := form height.
	form
		fill: ((w - 1 @ (h - pixels)) corner: (w @ h))
		rule: Form over
		fillColor: self class scavengeTimeColor
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> fps [
	"The label reads this: the smoothed (EMA) fps, rounded. The graph uses rawFps."

	^ (emaFps ifNil: [self rawFps]) rounded
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:08'
}
SRGCFpsGraph >> labelString [
	"As GcGraph>>labelString, but print the frame time in ms next to fps. Derived from
	the same EMA as fps (1000/fps) so the two read consistently and neither jitters."

	| ms |
	ms := (emaFps notNil and: [emaFps > 0]) ifTrue: [1000 / emaFps] ifFalse: [nil].
	^ String streamContents: [:s |
		s nextPutAll: 'fps '; print: self fps.
		ms ifNotNil: [s nextPutAll: '  '; nextPutAll: (ms asFloat printShowingDecimalPlaces: 1); nextPutAll: 'ms'].
		s nextPutAll: '  fullGC '; print: (Smalltalk vmParameterAt: 7);
		  nextPutAll: '  scavenge '; print: (Smalltalk vmParameterAt: 9);
		  nextPutAll: '  rootTable '; print: self rootTableSize]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> rawFps [
	"Instantaneous fps for the graph bar (one frame's delta), before smoothing."

	^ super fps
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:10'
}
SRGCFpsGraph >> updateGraph [
	"Bar = this frame's time in ms (scaled so maxFrameMs fills the height). The bottom
	darker portion of the bar is the frame's scavenge time, so you see how much of the
	frame the young-space GC ate. Scavenge *frames* are shown in the FPS bar itself, so
	no background colouring here."

	| fps alpha frameMs scaled scavengeMs scavMs scavScaled height scavenges scavenged |
	fps := self rawFps.
	"Fold this frame's instantaneous fps into the label's EMA (the label reads fps)."
	alpha := self class emaAlpha.
	emaFps := emaFps
		ifNil: [fps]
		ifNotNil: [emaFps * (1 - alpha) + (fps * alpha)].

	height := self graph height.
	frameMs := deltaTime ifNil: [0].
	scaled := (frameMs * height / self class maxFrameMs) rounded min: height.

	"p9 = scavenge count, p10 = cumulative scavenge ms. The count reliably marks a
	razor frame; the ms delta sizes the coloured portion (a razor shows at least 1px
	even when its time rounds below a pixel)."
	scavenges := Smalltalk vmParameterAt: 9.
	scavengeMs := Smalltalk vmParameterAt: 10.
	scavenged := lastScavengeCount notNil and: [scavenges > lastScavengeCount].
	scavMs := lastScavengeMs ifNil: [0] ifNotNil: [scavengeMs - lastScavengeMs].
	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	"A scavenge frame colours the whole bar coral; other frames are the plain bar."
	self graph
		addValue: scaled
		color: (scavenged ifTrue: [self class scavengeColor] ifFalse: [self class deepOceanColor])
		bgColor: self class backgroundColor.

	"On a scavenge frame, overlay the actual scavenge-time portion at the bottom in a
	darker coral (at least 1px, since a single scavenge is often sub-ms)."
	scavenged ifTrue: [
		scavScaled := ((scavMs * height / self class maxFrameMs) rounded min: scaled) max: 1.
		self drawScavengePortion: scavScaled]
]
