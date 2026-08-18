Class {
	#name : #GcGraphMorph,
	#superclass : #Morph,
	#instVars : [
		'panel'
	],
	#category : #'SWA-GCStats'
}

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:50'
}
GcGraphMorph class >> initialize [
	"Register the Apps-menu entry for the live GC \/ memory graph. The 'SWA '
	label prefix groups all SWA tools together in the (alphabetically sorted)
	Apps menu. Idempotent: removes any prior entry for this receiver first."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'SWA GC Stats'.
		{self. #open}.
		'Live graph of frame time, GC activity and object memory composition' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:58'
}
GcGraphMorph class >> open [
	"Apps-menu action: open the live GC \/ memory graph in a window."
	| window |
	Smalltalk at: #World ifAbsent: [^ nil].
	World ifNil: [^ nil].
	window := (SystemWindow labelled: 'SWA GC Stats') model: nil.
	window addMorph: self new frame: (0@0 corner: 1@1).
	window setWindowColor: GcGraph windowColor.
	window openInWorld.
	window extent: 500 @ 320.
	window center: World center.
	^ window
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:50'
}
GcGraphMorph class >> unload [
	"Remove the Apps-menu entry when the package is unloaded."
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 7/31/2026 11:06'
}
GcGraphMorph class >> xrMenuOpen: aMenu [
	<xrMenu: #(world apps) label: 'GC Stats' priority: 300>
	"Open in the 2D world; the framework promotes the window into 3D."
	^ self open
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:58'
}
GcGraphMorph >> defaultColor [
	"Morph's default is a saturated blue, which shows through wherever the
	graph forms have not been painted yet."
	^ GcGraph backgroundColor
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:53'
}
GcGraphMorph >> drawOn: aCanvas [

	"Just blit the panel's retained backing Form (ImageMorph-style). All compositing
	happened once in #step via panel refresh; drawing is a single paintImage:."
	aCanvas paintImage: panel form at: self topLeft
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:54'
}
GcGraphMorph >> extent: aPoint [
	"Resizing the morph re-fits the panel's graph forms to the new size: wider shows
	more history, taller shows more detail. Clamp to a usable minimum so a drag cannot
	produce zero-sized forms."
	| e |
	panel isNil ifTrue: [^ super extent: aPoint].
	e := aPoint truncated max: 120 @ 90.
	panel fitWidth: e x height: e y labelStripHeight: panel labelStripHeight.
	"Graph forms changed size, so rebuild the backing Form once (not per frame)."
	panel ensureBackingForm.
	super extent: panel extent
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:35'
}
GcGraphMorph >> initialize [
	super initialize.
	"Shared GC-stats model -- the same panel (with the improved graphs and the
	survivor graph) that drives the XR SRGCStats texture. 1x scale for screen pixels."
	panel := GcStatsPanel new.
	panel scaleForFactor: 1.
	self extent: 480 @ 300
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:28'
}
GcGraphMorph >> panel [
	^ panel
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:28'
}
GcGraphMorph >> position: aPoint [
	"The panel blits its graph forms at draw time relative to my topLeft, so moving me
	needs nothing beyond the usual Morph behaviour."
	super position: aPoint
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:54'
}
GcGraphMorph >> step [
	"Advance + composite into the panel's backing Form once, then invalidate so the
	single blit in #drawOn: repaints. No per-frame form allocation, no re-issued ops."
	panel refresh.
	self changed
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 11:58'
}
GcGraphMorph >> stepTime [
	"0 = step every Morphic cycle (Morphic clamps to a 1ms minimum). We WANT this: the
	fps graph measures the interval between steps, so stepping once per Morphic frame
	makes that interval the real Morphic frame time -- i.e. the actual fps. The redraw
	is a single blit of the panel's retained backing Form, so this is cheap."
	^0
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> wantsSteps [ 
	^true
]
