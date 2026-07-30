"
Strip showing the resident memory of the whole OS process, split into the part
GcGraphMorph already covers and the part it cannot see.

	deep ocean   committed Squeak object memory
	coral        everything else that is resident: the VM binary, shared
	             libraries, the raylib and OpenGL driver heaps, and every byte
	             allocated through FFI

Reads /proc/self/statm, which costs about 0.08 ms, so it is safe on every step.
On a platform without /proc the strip draws nothing and the label says so.
"
Class {
	#name : #SWAProcessGraph,
	#superclass : #SWAStackedGraph,
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAProcessGraph >> labelString [
	| rss |
	rss := SWAMemoryProbe rssKB.
	rss ifNil: [^'process  /proc unavailable'].
	^String streamContents: [:s |
		s nextPutAll: 'rss '; nextPutAll: (self mbString: rss);
		  nextPutAll: '  image '; nextPutAll: (self mbString: SWAMemoryProbe imageCommittedKB);
		  nextPutAll: '  outside '; nextPutAll: (self mbString: SWAMemoryProbe nonImageKB);
		  nextPutAll: '  range '; nextPutAll: self rangeString]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAProcessGraph >> segments [
	"Object memory at the bottom, everything outside it stacked on top, so the
	coral band is literally the memory GcGraphMorph is blind to."
	| rss image |
	rss := SWAMemoryProbe rssKB.
	rss ifNil: [^#()].
	image := SWAMemoryProbe imageCommittedKB min: rss.
	^{image -> self class deepOceanColor.
	   (rss - image) -> self class coralColor}
]
