"
Samples which process holds the CPU, from a process above both interactive
loops, and reports how the Morphic UI process and the XR world process divide a
second between them.

The question it answers: do the two loops interleave finely, or does each run a
whole cycle and then hand over? Both sit at userSchedulingPriority and neither
preempts the other, so the answer is a property of where they yield, not of the
scheduler.

Uses Processor preemptedProcess, the same reading MessageTally spyAllEvery:on:
takes. The sample arrays are preallocated and the Delay is reused, so the probe
itself allocates nothing while measuring -- it is often pointed at allocation
problems.
"
Class {
	#name : #SWALoopSwitchProbe,
	#superclass : #Object,
	#instVars : [
		'stamps',
		'samples',
		'count',
		'periodMillis'
	],
	#category : #'SWA-MessageTally',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe class >> measure: durationMillis [
	"Answers the probe. Safe to call from a tool process: the sampling runs on its own
	process above both loops, and the caller just blocks on the semaphore."

	| probe done |
	probe := self new.
	done := Semaphore new.
	[[probe runFor: durationMillis] ensure: [done signal]]
		forkAt: Processor userInterruptPriority.
	done wait.
	^ probe.
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> elapsedMillis [
	count < 2 ifTrue: [^ 0].
	^ (stamps at: count) - (stamps at: 1).
]

{
	#category : #initializing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:21'
}
SWALoopSwitchProbe >> initialize [
	super initialize.
	periodMillis := 1.
	count := 0.
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> nameOf: aProcessOrNil [
	aProcessOrNil ifNil: [^ 'idle'].
	aProcessOrNil == Project current uiProcess ifTrue: [^ 'Morphic UI'].
	^ aProcessOrNil name ifNil: ['priority ' , aProcessOrNil priority printString].
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> occupancy [
	"name -> sample count, commonest first."

	| counts |
	counts := Dictionary new.
	1 to: count do: [:i | | key |
		key := self nameOf: (samples at: i).
		counts at: key put: (counts at: key ifAbsent: [0]) + 1].
	^ counts associations asArray sort: [:a :b | a value >= b value].
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> pad: aNumber width: anInteger [
	^ (aNumber asFloat printShowingDecimalPlaces: 1) padded: #left to: anInteger with: $ .
]

{
	#category : #initializing,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:21'
}
SWALoopSwitchProbe >> periodMillis: anInteger [
	periodMillis := anInteger max: 1.
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:23'
}
SWALoopSwitchProbe >> report [
	| ms perSample |
	ms := self elapsedMillis.
	perSample := count > 1 ifTrue: [ms / (count - 1)] ifFalse: [0].
	^ String streamContents: [:s |
		s nextPutAll: 'SWALoopSwitchProbe  '; print: count; nextPutAll: ' samples over ';
			print: ms; nextPutAll: ' ms  ('; nextPutAll: (self pad: perSample width: 1);
			nextPutAll: ' ms/sample)'; cr; cr.
		s nextPutAll: 'switches '; print: self switchCount;
			nextPutAll: '   = '; print: (ms = 0 ifTrue: [0] ifFalse: [self switchCount * 1000 // ms]);
			nextPutAll: '/s'; cr; cr.
		s nextPutAll: 'process                  share    runs   mean ms   max ms'; cr.
		self runStats do: [:assoc | | runs total longest |
			runs := assoc value at: 1.
			total := assoc value at: 2.
			longest := assoc value at: 3.
			s nextPutAll: ((assoc key truncateTo: 22) padded: #right to: 23 with: $ );
				nextPutAll: (self pad: total * 100 / count width: 7);
				nextPutAll: (runs printString padded: #left to: 8 with: $ );
				nextPutAll: (self pad: total * perSample / runs width: 10);
				nextPutAll: (self pad: longest * perSample width: 9);
				cr]].
]

{
	#category : #measuring,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> runFor: durationMillis [
	"Must run above userSchedulingPriority, or the loops being measured starve it."

	| capacity deadline delay |
	capacity := durationMillis // periodMillis + 64.
	stamps := Array new: capacity.
	samples := Array new: capacity.
	count := 0.
	delay := Delay forMilliseconds: periodMillis.
	deadline := Time millisecondClockValue + durationMillis.
	[Time millisecondClockValue < deadline and: [count < capacity]] whileTrue: [
		count := count + 1.
		stamps at: count put: Time millisecondClockValue.
		samples at: count put: Processor preemptedProcess.
		delay wait].
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> runStats [
	"name -> { runs. total samples. longest run }."

	| stats |
	stats := Dictionary new.
	self runsDo: [:name :length | | each |
		each := stats at: name ifAbsentPut: [Array with: 0 with: 0 with: 0].
		each at: 1 put: (each at: 1) + 1.
		each at: 2 put: (each at: 2) + length.
		each at: 3 put: ((each at: 3) max: length)].
	^ stats associations asArray sort: [:a :b | (a value at: 2) >= (b value at: 2)].
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> runsDo: aBlock [
	"aBlock gets name and run length in samples, for each unbroken stretch."

	| start |
	count = 0 ifTrue: [^ self].
	start := 1.
	2 to: count do: [:i |
		(samples at: i) == (samples at: i - 1) ifFalse: [
			aBlock value: (self nameOf: (samples at: start)) value: i - start.
			start := i]].
	aBlock value: (self nameOf: (samples at: start)) value: count - start + 1.
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> sampleCount [
	^ count.
]

{
	#category : #reporting,
	#'squeak_changestamp' : 'MCPServer 9/18/2026 14:22'
}
SWALoopSwitchProbe >> switchCount [
	| n |
	n := 0.
	2 to: count do: [:i |
		(samples at: i) == (samples at: i - 1) ifFalse: [n := n + 1]].
	^ n.
]
