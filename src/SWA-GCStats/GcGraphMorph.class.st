Class {
	#name : #GcGraphMorph,
	#superclass : #Morph,
	#instVars : [
		'graph',
		'fullGraph'
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
	#category : #'xr menu',
	#'squeak_changestamp' : 'MCPServer 7/30/2026 16:48'
}
GcGraphMorph class >> srMenuOpenInXr: aMenu [
	<srMenu: #(world apps) label: 'GC Stats' priority: 300>
	| panel |
	panel := SRMorphPanel new morph: self open; yourself.
	panel position: aMenu position.
	aMenu world addChild: panel.
	^ panel
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
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:56'
}
GcGraphMorph >> drawOn: aCanvas [

	| font |
	aCanvas paintImage: graph form at: self topLeft.
	aCanvas paintImage: fullGraph form at: self topLeft + (0 @ graph form height).

	font := TextStyle defaultFont.
	aCanvas
		drawString: graph labelString
		at: self topLeft + (2 @ 1) font: font color: GcGraph slateColor.
	aCanvas
		drawString: fullGraph labelString
		at: self topLeft + (2 @ (graph form height + 1)) font: font color: GcGraph slateColor
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'MCPServer 7/30/2026 12:50'
}
GcGraphMorph >> extent: aPoint [
	"Split my height between the timing\/GC graph (top) and the memory graph
	(bottom). Clamp to a usable minimum so window resizing cannot produce
	zero-sized forms."
	| e top |
	e := (aPoint truncated) max: 80@60.
	super extent: e.
	top := e y // 2.
	graph extent: e x @ top.
	fullGraph extent: e x @ (e y - top)
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'jl 7/14/2006 10:33'
}
GcGraphMorph >> initialize [
	super initialize.
	graph := GcGraph new.
	fullGraph := GcFullGraph new.

	self extent: 400@400.
]

{
	#category : #geometry,
	#'squeak_changestamp' : 'jl 7/14/2006 10:46'
}
GcGraphMorph >> position: aPoint [
	super position: aPoint.
	graph graph position: aPoint.
	fullGraph graph position: aPoint + (0@ graph form height)
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'jl 7/14/2006 10:59'
}
GcGraphMorph >> step [
	self changed.
	graph updateTime.
	graph updateGraph.
	fullGraph updateGraph
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> stepTime [
	^1
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> wantsSteps [ 
	^true
]
