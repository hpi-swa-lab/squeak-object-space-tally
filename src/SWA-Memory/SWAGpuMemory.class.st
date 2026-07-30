"
Tally of the bytes we hand to the GPU through raylib.

There is no portable API that asks a GPU ""how much have I allocated"", and on the
Quest there is no API at all, so we count what we upload ourselves. The image
only has two upload sites:

	SRMeshSourceRaw>>createInternalMesh    -> Raylib uploadMesh:dynamic:
	SRTexture>>buildAndUploadRlTexture     -> Raylib loadTextureFromImage:

Both notify this class. The figures are therefore exact for our own vertex and
pixel data and ignore driver overhead (padding, staging buffers, the framebuffer
and swapchain), so treat them as a lower bound.

Uploads and releases are counted separately on purpose. The difference

	SWAGpuMemory meshBytesLive

is the amount currently resident on the GPU, and watching it only ever grow is
how you notice that nothing releases its meshes.

	SWAGpuMemory report
	SWAGpuMemory reset
"
Class {
	#name : #SWAGpuMemory,
	#superclass : #Object,
	#classInstVars : [
		'meshBytesUploaded',
		'meshBytesReleased',
		'meshUploads',
		'meshReleases',
		'textureBytesUploaded',
		'textureBytesReleased',
		'textureUploads',
		'textureReleases'
	],
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> bytesForMeshSource: aMeshSource [
	"Bytes of vertex data that uploadMesh: copies into VBOs. Sums the actual
	Smalltalk arrays rather than recomputing from the vertex count, so it stays
	correct when an attribute is absent."
	| total |
	total := 0.
	#(vertices normals texcoords colors indices) do: [:each |
		(aMeshSource perform: each) ifNotNil: [:array |
			total := total + ([array byteSize] on: Error do: [:e | 0])]].
	^total
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> bytesForTextureWidth: w height: h mipmapped: aBoolean [
	"Four bytes per texel. A full mipmap chain adds one third on top, since
	1 + 1/4 + 1/16 + ... converges to 4/3."
	| base |
	base := w * h * 4.
	^aBoolean ifTrue: [base * 4 // 3] ifFalse: [base]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> liveCounts [
	"Answer #(meshes textures) still resident, by upload minus release count."
	meshUploads ifNil: [self reset].
	^{meshUploads - meshReleases. textureUploads - textureReleases}
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> meshBytesLive [
	meshBytesUploaded ifNil: [self reset].
	^meshBytesUploaded - meshBytesReleased
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> noteMeshReleased: byteCount [
	meshBytesReleased ifNil: [self reset].
	meshBytesReleased := meshBytesReleased + byteCount.
	meshReleases := meshReleases + 1
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> noteMeshUploaded: byteCount [
	"Called from the upload site. Must never fail: a broken counter may not take
	the render loop down with it."
	meshBytesUploaded ifNil: [self reset].
	meshBytesUploaded := meshBytesUploaded + byteCount.
	meshUploads := meshUploads + 1
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:58'
}
SWAGpuMemory class >> noteMeshUploadedFor: aMeshSource [
	"Measure and tally in one step, swallowing any error.

	This is called from the live render path, so accounting is not allowed to
	raise: a mistake here would otherwise surface as a walkback in the middle of
	a frame. Answer self so the caller can ignore the result."
	[self noteMeshUploaded: (self bytesForMeshSource: aMeshSource)]
		on: Error do: [:e | nil]
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> noteTextureReleased: byteCount [
	textureBytesReleased ifNil: [self reset].
	textureBytesReleased := textureBytesReleased + byteCount.
	textureReleases := textureReleases + 1
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> noteTextureUploaded: byteCount [
	textureBytesUploaded ifNil: [self reset].
	textureBytesUploaded := textureBytesUploaded + byteCount.
	textureUploads := textureUploads + 1
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:58'
}
SWAGpuMemory class >> noteTextureUploadedWidth: w height: h mipmapped: aBoolean [
	"Measure and tally in one step, swallowing any error. See the comment in
	#noteMeshUploadedFor: for why this may not signal."
	[self noteTextureUploaded:
		(self bytesForTextureWidth: w height: h mipmapped: aBoolean)]
		on: Error do: [:e | nil]
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> report [
	"Textual summary. A releases count of zero next to a large uploaded figure
	means those bytes are stranded on the GPU."
	meshUploads ifNil: [self reset].
	^String streamContents: [:s |
		s nextPutAll: 'meshes    '; print: meshUploads; nextPutAll: ' uploaded, ';
		  print: meshReleases; nextPutAll: ' released, live ';
		  print: self meshBytesLive // 1024; nextPutAll: ' kB'; cr.
		s nextPutAll: 'textures  '; print: textureUploads; nextPutAll: ' uploaded, ';
		  print: textureReleases; nextPutAll: ' released, live ';
		  print: self textureBytesLive // 1024; nextPutAll: ' kB'; cr.
		s nextPutAll: 'total live '; print: self totalBytesLive // 1024; nextPutAll: ' kB'; cr]
]

{
	#category : #accounting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> reset [
	"Zero every counter. Note this loses track of what is already resident on the
	GPU, so the live figures become a delta from now on."
	meshBytesUploaded := meshBytesReleased := meshUploads := meshReleases := 0.
	textureBytesUploaded := textureBytesReleased := textureUploads := textureReleases := 0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> textureBytesLive [
	textureBytesUploaded ifNil: [self reset].
	^textureBytesUploaded - textureBytesReleased
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:53'
}
SWAGpuMemory class >> totalBytesLive [
	^self meshBytesLive + self textureBytesLive
]
