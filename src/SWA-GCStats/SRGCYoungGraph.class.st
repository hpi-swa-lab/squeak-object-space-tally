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
		'survivorYoung',
		'frameScavengeCount'
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
	#'squeak_changestamp' : 'MCPServer 8/21/2026 13:33'
}
SRGCYoungGraph >> labelString [
	| s avg |
	s := self labelStreamReset.
	s nextPutAll: 'Y '. self mbPrint: self usedYoungSpace on: s.
	s nextPut: $/. self mbPrint: self youngSpace on: s.
	survivorYoung ifNotNil: [s nextPutAll: ' s'. self mbPrint: survivorYoung on: s].
	s nextPutAll: '  scav '; print: (Smalltalk vmParameterAt: 9).
	avg := self averageScavengeMs.
	avg ifNotNil: [s nextPutAll: ' '. self msPrint: avg asFloat on: s. s nextPutAll: 'ms'].
	^ s contents
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:44'
}
SRGCYoungGraph >> noteFrame [
	"The survivor floor has to be read at the frame the scavenge happened. Read it at
	the next paint instead and eden has already refilled: at 16 MB/s a 100 ms paint
	interval puts 1.6 MB of fresh garbage under the line, which is how the band came to
	show 600 KB while the heap diff measured 1.7 KB.

	Two vmParameterAt: reads, so it is affordable per frame."

	| scavenges |
	scavenges := Smalltalk vmParameterAt: 9.
	frameScavengeCount
		ifNil: [frameScavengeCount := scavenges. ^ self].
	scavenges > frameScavengeCount ifTrue: [survivorYoung := self usedYoungSpace].
	frameScavengeCount := scavenges.
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 9/18/2026 15:44'
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
		"#survivorYoung is latched in #noteFrame, at the frame of the scavenge."
		frameScavengeCount ifNil: [survivorYoung := self usedYoungSpace]].
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
