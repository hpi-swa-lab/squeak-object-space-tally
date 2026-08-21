Class {
	#name : #GcGraphMorph,
	#superclass : #Morph,
	#instVars : [
		'panel',
		'recorder'
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
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:47'
}
GcGraphMorph >> buttonBounds [
	"Top-right corner, over the panel blit. Drawn in #drawOn: after the panel Form and
	hit-tested in #mouseDown:, so no submorph is needed."
	| w h |
	w := 74. h := 20.
	^ (self right - w - 6) @ (self top + 6) extent: w @ h
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
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:48'
}
GcGraphMorph >> drawButtonOn: aCanvas [
	"The record/stop toggle. Coral (the full-GC colour) means 'recording, click to
	stop'; the ocean colour means 'idle, click to record'. Same palette as the graphs
	so the control reads as part of the same tool."
	| r label fill |
	r := self buttonBounds.
	fill := self isRecording ifTrue: [GcGraph coralColor] ifFalse: [GcGraph deepOceanColor].
	aCanvas fillRoundRect: r radius: 5 fillStyle: fill.
	aCanvas frameRoundRect: r radius: 5 width: 1 color: (Color gray: 0.25).
	label := self isRecording ifTrue: ['Stop'] ifFalse: ['Record'].
	self isRecording
		ifTrue: [aCanvas fillRectangle: (r center - (4@4) extent: 8@8) color: Color white]
		ifFalse: [aCanvas fillOval: (r left + 8 @ (r center y - 4) extent: 8@8) color: (Color r: 1 g: 0.3 b: 0.3)].
	aCanvas
		drawString: label
		in: (r left + 20 @ r top corner: r bottomRight)
		font: Preferences standardButtonFont
		color: Color white
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:48'
}
GcGraphMorph >> drawOn: aCanvas [

	"Just blit the panel's retained backing Form (ImageMorph-style). All compositing
	happened once in #step via panel refresh; drawing is a single paintImage:."
	aCanvas paintImage: panel form at: self topLeft.
	self drawButtonOn: aCanvas
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
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:48'
}
GcGraphMorph >> handlesMouseDown: anEvent [
	^ true
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
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
GcGraphMorph >> intoWorld: aWorld [
	"Arm the change ticker when the panel opens, so the changes lane has data; it stays
	cheap (just a counter) while armed."
	super intoWorld: aWorld.
	SRChangeTicker current armFor: self
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:32'
}
GcGraphMorph >> invokeLaneMenu: anEvent [
	"Pop a menu that toggles each GC Stats lane. Same preferences as the XR panel
	(GcStatsPanel class-side booleans), so toggling here also affects the XR panel and
	persists. The setter calls GcStatsPanel>>refreshAllPanels, which re-fits this morph."
	| menu |
	menu := MenuMorph new.
	menu addTitle: 'GC Stats lanes'.
	GcStatsPanel lanePrefsDo: [:label :getter :setter |
		menu
			add: (((GcStatsPanel perform: getter) ifTrue: ['[x] '] ifFalse: ['[ ] ']), label)
			target: GcStatsPanel
			selector: setter
			argument: (GcStatsPanel perform: getter) not].
	menu popUpEvent: anEvent in: self world
]

{
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:47'
}
GcGraphMorph >> isRecording [
	^ recorder notNil and: [recorder isRecording]
]

{
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 10:31'
}
GcGraphMorph >> mouseDown: anEvent [
	"Right-click anywhere pops the lane on/off menu. Left-click on the record/stop button
	toggles recording; a left-click elsewhere is left to the window (drag, raise)."
	anEvent yellowButtonPressed
		ifTrue: [^ self invokeLaneMenu: anEvent].
	(self buttonBounds containsPoint: anEvent position)
		ifTrue: [self toggleRecording. self changed]
		ifFalse: [super mouseDown: anEvent]
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 15:18'
}
GcGraphMorph >> outOfWorld: aWorld [
	"Disarm when the panel closes -- no subscriber left behind once nothing shows it."
	super outOfWorld: aWorld.
	SRChangeTicker current disarmFor: self
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
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:48'
}
GcGraphMorph >> step [
	"Advance + composite into the panel's backing Form once, then invalidate so the
	single blit in #drawOn: repaints. No per-frame form allocation, no re-issued ops."
	self isRecording ifTrue: [recorder sampleNow].
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
	#category : #'record button',
	#'squeak_changestamp' : 'MCPServer 8/18/2026 14:48'
}
GcGraphMorph >> toggleRecording [
	"Record button pressed. Idle -> start a recording sampled by this morph's own step
	(one sample per frame, same cadence the live panel advances on). Recording -> stop
	and open it in a SWA trace pane for analysis."
	self isRecording
		ifTrue: [ | r |
			r := recorder.
			recorder := nil.
			r stop.
			r openInPane]
		ifFalse: [
			recorder := SRGCRecorder new source: #morphic; yourself.
			recorder armWithCapacity: SRGCRecorder defaultCapacity]
]

{
	#category : #'stepping and presenter',
	#'squeak_changestamp' : 'jl 7/14/2006 10:20'
}
GcGraphMorph >> wantsSteps [ 
	^true
]
