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
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAProcessGraph >> labelString [
	^self reading ifNil: ['process  /proc unavailable'] ifNotNil: [:r |
		String streamContents: [:s |
			s nextPutAll: 'rss '; nextPutAll: (self mbString: r first);
			  nextPutAll: '  image '; nextPutAll: (self mbString: r second);
			  nextPutAll: '  outside '; nextPutAll: (self mbString: r first - r second);
			  nextPutAll: '  range '; nextPutAll: self rangeString]]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAProcessGraph >> segments [
	"Object memory at the bottom, everything outside it stacked on top, so the
	coral band is literally the memory GcGraphMorph is blind to."
	^self reading ifNil: [#()] ifNotNil: [:r |
		| rss image |
		rss := r first.
		image := r second min: rss.
		{image -> self class deepOceanColor.
		 (rss - image) -> self class coralColor}]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:53'
}
SWAProcessGraph >> takeReading [
	"Resident and image-committed kilobytes, or nil where /proc is unavailable."
	| rss |
	rss := SWAMemoryProbe rssKB.
	rss ifNil: [^nil].
	^{rss. SWAMemoryProbe imageCommittedKB}
]
