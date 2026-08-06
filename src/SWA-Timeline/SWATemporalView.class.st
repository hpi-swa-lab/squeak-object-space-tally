"
Abstract base for the SWA views that lay nodes out on TIME rather than on
containment: SWATimelineMorph (a linear, zoomable time axis) and SWACalendarMorph
(a GitHub-style day grid). Like the flamegraph, these are alternatives to the
treemap reached from the Tree button, sharing the same window and chrome.

GENERIC BY DESIGN. Neither view knows what a commit or a method is. A node is
placeable iff it answers SWANode>>eventTimeStamp, and it belongs to an atomic act
iff it answers SWANode>>eventGroupKey. So the same two views serve the Change Map
(.changes records), the Git Map (commits) and a plain Code Map (methods by last
changed) with no per-tool code.

MEASURE -- what the vertical extent / colour intensity means -- is switchable,
because ""how much happened"" has three honest answers:
	#loc      lines (each node's own weight: diff lines for a change, LOC for a
		  method). The default: it is the only one that distinguishes a
		  typo fix from a rewrite.
	#count    number of changes -- activity irrespective of size
	#commits  number of DISTINCT commits/saves -- how many separate acts, so one
		  huge commit stops outweighing ten small ones

Subclasses supply the layout (#rebuildLayout), the drawing (#renderStaticLayerOn:at:)
and the hit test (#nodeAt: / #cellAt:); everything else -- event collection,
measures, colour (including dataset metrics), selection, marks, search-dim and the
cached-Form render loop -- lives here.
"
Class {
	#name : #SWATemporalView,
	#superclass : #SWAView,
	#instVars : [
		'events',
		'measure',
		'colorMode',
		'metaInfo',
		'viewStart',
		'viewEnd',
		'timeHistory',
		'dragStart',
		'dragNow'
	],
	#category : #'SWA-Timeline',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:38'
}
SWATemporalView class >> on: aNode [
	"Create a temporal view over any SWANode tree whose leaves answer
	#eventTimeStamp. Same constructor shape as the treemaps and the flamegraph, so
	SWAStructure>>buildViewExtent: can build one without a special case."
	^ self new setRoot: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:07'
}
SWATemporalView >> baseColorForNode: aNode [
	"Intrinsic fill for one event. Dataset metrics are handled upstream by
	SWAView>>intrinsicColorForNode:, which consults #metricForMode: first."
	| m |
	m := self colorMode.
	m == #author ifTrue: [
		| a |
		a := (aNode respondsTo: #author) ifTrue: [aNode author] ifFalse: [nil].
		^ a ifNil: [Color gray: 0.35] ifNotNil: [:x | Color h: x hash \\ 360 s: 0.55 v: 0.82]].
	m == #group ifTrue: [
		| k |
		k := aNode eventGroupKey.
		^ k ifNil: [Color gray: 0.35] ifNotNil: [:x | Color h: x hash \\ 360 s: 0.5 v: 0.85]].
	"Node-family modes: a CATEGORY hashes to a hue, a VALUE goes on the intensity
	ramp. Category first -- #kind is both a category and nothing else, and asking
	for a value would answer nil and fall through to the heat of the measure, which
	is not what was picked."
	(aNode eventCategoryFor: m) ifNotNil: [:k |
		^ Color h: k asString hash \\ 360 s: 0.5 v: 0.85].
	(aNode eventValueFor: m) ifNotNil: [:v |
		^ self intensityColorFor: v max: (self maxEventValueFor: m)].
	"A nil CATEGORY is not missing data to be heat-mapped -- it is 'this event has
	no package', which must read as neutral rather than as cold."
	(self isCategoricalColorMode: m) ifTrue: [^ Color gray: 0.28].
	^ self heatColorForNode: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> colorMode [
	^ colorMode ifNil: [#default]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> colorMode: aSymbol [
	"Recolouring never moves anything, so only the pixels are dropped -- the same
	'recolour is instant, resize reflows' split the treemaps use."
	colorMode := aSymbol.
	self flushCache
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:07'
}
SWATemporalView >> colorModeOptions [
	"Intrinsic colour modes. Dataset metrics are appended by SWAView's machinery,
	so a loaded coverage/churn/duplication set colours these views too."
	| opts |
	opts := OrderedCollection new.
	opts add: {#default. 'By measure (heat)'}.
	opts add: {#author. 'By author'}.
	opts add: {#group. 'By commit / save'}.
	"Whatever the node family adds -- see SWANode>>eventColorModes. Asked of one
	event, because a view's events are all of the same family."
	self events ifNotEmpty: [:e | opts addAll: e first eventColorModes].
	^ opts asArray
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> drawOn: aCanvas [
	"Blit the cached static layer, like the treemap and flamegraph: rendering these
	views is far too expensive to redo per frame."
	| form |
	self ensureLayout.
	self ensureZoomBar.
	form := self ensureCachedForm.
	aCanvas
		image: form
		at: self position
		sourceRect: form boundingBox
		rule: Form over
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:17'
}
SWATemporalView >> durationSecondsOf: aNode [
	"How LONG aNode lasted on the time axis, in seconds, or nil for an instant.
	The companion of #secondsOf:, and the whole of what a view needs to draw a node
	as a span rather than as a point."
	^ aNode eventDurationMicros ifNotNil: [:us | us / 1000000]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> ensureCachedForm [
	| form |
	cachedForm ifNotNil: [^ cachedForm].
	form := Form extent: self extent depth: Display depth.
	self renderStaticLayerOn: form getCanvas at: 0 @ 0.
	^ cachedForm := form
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> ensureLayout [
	self subclassResponsibility
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWATemporalView >> events [
	"Every placeable node under the root, chronologically. Built once and cached.

	Only LEAVES are collected. In a change/git tree the containers (day, commit,
	class) carry a timestamp too, and counting them as well would double-count every
	change against its own ancestors; the leaf is the event."
	events ifNotNil: [^ events].
	events := OrderedCollection new.
	rootNode ifNil: [^ events].
	rootNode withAllChildrenDo: [:n |
		(n isLeaf and: [n eventTimeStamp notNil]) ifTrue: [events add: n]].
	events := events asSortedCollection: [:a :b |
		a eventTimeStamp asSeconds <= b eventTimeStamp asSeconds].
	events := events asOrderedCollection.
	^ events
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> extent: aPoint [
	aPoint = self extent ifFalse: [self flushLayout].
	super extent: aPoint
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> flushCache [
	"Drop only the rendered pixels -- the layout survives. This is the cheap path
	used for recolouring and selection."
	cachedForm := nil.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWATemporalView >> flushEvents [
	events := nil.
	self flushLayout
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> flushLayout [
	"Invalidate geometry AND pixels. Subclasses extend to drop their own caches."
	cachedForm := nil.
	self changed
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> handlesMouseDown: evt [
	^ true
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATemporalView >> handlesMouseWheel: evt [
	"Always -- CTRL-wheel zooms time even when everything fits vertically and there is
	nothing to scroll."
	^ true
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> hasGroupKeys [
	"Do these events belong to atomic acts (commits/saves)? Answers on the FIRST one
	that does -- the answer is really a property of the node class, so this returns
	immediately for a change/git tree and only walks the whole list (cheaply) for a
	code tree, where there is nothing to find."
	^ (self events anySatisfy: [:n | n eventGroupKey notNil])
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> heatColorForNode: aNode [
	"Default event colour: a log heat on the node's own contribution to the current
	measure, so a big rewrite reads hotter than a one-line tweak inside the same
	bar. Log-scaled because change sizes are heavily skewed -- most edits are tiny
	and a linear ramp would paint everything at the cold end."
	| v t |
	v := self valueForNode: aNode.
	t := v <= 1 ifTrue: [0.0] ifFalse: [((v ln / 200 ln) min: 1.0) max: 0.0].
	^ Color h: 200 - (t * 190) s: 0.55 + (t * 0.2) v: 0.62 + (t * 0.3)
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> history [
	"The panel's Back button drives this; for a temporal view 'back' is a time range,
	not a node."
	^ timeHistory ifNil: [timeHistory := OrderedCollection new]
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:33'
}
SWATemporalView >> initialize [
	super initialize.
	self extent: 1000 @ 600.
	self color: (Color gray: 0.12).
	self borderWidth: 0.
	measure := #loc.
	colorMode := #default
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> intensityColorFor: aValue max: aMax [
	"GitHub-style single-hue intensity ramp for an AGGREGATE bucket (a day, a bar):
	a dark empty cell, then four steps of green. Log-normalised against aMax for the
	same skew reason as #heatColorForNode:."
	| t |
	aValue <= 0 ifTrue: [^ Color gray: 0.17].
	t := aMax <= 1
		ifTrue: [1.0]
		ifFalse: [(((aValue max: 1) ln / aMax ln) min: 1.0) max: 0.0].
	^ Color h: 135 s: 0.35 + (t * 0.45) v: 0.32 + (t * 0.58)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:07'
}
SWATemporalView >> isCategoricalColorMode: aSymbol [
	"Does aSymbol name a CATEGORY of the node family rather than a quantity? Decided
	by asking the events, not from a hardcoded list, so a node family that adds a
	mode does not have to tell this class about it too. Cached per mode: this is
	consulted once per drawn cell."
	| known |
	known := self valueOfProperty: #categoricalModes ifAbsentPut: [Dictionary new].
	^ known at: aSymbol ifAbsentPut: [
		self events anySatisfy: [:n | (n eventCategoryFor: aSymbol) notNil]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 16:07'
}
SWATemporalView >> maxEventValueFor: aSymbol [
	"Largest single-event value under aSymbol, which sets the ramp for a value
	colour mode. Cached per mode -- an uncached scan of 42769 events per drawn cell
	would be quadratic."
	| known |
	known := self valueOfProperty: #maxEventValues ifAbsentPut: [Dictionary new].
	^ known at: aSymbol ifAbsentPut: [
		(self events inject: 0 into: [:m :n | m max: ((n eventValueFor: aSymbol) ifNil: [0])])
			max: 0.000000001]
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> measure [
	"#loc / #count / #commits -- see the class comment."
	^ measure ifNil: [#loc]
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> measure: aSymbol [
	"Switch the measure and re-lay-out (unlike colour, the measure changes tile
	geometry, so the cached Form is not enough)."
	measure := aSymbol.
	self flushLayout.
	self refreshChrome
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> measureLabel [
	| m |
	m := self measure.
	^ (self measureOptions detect: [:p | p first == m] ifNone: [{m. m asString}]) second
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> measureOptions [
	"{ symbol. label } pairs. #commits is offered only when the nodes actually
	belong to commits/saves -- on a plain Code Map they do not, and an always-zero
	measure is worse than an absent one."
	| opts |
	opts := OrderedCollection new.
	opts add: {#loc. 'Lines (diff size / LOC)'}.
	opts add: {#count. 'Number of changes'}.
	self hasGroupKeys ifTrue: [opts add: {#commits. 'Number of commits / saves'}].
	^ opts asArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> metaInfo: aString [
	metaInfo := aString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> metaInfoString [
	^ metaInfo ifNil: ['']
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> minTimeSpanUnits [
	"Smallest span #timeSpan will report, so a burst of simultaneous events still gets
	a drawable width. One hour in the default (seconds) unit -- every change in one
	commit shares a timestamp exactly, and a zero-width axis divides by zero."
	^ 3600
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> minZoomUnits [
	"Refuse to zoom tighter than this, because past it the view shows nothing new --
	for the bucketed timeline, one minute is where every bucket is already one second
	wide. Views whose layout keeps resolving further down (a trace) override."
	^ 60
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> panBy: aFraction [
	"Slide the visible range sideways by aFraction of its own width, clamped to the full
	span so panning can never leave the data.

	Deliberately does NOT touch the zoom history. Panning is not zooming, and a Back
	button that has to undo forty nudges before it undoes the zoom you actually want to
	leave is a Back button nobody presses. Hitting the edge keeps the WIDTH and gives up
	the movement, rather than squashing the range against the boundary."
	| r full width delta lo hi |
	r := self viewRange ifNil: [^ self].
	full := self timeSpan ifNil: [^ self].
	width := r second - r first.
	delta := (width * aFraction) rounded.
	lo := r first + delta.
	hi := r second + delta.
	lo < full first ifTrue: [hi := hi + (full first - lo). lo := full first].
	hi > full second ifTrue: [lo := lo - (hi - full second). hi := full second].
	lo := lo max: full first.
	hi := hi min: full second.
	(lo = r first and: [hi = r second]) ifTrue: [^ self].
	viewStart := lo.
	viewEnd := hi.
	self flushLayout.
	self refreshChrome
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> panLeft [
	"Slide the view a quarter-range earlier."
	self panBy: -0.25
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> panRight [
	"Slide the view a quarter-range later."
	self panBy: 0.25
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> refreshChrome [
	navPanel ifNotNil: [:p | p refresh]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> renderStaticLayerOn: aCanvas at: anOrigin [
	self subclassResponsibility
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> resetZoom [
	timeHistory := OrderedCollection new.
	viewStart := viewEnd := nil.
	self flushLayout.
	self refreshChrome
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 13:17'
}
SWATemporalView >> secondsOf: aNode [
	"aNode's position on the time axis, in seconds, or nil.

	FRACTIONAL where the node knows better. #eventTimeStamp asSeconds is a whole
	number, which is the right resolution for a commit and the wrong one for a tool
	call that ran for 300 ms -- at one-second granularity a burst of them collapses
	onto a single instant and a span view of them has nothing to draw. A node that
	implements #eventMicros answers here at microsecond resolution instead.

	No regression for anyone: SWANode>>eventMicros derives from #eventTimeStamp when
	a node has only a date, and that derivation lands on the same whole second."
	aNode eventMicros ifNotNil: [:us | ^ us / 1000000].
	^ aNode eventTimeStamp ifNotNil: [:t | t asSeconds]
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> selectNode: aNode [
	selectedNode := aNode.
	self flushCache.
	self refreshChrome
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> selectTileNode: aNode [
	"Same name the treemaps use, so panel code and scripts can drive any SWA view
	the same way."
	self selectNode: aNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> selectedSourceString [
	"Show-pane content: reuse whatever the node family already knows how to show --
	an inline diff for a change node, plain source otherwise."
	| n |
	n := selectedNode ifNil: [^ ''].
	(n respondsTo: #hasDiffBaseline) ifTrue: [
		n hasDiffBaseline ifTrue: [
			^ (('"diff vs previous version  (', (n crossRefKey ifNil: ['?']), ')"',
				String cr, String cr) asText),
			  (TextDiffBuilder buildDisplayPatchFrom: n diffFromSource to: n diffToSource)]].
	(n respondsTo: #sourceText) ifTrue: [^ (n sourceText ifNil: ['']) asString].
	(n respondsTo: #sourceString) ifTrue: [^ (n sourceString ifNil: ['']) asString].
	^ ''
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> selectionPathString [
	"Detail line for the selected event. (SWAPane content protocol.)"
	| n |
	n := selectedNode ifNil: [^ ''].
	^ String streamContents: [:s |
		s nextPutAll: n name.
		n eventTimeStamp ifNotNil: [:t |
			s nextPutAll: '   '; nextPutAll: t asDate printString;
				nextPutAll: ' '; nextPutAll: t asTime print24].
		(n respondsTo: #author) ifTrue: [
			n author ifNotNil: [:a | s nextPutAll: '   '; nextPutAll: a]].
		s nextPutAll: '   '; print: (self valueForNode: n); nextPutAll: ' lines']
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:35'
}
SWATemporalView >> setRoot: aNode [
	rootNode := aNode.
	events := nil.
	self flushLayout.
	self flushMarksCache.
	self rebuildKeyIndex.
	^ self
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:54'
}
SWATemporalView >> structureLabel [
	^ self class name
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> timeAtX: anX [
	"Inverse of the x mapping -- what moment a pixel column stands for, in this view's
	time units."
	| range |
	range := self viewRange ifNil: [^ nil].
	^ range first + ((anX max: 0) / (self width max: 1) * (range second - range first))
]

{
	#category : #events,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> timeSpan [
	"{ first . last } over all events, in this view's TIME UNITS (see #timeUnitsOf:),
	or nil when there are none. Padded to at least #minTimeSpanUnits so a burst of
	simultaneous events -- every change in one commit shares a timestamp exactly --
	still gets a drawable width instead of dividing by zero."
	| evts first last |
	evts := self events.
	evts isEmpty ifTrue: [^ nil].
	first := self timeUnitsOf: evts first.
	last := self timeUnitsOf: evts last.
	last - first < self minTimeSpanUnits
		ifTrue: [last := first + self minTimeSpanUnits].
	^ {first. last}
]

{
	#category : #'time base',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> timeUnitsOf: aNode [
	"WHERE aNode sits on this view's time axis, in whatever unit the view works in.

	This is the seam that lets one set of range/zoom/pan machinery serve views at
	wildly different scales. The change and git timelines work in SECONDS, because
	that is the resolution their data actually has -- a commit is dated, not timed.
	A call trace works in MICROSECONDS, and would be a single degenerate bar if it
	were forced through #asSeconds.

	Default is seconds, which is what every existing temporal view wants."
	^ self secondsOf: aNode
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> valueForNode: aNode [
	"One event's contribution to the current measure. Under #commits a single node
	is one share of its commit, which has no meaningful per-node value -- treat it
	as 1 so stacked segments still divide the bar evenly."
	self measure == #loc ifTrue: [^ aNode totalSize max: 0].
	^ 1
]

{
	#category : #measure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:34'
}
SWATemporalView >> valueForNodes: aCollection [
	"The measure's value for a bucket of events.

	#commits is deliberately NOT a sum over nodes -- it counts DISTINCT group keys,
	so a commit touching 40 methods contributes 1, not 40. That is the whole reason
	it exists as a separate measure."
	| m |
	aCollection isEmpty ifTrue: [^ 0].
	m := self measure.
	m == #count ifTrue: [^ aCollection size].
	m == #commits ifTrue: [
		| keys |
		keys := Set new.
		aCollection do: [:n | n eventGroupKey ifNotNil: [:k | keys add: k]].
		^ keys size].
	^ aCollection inject: 0 into: [:s :n | s + (n totalSize max: 0)]
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> viewRange [
	"{ start . end } currently shown, in this view's time units; defaults to the whole
	span."
	| span |
	(viewStart notNil and: [viewEnd notNil]) ifTrue: [^ {viewStart. viewEnd}].
	span := self timeSpan ifNil: [^ nil].
	viewStart := span first.
	viewEnd := span second.
	^ {viewStart. viewEnd}
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWATemporalView >> wheelZoomBy: aFactor at: localY [
	"CTRL-wheel over a temporal view zooms TIME, the only axis it has to zoom. Routed
	through #zoomIn / #zoomOut so the wheel, the +/- buttons and the menu all leave the
	same trail in the zoom history."
	^ aFactor > 1
		ifTrue: [self zoomIn]
		ifFalse: [self zoomOut]
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> zoomBarSpecs [
	"The floating zoom strip, shared with the flow view (SWAView>>ensureZoomBar). Every
	button is a selector the right-click menu also offers -- drag-to-zoom and the menu
	remain the precise tools; this is for the two thirds of the work that is 'a bit
	further in' and 'a bit to the left', where reaching for a menu each time is
	tiresome."
	^ {
		{'-'.    #zoomOut.    'Zoom out one step (undoes the last zoom)'}.
		{'+'.    #zoomIn.     'Zoom in: halve the visible time range'}.
		{'<'.    #panLeft.    'Pan left by a quarter of the visible range'}.
		{'>'.    #panRight.   'Pan right by a quarter of the visible range'}.
		{'1:1'.  #resetZoom.  'Show the whole span again'}
	}
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:23'
}
SWATemporalView >> zoomIn [
	"Halve the visible time range, keeping its centre.

	Goes through #zoomToStart:end: like a drag does, so it pushes the same history: '-'
	undoes '+' exactly, and the pane's Back button still walks the whole trail. Refused
	silently below #minZoomUnits, which is where the view has no more detail to give."
	| r c q |
	r := self viewRange ifNil: [^ self].
	c := (r first + r second) // 2.
	q := (r second - r first) // 4.
	self zoomToStart: c - q end: c + q
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> zoomOut [
	"Pop one zoom level; at the top, reset to the full span."
	| prev |
	self history isEmpty ifTrue: [
		viewStart := viewEnd := nil.
		self flushLayout.
		^ self refreshChrome].
	prev := self history removeLast.
	viewStart := prev first. viewEnd := prev second.
	selectedNode := nil.
	self flushLayout.
	self refreshChrome
]

{
	#category : #zooming,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 11:26'
}
SWATemporalView >> zoomToStart: s end: e [
	"Focus a time range, remembering the previous one so Back / right-click returns.
	Ranges shorter than #minZoomUnits are refused -- past that the view has no more
	detail to give."
	| lo hi |
	lo := s min: e. hi := s max: e.
	hi - lo < self minZoomUnits ifTrue: [^ self].
	self history addLast: self viewRange.
	viewStart := lo. viewEnd := hi.
	selectedNode := nil.
	self flushLayout.
	self refreshChrome
]
