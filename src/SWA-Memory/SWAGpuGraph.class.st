"
Strip showing the bytes we have handed to the GPU, as counted by SWAGpuMemory.

	seafoam         vertex data still resident (meshes)
	shallow ocean   pixel data still resident (textures, mipmaps included)

This is the portable half of the GPU story: it is derived from our own upload
sites rather than from any driver API, so it reads the same on the desktop and
on the Quest. It undercounts, because driver-side padding, staging buffers, the
framebuffer and the swapchain are invisible to us.

For the true device figure on desktop NVIDIA, see SWAVramGraph.
"
Class {
	#name : #SWAGpuGraph,
	#superclass : #SWAStackedGraph,
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAGpuGraph >> labelString [
	| counts |
	counts := SWAGpuMemory liveCounts.
	^String streamContents: [:s |
		s nextPutAll: 'gpu mesh '; nextPutAll: (self mbString: SWAGpuMemory meshBytesLive // 1024);
		  nextPut: $(; print: counts first; nextPut: $);
		  nextPutAll: '  tex '; nextPutAll: (self mbString: SWAGpuMemory textureBytesLive // 1024);
		  nextPut: $(; print: counts second; nextPut: $);
		  nextPutAll: '  range '; nextPutAll: self rangeString]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:59'
}
SWAGpuGraph >> segments [
	^{SWAGpuMemory meshBytesLive // 1024 -> self class seafoamColor.
	  SWAGpuMemory textureBytesLive // 1024 -> self class shallowOceanColor}
]
