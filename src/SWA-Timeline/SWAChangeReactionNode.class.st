"
One subscriber's reaction to a single change: which handler ran, how long it took,
how much it allocated.

The child level of the change trace. When SWAChangeTraceRecorder captures an edit it
also captures, via SWAInstrumentedActionSequence, one of these per SystemChangeNotifier
subscriber that fired for it -- SmalltalkImage>>event:, GSCodeMapper>>systemChanged:,
MCWorkingCopy class>>methodModified:, ChangeSet>>event:, and so on. subscriberName is
'Receiver>>selector', durationMicros is the wall time of that send, and the inherited
allocatedBytes is what it allocated.

This is where the trace earns its keep: the change node above sums its reactions, but
the reactions themselves say WHICH one is expensive. Colour by #kind here is the
subscriber, not the change type, so a lane-per-subscriber span view shows GSCodeMapper
paying the same tax on every edit.
"
Class {
	#name : #SWAChangeReactionNode,
	#superclass : #SWAChangeTraceNode,
	#instVars : [
		'subscriberName',
		'durationMicros'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> crossRefKey [
	"Link to the HANDLER method, so selecting an expensive reaction can browse the code
	that costs -- e.g. 'GSCodeMapper class>>systemChanged:'. subscriberName already has
	that form."
	^ subscriberName
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> durationMicros [
	^ durationMicros ifNil: [0]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> eventCategoryFor: aSymbol [
	"At the reaction level #kind and #subscriber both mean the HANDLER -- that is the
	useful hue here (GSCodeMapper vs ChangeSet), not the change type."
	(aSymbol == #kind or: [aSymbol == #subscriber])
		ifTrue: [^ subscriberName].
	^ super eventCategoryFor: aSymbol
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> eventColorModes [
	^ { {#subscriber. 'By subscriber'} }
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> eventDurationMicros [
	"Wall time of this reaction, so a spans view can draw it as a box of its real
	width instead of an instant."
	^ durationMicros
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> eventLaneKey [
	"One lane per subscriber in a spans view, so each handler's reactions line up in a
	row and a constant tax like GSCodeMapper's reads as a solid band."
	^ subscriberName
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> eventValueFor: aSymbol [
	"#duration is this level's second axis: how long the reaction took, in micros.
	#bytes falls through to the inherited allocation."
	aSymbol == #duration ifTrue: [^ self durationMicros].
	^ super eventValueFor: aSymbol
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> isLeaf [
	"A reaction is always a leaf -- it has no children and IS the event a timeline
	collects. The inherited test keys on kind == #change, which a reaction is not."
	^ true
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:21'
}
SWAChangeReactionNode >> subscriberName [
	^ subscriberName
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:25'
}
SWAChangeReactionNode >> subscriberName: aString micros: whenMicros durationMicros: durMicros allocatedBytes: bytes [
	subscriberName := aString.
	durationMicros := durMicros.
	self micros: whenMicros allocatedBytes: bytes.
	"eventTimeStamp too: SWATimelineMorph>>events collects only nodes that answer one
	and sorts by it. #eventMicros (from whenMicros) keeps sub-second ordering; the
	DateAndTime is just second-resolution and only needs to be non-nil and monotonic."
	self timeStamp: DateAndTime now.
	self label: aString.
	self kind: #reaction.
	self changeType: #reaction.
]
