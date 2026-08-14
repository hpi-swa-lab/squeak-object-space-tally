"
GcFullGraph variant for SRGCStats: the free-space band (which barely moves) is replaced by young space, and young is plotted against its OWN eden capacity so the scavenge sawtooth is actually visible. The shared desktop GcFullGraph plots young at the global memory scale, where a few MB of eden is under one pixel and looks static.

Bands, bottom to top: used old space (deepOcean) at the global scale, then a young-space band (seafoam) whose height is usedYoungSpace/youngSpace of a fixed band, so a filling eden climbs and a scavenge drops it. No free-space band.
"
Class {
	#name : #SRGCMemGraph,
	#superclass : #GcFullGraph,
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:47'
}
SRGCMemGraph >> labelString [
	"Drop the free-space field (removed from the graph); keep old, young/eden, range."

	^ String streamContents: [:s |
		s nextPutAll: 'old '; nextPutAll: (self mbString: self usedOldSpace);
		  nextPutAll: '  young '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace);
		  nextPutAll: '  range '; nextPutAll: (self mbString: scale * graph height)]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:46'
}
SRGCMemGraph >> updateGraph [
	"One column: used old space (deepOcean) at the global scale, then a young-space
	band (seafoam) plotted against eden capacity so the scavenge sawtooth is visible.
	No free-space band. Mirrors GcFullGraph but swaps free -> young-scaled-to-eden."

	| rescaled height oldTop bandH youngFill youngTop |
	rescaled := self updateScale.
	height := graph height.

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
