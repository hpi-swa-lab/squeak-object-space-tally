"
A single live-captured system change, timed to the microsecond and weighted by the
memory it cost.

The SWA-ChangeMap SWAChangeNode models changes parsed from the .changes file, dated
to the second and weighted by diff lines. This subclass is its live twin: it is fed
by SWAChangeTraceRecorder straight from SystemChangeNotifier as you edit, carries a
utcMicrosecondClock stamp (a burst of edits inside one second must not collapse onto
one instant in a span view), and weighs by allocatedBytes -- the bytes allocated
during that edit's synchronous fan-out to all ~8 SystemChangeNotifier subscribers.

That weight is the point: it makes the per-edit GC cost of the fan-out (GSCodeMapper
rebuilding dependent sets, Monticello dirtying working copies) the height of each
span on the trace, so a run of edits shows where the scavenger pressure comes from.

crossRefKey is inherited, so a captured method change links to the same method in the
Code Map and Space Tally.
"
Class {
	#name : #SWAChangeTraceNode,
	#superclass : #SWAChangeNode,
	#instVars : [
		'micros',
		'allocatedBytes'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:24'
}
SWAChangeTraceNode >> allocatedBytes [
	"A reaction carries its own bytes; a change container sums its reactions, so the
	change's weight is the whole fan-out's allocation."
	self isLeaf ifTrue: [^ allocatedBytes ifNil: [0]].
	^ self children inject: 0 into: [:s :c | s + c allocatedBytes]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:05'
}
SWAChangeTraceNode >> crossRefKey [
	"Link to the Code Map / Space Tally. A change with a selector answers
	'ClassName>>selector', a class-level change answers the class name. Overridden
	because the parent keys on #method/#methodRemoval changeTypes; the live trace uses
	#added/#removed/#modified and distinguishes method vs class by the selector."
	self isLeaf ifFalse: [^ nil].
	self methodClassName ifNil: [^ nil].
	self methodSelector ifNotNil: [:sel |
		^ self methodClassName asString, '>>', sel asString].
	^ self methodClassName asString
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:08'
}
SWAChangeTraceNode >> eventCategoryFor: aSymbol [
	"#kind is the change TYPE here (added / removed / modified ...), not the generic
	nodeKind, so the timeline can hash each type to its own hue."
	aSymbol == #kind ifTrue: [^ self changeType].
	^ super eventCategoryFor: aSymbol
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:08'
}
SWAChangeTraceNode >> eventColorModes [
	"Offer colour-by-change-kind on top of the generic modes. Consumed by
	SWATemporalView>>colorModeOptions; #kind routes through eventCategoryFor: #kind."
	^ { {#kind. 'By change kind'} }
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:03'
}
SWAChangeTraceNode >> eventMicros [
	"Real capture time. Leaves carry it directly; containers derive from their first
	leaf so a bucket lands where its events actually are, not at a truncated second."
	micros ifNotNil: [^ micros].
	^ self children
		ifEmpty: [super eventMicros]
		ifNotEmpty: [:kids | kids first eventMicros]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:03'
}
SWAChangeTraceNode >> eventValueFor: aSymbol [
	"#bytes is this family's whole reason to exist: a span's height is the memory that
	edit cost. #count and #duration fall through to super."
	aSymbol == #bytes ifTrue: [^ self totalSize].
	^ super eventValueFor: aSymbol
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:24'
}
SWAChangeTraceNode >> isLeaf [
	"A change is a leaf only until its reactions are attached. Once it has children it
	is a container of reactions, and the timeline must collect the reactions as the
	events, not the change. (The parent keys leaf on kind == #change, which is always
	true here and would hide the reactions.)"
	^ self children isEmpty
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:03'
}
SWAChangeTraceNode >> micros: anInteger allocatedBytes: bytes [
	micros := anInteger.
	allocatedBytes := bytes.
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:03'
}
SWAChangeTraceNode >> nodeKind [
	"#changeTrace, distinct from the parsed #change family, so marks and lanes keep the
	live trace separate from a .changes treemap."
	^ #changeTrace
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:03'
}
SWAChangeTraceNode >> totalSize [
	"Weight is bytes allocated during the fan-out, not diff lines: this is the GC-cost
	view of a change, not the code-size view. Floored at 1 so a tile never vanishes;
	containers sum their children."
	self isLeaf ifTrue: [^ self allocatedBytes max: 1].
	^ (self children inject: 0 into: [:s :c | s + c totalSize]) max: 1
]
