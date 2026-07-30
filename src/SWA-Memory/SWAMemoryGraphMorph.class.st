"
GcGraphMorph widened to cover memory outside the Squeak object memory.

	SWAMemoryGraphMorph open

Where GcGraphMorph stacks two fixed strips, this holds a collection of them and
draws each with its label, so strips can be added or dropped per platform:

	GcGraph          fps, with the column tinted on full GC and on tenure
	GcFullGraph      committed object memory: live old, young, free
	SWAProcessGraph  process RSS split into object memory and everything else
	SWAGpuGraph      bytes we uploaded to the GPU, meshes and textures
	SWAVramGraph     true device VRAM, only when NVML is present

The first two are the originals, reused unchanged. The last is dropped on any
machine without desktop NVIDIA, which is what lets the morph run on the Quest.

Beware that the strips do not share a time axis. The morph steps as fast as
morphic allows, which is what makes the fps reading meaningful, so the top two
strips advance once per frame. The three below are backed by probes and throttle
themselves to one column every 250 ms, so they show a much longer history in the
same width. Line up an event between an upper and a lower strip only by the
label, never by horizontal position.

Cost per probed column is about 0.08 ms for /proc/self/statm and 0.26 ms for
NVML.
"
Class {
	#name : #SWAMemoryGraphMorph,
	#superclass : #Morph,
	#instVars : [
		'strips'
	],
	#category : #'SWA-Memory-Graph',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:03'
}
SWAMemoryGraphMorph class >> initialize [
	"Register the Apps-menu entry, next to 'SWA GC Stats'. Same shape as
	GcGraphMorph class>>initialize, and equally idempotent."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA Memory Stats'.
		{self. #open}.
		'Live graph of the whole process: object memory, FFI and native memory, GPU uploads and VRAM' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:03'
}
SWAMemoryGraphMorph class >> open [
	"Apps-menu action: open the whole-process memory graph in a window."
	| window morph |
	Smalltalk at: #World ifAbsent: [^ nil].
	World ifNil: [^ nil].
	morph := self new.
	window := (SystemWindow labelled: 'SWA Memory Stats') model: nil.
	window addMorph: morph frame: (0@0 corner: 1@1).
	window setWindowColor: GcGraph windowColor.
	window openInWorld.
	"100 pixels per strip, plus room for the window title bar."
	window extent: 500 @ (morph strips size * 100 + 24).
	window center: World center.
	^ window
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> buildStrips [
	"The portable four, plus the VRAM strip where a driver can supply it."
	| result |
	result := OrderedCollection new.
	result add: GcGraph new.
	result add: GcFullGraph new.
	result add: SWAProcessGraph new.
	result add: SWAGpuGraph new.
	SWAVramGraph isAvailable ifTrue: [result add: SWAVramGraph new].
	^result
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> defaultColor [
	^GcGraph backgroundColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> drawOn: aCanvas [
	"Blit each strip's form under the previous one and write its label over it."
	| font y |
	font := TextStyle defaultFont.
	y := 0.
	strips do: [:each |
		aCanvas paintImage: each form at: self topLeft + (0 @ y).
		aCanvas
			drawString: each labelString
			at: self topLeft + (2 @ (y + 1))
			font: font
			color: GcGraph slateColor.
		y := y + each form height]
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> extent: aPoint [
	"Split the height evenly over the strips. Any remainder from the division
	goes to the last strip so the morph has no unpainted sliver at the bottom."
	| stripHeight |
	stripHeight := aPoint y // strips size.
	strips doWithIndex: [:each :i |
		each extent: aPoint x @ (i = strips size
			ifTrue: [aPoint y - (stripHeight * (strips size - 1))]
			ifFalse: [stripHeight])].
	super extent: aPoint
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> initialize [
	super initialize.
	strips := self buildStrips.
	self extent: 400 @ (100 * strips size)
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> step [
	self changed.
	strips do: [:each | each stepUpdate]
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:01'
}
SWAMemoryGraphMorph >> stepTime [
	"As fast as morphic will go, matching GcGraphMorph, so the fps strip really
	measures the frame rate. The probe-backed strips throttle themselves."
	^1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> strips [
	^strips
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 18:00'
}
SWAMemoryGraphMorph >> wantsSteps [
	^true
]
