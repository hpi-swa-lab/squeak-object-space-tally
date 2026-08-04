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
		'structureRoot',
		'structures'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/28/2026 16:58'
}
SWADataset class >> callTallyFrom: aSWACoverage named: aString [
	"Turn a COLLECTED live tally (a SWACoverage whose resultMap maps
	'Class>>selector' -> invocation count) into a retained, named dataset carrying
	invocation data. Its #call metric colours a Code Map by call count.

	Two structures come along when the tally captured a call tree: PRIMARY = the
	captured call tree (flamegraph), DERIVED = its code-map grouping. Both re-project
	the same data, so the Tree button morphs freely between them.

	Pure construction -- no treemap, no UI. Shared by the pane's Call-Tally generator
	(#addCallTallyDataset:name:) and the workspace entry point
	(#fromCallTally:packages:)."
	| data ds callTreeRoot |
	data := SWACoverageData new.
	aSWACoverage resultMap keysAndValuesDo: [:key :count |
		data recordInvocationCount: count for: key].
	ds := self coverageFrom: data named: aString.
	callTreeRoot := aSWACoverage collectCallTree.
	callTreeRoot ifNotNil: [
		ds structures: {
			SWAStructure key: #callTree label: 'Flamegraph (call tree)'
				view: SWASamplingTallyFlamegraphMorph rootBlock: [callTreeRoot].
			SWAStructure key: #grouping label: 'Grouped by class (treemap)'
				view: SWASamplingTallyTreemapMorph rootBlock: [callTreeRoot asCodeGroupingRoot] }].
	^ ds
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:21'
}
SWADataset class >> callTimingFrom: aSWACoverage named: aString [
	"Turn a COLLECTED TIMING run (a SWACoverage harvested by #collectTiming, so it
	carries #resultMap counts PLUS #timeMap / #selfTimeMap microseconds) into a
	retained, named dataset. Superset of #callTallyFrom:named:: the resulting dataset
	offers 'By call' AND 'By self time' / 'By total time', so one run answers both
	'called how often' and 'cost how long' and you flip metrics instead of re-running.

	The attached call tree is the SAME structure the counting tally attaches, but its
	nodes are weighted in MICROSECONDS of self time instead of invocations -- i.e. a
	real time flamegraph, directly comparable with the sampling one.

	Pure construction -- no treemap, no UI. Shared by the pane's timing generators and
	the workspace entry point #fromCallTiming:packages:."
	| data ds callTreeRoot |
	data := SWACoverageData new.
	aSWACoverage resultMap keysAndValuesDo: [:key :count |
		data recordInvocationCount: count for: key].
	aSWACoverage timeMap keysAndValuesDo: [:key :micros |
		data
			recordMicros: micros
			selfMicros: (aSWACoverage selfTimeMap at: key ifAbsent: [0])
			for: key].
	ds := self coverageFrom: data named: aString.
	callTreeRoot := aSWACoverage collectCallTree.
	callTreeRoot ifNotNil: [
		ds structures: {
			SWAStructure key: #callTree label: 'Flamegraph (time)'
				view: SWASamplingTallyFlamegraphMorph rootBlock: [callTreeRoot].
			SWAStructure key: #grouping label: 'Grouped by class (treemap)'
				view: SWASamplingTallyTreemapMorph rootBlock: [callTreeRoot asCodeGroupingRoot] }].
	^ ds
]

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
	#'squeak_changestamp' : 'MCPServer 7/28/2026 16:58'
}
SWADataset class >> fromCallTally: aBlock packages: packageNames [
	"WORKSPACE entry point: instrument packageNames, run aBlock, collect when it
	returns, and answer the resulting call-tally dataset -- ready to be handed to a
	Code Map with

		| ds |
		ds := SWADataset fromCallTally: [self doSomething] packages: #('SWA-Base').
		SWAPane openPanes first treemap addDataset: ds.

	Scope matters: only methods in packageNames are counted, so pick the packages you
	actually want to see coloured. The pane's Data menu offers the same thing with the
	scope taken from the shown Code Map."
	| cov |
	cov := SWACoverage tallyPackages: packageNames while: aBlock.
	^ self callTallyFrom: cov named: 'Call Tally (doit)'
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/29/2026 17:21'
}
SWADataset class >> fromCallTiming: aBlock packages: packageNames [
	"WORKSPACE entry point, stopwatch twin of #fromCallTally:packages:: instrument
	packageNames with timing wrappers, run aBlock, collect when it returns, and answer
	the resulting dataset -- ready to hand to a Code Map with

		| ds |
		ds := SWADataset fromCallTiming: [self doSomething] packages: #('SWA-Base').
		SWAPane openPanes first treemap addDataset: ds.

	Scope matters twice over here: only methods in packageNames are timed, and time
	spent anywhere else is charged as SELF time to whichever instrumented method was
	running. Widen the scope and that time moves down into the real callee."
	| cov |
	cov := SWACoverage timePackages: packageNames while: aBlock.
	^ self callTimingFrom: cov named: 'Call Timing (doit)'
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWADataset class >> gitChurnFrom: aSWAGitChurnData named: aName [
	"A #gitChurn dataset over per-method git history (see SWAGitChurnData) --
	the bridge that lets a repository's commit log colour a Code Map."
	^ self new
		kind: #gitChurn;
		name: aName;
		source: aSWAGitChurnData;
		yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:05'
}
SWADataset class >> maskFrom: aBaseDataset minus: anOverlayDataset named: aString [
	"Wrap a MASK operation as a retained, named #masked dataset: highlights the method
	keys touched in anOverlayDataset (B) that aBaseDataset (A) never touched -- the
	Code Map analog of the Space Tally's 'Diff from this'. The dataset RETAINS its
	operands (via the SWAMaskSource) so it displays and navigates as 'B \ A'."
	^ self new
		kind: #masked;
		source: (SWAMaskSource left: aBaseDataset minus: anOverlayDataset);
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
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:31'
}
SWADataset class >> sampleTallyFrom: aSWASampleTallyData named: aString [
	"Wrap per-method self-sample counts (from the st-spy sampling profiler) as a
	retained, named #sampleTally dataset. Its single metric tints methods -- and, by
	#sum rollup, their classes/packages -- by CPU self-time heat. The mode symbol is
	minted later by the treemap on #addDataset:."
	^ self new
		kind: #sampleTally;
		source: aSWASampleTallyData;
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
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:47'
}
SWADataset class >> topicFrom: aSWATopicData named: aString [
	"Wrap a Biterm Topic Model (SWATopicData) as a retained, named #topic dataset. Its
	single CATEGORICAL metric tints each method by its dominant topic's hue family (no
	scalar heat). The mode symbol is minted later by the treemap on #addDataset:."
	^ self new
		kind: #topic;
		source: aSWATopicData;
		name: aString;
		yourself
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
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
					axes: #(#color #size); rollup: #sum;
					scale: (self spaceTallyScaleForMax: source maxInvocation); yourself)]].
		"A TIMING run (SWATimingWrapper) is a call tally that ALSO carries measured
		wall time, so it offers the #call metric above PLUS these two -- one dataset,
		flip the metric to switch the question from 'called how often' to 'cost how
		long'. Self time first: it is the one that names the culprit, while total
		time names the caller that contains it.

		Different ROLLUPS on purpose: self times partition the run, so a class or
		package node SUMS its methods. Inclusive times NEST -- a caller's total
		already contains its callees' -- so summing them inside one class would
		count the same microseconds twice; #max answers 'the costliest entry point
		in here' instead."
		(source respondsTo: #hasTimingData) ifTrue: [
			source hasTimingData ifTrue: [
				ms add: (SWADatasetMetric new
					dataset: self; id: #selfTime; label: 'By self time';
					axes: #(#color #size); rollup: #sum;
					scale: (self spaceTallyScaleForMax: source maxSelfMicros); yourself).
				ms add: (SWADatasetMetric new
					dataset: self; id: #totalTime; label: 'By total time (incl. callees)';
					axes: #(#color #size); rollup: #max;
					scale: (self spaceTallyScaleForMax: source maxMicros); yourself)]]].
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
	kind == #sampleTally ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #sampleTallySelf; label: 'By self samples (CPU heat)';
			axes: #(#color #size); rollup: #sum;
			scale: (self spaceTallyScaleForMax: source maxSelf); yourself)].
	kind == #masked ifTrue: [
		"Mirror EVERY metric the overlay B exposes, gated to the mask's survivor
		set: same id / label / axes / rollup / scale, but dispatched through this
		#masked dataset's SWAMaskSource, which returns B's real value for a
		surviving key and nil otherwise. So you keep 'By call', 'By coverage', etc.
		and pick which drives color -- calls, not just coverage."
		source overlayDataset metrics do: [:bm |
			ms add: (SWADatasetMetric new
				dataset: self; id: bm id; label: 'B\A: ', bm label;
				axes: bm axes; rollup: bm rollup;
				scale: bm scale; yourself)].
		ms isEmpty ifTrue: [
			"Overlay had no metrics: fall back to a boolean hit highlight."
			ms add: (SWADatasetMetric new
				dataset: self; id: #maskHit; label: 'By mask (B \ A hit)';
				axes: #(#color); rollup: #sum;
				scale: self maskScale; yourself)]].
	kind == #topic ifTrue: [
		ms add: ((SWADatasetMetric new
			dataset: self; id: #topic; label: 'By topic (hue families)';
			axes: #(#color); rollup: #max; yourself)
			colorBlock: [:node |
				(node isKindOf: SWACodeMethodNode)
					ifTrue: [source colorForKey: node crossRefKey]
					ifFalse: [nil]];
			yourself)].
	kind == #peer ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #peerWeight; label: 'By shared weight';
			axes: #(#color); rollup: #sum;
			scale: (self spaceTallyScaleForMax: source maxWeight); yourself)].
	"GIT CHURN: one scan of a repository's history, four different questions.
	Commits and changed lines SUM up the tree (a class's churn is its methods'
	churn). Recency and author count do NOT: 'when was this last touched' rolls up
	as the MOST RECENT touch, and 'how many hands' as the widest-shared method --
	summing either would be meaningless arithmetic on a timestamp / double-count
	the same person across siblings."
	kind == #gitChurn ifTrue: [
		ms add: (SWADatasetMetric new
			dataset: self; id: #gitCommits; label: 'By commits (git)';
			axes: #(#color #size); rollup: #sum;
			scale: (self spaceTallyScaleForMax: (source maxOf: #commits)); yourself).
		ms add: (SWADatasetMetric new
			dataset: self; id: #gitChurnLines; label: 'By changed lines (git)';
			axes: #(#color #size); rollup: #sum;
			scale: (self spaceTallyScaleForMax: (source maxOf: #churn)); yourself).
		ms add: (SWADatasetMetric new
			dataset: self; id: #gitRecency; label: 'By recency of last commit (git)';
			axes: #(#color); rollup: #max;
			scale: (self gitRecencyScaleFrom: source minLastChangeSeconds
				to: (source maxOf: #last)); yourself).
		ms add: (SWADatasetMetric new
			dataset: self; id: #gitAuthors; label: 'By number of authors (git)';
			axes: #(#color #size); rollup: #max;
			scale: (self spaceTallyScaleForMax: source maxAuthorCount); yourself)].
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
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:03'
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
	sampleTally: color by self-sample CPU heat.
	masked: color by mask hit (B \ A highlight).
	topic: color by dominant-topic hue family (categorical).
	peer: color by the peer's shared per-key weight (cross-reference)."
	| d |
	d := Dictionary new.
	kind == #coverage ifTrue: [
		self preferredColorMetric ifNotNil: [:m | d at: #color put: m]].
	kind == #duplication ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m].
		(self metrics detect: [:x | x supportsLinks] ifNone: [nil]) ifNotNil: [:m | d at: #decoration put: m]].
	kind == #spaceTally ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	kind == #sampleTally ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	kind == #masked ifTrue: [
		self preferredColorMetric ifNotNil: [:m | d at: #color put: m]].
	kind == #topic ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	kind == #peer ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	"gitChurn: colour by commit count -- 'how often has this been rewritten' is the
	question people actually arrive with; recency and churn lines are one menu pick
	away. Size stays intrinsic (LOC), per the rule above: sizing by commits would
	collapse everything the window did not touch."
	kind == #gitChurn ifTrue: [
		(self metrics detect: [:x | x supportsColor] ifNone: [nil]) ifNotNil: [:m | d at: #color put: m]].
	^ d
]

{
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:03'
}
SWADataset >> defaultScale [
	"A good out-of-the-box raw-value -> Color mapping chosen by #kind. Each metric
	that needs a range-aware ramp carries its own scale; this is a fallback."
	kind == #coverage ifTrue: [^ self coverageScale].
	kind == #duplication ifTrue: [^ self duplicationScale].
	kind == #spaceTally ifTrue: [^ self spaceTallyScaleForMax: source maxSelf].
	kind == #peer ifTrue: [^ self spaceTallyScaleForMax: source maxWeight].
	kind == #gitChurn ifTrue: [^ self spaceTallyScaleForMax: (source maxOf: #commits)].
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
	#category : #scales,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:02'
}
SWADataset >> gitRecencyScaleFrom: oldestSeconds to: newestSeconds [
	"A last-touched-time -> Color ramp for the git recency metric: blue = oldest
	change in the window, red = newest. LINEAR in time (unlike the byte ramps,
	which are log): a scan window is usually days or weeks, and what you want to
	see is 'this fortnight' standing out from 'last spring', not a compressed
	perceptual ordering. Closes over the window's own bounds, so the ramp always
	uses its full range whatever period was scanned."
	| span |
	span := (newestSeconds - oldestSeconds) max: 1.
	^ [:secs |
		| t |
		t := ((secs - oldestSeconds) / span) asFloat min: 1.0 max: 0.0.
		Color h: 240 * (1.0 - t) s: 0.62 v: 0.55 + (t * 0.33)]
]

{
	#category : #testing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:05'
}
SWADataset >> isMaskOp [
	"Whether this dataset is a MASK operation (an arithmetic between two other
	datasets), as opposed to a raw capture. Such a dataset carries operand refs."
	^ kind == #masked
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
	#category : #scale,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:04'
}
SWADataset >> maskScale [
	"Highlight ramp for a boolean MASK metric. The raw value is a survivor COUNT
	(#sum rollup: a method is 1.0, a class is the number of its surviving methods).
	Any survivor lights warm; classes with more new methods glow hotter. Zero/nil
	stays neutral (handled by nil upstream), so untouched-baseline code recedes."
	^ [:count |
		count <= 0
			ifTrue: [nil]
			ifFalse: [| t | t := ((count - 1) / 8.0) min: 1.0.
				Color h: 40 - (t * 40) s: 0.85 v: 0.70 + (t * 0.25)]]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:50'
}
SWADataset >> maskStructures [
	"Structures for a MASK dataset (B \\ A). When the overlay operand B carries a call
	tree (it is a call-tally dataset with a #callTree structure), offer a FLAMEGRAPH of
	the MASKED call tree: B's call tree pruned to the mask's survivor keys (methods in
	B not in A). Plus a grouped-by-class treemap of the same masked tree. If B has no
	call tree, a mask has no structure (stays decorate-only)."
	| overlay overlayTree survivors |
	overlay := source right.
	overlay ifNil: [^ #()].
	overlayTree := (overlay structureForKey: #callTree)
		ifNotNil: [:st | st root] ifNil: [nil].
	overlayTree ifNil: [^ #()].
	survivors := source coveredMethodKeys asSet.
	^ {
		SWAStructure key: #callTree label: 'Flamegraph (masked call tree)'
			view: SWASamplingTallyFlamegraphMorph
			rootBlock: [(overlayTree prunedToKeys: survivors)
				ifNil: [SWASamplingTallyNode new name: '(empty mask)'; yourself]
				ifNotNil: [:r | r rollUpTotals. r]].
		SWAStructure key: #grouping label: 'Grouped by class (treemap)'
			view: SWASamplingTallyTreemapMorph
			rootBlock: [((overlayTree prunedToKeys: survivors)
				ifNil: [SWASamplingTallyNode new name: '(empty mask)'; yourself]
				ifNotNil: [:r | r rollUpTotals. r]) asCodeGroupingRoot] }
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 14:05'
}
SWADataset >> operands [
	"For a mask (operation) dataset: { baseDataset. overlayDataset }. Empty otherwise."
	self isMaskOp ifFalse: [^ #()].
	^ { source left. source right }
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 18:17'
}
SWADataset >> preferredColorMetric [
	"The color metric to default to. Call-count (#call) is the more useful signal than
	covering-test count for call-tally datasets (and their B\A masks), so prefer it
	when present; otherwise fall back to the first color-capable metric. For a mask,
	the mirrored ids are #call / #coverage too, so the same preference applies."
	^ (self metrics detect: [:m | m id == #call and: [m supportsColor]] ifNone: [nil])
		ifNil: [self metrics detect: [:m | m supportsColor] ifNone: [nil]]
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
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:39'
}
SWADataset >> providesStructure [
	"Whether this dataset can BE a treemap's base structure (has its own tree),
	as opposed to only decorating an existing one."
	^ self structures notEmpty
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
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:39'
}
SWADataset >> structureForKey: aSymbol [
	"The SWAStructure with this key, or nil."
	^ self structures detect: [:s | s key == aSymbol] ifNone: [nil]
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

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:50'
}
SWADataset >> structures [
	"The ordered list of SWAStructure projections this dataset can supply as a base
	structure: its PRIMARY (native) tree first, then any DERIVED projections of the
	same data. Backward-compatible: a dataset that only set a legacy #structureRoot
	(e.g. a space tally loaded from a node-tree JSON) is presented as a single
	space-tally structure so the existing Tree machinery keeps working."
	structures ifNotNil: [^ structures].
	self isMaskOp ifTrue: [^ self maskStructures].
	structureRoot ifNotNil: [
		^ { SWAStructure
			key: modeSymbol
			label: (name ifNil: ['?'])
			view: SWASpaceTallyTreemapMorph
			rootBlock: [structureRoot] }].
	^ #()
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:38'
}
SWADataset >> structures: aCollectionOfStructures [
	"Set this dataset's explicit list of SWAStructure projections (primary first)."
	structures := aCollectionOfStructures asArray
]
