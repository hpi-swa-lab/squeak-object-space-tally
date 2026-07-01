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
		'scale',
		'metrics'
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
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:11'
}
SWADataset >> buildMetrics [
	"Construct this dataset's metrics (see #metrics for the cached accessor)."
	| ms |
	ms := OrderedCollection new.
	kind == #coverage ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #coverage; label: 'By coverage';
			axes: #(#color #size); rollup: #sum; yourself).
		(source respondsTo: #hasInvocationData) ifTrue: [
			source hasInvocationData ifTrue: [
				ms add: (SWADatasetMetric new
					dataset: self; id: #call; label: 'By call';
					axes: #(#color #size); rollup: #sum; yourself)]]].
	kind == #duplication ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #duplication; label: 'By duplication';
			axes: #(#color #links); rollup: #max; yourself)].
	^ ms
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
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:55'
}
SWADataset >> metrics [
	"The axis-bindable metrics this dataset exposes (SWADatasetMetric), BUILT ONCE and
	cached so the minted mode symbols (set by SWACodeTreemapMorph>>addDataset:) stick
	to the same instances every query returns.

	A single loaded file yields SEVERAL: a coverage file gives 'By coverage'
	(covering-test count) always, plus 'By call' (invocation count) WHEN the file
	carries invocation data; a duplication file gives 'By duplication'."
	^ metrics ifNil: [metrics := self buildMetrics]
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
