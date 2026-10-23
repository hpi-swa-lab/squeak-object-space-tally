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
		'meshObject',
		'labelFont',
		'frameCount',
		'deltaSum',
		'shownFps',
		'texture'
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:55'
}
SRFpsLabel class >> in: aWorld [
	^ aWorld children detect: [:each | each isKindOf: self] ifNone: [nil]
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
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:56'
}
SRFpsLabel class >> xrMenuToggle: aMenu [
	<xrMenu: #(world debug) label: #xrMenuToggleLabel: priority: 436>
	| label |
	(self in: aMenu world) ifNotNil: [:existing | existing remove. ^ nil].
	label := self new
		position: aMenu position;
		yourself.
	aMenu world addChild: label.
	^ label
]

{
	#category : #menu,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:56'
}
SRFpsLabel class >> xrMenuToggleLabel: aMenu [
	^ (self in: aMenu world)
		ifNil: ['FPS Label: OFF']
		ifNotNil: [:label | 'FPS Label: ON']
]

{
	#category : #collisions,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 12:55'
}
SRFpsLabel >> collisionGeometry [
	"Without a collider the hand ray cannot hit this label, so it can be neither grabbed
	nor context-menued. The child meshObject carries the oriented quad, so derive the
	frame from it rather than from self."

	| xf |
	xf := meshObject globalTransform.
	^ (SRCollisionPlane
		point: meshObject globalTranslation
		normal: (xf localDirToGlobal: Vector3 up) normalize
		up: (xf localDirToGlobal: 0 @ 0 @ 1) normalize
		width: meshObject globalScale x
		height: meshObject globalScale z)
		object: self.
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
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer (SqueakXR) 10/20/2026 13:43'
}
SRFpsLabel >> isSolid [
	^ false
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
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 11:16'
}
SRFpsLabel >> rebuildSource [
	"Size the texture to hold the widest string we draw ('fps 000') plus a small margin."
	| font w h |
	font := self labelFont.
	w := (font widthOfString: 'fps 000') + 8.
	h := font height + 4.
	source := SRTextureSourceForm width: w height: h fill: GcGraph backgroundColor.
	texture := SRTexture withSource: source.
	meshObject material
		shader: SRShader morphicPanel;
		texture: texture.
	meshObject scale: (Vector3 x: 1.0 y: 1.0 z: h / w).
	self redraw.
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 11:16'
}
SRFpsLabel >> redraw [

	source editDo: [:each |
		each
			fillColor: GcGraph backgroundColor;
			drawString: 'fps ', shownFps printString
				at: 4 @ 2
				color: GcGraph slateColor
				on: GcGraph backgroundColor
				font: self labelFont].
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
