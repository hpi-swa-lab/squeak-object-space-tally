"
Reads memory figures that live OUTSIDE the Squeak object memory.

Three sources, in order of portability:

1. /proc/self/statm    -- resident set size of the whole OS process. Essentially
                          free to read (20 reads measured at 0 ms). Available on
                          Linux and Android, so it works on the Quest too.
2. /proc/self/smaps_rollup -- Pss / Private_Dirty / Anonymous breakdown. Costs
                          about 23 ms per read, so poll it sparingly, not every step.
3. NVML (libnvidia-ml) -- true VRAM figures for the whole GPU. Desktop NVIDIA
                          only; absent on the Quest. Roughly 0.7 ms per call.

Everything degrades quietly: if a source is missing the accessor answers nil
rather than signalling, so a graph can just skip that strip.

The interesting derived number is

	SWAMemoryProbe nonImageKB

which is process RSS minus the committed Squeak object memory, i.e. the VM
itself, shared libraries, the raylib/OpenGL driver and every byte we ever
allocated through FFI.
"
Class {
	#name : #SWAMemoryProbe,
	#superclass : #Object,
	#classInstVars : [
		'nvmlState',
		'nvmlDevice',
		'nvmlBuffer',
		'cachedPageSizeKB',
		'gpuSource'
	],
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:31'
}
SWAMemoryProbe class >> contentsOfProcFile: aPath limit: maxBytes [
	"Answer the first maxBytes characters of a /proc file, or nil if it cannot be
	read. Files under /proc report a size of zero, so #contentsOfEntireFile would
	answer an empty string; we have to read until the stream runs dry instead.

	Read in doubling chunks rather than one maxBytes buffer. #next: allocates its
	whole argument up front, so the old fixed-limit read cost a 4000 byte String
	to fetch a 41 byte fdinfo file and a 1 MB String to fetch 67 KB of maps.
	Almost every file here is well under a kilobyte, so start small and grow."
	| stream |
	^[stream := FileStream readOnlyFileNamed: aPath.
	  [| out chunk size |
	   out := WriteStream on: (String new: 0).
	   size := 512.
	   [out position < maxBytes
		and: [chunk := stream next: (size min: maxBytes - out position).
			chunk size > 0]]
		whileTrue: [
			out nextPutAll: chunk.
			size := size * 2 min: 65536].
	   out contents]
		ensure: [stream close]]
		on: Error do: [:e | nil]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:06'
}
SWAMemoryProbe class >> derivePageSizeKB [
	"Answer kilobytes per page by comparing the two views the kernel offers of
	the same quantity, or 4 if that is not possible. Only legal page sizes are
	accepted, so a torn read cannot install a nonsense value."
	| status residentPages rssKilobytes candidate |
	status := self contentsOfProcFile: '/proc/self/status' limit: 4000.
	status ifNil: [^4].
	rssKilobytes := nil.
	status linesDo: [:line | | parts |
		(line beginsWith: 'VmRSS:') ifTrue: [
			parts := line findTokens: ': 	'.
			parts size >= 2 ifTrue: [rssKilobytes := (parts at: 2) asNumber]]].
	rssKilobytes ifNil: [^4].
	residentPages := self statm ifNil: [^4] ifNotNil: [:fields |
		fields size >= 2 ifTrue: [fields at: 2] ifFalse: [^4]].
	residentPages isZero ifTrue: [^4].
	candidate := (rssKilobytes / residentPages) rounded.
	^(#(4 16 64) includes: candidate) ifTrue: [candidate] ifFalse: [4]
]

{
	#category : #'gpu memory',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:44'
}
SWAMemoryProbe class >> gpuDrmKB [
	"Per-process GPU kilobytes reported by the kernel DRM fdinfo interface
	(amdgpu, i915, msm, ...), or nil where no open fd reports it. Prefers the
	current drm-resident-memory key over the older drm-memory-vram so the two
	are never added together."
	| resident vram |
	resident := 0.
	vram := 0.
	[(FileDirectory on: '/proc/self/fdinfo') fileNames do: [:name |
		| text |
		text := self contentsOfProcFile: '/proc/self/fdinfo/', name limit: 4000.
		text ifNotNil: [
			text linesDo: [:line |
				| parts |
				parts := line findTokens: ': ', (String with: Character tab).
				parts size >= 2 ifTrue: [
					parts first = 'drm-resident-memory'
						ifTrue: [resident := resident + (parts at: 2) asNumber].
					parts first = 'drm-memory-vram'
						ifTrue: [vram := vram + (parts at: 2) asNumber]]]]]]
		on: Error do: [:e | ^nil].
	resident > 0 ifTrue: [^resident].
	vram > 0 ifTrue: [^vram].
	^nil
]

{
	#category : #'gpu memory',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:44'
}
SWAMemoryProbe class >> gpuKgslKB [
	"Per-process GPU kilobytes on Adreno, from this process's own /dev/kgsl-3d0
	mappings. Qualcomm's kgsl exposes no per-process sysfs node on the Quest
	kernel, and debugfs is absent, so mappings are the only driver-side source.
	Buffers the driver never maps for the CPU are not counted."
	^self mappedKBForDevice: '/dev/kgsl-3d0'
]

{
	#category : #'gpu memory',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:31'
}
SWAMemoryProbe class >> gpuProcessKB [
	"Driver-side per-process GPU kilobytes, or nil where the platform has none.
	WSL has none: /dev/dxg is not a DRM device and exposes no drm- keys, and
	nvidia-smi answers 'Not available in WDDM driver model'. There vramKB, which
	covers the whole device, is the only real signal. macOS has no /proc, but its
	unified memory puts GPU allocations into rssKB anyway."
	self gpuSource caseOf: {
		[#drm] -> [^self gpuDrmKB].
		[#kgsl] -> [^self gpuKgslKB] }
		otherwise: [^nil]
]

{
	#category : #'gpu memory',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:31'
}
SWAMemoryProbe class >> gpuSource [
	"Which driver interface, if any, reports per-process GPU memory on this
	machine: #drm, #kgsl or #none. Probed once and cached, because the answer is
	a property of the kernel and driver, not of the moment. Only the decision is
	cached; the figures themselves are re-read on every sample.

	This matters: probing #drm opens every entry in /proc/self/fdinfo, and
	probing #kgsl reads all of /proc/self/maps. Doing that per sample cost about
	2 MB of garbage four times a second to answer a question whose answer never
	changed."
	gpuSource ifNotNil: [^gpuSource].
	self gpuDrmKB ifNotNil: [^gpuSource := #drm].
	(self gpuKgslKB ifNil: [0]) > 0 ifTrue: [^gpuSource := #kgsl].
	^gpuSource := #none
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:50'
}
SWAMemoryProbe class >> imageCommittedKB [
	"Committed Squeak object memory in kilobytes: old space (live plus free)
	plus the young space in use. Same figure GcFullGraph plots."
	^((Smalltalk vmParameterAt: 1) + (Smalltalk vmParameterAt: 2)) // 1024
]

{
	#category : #'gpu memory',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 10:44'
}
SWAMemoryProbe class >> mappedKBForDevice: aDevicePath [
	"Kilobytes this process has mapped from aDevicePath, per /proc/self/maps.
	Answer nil where /proc is unavailable. Costs about 3 ms."
	| text total |
	text := self contentsOfProcFile: '/proc/self/maps' limit: 1000000.
	text ifNil: [^nil].
	total := 0.
	text linesDo: [:line |
		| parts bounds |
		parts := line findTokens: ' '.
		(parts size >= 6 and: [(parts at: 6) = aDevicePath]) ifTrue: [
			bounds := (parts at: 1) findTokens: '-'.
			bounds size = 2 ifTrue: [
				total := total
					+ (Integer readFrom: (bounds at: 2) base: 16)
					- (Integer readFrom: (bounds at: 1) base: 16)]]].
	^total // 1024
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:50'
}
SWAMemoryProbe class >> nonImageKB [
	"Resident memory that is NOT Squeak object memory, in kilobytes: the VM
	binary, shared libraries, the raylib and OpenGL driver heaps and everything
	we allocated through FFI. This is exactly the part GcGraphMorph cannot see.

	Only the resident part of the object memory counts, so clamp at zero: a
	freshly grown old space may be committed but not yet touched."
	| rss |
	rss := self rssKB.
	rss ifNil: [^nil].
	^(rss - self imageCommittedKB) max: 0
]

{
	#category : #vram,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:52'
}
SWAMemoryProbe class >> nvmlAvailable [
	"Answer whether NVML is usable, initialising it once on first ask.
	False on the Quest and on any machine without an NVIDIA driver."
	nvmlState = #ready ifTrue: [
		"Squeak nils out every ExternalAddress when the image restarts, so a
		cached handle from the previous session shows up as null. Re-init
		instead of calling NVML with a dangling pointer."
		(nvmlDevice isNil or: [nvmlDevice isNull or: [nvmlBuffer isNull]])
			ifFalse: [^true].
		self nvmlReset].
	nvmlState = #unavailable ifTrue: [^false].
	^self nvmlSetUp
]

{
	#category : #'nvml ffi',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlDeviceGetHandleByIndex: idx into: aHandlePtr [
	"Writes one opaque nvmlDevice_t pointer into aHandlePtr."
	<cdecl: long 'nvmlDeviceGetHandleByIndex_v2' (ulong void*) module: 'libnvidia-ml.so.1'>
	^ self externalCallFailed
]

{
	#category : #'nvml ffi',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlDeviceGetMemoryInfo: aDevice into: aMemPtr [
	"Fills an nvmlMemory_t: three unsigned long long, total / free / used."
	<cdecl: long 'nvmlDeviceGetMemoryInfo' (void* void*) module: 'libnvidia-ml.so.1'>
	^ self externalCallFailed
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlGiveUp [
	"Record that NVML is not usable here and answer false."
	nvmlState := #unavailable.
	nvmlDevice := nil.
	nvmlBuffer := nil.
	^false
]

{
	#category : #'nvml ffi',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlInit [
	"NVML_SUCCESS is 0. Safe to call repeatedly; NVML refcounts."
	<cdecl: long 'nvmlInit_v2' () module: 'libnvidia-ml.so.1'>
	^ self externalCallFailed
]

{
	#category : #vram,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlReset [
	"Forget the cached device handle and scratch buffer. Must be sent after an
	image restart, because the ExternalAddresses from the previous session are
	dangling. Also useful to retry after plugging in a GPU."
	nvmlState := nil.
	nvmlDevice := nil.
	nvmlBuffer := nil
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> nvmlSetUp [
	"Load NVML and cache a handle for GPU 0 plus a scratch buffer for the
	nvmlMemory_t result. Answer true on success. Any failure (missing library,
	no device, unsupported call) is recorded so we never retry per step."
	^[| handlePtr |
	  self nvmlInit = 0 ifFalse: [^self nvmlGiveUp].
	  handlePtr := ExternalAddress allocate: 8.
	  [(self nvmlDeviceGetHandleByIndex: 0 into: handlePtr) = 0
			ifFalse: [^self nvmlGiveUp].
	   nvmlDevice := ExternalAddress fromInteger: (handlePtr unsignedLongLongAt: 1)]
		ensure: [handlePtr free].
	  nvmlBuffer := ExternalAddress allocate: 24.
	  nvmlState := #ready.
	  true]
		on: Error do: [:e | self nvmlGiveUp]
]

{
	#category : #private,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:06'
}
SWAMemoryProbe class >> pageSizeKB [
	"Kilobytes per page, derived once rather than assumed.

	statm counts pages, so a wrong page size scales every figure on the process
	strip by a constant factor. 4 kB is not safe to hardcode: arm64 Linux is
	built with 4, 16 or 64 kB pages, and Android has been moving towards 16,
	which is exactly the platform the Quest sits on.

	Derived by dividing the VmRSS kilobytes in /proc/self/status by the resident
	page count in statm, so it needs no FFI. Falls back to 4 if either file is
	unreadable or the numbers look implausible."
	^cachedPageSizeKB ifNil: [cachedPageSizeKB := self derivePageSizeKB]
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:52'
}
SWAMemoryProbe class >> report [
	"A one-shot textual summary of every source. Handy in a workspace:
		SWAMemoryProbe report
	"
	^String streamContents: [:s | | vram |
		s nextPutAll: 'process RSS      '; print: self rssKB; nextPutAll: ' kB'; cr.
		s nextPutAll: 'virtual          '; print: self virtualKB; nextPutAll: ' kB'; cr.
		s nextPutAll: 'image committed  '; print: self imageCommittedKB; nextPutAll: ' kB'; cr.
		s nextPutAll: 'outside image    '; print: self nonImageKB; nextPutAll: ' kB'; cr.
		vram := self vramKB.
		vram
			ifNil: [s nextPutAll: 'VRAM             not available (no NVML)'; cr]
			ifNotNil: [
				s nextPutAll: 'VRAM used        '; print: vram third; nextPutAll: ' kB of ';
				  print: vram first; nextPutAll: ' kB'; cr]]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 15:31'
}
SWAMemoryProbe class >> reset [
	"Drop every cached decision. Send this after moving an image to a different
	machine, where both the page size and the presence of a GPU may differ."
	cachedPageSizeKB := nil.
	gpuSource := nil.
	self nvmlReset
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:50'
}
SWAMemoryProbe class >> rssKB [
	"Resident set size of the whole OS process, in kilobytes. Answer nil where
	/proc is not available. Cheap enough to call on every graph step."
	| fields |
	fields := self statm.
	(fields isNil or: [fields size < 2]) ifTrue: [^nil].
	^(fields at: 2) * self pageSizeKB
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> smapsRollup [
	"Answer a Dictionary of key -> kilobytes from /proc/self/smaps_rollup, or nil.
	Keys are strings such as 'Rss', 'Pss', 'Private_Dirty', 'Anonymous'.

	Costs roughly 23 ms, so this is for on-demand inspection, not for stepping."
	| text result |
	text := self contentsOfProcFile: '/proc/self/smaps_rollup' limit: 4000.
	text ifNil: [^nil].
	result := Dictionary new.
	text linesDo: [:line | | parts |
		parts := line findTokens: ': 	'.
		(parts size >= 2 and: [parts last = 'kB'])
			ifTrue: [result at: parts first put: (parts at: 2) asNumber]].
	^result isEmpty ifTrue: [nil] ifFalse: [result]
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> statm [
	"Answer the seven page counts of /proc/self/statm as an Array, or nil.
	The fields are: size, resident, shared, text, lib, data, dirty."
	| text |
	text := self contentsOfProcFile: '/proc/self/statm' limit: 200.
	text ifNil: [^nil].
	^[(text findTokens: ' ', String cr, String lf) collect: [:each | each asNumber]]
		on: Error do: [:e | nil]
]

{
	#category : #'process memory',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:50'
}
SWAMemoryProbe class >> virtualKB [
	"Total mapped address space, in kilobytes. Much larger than rssKB because it
	includes reserved-but-untouched regions."
	| fields |
	fields := self statm.
	fields ifNil: [^nil].
	^fields first * self pageSizeKB
]

{
	#category : #vram,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> vramKB [
	"Answer an Array of #(totalKB freeKB usedKB) for GPU 0, or nil when NVML is
	not available. These are whole-device figures covering every process on the
	GPU, not just us. Roughly 0.7 ms per call."
	self nvmlAvailable ifFalse: [^nil].
	^[(self nvmlDeviceGetMemoryInfo: nvmlDevice into: nvmlBuffer) = 0
		ifFalse: [self nvmlGiveUp. nil]
		ifTrue: [{(nvmlBuffer unsignedLongLongAt: 1) // 1024.
				 (nvmlBuffer unsignedLongLongAt: 9) // 1024.
				 (nvmlBuffer unsignedLongLongAt: 17) // 1024}]]
		on: Error do: [:e | self nvmlGiveUp. nil]
]

{
	#category : #vram,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> vramTotalKB [
	"Total device VRAM in kilobytes, or nil."
	^self vramKB ifNotNil: [:triple | triple first]
]

{
	#category : #vram,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 17:51'
}
SWAMemoryProbe class >> vramUsedKB [
	"Device VRAM in use by all processes, in kilobytes, or nil."
	^self vramKB ifNotNil: [:triple | triple third]
]
