"
A change-notifier action sequence that times and measures each subscriber it runs.

SystemChangeNotifier fans one edit out to ~8 subscribers by running a
WeakActionSequenceTrappingErrors of WeakMessageSends. SWAChangeTraceRecorder swaps
its actionMap sequences for instances of this class while recording, so every
reaction (SmalltalkImage>>event:, GSCodeMapper>>systemChanged:, ...) is bracketed
individually: wall micros from utcMicrosecondClock and bytes from vmParameterAt: 34.

Scoped on purpose. Only the change notifier's own sequences are replaced, and only
between start and stop, so no other event system in the image pays for this. The
measurements are pushed to the recorder, which builds one reaction child per call
under the change's node.

Subclassing keeps the exact error-trapping semantics of the parent value loop; the
only addition is the bracket around each element's send.
"
Class {
	#name : #SWAInstrumentedActionSequence,
	#superclass : #WeakActionSequenceTrappingErrors,
	#type : #variable,
	#instVars : [
		'recorder'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #evaluating,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:24'
}
SWAInstrumentedActionSequence >> measure: aMessageSend with: anArray otherwise: aBlock [
	"Bracket one subscriber send for wall time and allocation. Parameter 34 is the
	cumulative bytes-allocated counter -- monotonic, it does not reset on GC -- so the
	delta is the memory this reaction allocated, which is exactly the GC pressure it
	adds, GC during the send or not."
	| t0 a0 result t1 a1 |
	recorder ifNil: [^ aMessageSend valueWithArguments: anArray otherwise: aBlock].
	"A WeakMessageSend whose receiver was collected fires nothing -- run it but do not
	record it as a reaction; its 'UndefinedObject>>sel' is noise, not a subscriber."
	aMessageSend receiver ifNil: [^ aMessageSend valueWithArguments: anArray otherwise: aBlock].
	t0 := Time utcMicrosecondClock.
	a0 := Smalltalk vmParameterAt: 34.
	result := aMessageSend valueWithArguments: anArray otherwise: aBlock.
	t1 := Time utcMicrosecondClock.
	a1 := Smalltalk vmParameterAt: 34.
	recorder
		reaction: aMessageSend
		micros: ((t1 - t0) max: 0)
		bytes: ((a1 - a0) max: 0).
	^ result
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:20'
}
SWAInstrumentedActionSequence >> recorder: aRecorder [
	recorder := aRecorder.
]

{
	#category : #evaluating,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAInstrumentedActionSequence >> valueWithArguments: anArray [
	"Entry point of one change's fan-out. Bracket the whole run so the recorder groups
	this event's reactions under one change node. anArray is { theEvent }."
	recorder ifNil: [^ super valueWithArguments: anArray].
	recorder beginChange: anArray first.
	^ [ super valueWithArguments: anArray ]
		ensure: [ recorder endChange ]
]

{
	#category : #evaluating,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:20'
}
SWAInstrumentedActionSequence >> valueWithArguments: anArray startingFrom: startIndex [
	"Same error-trapping loop as the parent, but each subscriber send is bracketed for
	wall time and allocation and reported to the recorder. The recorder is nil-guarded
	so an instance left in the map after #stop degrades to the plain sequence."
	| each answer |
	answer := nil.
	startIndex to: self size do: [:index |
		each := self at: index.
		[
			answer := self measure: each with: anArray otherwise: [ answer ].
		]
			on: Halt , Error
			do: [:exc |
				self valueWithArguments: anArray startingFrom: index + 1.
				exc pass]].
	^ answer
]
