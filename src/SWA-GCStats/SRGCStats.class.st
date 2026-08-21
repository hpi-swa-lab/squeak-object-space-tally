"
A live GC/FPS stats panel that renders into its own texture with zero per-frame allocation.

Motivation: measuring GC while perturbing GC as little as possible. Each step scrolls a one-pixel column into a persistent SRTextureSource buffer (in place, no Form, no new objects) and marks that column dirty; the frame's render then pushes the buffer to the GPU with one rlUpdateTexture (SRFastTexture>>syncToGpu). Contrast GcGraphMorph, which repaints a Form every step.

Layout mirrors SRMorphPanel: a child SRMeshObject carrying a vertical unit quad (SRPlane's mesh) and a material whose texture is the SRFastTexture. column is the current write x, advanced and wrapped ring-buffer style. lastGcCount / lastTenureCount / lastTime carry the same deltas GcGraph tracks (incremental vs full GC, and dt for FPS).
"
Class {
	#name : #SRGCStats,
	#superclass : #SRObject,
	#instVars : [
		'source',
		'fastTexture',
		'meshObject',
		'panel',
		'labelFont',
		'suspended'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats class >> baselineLabelFont [
	"The antialiased TrueType font the desktop GcGraphMorph uses, for comparison."

	^ TextStyle defaultFont
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:45'
}
SRGCStats class >> defaultLabelFont [
	"A bitmap StrikeFont at the render scale (Atlanta ships real 11px and 22px faces),
	so labels are drawn at native texture resolution -- crisp, not an upscaled bitmap."

	^ StrikeFont familyName: 'Atlanta' size: 11 * self textureScale
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:40'
}
SRGCStats class >> textureScale [
	"Supersampling factor: the texture is built this many times larger than the logical
	graph layout, then the GPU's bilinear filter minifies it, anti-aliasing the edges."
	^ 2
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/14/2026 17:04'
}
SRGCStats class >> xrMenuFullGC: aMenu [
	"Run a full GC (mark-sweep-compact old space + scavenge) and report the reclaimed
	young/old bytes on the Transcript."

	<xrMenu: #(world debug) label: 'Full GC' priority: 434>
	| youngBefore oldBefore |
	youngBefore := Smalltalk vmParameterAt: 2.
	oldBefore := Smalltalk vmParameterAt: 1.
	Smalltalk garbageCollect.
	Transcript showln: 'Full GC: young ', (youngBefore // 1024) printString, 'K -> ',
		((Smalltalk vmParameterAt: 2) // 1024) printString, 'K  old ',
		(oldBefore // 1024) printString, 'K -> ',
		((Smalltalk vmParameterAt: 1) // 1024) printString, 'K'.
	^ self
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:10'
}
SRGCStats class >> xrMenuSpawn: aMenu [
	<xrMenu: #(world debug) label: 'GC Stats (Fast)' priority: 435>
	| stats |
	stats := self new
		position: aMenu position;
		yourself.
	aMenu world addChild: stats.
	^ stats
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:31'
}
SRGCStats >> addCustomMenuItemsTo: aMenu [
	"Toggle each GC Stats lane on/off. Stored in Squeak preferences (GcStatsPanel class-side
	<preference:> booleans), so it persists and affects the Morphic panel too. Each toggle
	re-fits every live panel via GcStatsPanel>>refreshAllPanels."
	super addCustomMenuItemsTo: aMenu.
	GcStatsPanel lanePrefsDo: [:label :getter :setter |
		aMenu
			addItem: (((GcStatsPanel perform: getter) ifTrue: ['[x] '] ifFalse: ['[ ] ']), label)
			action: [self world
				ifNil: [GcStatsPanel perform: setter with: (GcStatsPanel perform: getter) not]
				ifNotNil: [:w | w addDeferredFrameMessage: [
					GcStatsPanel perform: setter with: (GcStatsPanel perform: getter) not]]]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:57'
}
SRGCStats >> buildPanelAndMesh [
	"Build (or rebuild) the panel model and the textured mesh from scratch. Extracted from
	#initialize so #reconfigure can re-run it after a lane toggle -- creating a FRESH panel,
	mesh and material is what actually un-freezes the render (a reused material keeps a
	stale cached internal material bound to a freed GPU texture). Any existing mesh child is
	removed first so we do not accumulate.

	Shared GC-stats model at the texture's native resolution so bars/lines are real pixels
	(supersampling, not an upscaled blit). Same panel drives the desktop GcGraphMorph."
	meshObject ifNotNil: [meshObject remove].
	panel := GcStatsPanel new.
	panel labelFont: self labelFont.
	panel scaleForFactor: self class textureScale.

	meshObject := SRMeshObject withMesh: SRPlane mesh.
	"Plane mesh lies in XZ; stand it up to face +Z like SRMorphPanel does."
	meshObject rotation: (Quaternion angle: 90 axis: Vector3 right).
	self addChild: meshObject.

	fastTexture := nil.
	self rebuildSource
]

{
	#category : #collision,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:31'
}
SRGCStats >> collisionGeometry [
	"A plane collider matching the quad so the hand ray can hit and grab this panel,
	which is what raises the context menu. The child meshObject carries the actual
	oriented quad (unit plane rotated up to face +Z), so derive the frame from it."

	| xf w h |
	xf := meshObject globalTransform.
	w := meshObject globalScale x.
	h := meshObject globalScale z.
	^ (SRCollisionPlane
		point: meshObject globalTranslation
		normal: (xf localDirToGlobal: Vector3 up) normalize
		up: (xf localDirToGlobal: 0 @ 0 @ 1) normalize
		width: w
		height: h)
		object: self
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:32'
}
SRGCStats >> ensureShader [
	"The backing Form is BGRA (see SRTextureSource), so the quad must draw with the
	morphicPanel shader which swizzles .bgra on the GPU. Set once, when a GL context
	exists to load it."

	meshObject material shader ifNil: [
		SRRenderer hasContext ifTrue: [
			meshObject material shader: SRShader morphicPanel load]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 13:38'
}
SRGCStats >> fastTexture [

	^ fastTexture
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:57'
}
SRGCStats >> initialize [

	super initialize.
	self name: 'GCStats'.
	self buildPanelAndMesh
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats >> labelFont [

	^ labelFont ifNil: [labelFont := self class defaultLabelFont]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:27'
}
SRGCStats >> labelFont: aFont [
	"Set the label font (e.g. a StrikeFont for crispness, or the class baseline font
	for desktop parity). Resize the label strips to fit the new font height."

	labelFont := aFont.
	panel ifNotNil: [panel labelFont: aFont].
	self resizeForLabelFont
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats >> labelStripHeight [
	"Height of the clear band above each graph, sized to the current label font."

	^ self labelFont height + 2
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:26'
}
SRGCStats >> panel [
	^ panel
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:58'
}
SRGCStats >> rebuildSource [
	"(Re)build the pixel buffer, GPU texture and quad aspect for the current label font.
	Layout: [fps label strip][fps graph][mem label strip][mem graph]."

	| extent |
	"The panel computes the composited size from its graph forms and our label font.
	Graph forms and the label font are already at the render scale (native texture
	resolution), so the texture is their actual size -- real pixels, no upscaling."
	extent := panel extentFor: (GcStatsTextureSurface new source: nil font: self labelFont).
	source := SRTextureSource width: extent x height: extent y fill: GcGraph backgroundColor.
	fastTexture := SRFastTexture on: source.
	meshObject material texture: fastTexture.
	meshObject scale: (Vector3 x: 1.0 y: 1.0 z: extent y / extent x)
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:57'
}
SRGCStats >> reconfigure [
	"Stop stepping/rendering, re-fit the panel to the current lane set + rebuild the texture,
	then start again. Suspending guarantees the resize never runs under a live step or
	render on this object, which is what left panels frozen after a lane toggle."
	suspended := true.
	[self buildPanelAndMesh]
		ensure: [suspended := false]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
SRGCStats >> remove [
	"Release the change ticker when this panel leaves the XR world."
	SRChangeTicker current disarmFor: self.
	super remove
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:51'
}
SRGCStats >> renderOn: aSRRenderer [
	"Push this frame's pixel changes to the GPU while the GL context is live. The
	child SRMeshObject draws the quad itself via the tree walk."

	"Only touch GL when a context is live, and never let a transient texture-rebuild error
	propagate: SRFrame>>renderObjects would flag us badRender: true and skip us forever."
	suspended == true ifTrue: [^ self].
	SRRenderer hasContext ifFalse: [^ self].
	self ensureShader.
	[fastTexture syncToGpu] on: Error do: [:e | "next frame retries the sync"]
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:45'
}
SRGCStats >> resizeForLabelFont [
	"The label font changed; the texture may need a different height. Rebuild it."

	self rebuildSource
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 13:38'
}
SRGCStats >> source [

	^ source
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:51'
}
SRGCStats >> step: deltaTime [

	"Advance the graphs and composite them onto the texture via the shared panel --
	the exact same layout/composite code the desktop GcGraphMorph uses, just aimed at
	an SRTextureSource surface instead of a Canvas."
	"Register as a ticker user here rather than in a world-enter hook (SRObject has
	none): armFor: is a Set add, so calling it every frame is harmless, and the changes
	lane has data while this panel is alive. #remove drops the registration."
	"Skip while suspended -- a reconfigure (lane toggle) is resizing the panel's graph forms
	and source, which must not run under a live step/composite."
	suspended == true ifTrue: [^ self].
	SRChangeTicker current armFor: self.
	panel stepGraphsWithDelta: deltaTime.
	panel renderOn: (GcStatsTextureSurface new source: source font: self labelFont).
	source notifyTextureChanged
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:26'
}
SRGCStats >> survivorGraph [
	^ panel survivorGraph
]
