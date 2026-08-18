"
GcStatsSurface backed by an SRTextureSource (the XR SRGCStats path). Blits into the pixel buffer that is uploaded to the GPU texture.
"
Class {
	#name : #GcStatsTextureSurface,
	#superclass : #GcStatsSurface,
	#instVars : [
		'source',
		'font',
		'labelColor',
		'bgColor'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsTextureSurface >> drawForm: aForm at: aPoint [
	source drawForm: aForm at: aPoint
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsTextureSurface >> drawLabel: aString at: aPoint [
	source drawString: aString at: aPoint color: labelColor on: bgColor font: font
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsTextureSurface >> fillLabelStripAt: y height: h [
	source fillRect: (0 @ y corner: source width @ (y + h)) color: bgColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsTextureSurface >> labelFont [
	^ font
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsTextureSurface >> source: anSRTextureSource font: aFont [
	source := anSRTextureSource.
	font := aFont.
	labelColor := GcGraph slateColor.
	bgColor := GcGraph backgroundColor
]
