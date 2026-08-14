"
A third GC Stats strip plotting three drivers of scavenge cost, each as its own auto-scaled line: survivors copied (p35, the direct cost of a scavenge), remembered-table size (p21, old->young pointers the scavenger must scan), and tenures per scavenge (p11 delta / p9 delta, objects promoted to old space). All three are sampled at each scavenge and held between scavenges, since p35 is only meaningful right after one.
"
Class {
	#name : #SRGCSurvivorGraph,
	#superclass : #GcFullGraph,
	#instVars : [
		'lastScavengeCount',
		'lastTenures',
		'survivors',
		'rootTable',
		'tenuresPerScav',
		'maxSurvivors',
		'maxRoot',
		'maxTenures',
		'lastFullGcCount',
		'retained'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:00'
}
SRGCSurvivorGraph class >> fullGcColor [
	"Faint full-column mark on the frame a full GC ran."
	^ self shallowOceanColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:00'
}
SRGCSurvivorGraph class >> retainedColor [
	"Survivors a full GC kept -- the truly retained set, plotted on the survivor scale
	so the gap to per-scavenge survivors is visible."
	^ self slateColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:36'
}
SRGCSurvivorGraph class >> rootColor [
	"Remembered-table size -- old->young pointers scanned every scavenge."
	^ self deepOceanColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:36'
}
SRGCSurvivorGraph class >> survivorColor [
	"Survivors copied per scavenge -- the direct cost of the scavenge."
	^ self coralColor
]

{
	#category : #constants,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:36'
}
SRGCSurvivorGraph class >> tenureColor [
	"Tenures per scavenge -- objects promoted to old space (should stay near zero)."
	^ self seafoamColor
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:02'
}
SRGCSurvivorGraph >> initialize [
	super initialize.
	graph := FormGraph new.
	graph width: 480 height: 50.
	survivors := 0.
	rootTable := 0.
	tenuresPerScav := 0.
	maxSurvivors := 1.
	maxRoot := 1.
	maxTenures := 1.
	retained := nil
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:02'
}
SRGCSurvivorGraph >> labelString [
	^ String streamContents: [:s |
		s nextPutAll: 'surv '; print: survivors;
		  nextPutAll: '  kept '; nextPutAll: (retained ifNil: ['?'] ifNotNil: [retained printString]);
		  nextPutAll: '  root '; print: rootTable;
		  nextPutAll: '  ten/scav '; print: tenuresPerScav rounded]
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 15:36'
}
SRGCSurvivorGraph >> plotValue: value max: aMax color: aColor [
	"Draw a short tick at value's height (scaled to aMax) in the newest 2px column."

	| height y |
	height := graph height.
	y := aMax isZero ifTrue: [0] ifFalse: [(value * height // aMax) min: height].
	graph drawFrom: (y - 1 max: 0) to: (y + 1 min: height) color: aColor width: 2
]

{
	#category : #update,
	#'squeak_changestamp' : 'MCPServer 8/14/2026 16:02'
}
SRGCSurvivorGraph >> updateGraph [
	"Sample p35/p21/tenures at each scavenge (held between scavenges) and plot three
	auto-scaled lines. Each line is a short tick at its value's height in the newest
	column, so the three traces stay distinguishable as the graph scrolls."

	| height scavenges scavengeCount tenures fullGcs fullGced |
	height := graph height.

	scavenges := Smalltalk vmParameterAt: 9.
	(lastScavengeCount notNil and: [scavenges > lastScavengeCount]) ifTrue: [
		scavengeCount := scavenges - lastScavengeCount.
		tenures := Smalltalk vmParameterAt: 11.
		survivors := Smalltalk vmParameterAt: 35.
		rootTable := Smalltalk vmParameterAt: 21.
		tenuresPerScav := lastTenures
			ifNil: [0]
			ifNotNil: [(tenures - lastTenures) / scavengeCount].
		lastTenures := tenures.
		maxSurvivors := maxSurvivors max: survivors.
		maxRoot := maxRoot max: rootTable.
		maxTenures := maxTenures max: tenuresPerScav].
	lastScavengeCount := scavenges.

	"p7 = full GC count. When it ticks, p35 holds the full GC's survivor count -- the
	truly retained set, usually far below the per-scavenge survivors."
	fullGcs := Smalltalk vmParameterAt: 7.
	fullGced := lastFullGcCount notNil and: [fullGcs > lastFullGcCount].
	fullGced ifTrue: [retained := Smalltalk vmParameterAt: 35].
	lastFullGcCount := fullGcs.

	graph shiftBy: 2.
	graph drawFrom: 0 to: height color: self class backgroundColor width: 2.

	"A full GC marks its whole column so you can see when it ran and what it kept."
	fullGced ifTrue: [graph drawFrom: 0 to: height color: self class fullGcColor width: 2].

	self plotValue: survivors max: maxSurvivors color: self class survivorColor.
	self plotValue: rootTable max: maxRoot color: self class rootColor.
	self plotValue: tenuresPerScav max: maxTenures color: self class tenureColor.
	retained ifNotNil: [self plotValue: retained max: maxSurvivors color: self class retainedColor]
]
