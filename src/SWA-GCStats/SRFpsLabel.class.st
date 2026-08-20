"
A tiny XR text label showing the average FPS, updated every 10 frames. Built the same
way as SRGCStats (its own SRObject carrying a texture quad, added to the XR menu), but it
draws ONLY a small fps string -- no graph. Averaging over 10 frames both cheapens the
redraw (one string blit every 10th frame) and steadies the number.
"
Class {
	#name : #SRFpsLabel,
	#superclass : #SRObject,
	#instVars : [
		'source',
		'fastTexture',
		'meshObject',
		'labelFont',
		'frameCount',
		'deltaSum',
		'shownFps'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel class >> defaultLabelFont [
	"Bitmap StrikeFont at render scale, crisp under point filtering (as SRGCStats)."
	^ StrikeFont familyName: 'Atlanta' size: 11 * self textureScale
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel class >> framesPerUpdate [
	"Average the fps and redraw the label once every this many frames."
	^ 10
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel class >> textureScale [
	"Supersampling factor, as SRGCStats: build the texture larger and let the GPU minify."
	^ 2
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel class >> xrMenuSpawn: aMenu [
	<xrMenu: #(world debug) label: 'FPS Label (Fast)' priority: 436>
	| label |
	label := self new
		position: aMenu position;
		yourself.
	aMenu world addChild: label.
	^ label
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> ensureShader [
	"The backing Form is BGRA (SRTextureSource), so draw the quad with the morphicPanel
	shader that swizzles .bgra on the GPU. Set once, when a GL context exists (as SRGCStats)."
	meshObject material shader ifNil: [
		SRRenderer hasContext ifTrue: [
			meshObject material shader: SRShader morphicPanel load]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> initialize [
	super initialize.
	self name: 'FpsLabel'.
	frameCount := 0.
	deltaSum := 0.0.
	shownFps := 0.
	meshObject := SRMeshObject withMesh: SRPlane mesh.
	"Plane mesh lies in XZ; stand it up to face +Z like SRGCStats does."
	meshObject rotation: (Quaternion angle: 90 axis: Vector3 right).
	self addChild: meshObject.
	self rebuildSource
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> labelFont [
	^ labelFont ifNil: [labelFont := self class defaultLabelFont]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> rebuildSource [
	"(Re)build the pixel buffer, GPU texture and quad aspect for the current font. Size the
	texture to hold the widest string we draw ('fps 000') plus a small margin."
	| font w h |
	font := self labelFont.
	w := (font widthOfString: 'fps 000') + 8.
	h := font height + 4.
	source := SRTextureSource width: w height: h fill: GcGraph backgroundColor.
	fastTexture := SRFastTexture on: source.
	meshObject material texture: fastTexture.
	meshObject scale: (Vector3 x: 1.0 y: 1.0 z: h / w).
	self redraw
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> redraw [
	"Paint the current shownFps string, over a fresh background."
	source fillColor: GcGraph backgroundColor.
	source
		drawString: 'fps ', shownFps printString
		at: 4 @ 2
		color: GcGraph slateColor
		on: GcGraph backgroundColor
		font: self labelFont.
	source notifyTextureChanged
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> renderOn: aSRRenderer [
	"Push this frame's pixel changes to the GPU while the GL context is live. The child
	SRMeshObject draws the quad itself via the tree walk (as SRGCStats)."
	self ensureShader.
	fastTexture syncToGpu
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/20/2026 18:42'
}
SRFpsLabel >> step: deltaTime [
	"Accumulate this frame's delta; every framesPerUpdate frames, average to fps and redraw.
	deltaTime is SRFrame's per-frame delta in milliseconds."
	frameCount := frameCount + 1.
	deltaSum := deltaSum + ((deltaTime isNil or: [deltaTime <= 0.0]) ifTrue: [0.0] ifFalse: [deltaTime]).
	frameCount >= self class framesPerUpdate ifTrue: [
		| avgDelta |
		avgDelta := deltaSum / frameCount.
		shownFps := avgDelta <= 0.05 ifTrue: [0] ifFalse: [(1000.0 / avgDelta) rounded].
		frameCount := 0.
		deltaSum := 0.0.
		self redraw]
]
