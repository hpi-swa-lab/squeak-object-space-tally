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
		'graph',
		'fullGraph',
		'survivorGraph',
		'labelFont'
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
	#category : #gc,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 17:45'
}
SRGCStats class >> promoteYoungToOld [
	"Empty young space by promoting every reachable young survivor into old space.
	A plain scavenge or even a full GC will NOT do this on Spur -- they keep survivors
	young as long as they fit in survivor space, so a stable working set gets re-copied
	forever. Forcing the tenure threshold (p6) to 1 makes the next scavenges tenure all
	survivors; restore the threshold afterward. After this, p35 (per-scavenge survivors)
	drops to ~0 and scavenges are cheap until young space refills."

	| savedThreshold |
	savedThreshold := Smalltalk vmParameterAt: 6.
	Smalltalk vmParameterAt: 6 put: 1.
	Smalltalk garbageCollectMost.
	Smalltalk garbageCollectMost.
	Smalltalk vmParameterAt: 6 put: savedThreshold
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
	#'squeak_changestamp' : 'MCPServer 8/14/2026 17:45'
}
SRGCStats class >> xrMenuPromoteYoung: aMenu [
	"Promote all young survivors to old space, so the scavenger stops re-copying the
	stable working set. Reports the per-scavenge survivor count before and after."

	<xrMenu: #(world debug) label: 'Promote Young->Old' priority: 433>
	| survBefore |
	Smalltalk garbageCollectMost.
	survBefore := Smalltalk vmParameterAt: 35.
	self promoteYoungToOld.
	Transcript showln: 'Promote Young->Old: survivors ', survBefore printString, ' -> ',
		(Smalltalk vmParameterAt: 35) printString.
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
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:45'
}
SRGCStats >> initialize [

	super initialize.
	self name: 'GCStats'.

	"Reuse the real GC Stats graph objects, but at the texture's native resolution so
	the bars and lines are actual pixels (real supersampling, not an upscaled blit)."
	graph := SRGCFpsGraph new.
	fullGraph := SRGCMemGraph new.
	survivorGraph := SRGCSurvivorGraph new.
	self scaleGraphForms.

	meshObject := SRMeshObject withMesh: SRPlane mesh.
	"Plane mesh lies in XZ; stand it up to face +Z like SRMorphPanel does."
	meshObject rotation: (Quaternion angle: 90 axis: Vector3 right).
	self addChild: meshObject.

	self rebuildSource
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
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats >> labelFont: aFont [
	"Set the label font (e.g. a StrikeFont for crispness, or the class baseline font
	for desktop parity). Resize the label strips to fit the new font height."

	labelFont := aFont.
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:45'
}
SRGCStats >> rebuildSource [
	"(Re)build the pixel buffer, GPU texture and quad aspect for the current label font.
	Layout: [fps label strip][fps graph][mem label strip][mem graph]."

	| w h labelH |
	labelH := self labelStripHeight.
	w := graph graph form width max: fullGraph graph form width.
	h := labelH + graph graph form height
		+ labelH + fullGraph graph form height
		+ labelH + survivorGraph graph form height.

	"Graph forms and the label font are already at the render scale (native texture
	resolution), so the texture is their actual size -- real pixels, no upscaling."
	source := SRTextureSource width: w height: h fill: GcGraph backgroundColor.
	fastTexture := SRFastTexture on: source.
	meshObject material texture: fastTexture.
	meshObject scale: (Vector3 x: 1.0 y: 1.0 z: h / w)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:32'
}
SRGCStats >> renderOn: aSRRenderer [
	"Push this frame's pixel changes to the GPU while the GL context is live. The
	child SRMeshObject draws the quad itself via the tree walk."

	self ensureShader.
	fastTexture syncToGpu
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:45'
}
SRGCStats >> scaleGraphForms [
	"Resize each graph's FormGraph to the render scale, so its bars/lines are drawn at
	native texture resolution (real pixels) rather than upscaled from a 1x form."

	| scale |
	scale := self class textureScale.
	graph graph width: 480 * scale height: 50 * scale.
	fullGraph graph width: 480 * scale height: 100 * scale.
	survivorGraph graph width: 480 * scale height: 50 * scale
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
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:46'
}
SRGCStats >> step: deltaTime [

	| labelH fpsGraphTop fullLabelTop fullGraphTop survLabelTop survGraphTop |
	"Advance the three real graphs, exactly as GcGraphMorph>>step does."
	graph updateTime.
	graph updateGraph.
	fullGraph updateGraph.
	survivorGraph updateGraph.

	"Layout at native texture resolution: [fps label][fps graph][mem label][mem graph]
	[surv label][surv graph]. Graph forms and the font are already at render scale, so
	everything blits 1:1 -- actual pixels, no upscaling."
	labelH := self labelStripHeight.
	fpsGraphTop := labelH.
	fullLabelTop := fpsGraphTop + graph graph form height.
	fullGraphTop := fullLabelTop + labelH.
	survLabelTop := fullGraphTop + fullGraph graph form height.
	survGraphTop := survLabelTop + labelH.

	"Clear the label strips (old text) then blit graphs and draw labels."
	source fillRect: (0 @ 0 corner: source width @ labelH) color: GcGraph backgroundColor.
	source fillRect: (0 @ fullLabelTop corner: source width @ (fullLabelTop + labelH)) color: GcGraph backgroundColor.
	source fillRect: (0 @ survLabelTop corner: source width @ (survLabelTop + labelH)) color: GcGraph backgroundColor.
	source drawForm: graph graph form at: 0 @ fpsGraphTop.
	source drawForm: fullGraph graph form at: 0 @ fullGraphTop.
	source drawForm: survivorGraph graph form at: 0 @ survGraphTop.
	source drawString: graph labelString at: 2 @ 1 color: GcGraph slateColor on: GcGraph backgroundColor font: self labelFont.
	source drawString: fullGraph labelString at: 2 @ (fullLabelTop + 1) color: GcGraph slateColor on: GcGraph backgroundColor font: self labelFont.
	source drawString: survivorGraph labelString at: 2 @ (survLabelTop + 1) color: GcGraph slateColor on: GcGraph backgroundColor font: self labelFont.

	source notifyTextureChanged
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:37'
}
SRGCStats >> survivorGraph [
	^ survivorGraph
]
