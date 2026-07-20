"
One named, axis-bindable METRIC exposed by a SWADataset (see journal 2026-06-30 + follow-ups).

A single loaded analysis file is NOT one overlay: e.g. squeak-coverage.json carries a covering-test count ('By coverage') AND, when present, a raw invocation count ('By call'). Each such metric is a SWADatasetMetric -- the actual unit the Color and Size menus bind to. The menu shows one entry per metric, labelled '<metric label> [<dataset name>]', e.g. 'By coverage [squeak-coverage.json]'.

A metric answers a RAW per-node value (#rawValueForKey:) and rolls it up to containers with its #rollup kind (#max for heat-style values like duplication/coverage color; #sum for additive size-style values like call counts). It can drive #color (via its #scale) and/or #size (as a tile weight), per #axes.

Instance variables:
	dataset    - the owning SWADataset (source data + display name)
	id         - metric identity, e.g. #coverage / #call / #duplication
	label      - menu phrase, e.g. 'By coverage' / 'By call' / 'By duplication'
	axes       - Array of #color and/or #size: which treemap axes this metric drives
	rollup     - #max or #sum: how container nodes aggregate leaf values
	scale      - raw value -> Color valuable (for the color axis); kind default if nil
	modeSymbol - the unique symbol minted for this metric in the Color/Size menus
"
Class {
	#name : #SWADatasetMetric,
	#superclass : #Object,
	#instVars : [
		'dataset',
		'id',
		'label',
		'axes',
		'rollup',
		'scale',
		'modeSymbol',
		'colorBlock'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> axes [
	"Array of #color and/or #size -- which treemap axes this metric can drive."
	^ axes ifNil: [#(#color)]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> axes: anArray [
	axes := anArray
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:47'
}
SWADatasetMetric >> colorBlock: aBlock [
	"Install a CATEGORICAL color function: a one-arg block taking a treemap node and
	answering its Color directly (or nil for a neutral tile), bypassing the scalar
	value->scale path. Used by metrics whose color is not a heat ramp over a scalar
	-- e.g. #topic, which tints by dominant-topic HUE FAMILY. When nil (the default)
	the metric uses the ordinary #valueForNode: through #scale."
	colorBlock := aBlock
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:47'
}
SWADatasetMetric >> colorForNode: aNode [
	"Tile tint for aNode. A CATEGORICAL metric (#colorBlock: set) answers the block's
	color directly (e.g. topic hue family); otherwise the metric value through #scale,
	or nil when the metric says nothing about aNode (caller falls back to a neutral
	base)."
	| v |
	colorBlock ifNotNil: [^ colorBlock value: aNode].
	v := self valueForNode: aNode.
	v ifNil: [^ nil].
	^ self scale value: v
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWADatasetMetric >> coverageSource [
	"The SWACoverageData behind a coverage-provenance metric (for the blue-test /
	covered-method relation), or nil."
	^ self isCoverageProvenance ifTrue: [dataset source] ifFalse: [nil]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> dataset [
	^ dataset
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> dataset: aSWADataset [
	dataset := aSWADataset
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> id [
	"Metric identity within its dataset: #coverage / #call / #duplication."
	^ id
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> id: aSymbol [
	id := aSymbol
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:47'
}
SWADatasetMetric >> isCategorical [
	"True when this metric colors by a CATEGORICAL function (#colorBlock:) rather than
	a scalar heat ramp -- e.g. #topic (dominant-topic hue families). Categorical
	metrics have no meaningful #valueForNode: heat and are unavailable on the #size
	axis."
	^ colorBlock notNil
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWADatasetMetric >> isCoverageProvenance [
	"True for the coverage metrics whose source carries the test<->method provenance
	relation (blue tests + click-to-see-covered / click-to-see-covering-tests). The
	'call' metric on the same source qualifies too -- same SWACoverageData behind it."
	^ (id == #coverage or: [id == #call])
		and: [dataset source isKindOf: SWACoverageData]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> label [
	"Menu phrase without the dataset tag, e.g. 'By coverage'."
	^ label
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> label: aString [
	label := aString
]

{
	#category : #links,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWADatasetMetric >> linksForKey: aCrossRefKey [
	"Array of (scoreFloat -> partnerCrossRefKey) associations, best-first, describing
	links FROM the method aCrossRefKey. Empty unless this is a link-capable
	(duplication) metric. Keyed by crossRefKey so it's independent of which nodes are
	on screen -- the view resolves partner keys to nodes (or their nearest visible
	ancestor)."
	self supportsLinks ifFalse: [^ #()].
	id == #duplication ifTrue: [^ dataset source matchesForKey: aCrossRefKey].
	^ #()
]

{
	#category : #links,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWADatasetMetric >> locForKey: aCrossRefKey [
	"Recorded LOC for a method key from the source (0 if unknown / source has none).
	Lets the view estimate a link's shared-duplicated-lines width even when the
	partner is off screen."
	(dataset source respondsTo: #locForKey:)
		ifTrue: [^ dataset source locForKey: aCrossRefKey].
	^ 0
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> menuLabel [
	"'By coverage [squeak-coverage.json]' -- metric phrase tagged with its dataset."
	^ label, ' [', (dataset name ifNil: ['?']), ']'
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> modeSymbol [
	^ modeSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> modeSymbol: aSymbol [
	modeSymbol := aSymbol
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:50'
}
SWADatasetMetric >> printOn: aStream [
	aStream nextPutAll: self class name; nextPut: $(.
	aStream nextPutAll: (self menuLabel).
	modeSymbol ifNotNil: [aStream nextPutAll: ' '; nextPutAll: modeSymbol].
	aStream nextPut: $)
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:05'
}
SWADatasetMetric >> rawValueForKey: aCrossRefKey [
	"The metric's raw domain value for a single method crossRefKey (no rollup),
	dispatched by #id onto the dataset's source. nil if the key is unknown/keyless."
	aCrossRefKey ifNil: [^ nil].
	id == #coverage ifTrue: [^ dataset source coveringTestCountFor: aCrossRefKey].
	id == #call ifTrue: [^ dataset source invocationCountFor: aCrossRefKey].
	id == #duplication ifTrue: [
		| ms |
		ms := dataset source matchesForKey: aCrossRefKey.
		^ (ms isNil or: [ms isEmpty]) ifTrue: [0.0] ifFalse: [ms first key]].
	id == #spaceTallySelf ifTrue: [^ dataset source bytesForKey: aCrossRefKey].
	id == #spaceTallyTotal ifTrue: [^ dataset source totalBytesForKey: aCrossRefKey].
	id == #sampleTallySelf ifTrue: [^ dataset source selfCountForKey: aCrossRefKey].
	id == #maskHit ifTrue: [^ dataset source weightForKey: aCrossRefKey].
	id == #peerWeight ifTrue: [^ dataset source weightForKey: aCrossRefKey].
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> rollup [
	"#max or #sum -- how container nodes aggregate their descendants' values."
	^ rollup ifNil: [#max]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> rollup: aSymbol [
	rollup := aSymbol
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> rollupForNode: aNode [
	"Aggregate the metric over aNode's descendants per #rollup. Returns nil if no
	descendant carries a value (so callers can distinguish 'no data' from 0)."
	| acc any |
	acc := nil. any := false.
	aNode children do: [:c |
		| v |
		v := self valueForNode: c.
		v ifNotNil: [
			any := true.
			acc := acc isNil
				ifTrue: [v]
				ifFalse: [self rollup == #sum ifTrue: [acc + v] ifFalse: [acc max: v]]]].
	^ any ifTrue: [acc] ifFalse: [nil]
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> scale [
	"Raw value -> Color valuable. Own override, else the dataset's kind default."
	^ scale ifNil: [scale := dataset defaultScale]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> scale: aValuable [
	scale := aValuable
]

{
	#category : #links,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWADatasetMetric >> sharedLocForKey: aKey score: aScore partnerKey: partnerKey [
	"Estimated duplicated-line impact of a link: the Jaccard score times the smaller
	method's LOC (the smaller of the two keys' recorded LOC). Drives link WIDTH."
	| locA locB |
	locA := self locForKey: aKey.
	locB := self locForKey: partnerKey.
	^ (aScore * (locA min: locB)) rounded
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> supportsColor [
	^ self axes includes: #color
]

{
	#category : #links,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWADatasetMetric >> supportsLinks [
	"True if this metric can decorate the map with links between related nodes
	(currently only duplication clone links)."
	^ self axes includes: #links
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> supportsSize [
	^ self axes includes: #size
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 12:55'
}
SWADatasetMetric >> valueForNode: aNode [
	"The metric value for aNode. A keyed node reads its own raw value; if that is nil
	but the node has children, fall back to aggregating the descendants (#rollup).
	Keyless containers always aggregate. nil when nothing at or below aNode has a value.

	The keyed-but-rollup fallback matters for cross-kind binding: a Code Map CLASS node
	carries a crossRefKey (the class name), which resolves for a per-class dataset
	(coverage/tally) but NOT for a method-keyed one (a #peer flamegraph keyed by
	Class>>selector). Without the fallback such a class tile would go dark even though
	its methods carry values -- so we roll up its children instead."
	| key raw |
	key := aNode crossRefKey.
	key ifNotNil: [
		raw := self rawValueForKey: key.
		raw ifNotNil: [^ raw].
		"Keyed but no own value: aggregate children if any (else genuinely nil)."
		aNode children isEmpty ifTrue: [^ nil]].
	^ self rollupForNode: aNode
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:49'
}
SWADatasetMetric >> weightForNode: aNode [
	"Tile-area weight for aNode when this metric drives the SIZE axis: the rolled-up
	metric value, floored at 0 (nil -> 0, so nodes the metric ignores collapse)."
	^ (self valueForNode: aNode) ifNil: [0]
]
