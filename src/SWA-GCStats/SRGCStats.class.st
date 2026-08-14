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
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats class >> defaultLabelFont [
	"A bitmap StrikeFont: 1-bit glyphs that stay crisp under point-filtering in 3D.
	Use #baselineLabelFont for pixel-parity with the desktop GC Stats instead."

	^ StrikeFont familyName: 'Atlanta' size: 11
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
	#'squeak_changestamp' : 'MCPServer 8/13/2026 16:47'
}
SRGCStats >> initialize [

	super initialize.
	self name: 'GCStats'.

	"Reuse the real GC Stats graph objects so the output is pixel-identical."
	graph := SRGCFpsGraph new.
	fullGraph := SRGCMemGraph new.

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
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:44'
}
SRGCStats >> rebuildSource [
	"(Re)build the pixel buffer, GPU texture and quad aspect for the current label font.
	Layout: [fps label strip][fps graph][mem label strip][mem graph]."

	| w h labelH |
	labelH := self labelStripHeight.
	w := graph graph form width max: fullGraph graph form width.
	h := labelH + graph graph form height + labelH + fullGraph graph form height.

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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 13:38'
}
SRGCStats >> source [

	^ source
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:45'
}
SRGCStats >> step: deltaTime [

	| labelH fpsGraphTop fullLabelTop fullGraphTop |
	"Advance the two real graphs, exactly as GcGraphMorph>>step does."
	graph updateTime.
	graph updateGraph.
	fullGraph updateGraph.

	"Layout: [fps label strip][fps graph][mem label strip][mem graph].
	Labels sit in their own clear strips, so text never overlaps the plot."
	labelH := self labelStripHeight.
	fpsGraphTop := labelH.
	fullLabelTop := fpsGraphTop + graph graph form height.
	fullGraphTop := fullLabelTop + labelH.

	"Clear the label strips (old text) then blit graphs and draw labels."
	source fillRect: (0 @ 0 corner: source width @ labelH) color: GcGraph backgroundColor.
	source fillRect: (0 @ fullLabelTop corner: source width @ (fullLabelTop + labelH)) color: GcGraph backgroundColor.
	source drawForm: graph graph form at: 0 @ fpsGraphTop.
	source drawForm: fullGraph graph form at: 0 @ fullGraphTop.
	source drawString: graph labelString at: 2 @ 1 color: GcGraph slateColor on: GcGraph backgroundColor font: self labelFont.
	source drawString: fullGraph labelString at: 2 @ (fullLabelTop + 1) color: GcGraph slateColor on: GcGraph backgroundColor font: self labelFont.

	source notifyTextureChanged
]
