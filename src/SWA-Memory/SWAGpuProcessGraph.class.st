"
A strip showing GPU memory attributed to this process by the graphics driver, as opposed to a tally the image keeps of its own uploads.

The number comes from SWAMemoryProbe gpuProcessKB: DRM fdinfo where the kernel offers it, otherwise the process's own /dev/kgsl-3d0 mappings on Adreno. Both are lower bounds, since neither counts memory the driver holds without mapping it for the CPU.

The strip is absent on platforms with no per-process source, which includes WSL. There SWAVramGraph, which reads the whole device through NVML, is the only real signal.

Like the other SWAStackedGraph strips this advances on its own interval, so its columns do not line up horizontally with the fps and object memory strips above it.
"
Class {
	#name : #SWAGpuProcessGraph,
	#superclass : #SWAStackedGraph,
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:44'
}
SWAGpuProcessGraph class >> isAvailable [
	"Answer whether this strip has a data source on this machine."
	^SWAMemoryProbe gpuProcessKB notNil
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAGpuProcessGraph >> labelString [
	^self reading
		ifNil: ['gpu  no per-process source']
		ifNotNil: [:kb | 'gpu mapped ', (self mbString: kb)]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:54'
}
SWAGpuProcessGraph >> segments [
	^self reading
		ifNil: [#()]
		ifNotNil: [:kb | {kb -> self class seafoamColor}]
]

{
	#category : #plotting,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:53'
}
SWAGpuProcessGraph >> takeReading [
	^SWAMemoryProbe gpuProcessKB
]
