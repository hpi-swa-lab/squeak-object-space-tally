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
		'metrics',
		'structureRoot'
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
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
}
SWADataset class >> peerFrom: aSWAPeerViewSource named: aString [
	"Wrap another open view as a #peer dataset -- cross-referencing as a normal
	dataset (color by the peer's per-key weight). Mints its mode symbol on
	#addDataset:."
	^ self new
		kind: #peer;
		source: aSWAPeerViewSource;
		name: aString;
		yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWADataset class >> spaceTallyFrom: aSWASpaceTallyClassSummary named: aString [
	"Wrap a per-class space-tally summary as a retained, named #spaceTally dataset.
	Its metrics (By instance bytes / By retained bytes) tint the Code Map's classes
	-- and, by #sum rollup, its packages -- by measured object-space bytes. The mode
	symbol is minted later by the treemap on #addDataset:."
	^ self new
		kind: #spaceTally;
		source: aSWASpaceTallyClassSummary;
		name: aString;
		yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:21'
}
SWADataset class >> spaceTallyFromJsonFile: aFilePath [
	"Load a space-tally JSON -- EITHER a full node tree (SWASpaceTallyJsonWriter
	output; the reconstructed tree is retained as structureRoot for the Tree button)
	OR a flat class-summary census (SWASpaceTallyClassSummary>>writeToFile:,
	decorate-only) -- and wrap it as a named #spaceTally dataset ready for
	SWACodeTreemapMorph>>addDataset:. Named after the file.

	Example:
		| ds map |
		ds := SWADataset spaceTallyFromJsonFile: 'tally.json'.
		map addDataset: ds; selectDataset: ds."
	| file json |
	file := FileStream readOnlyFileNamed: aFilePath.
	json := [Json readFrom: file] ensure: [file close].
	^ self spaceTallyFromJsonObject: json named: (FileDirectory localNameFor: aFilePath)
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:21'
}
SWADataset class >> spaceTallyFromJsonObject: aJsonObject named: aName [
	"Build a #spaceTally dataset from an ALREADY-PARSED space-tally JSON object.
	If it is a full node TREE, reconstruct the tree ONCE and keep it as the dataset's
	structureRoot (so it can also BE the Code Map's base structure via the Tree
	menu), deriving the per-class decorate summary from that same tree. If it is a
	flat class-summary census, there is no tree -- decorate-only."
	| ds summary root |
	((aJsonObject at: 'kind' ifAbsent: [nil]) = 'classSummary')
		ifTrue: [
			summary := SWASpaceTallyClassSummary new loadFlatJson: aJsonObject.
			^ self spaceTallyFrom: summary named: aName].
	"Node tree: reconstruct once, derive summary, retain the tree for structure."
	root := SWASpaceTallyJsonReader readJsonObject: aJsonObject.
	summary := SWASpaceTallyClassSummary fromTree: root.
	ds := self spaceTallyFrom: summary named: aName.
	ds structureRoot: root.
	^ ds
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:54'
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
	kind == #spaceTally ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #spaceTallySelf; label: 'By instance bytes';
			axes: #(#color #size); rollup: #sum;
			scale: (self spaceTallyScaleForMax: source maxSelf); yourself).
		ms add: (SWADatasetMetric new
			dataset: self; id: #spaceTallyTotal; label: 'By retained bytes';
			axes: #(#color #size); rollup: #sum;
			scale: (self spaceTallyScaleForMax: source maxTotal); yourself)].
	kind == #peer ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #peerWeight; label: 'By shared weight';
			axes: #(#color); rollup: #sum;
			scale: (self spaceTallyScaleForMax: source maxWeight); yourself)].
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
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:55'
}
SWADataset >> defaultBindings [
	"The FITTING DEFAULTS this dataset applies across the treemap axes when it is
	picked from the Data selector. A Dictionary axis (#color/#size/#decoration) ->
	metric (or absent = leave that axis intrinsic). Each axis can still be overridden
	afterward from its own menu (mix-and-match).

	SIZE is deliberately left INTRINSIC (LOC) by default for ALL kinds: sizing by a
	dataset metric collapses uncovered/unmatched/unmeasured code to zero width,
	destroying the structural map you want to read. The metric is still available on
	demand from the Size menu -- it just isn't a good DEFAULT.

	coverage: color by covering-test count (or call count if that's first).
	duplication: color by clone heat + decoration = clone links.
	spaceTally: color by instance (self) bytes.
	peer: color by the peer's shared per-key weight (cross-reference)."
	| d |
	d := Dictionary new.
	kind == #coverage ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	kind == #duplication ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m].
		(self metrics detect: [:x | x supportsLinks] ifNone: [nil]) ifNotNil: [:m | d at: #decoration put: m]].
	kind == #spaceTally ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	kind == #peer ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	^ d
]

{
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:55'
}
SWADataset >> defaultScale [
	"A good out-of-the-box raw-value -> Color mapping chosen by #kind. Each metric
	that needs a range-aware ramp carries its own scale; this is a fallback."
	kind == #coverage ifTrue: [^ self coverageScale].
	kind == #duplication ifTrue: [^ self duplicationScale].
	kind == #spaceTally ifTrue: [^ self spaceTallyScaleForMax: source maxSelf].
	kind == #peer ifTrue: [^ self spaceTallyScaleForMax: source maxWeight].
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
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:20'
}
SWADataset >> providesStructure [
	"Whether this dataset can BE a treemap's base structure (has its own tree),
	as opposed to only decorating an existing one."
	^ structureRoot notNil
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
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 10:39'
}
SWADataset >> spaceTallyScaleForMax: aMax [
	"A raw-bytes -> Color ramp for a space-tally metric, LOG-normalized against
	aMax (the dataset's own largest per-class value) because byte totals span many
	orders of magnitude. Cool blue (small) -> green -> yellow -> red (largest).
	Closes over aMax so each metric (self vs total) scales to its own range."

	| logMax |
	logMax := (aMax max: 1) ln.
	^ [:bytes |
		| t |
		t := bytes <= 0
			ifTrue: [0.0]
			ifFalse: [logMax <= 0 ifTrue: [1.0] ifFalse: [((bytes max: 1) ln / logMax) min: 1.0]].
		"hue 220 (blue) down to 0 (red) as t goes 0->1"
		Color h: 220 * (1.0 - t) s: 0.70 v: 0.45 + (t * 0.45)]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:20'
}
SWADataset >> structureRoot [
	"The node tree this dataset can supply as a treemap's base STRUCTURE (its own
	root), or nil if it can only decorate an existing tree. A #spaceTally dataset
	loaded from a full node-tree JSON keeps its reconstructed SWASpaceTallyNode tree
	here; one loaded from a flat class-summary census has no tree and stays
	decorate-only."
	^ structureRoot
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:20'
}
SWADataset >> structureRoot: aNode [
	structureRoot := aNode
]
