"
A GcStatsPanel with no draw path: a zero-sized Morph that is only in the world
to be stepped, and blits the panel's backing Form straight onto Display.

Stepping is the whole point. #stepTime 0 means one step per Morphic cycle, so
#cycles counts real Morphic frames, which is the baseline. #drawOn: does
nothing and the bounds are empty, so the overlay costs Morphic no damage, no
compositing and no draw.

The panel is composited and blitted at most every #periodMillis (10 fps). Doing
it per cycle costs more than everything it measures -- the first version of this
class made the image unusable.

Morphic owns those pixels and repaints over them when it damages that
rectangle; the overlay comes back on the next paint.
"
Class {
	#name : #GcStatsOverlay,
	#superclass : #Morph,
	#instVars : [
		'panel',
		'origin',
		'extent',
		'periodMillis',
		'lastPaintMillis',
		'cycles',
		'lastCycleMillis'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #instances,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay class >> close [
	self allInstances do: [:each | each delete].
]

{
	#category : #instances,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay class >> open [
	^ self running ifNil: [self new openInWorld; yourself].
]

{
	#category : #instances,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay class >> running [
	^ self allInstances detect: [:each | each world notNil] ifNone: [nil].
]

{
	#category : #instances,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay class >> toggle [
	^ self running ifNil: [self open] ifNotNil: [:each | each delete. nil].
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:35'
}
GcStatsOverlay >> blit [
	| form |
	form := panel form.
	form displayOn: Display at: origin rule: Form over.
	Display forceToScreen: (origin extent: form extent).
]

{
	#category : #initializing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay >> delete [
	"The changes graph holds a ticker SystemChangeNotifier would keep alive."

	panel release.
	self currentWorld ifNotNil: [:w | w invalidRect: self displayRectangle].
	super delete.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:35'
}
GcStatsOverlay >> displayRectangle [
	^ origin extent: panel form extent.
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay >> drawOn: aCanvas [
	"Nothing. The panel goes onto Display directly in #blit."
]

{
	#category : #initializing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:54'
}
GcStatsOverlay >> initialize [
	super initialize.
	self bounds: (0 @ 0 extent: 0 @ 0).
	origin := 4 @ 24.
	extent := 640 @ 240.
	periodMillis := 100.
	lastPaintMillis := Time millisecondClockValue.
	cycles := 0.
	panel := GcStatsPanel new.
	panel scaleForFactor: 1.
	self resize.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:35'
}
GcStatsOverlay >> origin: aPoint [
	origin := aPoint.
]

{
	#category : #running,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:43'
}
GcStatsOverlay >> paint [
	"One sample per paint, but the sample carries the mean Morphic cycle time over the
	interval, so the fps lane reads the Morphic baseline and not the paint rate."

	"The fps lane already holds every cycle of the interval, measured in #step."

	| before |
	before := Smalltalk vmParameterAt: 34.
	panel stepGraphsWithDelta: nil.
	panel render.
	self blit.
	panel discountBytes: (Smalltalk vmParameterAt: 34) - before.
	lastPaintMillis := Time millisecondClockValue.
	cycles := 0.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:35'
}
GcStatsOverlay >> panel [
	^ panel.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:52'
}
GcStatsOverlay >> panelExtent [
	^ extent.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:52'
}
GcStatsOverlay >> panelExtent: aPoint [
	"Not #extent:. The Morph bounds stay empty; this is the size of the blitted Form."

	extent := aPoint truncated max: 120 @ 90.
	self resize.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:46'
}
GcStatsOverlay >> periodMillis [
	^ periodMillis.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:46'
}
GcStatsOverlay >> periodMillis: anInteger [
	"Lower bound on the interval between paints. 100 is 10 fps; a full composite plus
	forceToScreen: on every Morphic cycle costs more than everything it measures."

	periodMillis := anInteger max: 50.
]

{
	#category : #initializing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:35'
}
GcStatsOverlay >> resize [
	panel
		fitWidth: extent x
		height: extent y
		labelStripHeight: panel labelStripHeight.
	panel ensureBackingForm.
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:38'
}
GcStatsOverlay >> step [
	"Every cycle is measured; only every #periodMillis is drawn."

	| now |
	now := Time millisecondClockValue.
	cycles := cycles + 1.
	lastCycleMillis ifNotNil: [panel noteFrameMillis: now - lastCycleMillis].
	lastCycleMillis := now.
	now - lastPaintMillis < periodMillis ifTrue: [^ self].
	self paint.
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay >> stepTime [
	"0 is one step per Morphic cycle, which is what makes #cycles the Morphic frame
	count. The step itself is a counter and a clock read; the expensive part is
	throttled to #periodMillis."

	^ 0.
]

{
	#category : #stepping,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 13:51'
}
GcStatsOverlay >> wantsSteps [
	^ true.
]
