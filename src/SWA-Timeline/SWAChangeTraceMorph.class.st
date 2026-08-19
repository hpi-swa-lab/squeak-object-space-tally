"
Timeline of live system changes, weighted by the memory each edit cost.

Reuses SWATimelineMorph whole -- the histogram of activity over time, the per-bucket
stacked bands, the spans mode, the zoom/pan/axis -- and adds the two things this data
has that a change-set timeline does not:

 - measure #bytes: a bucket's height (and each band's share) is the bytes allocated
   during those edits' SystemChangeNotifier fan-out, so the GC cost of live-coding is
   the height of the trace. (#count still counts changes.)
 - default colour mode #kind, contributed by SWAChangeTraceNode>>eventColorModes, so
   each change type gets its own hue with no view-side code.

Fed by an SWAChangeTraceRecorder, refreshed by an SWAChangeTraceStepper as edits
arrive. Open with SWAChangeTraceRecorder open.
"
Class {
	#name : #SWAChangeTraceMorph,
	#superclass : #SWATimelineMorph,
	#instVars : [
		'recorder'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:33'
}
SWAChangeTraceMorph >> initialize [
	super initialize.
	measure := #bytes.
	colorMode := #kind.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:33'
}
SWAChangeTraceMorph >> isFollowingTail [
	"True when the visible window still covers the whole event span -- i.e. the user has
	not zoomed or panned in. Only then does a refresh re-fit the range to new events; a
	zoomed-in view is left alone. nil range (freshly reset) counts as following."
	| span |
	(viewStart isNil or: [viewEnd isNil]) ifTrue: [^ true].
	span := self timeSpan ifNil: [^ true].
	^ viewStart <= span first and: [viewEnd >= span second]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:25'
}
SWAChangeTraceMorph >> measureOptions [
	"In the histogram, height is bytes allocated or a plain count. In spans mode fall
	through to the inherited span catalogue."
	self layoutMode == #spans ifTrue: [^ super measureOptions].
	^ { {#bytes. 'Bytes allocated (GC cost)'}.
		{#duration. 'Time spent (us)'}.
		{#count. 'Number of reactions'} }
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:15'
}
SWAChangeTraceMorph >> minTimeSpanUnits [
	"Seconds. The inherited hour is for git/change-set timelines where every change in
	a commit shares one timestamp; a live trace has real sub-second spacing, and the
	hour floor stretches a two-minute session across an empty hour axis so the events
	pile into the first few buckets. Two seconds is enough to keep a single-event
	trace from dividing by zero."
	^ 2
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:35'
}
SWAChangeTraceMorph >> minZoomUnits [
	"One second. The inherited minute is right for a change-set timeline bucketed to
	the second, but reactions are microseconds apart -- a burst of a whole edit's
	fan-out lives inside one second -- so zoom has to resolve far tighter here to
	separate them."
	^ 1
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:09'
}
SWAChangeTraceMorph >> recorder: aRecorder [
	recorder := aRecorder.
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:33'
}
SWAChangeTraceMorph >> refreshFromRoot: aRoot info: aString [
	"Re-seat the rolling root and relayout, PRESERVING any zoom and selection the user
	set. Called by the stepper only when the event count changed.

	The earlier version called resetZoom on every refresh, which wiped a manual zoom or
	selection the instant the next change arrived -- live capture fought the user. Now:
	only the tail-following case (no manual zoom) re-derives the range; a zoomed-in view
	keeps its window, and the selected node is re-seated by identity if it survives."
	| keepStart keepEnd keepSelection wasFollowing |
	keepStart := viewStart. keepEnd := viewEnd.
	keepSelection := selectedNode.
	"Following = the visible range currently covers the whole span (no manual zoom).
	Derived from state, not a flag, so wheel/pan/back -- which set the range directly
	without going through #zoomToStart:end: -- are all handled."
	wasFollowing := self isFollowingTail.
	self setRoot: aRoot.
	self metaInfo: aString.
	wasFollowing
		ifTrue: [viewStart := viewEnd := nil]
		ifFalse: [viewStart := keepStart. viewEnd := keepEnd. selectedNode := keepSelection].
	self flushLayout.
	self flushCache.
	self refreshChrome.
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:26'
}
SWAChangeTraceMorph >> valueForNode: aNode [
	"One event's share of its bucket under #bytes -- its own allocation."
	self measure == #bytes ifTrue: [^ aNode allocatedBytes max: 0].
	self measure == #duration ifTrue: [^ (aNode eventValueFor: #duration) ifNil: [0]].
	^ super valueForNode: aNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/19/2026 14:25'
}
SWAChangeTraceMorph >> valueForNodes: aCollection [
	"Bucket height under #bytes is the summed allocation of the edits in it."
	self measure == #bytes ifTrue: [
		^ aCollection inject: 0 into: [:s :n | s + (n allocatedBytes max: 0)]].
	self measure == #duration ifTrue: [
		^ aCollection inject: 0 into: [:s :n | s + ((n eventValueFor: #duration) ifNil: [0])]].
	^ super valueForNodes: aCollection
]
