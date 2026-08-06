"
Abstract superclass for all SWA treemap nodes (static code map, message tally, space tally). Defines the shared tree protocol so views can be walked and cross-referenced uniformly.

Shared structure: parent + children form the tree.

Subclass responsibilities:
- children: answer child nodes (#() for leaves)
- name: short display label
- totalSize: treemap weight (LOC / sample count / bytes)
- crossRefKey: canonical cross-view identity String, or nil if this node is not cross-referenceable. Classes answer their class name; methods answer 'ClassName>>selector' (metaclass: 'ClassName class>>selector'). Packages/categories/native frames answer nil.

The crossRefKey lets the three independent views (CodeMap, StSpy, SpaceTally) be linked: class names are unique, and methods are identified by 'Class>>selector'.
"
Class {
	#name : #SWANode,
	#superclass : #Object,
	#instVars : [
		'parent',
		'children'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> children [
	"Child nodes. Answer #() (not a fresh collection) for leaves so reads are cheap.
	Subclasses with lazy/computed children override."
	^ children ifNil: [#()]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 16:56'
}
SWANode >> crossRefKey [
	"Canonical cross-view identity String, or nil if this node is not
	cross-referenceable. Classes answer their class name; methods answer
	'ClassName>>selector'. Packages/categories/native frames answer nil.
	Used to link the independent CodeMap / SamplingTally / SpaceTally views."
	^ nil
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> depth [
	^ parent isNil ifTrue: [0] ifFalse: [parent depth + 1]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:06'
}
SWANode >> eventCategoryFor: aSymbol [
	"The CATEGORICAL key this event has under aSymbol -- a session id, a model name,
	a package -- or nil when it has none.

	The companion of #eventValueFor:, which answers quantities. A temporal view
	colours a quantity with an intensity ramp and a category by hashing the key to a
	hue, and only the node knows which of its properties are which."
	aSymbol == #group ifTrue: [^ self eventGroupKey].
	aSymbol == #kind ifTrue: [^ self nodeKind].
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:06'
}
SWANode >> eventColorModes [
	"{ symbol . label } pairs this node family can be coloured by, beyond the
	generic ones a temporal view always offers. Empty by default.

	Asked of ONE event and applied to the view, because a view's events are all of
	the same family -- and asking all 42769 of them what they support, to build a
	menu, would be absurd."
	^ #()
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWANode >> eventDurationMicros [
	"How LONG this node lasted, in microseconds, or nil for an instant.

	This is the one piece the existing temporal contract was missing. A commit or a
	change is a point on the axis and needs only #eventTimeStamp; a CALL is an
	interval, and an interval is what turns a histogram of instants
	(SWATimelineMorph) into a flame chart. Implementing this -- plus #eventMicros --
	is the whole contract a node family needs to be drawn as spans.

	nil by default: almost nothing is an interval."
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWANode >> eventGroupKey [
	"The identity of the ATOMIC ACT this node was part of -- a git commit, an image
	save -- or nil when it does not belong to one. Used by the temporal views'
	'commits' measure, which counts distinct acts rather than individual changes.
	nil by default."
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:17'
}
SWANode >> eventLaneKey [
	"Which horizontal BAND this node belongs in when a temporal view draws spans
	rather than instants.

	A histogram of instants needs no such thing -- everything stacks into one
	bucket. Spans do: two things that overlap in time cannot share a row, and the
	useful grouping is almost never 'whatever happened to arrive next'. For a
	conversation it is who was speaking; for a trace it is the process.

	Defaults to #nodeKind, which every SWANode has."
	^ self nodeKind
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:03'
}
SWANode >> eventMicros [
	"WHEN this node happened, as absolute microseconds on the utcMicrosecondClock, or
	nil if it has no position in time.

	The microsecond twin of #eventTimeStamp, added for the TRACE view. Both exist on
	purpose: #eventTimeStamp is a DateAndTime, which is the right currency for a
	change set or a commit and the wrong one for a call that lasted 40 us -- the
	existing temporal views truncate it with #asSeconds, which at trace scale rounds
	every event in a run to the same instant. Nodes that are only dated to the second
	implement #eventTimeStamp; nodes that are timed implement this.

	Default derives from #eventTimeStamp when there is one, so any existing node
	family is placeable on a microsecond axis for free (at second resolution), and
	nil otherwise."
	^ self eventTimeStamp
		ifNil: [nil]
		ifNotNil: [:t | t asSeconds * 1000000]
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWANode >> eventTimeStamp [
	"WHEN this node happened, as a DateAndTime/TimeStamp, or nil if it has no
	position in time. This is the whole contract the temporal views
	(SWATimelineMorph, SWACalendarMorph) need -- implementing it is what makes a
	node family placeable on a time axis, without those views knowing anything about
	changes, commits or methods.

	nil by default: most nodes (a package, a heap object) are not events."
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:28'
}
SWANode >> eventValueFor: aSymbol [
	"How much this event is WORTH under aSymbol, or nil when the node has nothing to
	say about that measure.

	This is what a span's HEIGHT maps. A histogram of instants can only ever plot
	how many things happened near a moment; once an event is a box on the axis its
	height is free, and 'this call took four seconds' or 'this message cost three
	cents' is a far more useful second dimension than a repeat of the count."
	aSymbol == #count ifTrue: [^ 1].
	aSymbol == #duration ifTrue: [^ self eventDurationMicros].
	(aSymbol == #loc or: [aSymbol == #bytes]) ifTrue: [^ self totalSize max: 0].
	^ nil
]

{
	#category : #temporal,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:28'
}
SWANode >> eventValueIsPerGroup: aSymbol [
	"Does #eventValueFor: answer a quantity belonging to the whole GROUP
	(#eventGroupKey) rather than to this node alone?

	Cost and tokens are accounted per MESSAGE, and every part of that message
	answers the same number. Colour may repeat it harmlessly; a HEIGHT may not --
	summing it over the parts would multiply the message's cost by its part count
	and make the chart lie about the totals. A view that plots such a measure
	divides by the group size."
	^ false
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> isLeaf [
	^ self children isEmpty
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:56'
}
SWANode >> markKey [
	"Cross-view identity String used by the GLOBAL mark set (SWAMarkSet) to bookmark
	this node across every open view, or nil if this node is not markable. Defaults
	to #crossRefKey (class name, or 'ClassName>>selector' for methods). Node kinds
	that have no crossRefKey but ARE meaningful marks -- notably PACKAGES and
	CATEGORIES -- override this to answer their own name. Kept distinct from
	crossRefKey so the coverage/space-tally cross-referencing (which is deliberately
	class-granular and nil for packages) is unaffected."
	^ self crossRefKey
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> name [
	^ self subclassResponsibility
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:10'
}
SWANode >> nodeKind [
	"A machine-readable Symbol naming the KIND of thing this node represents -- what its
	markKey points at -- independent of the view it is shown in. For code nodes this is
	the existing #kind (#class / #package / #method / #category); other node families
	answer their own (#spaceTally, #samplingTally, #change). Recorded in mark provenance
	(as a String) so a mark remembers whether it is a class, a package, a space-tally
	node, etc. Default: #kind if the node defines one, else a symbol derived from the
	class name (strip 'SWA'/'Node', lowercase first letter)."
	| n |
	(self respondsTo: #kind) ifTrue: [^ self kind].
	n := self class name asString.
	(n beginsWith: 'SWA') ifTrue: [n := n allButFirst: 3].
	(n endsWith: 'Node') ifTrue: [n := n allButLast: 4].
	n isEmpty ifTrue: [^ #node].
	^ (n first asLowercase asString, n allButFirst) asSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> parent: aNode [
	parent := aNode
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> pathString [
	"Slash-separated path from the root to the receiver (for balloon help)."
	^ parent isNil
		ifTrue: [self name]
		ifFalse: [parent pathString, ' / ', self name]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> totalSize [
	"Treemap weight (LOC / sample count / bytes). Subclasses define."
	^ self subclassResponsibility
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:32'
}
SWANode >> withAllChildrenDo: aBlock [
	"Evaluate aBlock with the receiver and every descendant (depth-first)."
	aBlock value: self.
	self children do: [:c | c withAllChildrenDo: aBlock]
]
