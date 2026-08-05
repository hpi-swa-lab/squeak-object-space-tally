"
Treemap over an SWAOpenCodeNode tree -- either the file tree (what the agent
read and wrote on disk) or the session tree (every tool call, grouped by
conversation). Tile area is the number of accesses.

The default colouring is the READ/WRITE MIX rather than a single intensity,
because the interesting distinction here is not how much a thing was touched
but whether it was touched to LOOK or to CHANGE. Blue means the agent kept
reading it and never edited it -- attention spent without producing anything,
which no other tool in the suite can show. Orange means it was rewritten.

#alternateStructures puts the Timeline and Calendar in the Tree menu, over the
same nodes: SWAOpenCodeNode answers #eventTimeStamp and #eventGroupKey, so the
temporal views need nothing else.
"
Class {
	#name : #SWAOpenCodeTreemapMorph,
	#superclass : #SWATreemapMorph,
	#instVars : [
		'statsCache'
	],
	#category : #'SWA-OpenCode',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> alternateStructures [
	"SWAOpenCodeNodes answer #eventTimeStamp and #eventGroupKey, so the temporal
	views work over these very nodes with no adaptation -- 'when did this happen'
	and 'on which days' over the same tree, from the Tree menu."
	^ {
		SWAStructure key: #timeline label: 'Timeline (tool calls over time)'
			view: SWATimelineMorph rootBlock: [rootNode].
		SWAStructure key: #calendar label: 'Calendar (activity per day)'
			view: SWACalendarMorph rootBlock: [rootNode]
	}
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> balloonPayload: aPayload on: s [
	(aPayload isKindOf: SWAOpenCodeSession) ifTrue: [
		s nextPutAll: 'agent:  '; nextPutAll: (aPayload agent ifNil: ['-']); cr.
		s nextPutAll: 'model:  '; nextPutAll: (aPayload modelId ifNil: ['-']); cr.
		s nextPutAll: 'cost:   $'; nextPutAll: (aPayload cost printShowingDecimalPlaces: 2); cr.
		s nextPutAll: 'wall:   '; nextPutAll: (aPayload durationMinutes printShowingDecimalPlaces: 1);
		  nextPutAll: ' min'; cr.
		aPayload wasCompacted ifTrue: [s nextPutAll: '(context was compacted)'; cr]].
	(aPayload isKindOf: SWAOpenCodeToolCall) ifTrue: [
		s nextPutAll: 'tool:   '; nextPutAll: aPayload tool asString; cr.
		s nextPutAll: 'status: '; nextPutAll: (aPayload status ifNil: ['-']) asString; cr.
		aPayload durationMillis > 0 ifTrue: [
			s nextPutAll: 'took:   '; print: aPayload durationMillis; nextPutAll: ' ms'; cr].
		aPayload command ifNotNil: [:c |
			s nextPutAll: 'cmd:    '; nextPutAll: (c first: (c size min: 120)); cr]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> balloonStringFor: aNode [
	^ String streamContents: [:s |
		s nextPutAll: aNode name; cr.
		s nextPutAll: 'kind:   '; nextPutAll: aNode nodeKind asString; cr.
		s print: aNode reads; nextPutAll: ' reads, '.
		s print: aNode writes; nextPutAll: ' writes'.
		aNode others > 0 ifTrue: [s nextPutAll: ', '; print: aNode others; nextPutAll: ' untargeted'].
		s cr.
		aNode eventTimeStamp ifNotNil: [:t |
			s nextPutAll: 'last:   '; nextPutAll: t printString; cr].
		aNode payload ifNotNil: [:p | self balloonPayload: p on: s].
		aNode crossRefKey ifNotNil: [:k | s nextPutAll: 'key:    '; nextPutAll: k]]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:00'
}
SWAOpenCodeTreemapMorph >> baseColorForNode: aNode [
	"Dataset metrics win when one is bound to colour; otherwise the intrinsic modes."
	(self metricForMode: colorMode) ifNotNil: [:metric |
		^ (metric colorForNode: aNode) ifNil: [Color gray: 0.22]].
	colorMode == #writes ifTrue: [^ self intensityColorFor: aNode writes max: self maxWrites].
	colorMode == #reads ifTrue: [^ self intensityColorFor: aNode reads max: self maxReads].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #kind ifTrue: [^ self colorByNodeKind: aNode].
	^ self colorByAccessMix: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> colorByAccessMix: aNode [
	"Hue = what the accesses were FOR, brightness = how many there were.

	Blue (ratio 0) is read-only: the agent looked and looked and never changed it.
	Orange (ratio 1) is write-heavy. Grey means the node only carries calls that
	targeted nothing (bash and friends), which is not an access of this thing at all
	and must not be allowed to masquerade as one."
	| touched ratio |
	touched := aNode reads + aNode writes.
	touched = 0 ifTrue: [^ Color gray: 0.25].
	ratio := aNode writes / touched.
	^ Color
		h: 210 - (ratio * 180)
		s: 0.55
		v: 0.35 + (0.5 * (self relativeWeightOf: aNode))
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:29'
}
SWAOpenCodeTreemapMorph >> colorByNodeKind: aNode [
	| k |
	k := aNode nodeKind.
	k == #openCodeRoot ifTrue: [^ Color gray: 0.35].
	k == #openCodeDir ifTrue: [^ Color r: 0.25 g: 0.35 b: 0.5].
	k == #openCodeFile ifTrue: [^ Color r: 0.3 g: 0.55 b: 0.75].
	k == #openCodeSession ifTrue: [^ Color r: 0.45 g: 0.4 b: 0.65].
	k == #openCodeCall ifTrue: [^ Color r: 0.55 g: 0.5 b: 0.3].
	k == #openCodeMessage ifTrue: [^ Color r: 0.35 g: 0.33 b: 0.5].
	k == #openCodePart ifTrue: [^ Color r: 0.5 g: 0.48 b: 0.35].
	^ Color gray: 0.3
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> colorByRecency: aNode [
	"Warm = touched recently, cold = long ago. Scaled over the span actually
	present in this tree, not an absolute calendar, so a history of one week and a
	history of one year both use the full ramp."
	| ts span lo hi f |
	ts := aNode eventTimeStamp ifNil: [^ Color gray: 0.2].
	lo := self earliestSeconds.
	hi := self latestSeconds.
	span := hi - lo.
	span <= 0 ifTrue: [^ Color r: 0.8 g: 0.5 b: 0.2].
	f := ((ts asSeconds - lo) / span) asFloat max: 0.0.
	^ Color h: 220 - (f * 190) s: 0.6 v: 0.75
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:00'
}
SWAOpenCodeTreemapMorph >> colorModeOptions [
	^ {
		{#accessMix. 'Read / write mix'}.
		{#writes. 'Write intensity'}.
		{#reads. 'Read intensity'}.
		{#recency. 'Recency of last access'}.
		{#kind. 'Node kind'}
	}
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> earliestSeconds [
	^ self stats at: #lo
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:02'
}
SWAOpenCodeTreemapMorph >> formatWeight: aNumber [
	^ aNumber printString , ' acc'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:00'
}
SWAOpenCodeTreemapMorph >> initialize [
	super initialize.
	colorMode := #accessMix
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> latestSeconds [
	^ self stats at: #hi
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> maxAccesses [
	^ self stats at: #maxAccesses
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> maxReads [
	^ self stats at: #maxReads
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> maxWrites [
	^ self stats at: #maxWrites
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:12'
}
SWAOpenCodeTreemapMorph >> overlayClass [
	"The event/menu overlay this view uses -- a view-policy hook the SWAPane also
	reads when morphing between structures. The base overlay is enough here: it
	already supplies hover highlight, canvas-drawn tooltips, click-select /
	click-again-zoom / shift-mark and the Size/Color menus, and this view adds no
	decoration (clone links, coverage bars) that would need a subclass."
	^ SWATreemapOverlay
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> relativeWeightOf: aNode [
	"0..1 on a LOG scale. Accesses are heavily skewed -- a handful of files are
	touched fifty times while most are touched once -- so a linear ramp would paint
	everything except the top few the same dark shade."
	| max v |
	max := self maxAccesses.
	max <= 1 ifTrue: [^ 1.0].
	v := (aNode reads + aNode writes) max: 1.
	^ (v ln / max ln) min: 1.0
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> setRoot: aNode [
	statsCache := nil.
	^ super setRoot: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:01'
}
SWAOpenCodeTreemapMorph >> stats [
	"Colour ramps need the extremes of the WHOLE tree, and every tile asks for them
	on every repaint. One walk, cached, flushed in #setRoot:.

	Maxima are taken over LEAVES only. A container's rolled-up total is by
	construction the largest number in its subtree, so including containers would
	set the ceiling to the root's grand total and flatten every leaf to the bottom
	of the ramp."
	| maxA maxR maxW lo hi |
	statsCache ifNotNil: [^ statsCache].
	maxA := 0. maxR := 0. maxW := 0. lo := nil. hi := nil.
	rootNode ifNotNil: [
		rootNode withAllChildrenDo: [:n |
			n isLeaf ifTrue: [
				maxA := maxA max: n reads + n writes.
				maxR := maxR max: n reads.
				maxW := maxW max: n writes].
			n eventTimeStamp ifNotNil: [:ts |
				| secs |
				secs := ts asSeconds.
				(lo isNil or: [secs < lo]) ifTrue: [lo := secs].
				(hi isNil or: [secs > hi]) ifTrue: [hi := secs]]]].
	^ statsCache := Dictionary new
		at: #maxAccesses put: (maxA max: 1);
		at: #maxReads put: (maxR max: 1);
		at: #maxWrites put: (maxW max: 1);
		at: #lo put: (lo ifNil: [0]);
		at: #hi put: (hi ifNil: [0]);
		yourself
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 15:00'
}
SWAOpenCodeTreemapMorph >> viewKind [
	^ #openCodeMap
]
