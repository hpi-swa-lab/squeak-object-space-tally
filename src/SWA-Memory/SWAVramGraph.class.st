"
Strip showing true device VRAM, read from NVML.

	coral        VRAM in use
	pale ocean   VRAM free

The scale is pinned to the physical size of the card, so the strip is an
absolute gauge rather than an auto-ranging one and the height of the coral band
can be compared across sessions.

These are whole-device figures covering every process on the GPU, not only
Squeak. On a machine driving a desktop compositor a large constant baseline is
normal; what matters is the movement.

Availability is the point of SWAVramGraph class>>isAvailable: NVML is desktop
NVIDIA only, so SWAMemoryGraphMorph leaves this strip out on the Quest and on
AMD or Intel hardware.
"
Class {
	#name : #SWAVramGraph,
	#superclass : #SWAStackedGraph,
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAVramGraph class >> isAvailable [
	"Answer whether this strip has a data source on this machine."
	^SWAMemoryProbe nvmlAvailable
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAVramGraph >> labelString [
	| vram |
	vram := SWAMemoryProbe vramKB.
	vram ifNil: [^'vram  NVML unavailable'].
	^String streamContents: [:s |
		s nextPutAll: 'vram used '; nextPutAll: (self mbString: vram third);
		  nextPut: $/; nextPutAll: (self mbString: vram first);
		  nextPutAll: '  (whole device)']
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAVramGraph >> rangeKB [
	"Pin the axis to the physical size of the card. The card does not change
	size, so the scale settles once and the strip reads as an absolute gauge."
	^SWAMemoryProbe vramTotalKB ifNil: [0]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAVramGraph >> segments [
	| vram |
	vram := SWAMemoryProbe vramKB.
	vram ifNil: [^#()].
	^{vram third -> self class coralColor.
	  vram second -> self class paleOceanColor}
]
