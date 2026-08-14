"
GcGraph whose FPS bars are scaled so maxFps maps to the full graph height, instead of the stock 1 fps = 1 pixel (which saturates any graph shorter than the frame rate). Only the plotted bar is scaled; the label still prints the true fps. Used by SRGCStats so its short (50px) FPS strip shows a meaningful curve up to maxFps rather than a solid block.
"
Class {
	#name : #SRGCFpsGraph,
	#superclass : #GcGraph,
	#instVars : [
		'emaFps'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph class >> emaAlpha [
	"Smoothing factor for the label's exponential moving average of fps.
	~0.1 is about a 10-frame time constant: stable to read, still tracks changes."

	^ 0.1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:36'
}
SRGCFpsGraph class >> maxFps [
	"Full graph height corresponds to this frame rate."

	^ 120
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> fps [
	"The label reads this: the smoothed (EMA) fps, rounded. The graph uses rawFps."

	^ (emaFps ifNil: [self rawFps]) rounded
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> rawFps [
	"Instantaneous fps for the graph bar (one frame's delta), before smoothing."

	^ super fps
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/13/2026 15:38'
}
SRGCFpsGraph >> updateGraph [
	"As GcGraph>>updateGraph, but the plotted bar is scaled so maxFps fills the
	graph height. The label (which reads self fps) is unaffected."

	| gcCount fps tenurCount scaled alpha |
	gcCount := Smalltalk vmParameterAt: 7.
	tenurCount := Smalltalk vmParameterAt: 11.
	fps := self rawFps.
	"Fold this frame's instantaneous fps into the label's EMA."
	alpha := self class emaAlpha.
	emaFps := emaFps
		ifNil: [fps]
		ifNotNil: [emaFps * (1 - alpha) + (fps * alpha)].
	"The bar stays instantaneous so GC hitches remain visible."
	scaled := (fps * self graph height / self class maxFps) rounded min: self graph height.
	(lastGcCount = gcCount)
		ifTrue: [
			lastTenurCount = tenurCount
				ifTrue: [
					self graph
						addValue: scaled
						color: self class deepOceanColor
						bgColor: self class backgroundColor]
				ifFalse: [
					self graph
						addValue: scaled
						color: self class deepOceanColor
						bgColor: self class seafoamColor.
					lastTenurCount := tenurCount]]
		ifFalse: [
			self graph
				addValue: scaled
				color: self class deepOceanColor
				bgColor: self class coralColor.
			lastTenurCount := tenurCount.
			lastGcCount := gcCount]
]
