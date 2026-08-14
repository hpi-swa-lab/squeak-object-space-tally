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
		'emaScavengeMs'
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
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:08'
}
SRGCMemGraph >> labelString [
	"Drop the free-space field (removed from the graph); keep old, young/eden, range."

	^ String streamContents: [:s | | avg |
		s nextPutAll: 'old '; nextPutAll: (self mbString: self usedOldSpace);
		  nextPutAll: '  young '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace);
		  nextPutAll: '  range '; nextPutAll: (self mbString: scale * graph height).
		avg := self averageScavengeMs.
		avg ifNotNil: [
			s nextPutAll: '  scav '; nextPutAll: (avg asFloat printShowingDecimalPlaces: 2); nextPutAll: 'ms']]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:07'
}
SRGCMemGraph >> updateGraph [
	"One column: used old space (deepOcean) at the global scale, then a young-space
	band (seafoam) plotted against eden capacity so the scavenge sawtooth is visible.
	No free-space band. Mirrors GcFullGraph but swaps free -> young-scaled-to-eden."

	| rescaled height oldTop bandH youngFill youngTop scavenges scavengeMs countDelta |
	rescaled := self updateScale.
	height := graph height.

	"p9 = scavenge (incremental GC) count, p10 = cumulative scavenge ms. The count
	ticks on exactly the frame young space is razored. On a scavenge frame, fold this
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
			ifNotNil: [emaScavengeMs * (1 - alpha) + (sample * alpha)]].
	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	self graph shiftBy: 2.
	self graph
		drawFrom: 0 to: height
		color: (rescaled ifTrue: [self class slateColor] ifFalse: [self class backgroundColor])
		width: 2.

	"Used old space, global scale (same as the desktop graph)."
	oldTop := (self usedOldSpace // scale) min: height.
	self graph drawFrom: 0 to: oldTop color: self class deepOceanColor width: 2.

	"Young space filling its own band above old space: height proportional to eden
	occupancy, so it climbs as eden fills and drops on a scavenge."
	bandH := (self class youngBandHeight min: height - oldTop) max: 0.
	youngFill := self youngSpace isZero
		ifTrue: [0]
		ifFalse: [(self usedYoungSpace * bandH // self youngSpace) min: bandH].
	youngTop := (oldTop + youngFill) min: height.
	self graph drawFrom: oldTop to: youngTop color: self class seafoamColor width: 2
]
