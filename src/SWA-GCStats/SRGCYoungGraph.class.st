"
The young-space lane of the GC Stats panel, split out as its own toggleable graph: the
scavenge sawtooth (used young vs eden) with the survivor floor (the level young drops to
right after a scavenge) drawn deeper. Tracks a scavenge-time EMA for the label.
"
Class {
	#name : #SRGCYoungGraph,
	#superclass : #GcFullGraph,
	#instVars : [
		'lastScavengeCount',
		'lastScavengeMs',
		'emaScavengeMs',
		'survivorYoung'
	],
	#category : #'SWA-GCStats',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:00'
}
SRGCYoungGraph >> averageScavengeMs [
	"Mean ms per scavenge (EMA), or nil if none seen. A single scavenge is sub-ms."
	^ emaScavengeMs
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:00'
}
SRGCYoungGraph >> labelString [
	^ String streamContents: [:s | | avg |
		s nextPutAll: 'Y '; nextPutAll: (self mbString: self usedYoungSpace);
		  nextPut: $/; nextPutAll: (self mbString: self youngSpace).
		survivorYoung ifNotNil: [s nextPutAll: ' s'; nextPutAll: (self mbString: survivorYoung)].
		s nextPutAll: '  scav '; print: (Smalltalk vmParameterAt: 9).
		avg := self averageScavengeMs.
		avg ifNotNil: [s nextPutAll: ' '; nextPutAll: (avg asFloat printShowingDecimalPlaces: 2); nextPutAll: 'ms']]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 8/21/2026 11:00'
}
SRGCYoungGraph >> updateGraph [
	"Young space, full height: the scavenge sawtooth (used young vs eden), with the survivor
	floor (usedYoung captured right after the last scavenge) drawn deeper. p9/p10 fold into a
	scavenge-time EMA on a scavenge frame."
	| height used youngFill scavenges scavengeMs countDelta |
	height := graph height.

	scavenges := Smalltalk vmParameterAt: 9.
	scavengeMs := Smalltalk vmParameterAt: 10.
	countDelta := lastScavengeCount ifNil: [0] ifNotNil: [scavenges - lastScavengeCount].
	countDelta > 0 ifTrue: [ | alpha sample |
		alpha := self class scavengeEmaAlpha.
		sample := (scavengeMs - lastScavengeMs) / countDelta.
		emaScavengeMs := emaScavengeMs ifNil: [sample] ifNotNil: [emaScavengeMs * (1 - alpha) + (sample * alpha)].
		survivorYoung := self usedYoungSpace].
	lastScavengeCount := scavenges.
	lastScavengeMs := scavengeMs.

	used := self usedYoungSpace.
	self graph shiftBy: 2.
	self graph drawFrom: 0 to: height color: self class backgroundColor width: 2.
	youngFill := self youngSpace isZero
		ifTrue: [0]
		ifFalse: [(used * height // self youngSpace) min: height].
	self graph drawFrom: 0 to: youngFill color: self class seafoamColor width: 2.
	survivorYoung ifNotNil: [ | survFill |
		survFill := self youngSpace isZero
			ifTrue: [0]
			ifFalse: [(survivorYoung * height // self youngSpace) min: youngFill].
		self graph drawFrom: 0 to: survFill color: self class survivorColor width: 2]
]
