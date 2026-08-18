"
Abstract drawing-surface adapter for GcStatsPanel>>renderOn:. Subclasses wrap a concrete backend (a Morphic Canvas or an SRTextureSource) and implement the same small drawing protocol so one shared composite routine drives both.

Required protocol:
  labelFont                        -- font used for label strips (drives strip height)
  fillLabelStripAt: y height: h    -- clear a horizontal label band at panel-local y
  drawForm: aForm at: aPoint       -- blit a graph form at panel-local point
  drawLabel: aString at: aPoint    -- draw label text at panel-local point

Panel-local coordinates start at 0@0; subclasses add any backend origin (e.g. the morph's topLeft).
"
Class {
	#name : #GcStatsSurface,
	#superclass : #Object,
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsSurface >> drawForm: aForm at: aPoint [
	self subclassResponsibility
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsSurface >> drawLabel: aString at: aPoint [
	self subclassResponsibility
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:25'
}
GcStatsSurface >> fillLabelStripAt: y height: h [
	self subclassResponsibility
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:24'
}
GcStatsSurface >> labelFont [
	^ self subclassResponsibility
]
