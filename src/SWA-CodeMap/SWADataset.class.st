"
A retained, named analysis overlay for the Code Map -- the first step of the layered-datasets architecture (see journal 2026-06-30).

A dataset wraps an image-independent, crossRefKey-keyed analysis result (currently a SWACoverageData or SWADuplicationData) and can answer, per treemap node, a RAW domain value (#valueForNode:) plus a Color (#colorForNode:) via a swappable #scale. Unlike the legacy single-ivar overlays (coverageData / dupScores), datasets are RETAINED and NAMED: you can load coverage twice and get two distinct datasets, each with its own minted mode symbol (#coverage_1, #coverage_2, ...), both selectable in the Color menu, switchable instantly without reloading.

This is an ADDITIVE parallel layer. The legacy colorMode / coverageData / dupScores machinery is untouched; datasets will absorb it piece-meal later.

Instance variables:
	name       - display label (usually derived from the source file)
	kind       - #coverage or #duplication; selects the default scale and the value query
	modeSymbol - the unique symbol minted for this dataset in the Color menu (e.g. #coverage_1)
	source     - the wrapped SWACoverageData / SWADuplicationData (holds the keyed values + JSON round-trip)
	scale      - a block/valuable mapping a raw value -> Color; kind-specific default, overridable
"
Class {
	#name : #SWADataset,
	#superclass : #Object,
	#instVars : [
		'name',
		'kind',
		'modeSymbol',
		'source',
		'scale'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset class >> coverageFrom: aSWACoverageData named: aString [
	"Wrap a SWACoverageData as a retained, named coverage dataset. The mode symbol
	is minted later by the treemap when the dataset is added (#addDataset:)."
	^ self new
		kind: #coverage;
		source: aSWACoverageData;
		name: aString;
		yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset class >> duplicationFrom: aSWADuplicationData named: aString [
	"Wrap a SWADuplicationData as a retained, named duplication dataset."
	^ self new
		kind: #duplication;
		source: aSWADuplicationData;
		name: aString;
		yourself
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> capabilities [
	"Which treemap axes this dataset can drive. First pass: color only. Size/detail/
	decoration come as the layered-datasets refactor absorbs the legacy overlays."
	^ #(#color)
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> colorForNode: aNode [
	"The tile tint for aNode: the raw value run through the #scale. When this dataset
	has no value for aNode, answer nil so the caller can fall back to a neutral base."
	| v |
	v := self valueForNode: aNode.
	v ifNil: [^ nil].
	^ self scale value: v
]

{
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset >> coverageScale [
	"Coverage heat by covering-test count: 0 tests -> dark red (uncovered), then
	green deepening as more tests exercise the method. Raw value is a test count."
	^ [:count |
		count <= 0
			ifTrue: [Color h: 0 s: 0.55 v: 0.35]
			ifFalse: [| t | t := (count / 5.0) min: 1.0.
				Color h: 130 s: 0.55 v: 0.45 + (t * 0.5)]]
]

{
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset >> defaultScale [
	"A good out-of-the-box raw-value -> Color mapping chosen by #kind. We KNOW the
	kinds of data we deal with (coverage, duplication), so each ships a sensible
	default -- while the scale stays a separate, swappable object (see #scale:)."
	kind == #coverage ifTrue: [^ self coverageScale].
	kind == #duplication ifTrue: [^ self duplicationScale].
	^ [:v | Color gray: 0.3]
]

{
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset >> duplicationScale [
	"Jaccard clone heat, matching the legacy dup ramp: below 0.5 cool gray-blue,
	0.5..1.0 yellow->orange->red (1.0 = vivid red, likely exact copy). Raw value is
	a Jaccard score in 0..1."
	^ [:score |
		score < 0.5
			ifTrue: [Color h: 220 s: 0.25 v: 0.30 + (score * 0.2)]
			ifFalse: [| t | t := ((score - 0.5) / 0.5) min: 1.0.
				Color h: 60 * (1.0 - t) s: 0.85 v: 0.95]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> kind [
	"#coverage or #duplication -- selects the value query and default scale."
	^ kind
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> kind: aSymbol [
	kind := aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> modeSymbol [
	"The unique symbol this dataset occupies in the Color menu (e.g. #coverage_1)."
	^ modeSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> modeSymbol: aSymbol [
	modeSymbol := aSymbol
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> name [
	"Display label shown in the Color menu."
	^ name
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> name: aString [
	name := aString
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:06'
}
SWADataset >> printOn: aStream [
	aStream nextPutAll: self class name; nextPut: $(.
	aStream nextPutAll: (name ifNil: ['?']); nextPutAll: ' '; print: kind.
	modeSymbol ifNotNil: [aStream nextPutAll: ' '; nextPutAll: modeSymbol].
	aStream nextPut: $)
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> rollupMaxForNode: aNode [
	"Aggregate value for a container node (no crossRefKey): the max value among its
	descendants, so a class/category lights up when it contains a hot method. Nil
	if nothing below has a value."
	| best |
	best := nil.
	aNode children do: [:c |
		| v |
		v := self valueForNode: c.
		v ifNotNil: [best := best isNil ifTrue: [v] ifFalse: [best max: v]]].
	^ best
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> scale [
	"A valuable (raw value -> Color). Lazily the kind-specific default."
	^ scale ifNil: [scale := self defaultScale]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> scale: aValuable [
	"Override the kind-specific default scale (raw value -> Color)."
	scale := aValuable
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> source [
	"The wrapped analysis result (SWACoverageData / SWADuplicationData)."
	^ source
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> source: anObject [
	source := anObject
]

{
	#category : #querying,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:05'
}
SWADataset >> valueForNode: aNode [
	"Raw domain value for aNode, or nil if this dataset says nothing about it.
	Keyed by the node's crossRefKey (the cross-view identity); nodes with no key
	(packages/categories) get a rolled-up value from their children so containers
	still light up. The number->Color mapping is the #scale's job, not ours -- this
	keeps the value rebindable (color axis today, size axis later)."
	| key |
	kind == #coverage ifTrue: [
		key := aNode crossRefKey.
		key ifNotNil: [^ source coveringTestCountFor: key].
		^ self rollupMaxForNode: aNode].
	kind == #duplication ifTrue: [
		key := aNode crossRefKey.
		key ifNotNil: [
			| ms |
			ms := source matchesForKey: key.
			^ (ms isNil or: [ms isEmpty]) ifTrue: [0.0] ifFalse: [ms first key]].
		^ self rollupMaxForNode: aNode].
	^ nil
]
