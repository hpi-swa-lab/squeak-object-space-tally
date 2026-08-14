"
GcFullGraph variant for SRGCStats: the free-space band (which barely moves) is replaced by young space, and young is plotted against its OWN eden capacity so the scavenge sawtooth is actually visible. The shared desktop GcFullGraph plots young at the global memory scale, where a few MB of eden is under one pixel and looks static.

Bands, bottom to top: used old space (deepOcean) at the global scale, then a young-space band (seafoam) whose height is usedYoungSpace/youngSpace of a fixed band, so a filling eden climbs and a scavenge drops it. No free-space band.
"
Class {
	#name : #SRGCMemGraph,
	#superclass : #GcFullGraph,
	#instVars : [
		'lastScavengeCount',
		'lastScavengeMs',
		'emaScavengeMs',
		'oldSpaceMax',
		'survivorYoung'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 14:54'
}
SRGCMemGraph class >> scavengeEmaAlpha [
	"Smoothing factor for the exponential moving average of scavenge time. The sample
	cadence is one per scavenge (not per frame), so ~0.1 is about a 10-scavenge time
	constant: stable enough to read a sub-ms value, still tracks a changing load."
	^ 0.1
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:04'
}
SRGCMemGraph class >> survivorColor [
	"Deeper seafoam for the survivor baseline -- the young-space bytes still live right
	after the last scavenge, i.e. the floor the sawtooth drops to."
	^ self seafoamColor muchDarker
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:46'
}
SRGCMemGraph class >> youngBandHeight [
	"Pixels reserved above the old-space band for the young-space fill indicator.
	Full eden fills this whole band; a scavenge drops it toward the band's base."

	^ 40
]

{
	#category : #'scavenge timing',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 14:55'
}
SRGCMemGraph >> averageScavengeMs [
	"Mean milliseconds per scavenge over the window, or nil if no scavenge has been
	seen yet. A single scavenge is sub-millisecond, so only the average over many is
	meaningful -- per-frame p10 deltas read 0."

	^ emaScavengeMs
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:39'
}
SRGCMemGraph >> labelString [
	"old (with its lane's max) and young/eden, plus the moving-average scavenge time."

	^ String streamContents: [:s | | avg |
		s nextPutAll: 'old '; nextPutAll: (self mbString: self usedOldSpace);
		  nextPut: $/; nextPutAll: (self mbString: (oldSpaceMax ifNil: [self usedOldSpace]));
		  nextPutAll: '  young '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace).
		avg := self averageScavengeMs.
		avg ifNotNil: [
			s nextPutAll: '  scav '; nextPutAll: (avg asFloat printShowingDecimalPlaces: 2); nextPutAll: 'ms']]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:04'
}
SRGCMemGraph >> updateGraph [
	"Two independent lanes so both are readable despite the huge old/young ratio:
	old space on the bottom (scaled to its own running max), the young-space scavenge
	sawtooth on top (scaled to eden), a slate divider between."

	| height youngLaneH oldLaneH youngFill oldFill scavenges scavengeMs countDelta |
	height := graph height.

	"p9 = scavenge count, p10 = cumulative scavenge ms. On a scavenge frame, fold this
	frame's ms-per-scavenge into an EMA (a single scavenge is sub-ms, so only the
	smoothed average is meaningful; per-frame p10 deltas often read 0)."
	scavenges := Smalltalk vmParameterAt: 9.
	scavengeMs := Smalltalk vmParameterAt: 10.
	countDelta := lastScavengeCount ifNil: [0] ifNotNil: [scavenges - lastScavengeCount].
	countDelta > 0 ifTrue: [ | alpha sample |
		alpha := self class scavengeEmaAlpha.
		sample := (scavengeMs - lastScavengeMs) / countDelta.
		emaScavengeMs := emaScavengeMs
			ifNil: [sample]
			ifNotNil: [emaScavengeMs * (1 - alpha) + (sample * alpha)].
		"Right after a scavenge, usedYoung is essentially the survivor bytes -- the floor
		the sawtooth drops to. Capture it as the survivor baseline."
		survivorYoung := self usedYoungSpace].
	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	"Lanes split proportionally so they scale with the (supersampled) form height."
	oldLaneH := (height * 55 // 100) min: height - 2.
	youngLaneH := height - oldLaneH - 1.

	"Old space auto-scales to its own running max, so its changes fill the lane rather
	than pinning at the top of a global scale."
	oldSpaceMax := (oldSpaceMax ifNil: [self usedOldSpace max: 1]) max: self usedOldSpace.

	self graph shiftBy: 2.
	self graph drawFrom: 0 to: height color: self class backgroundColor width: 2.

	"Bottom lane: old space, scaled to its own max within the lane."
	oldFill := (self usedOldSpace * oldLaneH // oldSpaceMax) min: oldLaneH.
	self graph drawFrom: 0 to: oldFill color: self class deepOceanColor width: 2.

	"Divider."
	self graph drawFrom: oldLaneH to: oldLaneH + 1 color: self class slateColor width: 2.

	"Top lane: young space vs eden capacity -- the scavenge sawtooth. The bottom of the
	band, up to the last scavenge's survivor level, is drawn deeper; fresh allocation
	above it is normal seafoam."
	youngFill := self youngSpace isZero
		ifTrue: [0]
		ifFalse: [(self usedYoungSpace * youngLaneH // self youngSpace) min: youngLaneH].
	self graph
		drawFrom: oldLaneH + 1
		to: oldLaneH + 1 + youngFill
		color: self class seafoamColor width: 2.

	survivorYoung ifNotNil: [ | survFill |
		survFill := self youngSpace isZero
			ifTrue: [0]
			ifFalse: [(survivorYoung * youngLaneH // self youngSpace) min: youngFill].
		self graph
			drawFrom: oldLaneH + 1
			to: oldLaneH + 1 + survFill
			color: self class survivorColor width: 2]
]
