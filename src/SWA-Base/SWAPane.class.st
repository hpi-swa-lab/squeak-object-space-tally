"
Shared window chrome for SWA navigable visualizations (treemap, flamegraph, class diagram).

A SWAPane wraps a ""view"" morph and supplies the common UI: header buttons (Back/Browse/Show), breadcrumb, selection-path and meta-info lines, and an optional Shout-highlighted source pane. Views implement the view protocol (breadcrumbString, selectionPathString, metaInfoString, selectedSourceString, zoomOut, browseSelected, navPanel:) and call #refresh after selection/zoom changes.

See squeak-object-space-tally/doc/ for full details.
"
Class {
	#name : #SWAPane,
	#superclass : #Morph,
	#instVars : [
		'view',
		'headerRow',
		'breadcrumbMorph',
		'selectionPathMorph',
		'metaInfoMorph',
		'runInfoMorph',
		'sourceMorph',
		'detailsPane',
		'detailsTitle',
		'sourceRow',
		'coveringTestsPane',
		'coveringTestsTitle',
		'provenanceEntries',
		'provenanceIndex',
		'depthButton',
		'fullButton',
		'savedWindowFrame',
		'liveTally',
		'coverageCancel',
		'tallyButton',
		'sourceSplitter',
		'coveringTestsColumn',
		'coveringTestsWidth',
		'structureViews',
		'activeStructureKey',
		'searchField',
		'tallyAsDataset',
		'bodyRow',
		'marksPanel',
		'marksList',
		'marksButton',
		'marksSplitter',
		'marksWidth',
		'marksSelectedKeys',
		'marksPrimaryIndex',
		'commentField',
		'commentEditKey'
	],
	#classVars : [
		'SampleTallyDuration',
		'TopicK',
		'TopicSweeps'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:49'
}
SWAPane class >> defaultWindowBounds [
	"Preferred opening bounds for a Code Map window: wide enough for the full button
	bar on one row and tall enough that the wrapped header + info lines + map all
	fit without the visualization overflowing the bottom edge. Clamped up to the
	button-bar minimum width by #enforceMinimumWidthOn:."
	^ 568 @ 205 corner: 1935 @ 1264
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> enforceMinimumWidthOn: aWindow [
	"Find the SWAPane inside aWindow and have it set the window's minimum width
	to the button bar's natural one-row width (widening the window to it if the
	requested default was narrower). Keeps every opener's explicit #extent: as a
	PREFERRED size that is then clamped up to fit the buttons."
	aWindow allMorphs
		detect: [:m | m isKindOf: SWAPane]
		ifFound: [:p | p enforceMinimumWindowWidth]
		ifNone: []
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:52'
}
SWAPane class >> initialize [
	"Register the Apps-menu entry for the code map.
	Idempotent: removes any prior entry for this receiver first."
	(TheWorldMenu respondsTo: #registerOpenCommand:) ifFalse: [^ self].
	TheWorldMenu unregisterOpenCommandWithReceiver: self.
	TheWorldMenu registerOpenCommand: {
		'Code Map'.
		{self. #open}.
		'Open a treemap of all packages, classes as leaves' }
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane class >> on: aViewMorph [
	"Build a navigation panel wrapping aViewMorph (a treemap/flamegraph morph)."
	^ self new setView: aViewMorph
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:51'
}
SWAPane class >> open [
	"Apps-menu action: open the whole-image code map (all packages, classes as leaves)."
	^ self openOnPackageNamed: '*' leafKind: #class
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openByteCompositionOnPackageNamed: aPackageGlob [
	"Byte-composition treemap rendered down to methods (leafKind nil) so the
	per-method doc/string/code bar is visible. See
	#openByteCompositionOnPackageNamed:leafKind:.

	(SWAPane openByteCompositionOnPackageNamed: 'Morphic*')"
	^ self openByteCompositionOnPackageNamed: aPackageGlob leafKind: nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openByteCompositionOnPackageNamed: aPackageGlob leafKind: aKindOrNil [
	"Open a BYTE-COMPOSITION code treemap: tiles sized by SOURCE-TEXT byte size and
	COLOURED by the doc/string/code composition bar (teal = documentation,
	amber = string literals, green-gray = code). Size and colour are independent
	live modes (Size / Color context menus): you can keep the byte size and recolour
	by author/kind/recency, or keep any size and turn the composition bar on/off.
	This opener just preselects both.

	aPackageGlob is a String>>match: glob over package names ('Kernel', 'Morphic*',
	'*'). aKindOrNil stops RENDERING at that #kind; nil (recommended for this mode)
	renders down to methods so the per-method bar is visible. The full tree and
	roll-ups are always built.

	The byte analysis (comment / string-literal / rest classification) is cached in
	a weak dictionary keyed on each CompiledMethod, so it is parsed once and reused
	across reopens, self-cleaning when methods are recompiled or removed.

	(SWAPane openByteCompositionOnPackageNamed: 'Kernel' leafKind: nil)
	(SWAPane openByteCompositionOnPackageNamed: '*' leafKind: nil)"
	| root window |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		weightMetric: #bytes;
		addPackages: aPackageGlob;
		yourself.
	window := root openTreemapLeafKind: aKindOrNil.
	window allMorphs
		detect: [:m | m isKindOf: SWACodeTreemapMorph]
		ifFound: [:tm | tm colorMode: #byteComposition]
		ifNone: [].
	window setLabel: 'Byte Composition Treemap: ', aPackageGlob, '  (sized by source bytes)'.
	^ window
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob [
	"Open a coverage-WEIGHTED code treemap: same package -> class -> category ->
	method structure as #openOnPackageNamed:, but tiles are sized by the actual
	covered counts (covering-test count per method, rolled up) instead of LOC.
	Uncovered methods collapse to nothing, so the layout shows -- proportionally --
	what the tests in aCoverageFileName actually exercised, with the usual green/
	blue tint and proportional coverage bars on aggregate tiles.

	aCoverageFileName is a SWACoverageData JSON file (Class>>selector keyed, image-
	independent). aPackageGlob is a String>>match: glob over package names.

	(SWAPane openCoverage: 'morphic-coverage.json' onPackageNamed: '*')
	(SWAPane openCoverage: 'squeak-coverage.json' onPackageNamed: 'Morphic*')"
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:37'
}
SWAPane class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: aKindOrNil [
	"See #openCoverage:onPackageNamed:. Sizes tiles by covering-TEST count. aKindOrNil
	stops RENDERING at that #kind (roll-ups still build over the full tree); nil
	renders down to methods."
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob
		leafKind: aKindOrNil weightMode: #tests
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: aKindOrNil weightMode: aWeightMode [
	"Coverage-WEIGHTED code treemap. aWeightMode selects the tile-size metric:
	  #tests       -- distinct covering-test count per method (default), or
	  #invocations -- raw call count (how many times each method actually ran).
	#invocations requires data generated by an invocation-counting runner; if the
	file has none (old JSON), we fall back to #tests and say so in the status line.
	aKindOrNil stops RENDERING at that #kind; nil renders down to methods.

	The mode is set as the live #weightMetric (the 'Size' menu shows it ticked), so
	the user can switch among Structure / Methods / LOC / Bytes / call count /
	covering tests in place.

	(SWAPane openCoverage: 'morphic-coverage.json' onPackageNamed: '*'
		leafKind: nil weightMode: #invocations)"
	| data mode root window note label |
	data := SWACoverageData fromFile: aCoverageFileName.
	mode := aWeightMode.
	note := ''.
	(mode == #invocations and: [data hasInvocationData not]) ifTrue: [
		mode := #tests.
		note := ' [no invocation data -- showing test count; re-run coverage to record invocations]'].
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		coverageData: data;
		coverageWeightMode: mode;
		weightMetric: mode;
		addPackages: aPackageGlob;
		yourself.
	window := root openTreemapLeafKind: aKindOrNil.
	window allMorphs
		detect: [:m | m isKindOf: SWACodeTreemapMorph]
		ifFound: [:tm | tm showCoverageData: data weightMode: mode]
		ifNone: [].
	window allMorphs
		detect: [:m | m isKindOf: SWAPane]
		ifFound: [:p |
			p treemapCoverageStatus: 'Coverage (', mode, '-weighted): ',
				data coveredMethodCount printString, ' methods, ',
				data testNames size printString, ' tests', note]
		ifNone: [].
	label := mode == #invocations
		ifTrue: ['  (sized by invocation count)']
		ifFalse: ['  (sized by covering-test count)'].
	window setLabel: 'Coverage Treemap: ', aPackageGlob, label.
	^ window
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openInvocations: aCoverageFileName onPackageNamed: aPackageGlob [
	"Open a coverage treemap sized by RAW INVOCATION COUNT -- how many times each
	method was actually called during the run -- instead of covering-test count.
	Requires data generated by an invocation-counting runner (falls back to test
	count, with a note, for older JSON files).

	(SWAPane openInvocations: 'morphic-coverage.json' onPackageNamed: '*')"
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob
		leafKind: nil weightMode: #invocations
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openOnPackageNamed: aPackageName [
	"Open a code-structure treemap (package -> classes -> categories -> methods)
	wrapped in a SWAPane. Defaults to #class render depth (Full/nil is omitted
	from the depth cycle -- it tiles the whole tree at once, which is unwieldy on a
	broad glob); cycle deeper/shallower with the Depth button.

	(SWAPane openOnPackageNamed: 'Morphic-Kernel')"
	^ self openOnPackageNamed: aPackageName leafKind: #class
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openOnPackageNamed: aPackageGlob leafKind: aKindOrNil [
	"Open a code-structure treemap (root -> packages -> classes -> categories ->
	methods) wrapped in a SWAPane, with Back/Browse/Show/Depth/Full chrome.

	aPackageGlob is a String>>match: glob matched against all package names. A plain
	name ('Kernel') simply matches one package; 'Morphic*' or '*' match many. We
	always build an aggregate SWACodeRootNode, so the single- and multi-package cases
	share one path.

	aKindOrNil stops *rendering* at nodes of that #kind (#package/#class/#category/
	#method); the full tree and all metric roll-ups are still built. nil renders the
	full depth. With a broad glob, #class avoids tiling thousands of method nodes.

	Delegates to SWACodeNode>>openTreemapLeafKind: for the actual build -- that wires
	up the click overlay (select / zoom / explore / context menu), the two-phase
	progress bar, the panel chrome, and the default window bounds.

	(SWAPane openOnPackageNamed: 'Kernel' leafKind: nil)
	(SWAPane openOnPackageNamed: '*' leafKind: #class)"
	| root window |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		addPackages: aPackageGlob;
		yourself.
	window := root openTreemapLeafKind: aKindOrNil.
	window setLabel: 'Code Treemap: ', aPackageGlob.
	^ window
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWAPane class >> openPanels [
	"All nav panels currently live in the world (still owned by a window/world).
	Discovered live rather than via a registry so closed panels drop out
	automatically."
	^ self allInstances select: [:p | p world notNil]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane class >> openTopics: aTopicFileName onPackageNamed: aPackageGlob [
	"Open a normal (LOC-weighted) code treemap tinted by a Biterm Topic Model.
	Loads an SWATopicData JSON file (Class>>selector keyed, image-independent),
	sets it on the root so #topic color mode paints each method-leaf tile by its
	dominant topic's hue family and each aggregate tile with a topic-mixture bar.

	Generate the file first (whole-image or per-package):
	  (SWABitermTopicModel onPackageNamed: 'Morphic') buildAndRun: 200) writeToFile: 'morphic-topics.json'

	(SWAPane openTopics: 'morphic-topics.json' onPackageNamed: 'Morphic*')"
	| data root window |
	data := SWATopicData new loadFromFile: aTopicFileName.
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		topicData: data;
		addPackages: aPackageGlob;
		yourself.
	window := root openTreemapLeafKind: nil.
	window allMorphs
		detect: [:m | m isKindOf: SWACodeTreemapMorph]
		ifFound: [:tm | tm colorMode: #topic]
		ifNone: [].
	window allMorphs
		detect: [:m | m isKindOf: SWAPane]
		ifFound: [:p |
			p treemapCoverageStatus: 'Topics (BTM): ', data k printString,
				' topics in ', data hueFamilyCount printString, ' hue families, ',
				data methodNames size printString, ' methods']
		ifNone: [].
	window setLabel: 'Topic Treemap: ', aPackageGlob, '  (BTM hue families)'.
	^ window
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:29'
}
SWAPane class >> sampleTallyDuration [
	"Seconds the external st-spy sampling profiler runs when 'Generate: sample tally'
	is picked in the Data menu. Configurable via the Preferences browser."
	<preference: 'Sample Tally duration (seconds)'
		category: 'SWA'
		description: 'How many seconds the external st-spy sampling profiler runs when generating a Sample Tally dataset from the Code Map Data menu.'
		type: #Number>
	^ SampleTallyDuration ifNil: [10]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:29'
}
SWAPane class >> sampleTallyDuration: aNumber [
	"Set the Sample Tally profiling duration (seconds). Backs the #sampleTallyDuration
	preference."
	SampleTallyDuration := aNumber
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane class >> topicK [
	"Number of topics (k) the Biterm Topic Model fits when 'Generate: topic model' is
	picked in the Data menu. Configurable via the Preferences browser."
	<preference: 'Topic model: number of topics (k)'
		category: 'SWA'
		description: 'How many latent topics the Biterm Topic Model fits when generating a Topic dataset from the Code Map Data menu.'
		type: #Number>
	^ TopicK ifNil: [20]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane class >> topicK: aNumber [
	"Set the Topic model topic count (k). Backs the #topicK preference."
	TopicK := aNumber
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane class >> topicSweeps [
	"Number of Gibbs-sampling sweeps the Biterm Topic Model runs when generating a
	Topic dataset. More sweeps = better convergence but slower. Preferences-configurable."
	<preference: 'Topic model: Gibbs sweeps'
		category: 'SWA'
		description: 'How many Gibbs-sampling sweeps the Biterm Topic Model runs when generating a Topic dataset from the Code Map Data menu. More sweeps converge better but take longer.'
		type: #Number>
	^ TopicSweeps ifNil: [200]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane class >> topicSweeps: aNumber [
	"Set the Topic model Gibbs sweep count. Backs the #topicSweeps preference."
	TopicSweeps := aNumber
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:52'
}
SWAPane class >> unload [
	"Remove the Apps-menu entry."
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> acceptComment: aText [
	"Save the edited comment onto the mark currently being edited. No-op if no row is
	being edited. The mark set notifies all panes so every open Marks editor/list
	refreshes; comments persist in the global SWAMarkSet (image-resident)."
	commentEditKey ifNil: [^ self].
	SWAMarkSet default commentAt: commentEditKey put: aText asString.
	commentField ifNotNil: [commentField hasUnacceptedEdits: false]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:24'
}
SWAPane >> acquireTestCoverageThenColor [
	"Run test coverage WITH provenance for the shown packages (forked, Stop-able),
	then color the map by it. Invoked lazily when the user picks 'By test coverage'
	in the Color menu with no coverage data loaded yet -- the menu-driven equivalent
	of the old Cover button. On a broad selection like '*' this never wedges the
	image: hit STOP to abort and keep the partial result."
	| root names tm testClasses |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Coverage: only on a Code Map'].
	names := root packageNames.
	testClasses := SWACoverage testClassesForPackages: names.
	testClasses isEmpty ifTrue: [
		^ self treemapCoverageStatus: 'Coverage: no related test classes found'].
	tm := self treemap.
	self treemapCoverageStatus: 'Coverage: running ', testClasses size printString,
		' test classes (use STOP to abort)...'.
	SWACoverage
		runProvenanceForPackages: names
		tests: testClasses
		then: [:data |
			tm showCoverageData: data weightMode: #tests.
			tm noteColorMode: #coverage.
			tm coverageStatus: 'Coverage: ', data coveredMethodCount printString,
				' methods, ', data testNames size printString, ' tests (select a method to see them)'.
			self refresh]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:22'
}
SWAPane >> activeStructureKey [
	"The structure symbol currently displayed (#intrinsic by default)."
	^ activeStructureKey ifNil: [activeStructureKey := #intrinsic]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 18:04'
}
SWAPane >> addCallTallyDataset: aSWACoverage name: aName [
	"Turn a collected live tally (a SWACoverage whose resultMap is 'Class>>selector'
	-> invocation count) into a retained, named SWADataset carrying invocation data,
	make it active, and select its #call metric so the map colors by call count.
	The shared tail of the Call-Tally generator; peer of #addCoverageDataset:name:."
	| data tm ds callMetric |
	data := SWACoverageData new.
	aSWACoverage resultMap keysAndValuesDo: [:key :count |
		data recordInvocationCount: count for: key].
	tm := self treemap.
	ds := tm addDataset: (SWADataset coverageFrom: data named: aName).
	tm selectDataset: ds.
	"Prefer the #call metric (invocation counts) over the default #coverage metric."
	callMetric := ds metrics detect: [:m | m id == #call] ifNone: [nil].
	callMetric ifNotNil: [tm colorMode: callMetric modeSymbol].
	self treemapCoverageStatus: 'Call Tally (', ds name, '): ',
		data invocationMap size printString, ' methods invoked'.
	self refresh.
	^ ds
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> addCoverageDataset: aCoverageData name: aName [
	"Retain an already-built SWACoverageData as a named, ACTIVE coverage dataset --
	the shared tail of both the file LOAD path (#loadCoverageJson:name:) and the
	async GENERATE paths (coverage run, call tally). Answers the dataset."
	| tm ds |
	tm := self treemap.
	ds := tm addDataset: (SWADataset coverageFrom: aCoverageData named: aName).
	tm selectDataset: ds.
	self treemapCoverageStatus: 'Coverage (', ds name, '): ', aCoverageData coveredMethodCount printString,
		' methods, ', aCoverageData testNames size printString, ' tests',
		(aCoverageData hasInvocationData ifTrue: [' (+call counts)'] ifFalse: ['']).
	self refresh.
	^ ds
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> addDuplicationDataset: aDuplicationData name: aName [
	"Retain an already-built SWADuplicationData as a named, ACTIVE duplication
	dataset -- the shared tail of the file LOAD path (#loadDuplicationJson:name:)
	and the async GENERATE path. Answers the dataset."
	| tm ds |
	tm := self treemap.
	ds := tm addDataset: (SWADataset duplicationFrom: aDuplicationData named: aName).
	tm selectDataset: ds.
	self treemapCoverageStatus: 'Duplication (', ds name, '): ', aDuplicationData matchedMethodCount printString,
		' methods with near-duplicates of ', aDuplicationData methodNames size printString, ' analysed'.
	self refresh.
	^ ds
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:32'
}
SWAPane >> addSampleTallyDataset: aSampleTallyData name: aName [
	"Retain an already-built SWASampleTallyData as a named, ACTIVE #sampleTally
	dataset and color the map by its self-sample heat. Shared tail of the Sample-Tally
	generator; peer of #addCoverageDataset:name: / #addDuplicationDataset:name:."
	| tm ds |
	tm := self treemap.
	ds := tm addDataset: (SWADataset sampleTallyFrom: aSampleTallyData named: aName).
	tm selectDataset: ds.
	self treemapCoverageStatus: 'Sample Tally (', ds name, '): ',
		aSampleTallyData methodNames size printString, ' methods sampled, ',
		aSampleTallyData totalSamples printString, ' self-samples'.
	self refresh.
	^ ds
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane >> addTopicDataset: aSWATopicData name: aName [
	"Retain an already-built SWATopicData as a named, ACTIVE #topic dataset and color
	the map by dominant-topic hue family. Shared tail of the Topic generator and the
	Topic file-load path; peer of #addCoverageDataset:name: etc."
	| tm ds |
	tm := self treemap.
	ds := tm addDataset: (SWADataset topicFrom: aSWATopicData named: aName).
	tm selectDataset: ds.
	self treemapCoverageStatus: 'Topics (', ds name, '): ', aSWATopicData k printString,
		' topics in ', aSWATopicData hueFamilyCount printString, ' hue families, ',
		aSWATopicData methodNames size printString, ' methods'.
	self refresh.
	^ ds
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> breadcrumbContents [
	"Breadcrumb string from the view (empty if unsupported)."
	^ (view respondsTo: #breadcrumbString)
		ifTrue: [view breadcrumbString ifNil: ['']]
		ifFalse: ['']
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAPane >> browseSelected [
	"Browse button: delegate to the view (it knows what 'selected' means)."
	(view respondsTo: #browseSelected)
		ifTrue: [view browseSelected]
		ifFalse: [Beeper beep]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> buttonLabelled: aString action: aSelector [
	"A header button that sends aSelector to THIS panel when pressed."
	^ SimpleButtonMorph new
		label: aString;
		color: (Color gray: 0.3);
		target: self;
		actionSelector: aSelector;
		hResizing: #rigid; vResizing: #rigid;
		yourself
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 17:44'
}
SWAPane >> chooseJsonFilePrompt: aPromptString [
	"Open a *.json file chooser and answer the chosen full path, or nil if cancelled.
	Falls back to a text path prompt if no file chooser is available (e.g. headless).
	aPromptString labels the fallback text prompt."
	| result |
	(Smalltalk includesKey: #StandardFileMenu) ifTrue: [
		result := StandardFileMenu oldFileFrom: FileDirectory default withPattern: '*.json'.
		result ifNil: [^ nil].
		^ result directory fullNameFor: result name].
	"Fallback."
	^ (UIManager default request: aPromptString initialAnswer: '')
		ifNil: [nil] ifNotNil: [:s | s isEmpty ifTrue: [nil] ifFalse: [s withBlanksTrimmed]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> clearAllMarks [
	"Menu 'Clear all': remove EVERY mark globally, regardless of selection."
	marksSelectedKeys := Set new.
	marksPrimaryIndex := 0.
	commentEditKey := nil.
	SWAMarkSet default clear
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:23'
}
SWAPane >> clearCoverage [
	"Remove the coverage overlay and its status line. Also drops the coverage data
	from the root node (so the #invocations/#tests SIZE metrics disappear) and, if
	the map was sized by one of those dynamic metrics, reverts the size to LOC so it
	does not collapse to an empty map."
	| tm |
	tm := self treemap.
	tm ifNil: [^ self].
	tm showCoverage: nil.
	((tm respondsTo: #rootNode) and: [tm rootNode respondsTo: #coverageData:])
		ifTrue: [tm rootNode coverageData: nil].
	((tm respondsTo: #weightMetric) and: [
		tm weightMetric == #invocations or: [tm weightMetric == #tests]])
		ifTrue: [tm weightMetric: #loc].
	(tm respondsTo: #coverageStatus:) ifTrue: [tm coverageStatus: nil].
	self refresh
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> clearMarks [
	"Clear button: remove the SELECTED marks if any rows are selected, otherwise ALL
	marks (globally). Every open pane's list + green borders refresh."
	(marksSelectedKeys notNil and: [marksSelectedKeys notEmpty])
		ifTrue: [
			SWAMarkSet default removeAll: marksSelectedKeys asArray.
			marksSelectedKeys := Set new.
			marksPrimaryIndex := 0.
			commentEditKey := nil]
		ifFalse: [SWAMarkSet default clear]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane >> codeMapGeneratorEntries [
	"{ menuLabel. generatorSelector } pairs for the async, on-the-fly dataset
	GENERATORS offered -- in italic -- under the Data menu. Each is the async twin of
	the 'Load' button: picking it computes data for the shown packages and retains it
	as a named SWADataset (so it then appears in the Color/Size menus like any loaded
	file). Empty unless the wrapped view is a Code Map.

	Call Tally is TWO-PHASE (instrument -> exercise -> collect): its label reflects
	whether a tally is currently live, so a second pick collects."
	| entries |
	(self treemap isKindOf: SWACodeTreemapMorph) ifFalse: [^ #()].
	entries := OrderedCollection new.
	entries add: { 'Generate: duplication (clone heat)'. #generateDuplicationDataset }.
	entries add: { 'Generate: test coverage (run related tests)'. #generateCoverageDataset }.
	(liveTally notNil and: [tallyAsDataset == true])
		ifTrue: [entries add: { 'Generate: call tally -- COLLECT now'. #generateCallTallyDataset }]
		ifFalse: [liveTally isNil ifTrue: [
			entries add: { 'Generate: call tally (instrument + exercise)'. #generateCallTallyDataset }]].
	entries add: { 'Generate: sample tally (', self class sampleTallyDuration printString, 's CPU heat)'. #generateSampleTallyDataset }.
	entries add: { 'Generate: topic model (k=', self class topicK printString, ')'. #generateTopicDataset }.
	^ entries
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:22'
}
SWAPane >> codeMapView [
	"The intrinsic Code Map view (holds the loaded datasets). It is the view first
	wrapped by this panel; registered under #intrinsic on first structure access."
	^ self structureViews at: #intrinsic ifAbsent: [
		"Not yet registered: the current view IS the intrinsic one (nothing morphed)."
		(view respondsTo: #datasets) ifTrue: [view] ifFalse: [nil]]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:38'
}
SWAPane >> codeRoot [
	"The SWACodeRootNode this panel's code map is showing, or nil if the wrapped
	view is not a code map."
	| tm |
	tm := self treemap.
	(tm notNil and: [tm rootNode isKindOf: SWACodeRootNode])
		ifTrue: [^ tm rootNode].
	^ nil
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 18:04'
}
SWAPane >> collectInvocationTally [
	"Read invocation counts from the live tally, uninstall the wrappers, and either
	(a) retain the result as a #call-metric DATASET when the tally was started from
	the Data-menu 'Generate: call tally' entry (#tallyAsDataset), or (b) overlay the
	legacy green tally ramp (Tally button). Either way the wrappers are UNINSTALLED
	first so instrumentation never lingers. Resets the Tally button + live state."
	| n tm cov |
	liveTally ifNil: [^ self].
	liveTally collectTally.
	liveTally uninstall.
	cov := liveTally.
	n := cov resultMap size.
	tm := self treemap.
	tallyAsDataset == true
		ifTrue: [
			tallyAsDataset := false.
			liveTally := nil.
			self updateTallyButton.
			^ self addCallTallyDataset: cov name: 'Call Tally (generated)'].
	tm showCoverage: cov.
	(tm respondsTo: #noteColorMode:) ifTrue: [tm noteColorMode: #tally].
	self treemapCoverageStatus: 'Tally: ', n printString, ' methods invoked'.
	self refresh.
	liveTally := nil.
	self updateTallyButton
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> commentFieldText [
	"The comment for the mark currently being edited (primary/last-clicked row), as
	Text for the PluggableTextMorph."
	commentEditKey ifNil: [^ Text new].
	^ (SWAMarkSet default commentAt: commentEditKey) asText
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> copyMarks [
	"Copy marks to the clipboard: the SELECTED marks if any rows are selected,
	otherwise ALL marks. Each line is 'key' or 'key  --  comment'."
	| picked |
	picked := self selectedMarkKeys.
	SWAMarkSet default copyKeysToClipboard: picked.
	self flashMarksMessage: 'Copied ', picked size printString, ' mark(s)'
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWAPane >> coverageTally [
	"Button action: toggle the live invocation tally. First press instruments the
	shown packages; second press collects counts and overlays them."
	| root |
	liveTally ifNotNil: [^ self collectInvocationTally].
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Coverage: only on a Code Map'].
	self startInvocationTally: root
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWAPane >> crossRefMenuLabel [
	"Human-readable label for this panel in a cross-reference chooser:
	the enclosing window's title, else the view's class name."
	| win |
	win := self enclosingWindow.
	(win notNil and: [win label notNil]) ifTrue: [^ win label].
	^ view class name
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:56'
}
SWAPane >> crossReferenceAsDataset: aPeerPanel [
	"Data-menu action for a peer entry: wrap the peer view as a #peer dataset (its
	per-key weight becomes a color metric), retain + select it. This IS the old X-ref
	behavior, now a normal, mix-and-matchable dataset. If this peer is already loaded
	as a dataset, just re-select it rather than duplicating."
	| tm peerView existing ds |
	tm := self treemap.
	peerView := aPeerPanel treemap.
	(tm isNil or: [peerView isNil]) ifTrue: [^ Beeper beep].
	existing := (tm respondsTo: #datasets)
		ifTrue: [tm datasets detect: [:d | d kind == #peer and: [d source peerView == peerView]] ifNone: [nil]]
		ifFalse: [nil].
	ds := existing ifNil: [
		tm addDataset: (SWADataset
			peerFrom: (SWAPeerViewSource new peerView: peerView; yourself)
			named: aPeerPanel crossRefMenuLabel)].
	tm selectDataset: ds.
	self refresh
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:16'
}
SWAPane >> cycleLeafKind [
	"Depth button: cycle the view's render depth (leafKind). The default order is
	Package -> Class -> Category -> Method -> Package (Full/nil omitted; it renders
	the whole tree at once, which doesn't make sense here). A view may narrow this to
	its own meaningful depths by answering #leafKindOrder -- e.g. the class diagram
	cycles just Class <-> Method (classes only vs classes + methods). Only affects
	rendering; the tree and metric roll-ups are unchanged, so this is cheap to
	re-apply. If the view is at a depth outside the order, the first press goes to
	the order's first entry."
	| order current next |
	(view respondsTo: #leafKind:) ifFalse: [^ Beeper beep].
	order := (view respondsTo: #leafKindOrder)
		ifTrue: [view leafKindOrder]
		ifFalse: [{ #package. #class. #category. #method }].
	current := (view respondsTo: #leafKind) ifTrue: [view leafKind] ifFalse: [nil].
	next := order at: ((order indexOf: current) \\ order size) + 1.
	view leafKind: next.
	self updateDepthLabel.
	self refresh
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:40'
}
SWAPane >> dataMenuMorph [
	"Build the top-level Data menu for ANY view: None, one entry per RETAINED dataset,
	then -- in italic, below a separator -- the async GENERATOR entries (the on-the-fly
	twins of the 'Load' button: compute duplication/coverage/... for the shown
	packages and retain the result as a dataset). Finally -- below a separator -- one
	entry per OPEN PEER view (cross-reference as a dataset). The active dataset is
	ticked. Answers nil if there is nothing to pick."
	| tm menu active current peers any gens |
	tm := self treemap.
	tm ifNil: [^ nil].
	menu := MenuMorph new defaultTarget: self.
	active := (tm respondsTo: #activeDataset) ifTrue: [tm activeDataset] ifFalse: [nil].
	current := active ifNil: [#none] ifNotNil: [active modeSymbol].
	menu add: (current == #none ifTrue: ['* '] ifFalse: ['   ']), 'None (intrinsic)'
		selector: #setDataMode: argument: #none.
	any := false.
	(tm respondsTo: #datasets) ifTrue: [
		tm datasets do: [:ds |
			any := true.
			menu add: (current == ds modeSymbol ifTrue: ['* '] ifFalse: ['   ']),
					'Data: ', (ds name ifNil: ['?'])
				selector: #setDataMode: argument: ds modeSymbol]].
	"Italic async GENERATOR entries (compute a dataset on the fly)."
	gens := self codeMapGeneratorEntries.
	gens isEmpty ifFalse: [
		any := true.
		menu addLine.
		gens do: [:pair |
			| item |
			menu add: pair first selector: pair second argument: nil.
			item := menu lastSubmorph.
			(item isKindOf: MenuItemMorph) ifTrue: [item emphasis: 2]]].
	peers := self peerPanels.
	peers isEmpty ifFalse: [
		menu addLine.
		peers do: [:p |
			menu add: 'X-ref: ', p crossRefMenuLabel
				selector: #crossReferenceAsDataset: argument: p]].
	^ (any or: [peers notEmpty]) ifTrue: [menu] ifFalse: [nil]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:13'
}
SWAPane >> datasetNameFor: aPath [
	"A short display name for a dataset loaded from aPath: the file's base name."
	| segs |
	aPath ifNil: [^ 'loaded'].
	segs := (aPath asString copyReplaceAll: '\' with: '/') findTokens: '/'.
	^ segs isEmpty ifTrue: [aPath asString] ifFalse: [segs last]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:48'
}
SWAPane >> deselect [
	"Header 'Deselect' button: clear the current selection so the map shows EVERYTHING
	again -- drops the selected tile, any link/coverage selection filters, and any
	duplicate diff. Restores the full overview and forces a repaint of the map + its
	overlay so the tiles/links redraw immediately."
	(view respondsTo: #selectTileNode:)
		ifTrue: [view selectTileNode: nil].
	"Force the tile layer + overlay to repaint (selection border, filtered links, dim)."
	(view respondsTo: #flushCacheKeepingSelection)
		ifTrue: [view flushCacheKeepingSelection].
	view changed.
	(view respondsTo: #overlayMorph)
		ifTrue: [view overlayMorph ifNotNil: [:o | o changed]].
	self refresh
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:59'
}
SWAPane >> detailInfoContents [
	"Multi-line details for the Show-mode details box (beside the source). Views opt
	in by implementing #detailInfoString; otherwise '' (no box content)."
	(view respondsTo: #detailInfoString) ifTrue: [^ view detailInfoString ifNil: ['']].
	^ ''
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:07'
}
SWAPane >> enclosingWindow [
	"The SystemWindow that contains this panel, or nil if opened bare in the world."
	^ self ownerThatIsA: SystemWindow
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:45'
}
SWAPane >> enforceMinimumWindowWidth [
	"Set the enclosing window's MINIMUM width to the button bar's natural one-row
	width (#headerNaturalWidth), and widen the window to it if it is currently
	narrower. This guarantees the window can't be sized so narrow that buttons clip,
	while still allowing the bar to wrap on extra rows above that floor. The MAP
	follows the window width either way (it is #spaceFill), so the window -- not the
	button bar -- drives the map width."
	| win minW |
	win := self enclosingWindow ifNil: [^ self].
	minW := self headerNaturalWidth.
	win minimumExtent: minW @ (win minimumExtent y max: 320).
	win width < minW ifTrue: [win extent: minW @ win height]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:46'
}
SWAPane >> exportCoverage [
	"Button: write the current provenance coverage (SWACoverageData) to a reusable,
	image-independent JSON file. (Export is a save -- a text prompt with a default
	path is friendlier than a chooser for naming a new file.)"
	| data path |
	data := self treemap coverageData.
	data ifNil: [^ self treemapCoverageStatus: 'No coverage to export (run Cover first)'].
	path := UIManager default
		request: 'Write coverage JSON to:'
		initialAnswer: (FileDirectory default fullNameFor: 'swa-coverage.json').
	(path isNil or: [path isEmpty]) ifTrue: [^ self].
	[data writeToFile: path withBlanksTrimmed]
		on: Error do: [:e | ^ self treemapCoverageStatus: 'Export failed: ', e messageText].
	self treemapCoverageStatus: 'Coverage written to ', path withBlanksTrimmed
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 12:33'
}
SWAPane >> extendMarksSelectionTo: anIndex [
	"SHIFT-click: select the contiguous range of rows between the previous primary row
	and anIndex (inclusive). With no prior primary, behaves like a single select."
	| items from to |
	items := self marksListItems.
	from := (marksPrimaryIndex isNil or: [marksPrimaryIndex = 0]) ifTrue: [anIndex] ifFalse: [marksPrimaryIndex].
	to := anIndex.
	marksSelectedKeys := Set new.
	(from min: to) to: (from max: to) do: [:i |
		(i between: 1 and: items size) ifTrue: [marksSelectedKeys add: (items at: i)]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 10:00'
}
SWAPane >> flashMarksMessage: aString [
	"Briefly show feedback (e.g. after Copy) in the run-info line."
	runInfoMorph ifNotNil: [runInfoMorph contents: aString]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAPane >> focusSearchField: evt [
	"Give the header search field keyboard focus (Ctrl+F). Selects any existing text so
	the user can type over it immediately."
	searchField ifNil: [^ self].
	evt hand newKeyboardFocus: searchField.
	searchField selectAll
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 18:04'
}
SWAPane >> generateCallTallyDataset [
	"Data-menu GENERATE (async twin of Load): a live CALL TALLY as a dataset. This is
	inherently TWO-PHASE and must be driven carefully -- instrumenting every shown
	method installs self-evicting wrappers that stay live until collected:
	  1st pick -- instrument the shown packages (wrappers installed; Tally button red),
	  2nd pick -- collect the counts, UNINSTALL the wrappers, and retain the result as
	              a named SWADataset whose #call metric colors the map.
	Between the two picks, EXERCISE the system so calls are counted. Reuses the same
	liveTally state machine as the Tally button, so the two never install twice."
	| root |
	liveTally ifNotNil: [^ self collectInvocationTally].
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Call Tally: only on a Code Map'].
	tallyAsDataset := true.
	self startInvocationTally: root.
	self treemapCoverageStatus: 'Call Tally: instrumented ', liveTally methods size printString,
		' methods -- EXERCISE the system, then pick ''Generate: call tally'' again (or press Tally) to collect'
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> generateCoverageDataset [
	"Data-menu GENERATE (async twin of Load): run SUnit coverage WITH provenance for
	the shown packages' related tests (forked + Stop-able via SWACoverage's run
	panel), then retain the result as a named, active SWADataset exactly as loading a
	coverage *.json would. Safe on a broad selection -- hit STOP to keep the partial."
	| root names testClasses |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Coverage: only on a Code Map'].
	names := root packageNames.
	testClasses := SWACoverage testClassesForPackages: names.
	testClasses isEmpty ifTrue: [
		^ self treemapCoverageStatus: 'Coverage: no related test classes found'].
	self treemapCoverageStatus: 'Coverage: running ', testClasses size printString,
		' test classes (use STOP to abort)...'.
	SWACoverage
		runProvenanceForPackages: names
		tests: testClasses
		then: [:data | self addCoverageDataset: data name: 'Coverage (generated)']
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> generateDuplicationDataset [
	"Data-menu GENERATE (async twin of Load): compute a duplication scan of the shown
	packages IN A FORK -- with an interruptible progress bar -- then retain the result
	as a named, active SWADataset exactly as loading a *.json would. Never wedges the
	UI: the fork runs at background priority and the dataset is installed back on the
	UI process."
	| root names |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Duplication: only on a Code Map'].
	names := root packageNames.
	names isEmpty ifTrue: [^ self treemapCoverageStatus: 'Duplication: no packages shown'].
	self treemapCoverageStatus: 'Duplication: analysing ', names size printString, ' package(s)...'.
	[ | data |
	  data := SWADuplicationData generatePackages: names asArray.
	  WorldState addDeferredUIMessage: [
		self addDuplicationDataset: data name: 'Duplication (generated)'] ]
		forkAt: Processor userBackgroundPriority
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:32'
}
SWAPane >> generateSampleTallyDataset [
	"Data-menu GENERATE (async twin of Load): run the external st-spy SAMPLING
	profiler against THIS image for #sampleTallyDuration seconds (a Preferences-
	configurable class pragma, default 10s), then retain the per-method self-sample
	counts as a named #sampleTally SWADataset that colors the map by CPU self-time
	heat. Fully async: st-spy samples in a detached process and #whenReadyDo: builds
	the tree + installs the dataset back on the UI process. EXERCISE the image during
	the window so there is something to sample."
	| tally secs |
	(self treemap isKindOf: SWACodeTreemapMorph) ifFalse: [
		^ self treemapCoverageStatus: 'Sample Tally: only on a Code Map'].
	secs := self class sampleTallyDuration.
	tally := SWASamplingTally new
		duration: secs;
		showProgress: true;
		yourself.
	tally record.
	tally failed ifTrue: [
		^ self treemapCoverageStatus: 'Sample Tally: could not start -- ', tally failureReason].
	self treemapCoverageStatus: 'Sample Tally: sampling this image for ', secs printString,
		's (exercise it now)...'.
	tally whenReadyDo: [:spy | | data |
		data := SWASampleTallyData fromSamplingTree: spy rootNode.
		self addSampleTallyDataset: data name: 'Sample Tally (', secs printString, 's)']
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:49'
}
SWAPane >> generateTopicDataset [
	"Data-menu GENERATE (async twin of Load): fit a Biterm Topic Model over the shown
	packages' methods IN A FORK (k = #topicK, sweeps = #topicSweeps, both Preferences-
	configurable), then retain the resulting SWATopicData as a named #topic SWADataset
	that tints each method by its dominant topic's hue family. Runs at background
	priority; the dataset is installed back on the UI process."
	| root leaves k sweeps |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Topic: only on a Code Map'].
	leaves := OrderedCollection new.
	root withAllChildrenDo: [:n | (n isKindOf: SWACodeMethodNode) ifTrue: [leaves add: n]].
	leaves isEmpty ifTrue: [^ self treemapCoverageStatus: 'Topic: no methods shown'].
	k := self class topicK.
	sweeps := self class topicSweeps.
	self treemapCoverageStatus: 'Topic: fitting BTM (k=', k printString, ', ',
		sweeps printString, ' sweeps) over ', leaves size printString, ' methods...'.
	[ | model data |
	  model := SWABitermTopicModel onMethodNodes: leaves.
	  model k: k.
	  data := model buildAndRun: sweeps.
	  WorldState addDeferredUIMessage: [
		data isNil
			ifTrue: [self treemapCoverageStatus: 'Topic: corpus empty after pruning -- nothing to model']
			ifFalse: [self addTopicDataset: data name: 'Topics (k=', k printString, ')']] ]
		forkAt: Processor userBackgroundPriority
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:37'
}
SWAPane >> growCoveringTestsPaneBy: deltaPixels [
	"Widen (positive) or narrow (negative) the covering-tests / duplicates list column
	by deltaPixels, from the SWAListSplitter drag. Clamped to a sane range; the source
	pane (spaceFill) absorbs the change. Relays out the Show row."
	coveringTestsColumn ifNil: [^ self].
	coveringTestsWidth := ((coveringTestsWidth ifNil: [340]) + deltaPixels) max: 140.
	coveringTestsWidth := coveringTestsWidth min: 900.
	coveringTestsColumn width: coveringTestsWidth.
	coveringTestsColumn owner ifNotNil: [:r | r layoutChanged].
	self layoutChanged
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:21'
}
SWAPane >> growMarksPanelBy: deltaPixels [
	"Widen (positive = dragging the splitter RIGHT) or narrow (negative) the
	left-docked Marks column by deltaPixels, from the SWASplitter drag. Clamped to a
	sane range; the view (spaceFill) absorbs the change. Relays out the body row."
	marksPanel ifNil: [^ self].
	marksWidth := ((marksWidth ifNil: [260]) + deltaPixels) max: 140.
	marksWidth := marksWidth min: 900.
	marksPanel width: marksWidth.
	marksPanel owner ifNotNil: [:r | r layoutChanged].
	self layoutChanged
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWAPane >> growSourceRowBy: deltaPixels [
	"Grow (deltaPixels > 0) or shrink the Show row's height by the given amount,
	driven by the splitter handle. Clamped to [120 .. panelHeight - 140] so the row
	stays usable and never swallows the treemap view above it."
	| newH maxH |
	sourceRow ifNil: [^ self].
	sourceRow owner ifNil: [^ self].
	maxH := (self height - 140) max: 120.
	newH := (sourceRow height + deltaPixels max: 120) min: maxH.
	newH = sourceRow height ifTrue: [^ self].
	sourceRow height: newH.
	sourceMorph ifNotNil: [sourceMorph height: newH].
	self layoutChanged
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:45'
}
SWAPane >> headerNaturalWidth [
	"The width the button bar needs to fit ALL its buttons on a SINGLE row: the sum
	of every button's width plus the inter-cell inset, with a little margin. Used to
	set the enclosing window's minimum width so buttons can never be clipped off the
	right edge (the bar still WRAPS at any width above this floor; this just stops the
	window getting narrower than one full row)."
	| inset margin |
	headerRow ifNil: [^ 200].
	inset := 6.
	margin := 24.
	^ margin + (headerRow submorphs inject: 0 into: [:sum :m | sum + m width + inset])
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:11'
}
SWAPane >> iconButtonGraphic: aForm action: aSelector [
	"A header button showing aForm as its icon that sends aSelector to THIS panel."
	^ IconicButton new
		labelGraphic: aForm;
		color: (Color gray: 0.3);
		borderWidth: 0;
		target: self;
		actionSelector: aSelector;
		hResizing: #rigid; vResizing: #rigid;
		yourself
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:19'
}
SWAPane >> importCoverage [
	"Button action (code map only): load a smalltalkCI Coveralls JSON file
	(coveralls_results.json) and overlay it as boolean coverage. Lets you view
	coverage produced by CI -- or a separate smalltalkCI run -- without re-running
	tests in this image."
	| path cov |
	(self treemap isKindOf: SWACodeTreemapMorph) ifFalse: [^ self].
	path := UIManager default
		request: 'Path to Coveralls JSON (coveralls_results.json):'
		initialAnswer: ''.
	(path isNil or: [path isEmpty]) ifTrue: [^ self].
	[cov := SWACoverage fromCoverallsFile: path withBlanksTrimmed]
		on: Error do: [:e |
			^ self treemapCoverageStatus: 'Coverage import failed: ', e messageText].
	self treemap showCoverage: cov.
	self treemapCoverageStatus: 'Coverage (imported): ', cov resultMap size printString,
		' methods covered'.
	self refresh
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:50'
}
SWAPane >> importData [
	"Unified Load button for the Code Map: open a *.json file chooser and overlay
	whatever kind of analysis data it holds, switching the view's color mode to
	match. Dispatch is by the JSON marker, so one button handles all kinds:
	  'SWACoverageData/1'    -> coverage overlay (green covered + blue tests)
	  'SWADuplicationData/1' -> duplication overlay (#duplication color mode)
	  'SWATopicData/1'       -> topic dataset (dominant-topic hue families)
	  space tally (kind=classSummary, or a node tree) -> per-class byte coloring
	Coverage/duplication/topic are image-independent ('Class>>selector'-keyed) and may
	be generated offline; space-tally JSON comes from SWASpaceTally>>writeToFile: (node
	tree) or SWASpaceTallyClassSummary>>writeToFile: (flat class census).

	Every load is ALSO retained as a named SWADataset, so loading twice gives two
	coexisting, switchable Color-menu entries."
	| tm path contents json format |
	tm := self treemap.
	(tm isKindOf: SWACodeTreemapMorph) ifFalse: [^ self].
	path := self chooseJsonFilePrompt: 'Load analysis JSON from:'.
	path ifNil: [^ self].
	[contents := (FileStream readOnlyFileNamed: path) contentsOfEntireFile.
	 json := Json readFrom: contents readStream]
		on: Error do: [:e | ^ self treemapCoverageStatus: 'Load failed: ', e messageText].
	(SWASpaceTallyClassSummary isSpaceTallyJson: json)
		ifTrue: [^ self loadSpaceTallyJson: json name: (self datasetNameFor: path)].
	format := (json at: 'format' ifAbsent: ['']) asString.
	(format beginsWith: 'SWADuplicationData')
		ifTrue: [^ self loadDuplicationJson: json name: (self datasetNameFor: path)].
	(format beginsWith: 'SWATopicData')
		ifTrue: [^ self loadTopicJson: json name: (self datasetNameFor: path)].
	"Default / 'SWACoverageData...' / legacy files with no marker -> coverage."
	self loadCoverageJson: json name: (self datasetNameFor: path)
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:07'
}
SWAPane >> loadCoverageJson: json [
	"Legacy entry: overlay coverage without a dataset name (keeps old callers working)."
	^ self loadCoverageJson: json name: 'coverage'
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> loadCoverageJson: json name: aName [
	"Overlay an already-parsed SWACoverageData JSON object (see #importData) as a
	retained, named SWADataset and make it the ACTIVE data source (shared tail
	#addCoverageDataset:name:). Its metrics ('By coverage', and 'By call' when the
	file has invocation data) stay selectable in the menus, and loading twice yields
	distinct entries you switch between instantly, no reload.

	Deliberately does NOT touch the legacy single-ivar coverage overlay."
	| data |
	data := SWACoverageData new.
	data loadFromJson: json.
	^ self addCoverageDataset: data name: aName
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:07'
}
SWAPane >> loadDuplicationJson: json [
	"Legacy entry: overlay duplication without a dataset name."
	^ self loadDuplicationJson: json name: 'duplication'
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 17:39'
}
SWAPane >> loadDuplicationJson: json name: aName [
	"Overlay an already-parsed SWADuplicationData JSON object as a retained, named
	SWADataset and make it the ACTIVE data source (shared tail
	#addDuplicationDataset:name:). Purely a dataset -- does NOT touch the legacy
	dupScores overlay."
	| data |
	data := SWADuplicationData new.
	data loadFromJson: json.
	^ self addDuplicationDataset: data name: aName
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:21'
}
SWAPane >> loadSpaceTallyJson: json name: aName [
	"Overlay an already-parsed space-tally JSON object (see #importData) as a
	retained, named #spaceTally SWADataset and make it the ACTIVE data source,
	applying its fitting defaults (color by instance bytes; size left intrinsic).

	Accepts EITHER flavor: a flat class-summary census (kind = classSummary) or a
	full node tree, aggregated per class on load. When loaded from a node tree, the
	dataset also RETAINS the reconstructed tree (structureRoot), so it can later BE
	the map's base structure via the Tree button. Its metrics -- 'By instance bytes'
	and 'By retained bytes' -- stay selectable in the Color/Size menus."
	| tm ds |
	tm := self treemap.
	ds := tm addDataset: (SWADataset spaceTallyFromJsonObject: json named: aName).
	tm selectDataset: ds.
	self treemapCoverageStatus: 'Space tally (', ds name, '): ',
		ds source classCount printString, ' classes',
		(ds providesStructure ifTrue: [' (Tree available)'] ifFalse: ['']).
	self refresh
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 10:51'
}
SWAPane >> loadTopicJson: json name: aName [
	"Load an already-parsed SWATopicData JSON object (see #importData) as a retained,
	named #topic SWADataset via the shared tail #addTopicDataset:name:. Refactors the
	old special-case topic load (SWAPane class>>openTopics:onPackageNamed:) into the
	same dataset path as coverage/duplication, so topic color is a switchable dataset
	metric like the rest -- no legacy #topic mode needed."
	| data |
	data := SWATopicData new loadFromJson: json.
	^ self addTopicDataset: data name: aName
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 10:00'
}
SWAPane >> marksChanged [
	"The global SWAMarkSet changed: flush this view's marked-node cache, repaint the
	view + its overlay (green borders), and refresh the Marks list panel if shown.
	Called on every open pane by SWAMarkSet>>notifyPanes."
	(view respondsTo: #flushMarksCache) ifTrue: [view flushMarksCache].
	view ifNotNil: [view changed].
	((view respondsTo: #overlayMorph) and: [view overlayMorph notNil])
		ifTrue: [view overlayMorph changed].
	self updateMarksList
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 10:00'
}
SWAPane >> marksListItems [
	"The list contents for the Marks panel: the global mark keys in mark order
	(package name / class name / 'ClassName>>selector')."
	^ SWAMarkSet default keys asArray
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> marksListMenu: aMenu [
	"Right-click context menu for the Marks list. Copy and Remove act on the current
	multi-selection when there is one, otherwise on all marks; the labels say which."
	| n |
	n := (marksSelectedKeys ifNil: [Set new]) size.
	aMenu addTitle: 'Marks'.
	n > 0
		ifTrue: [
			aMenu add: 'Copy selected (', n printString, ') to clipboard' target: self selector: #copyMarks.
			aMenu addLine.
			aMenu add: 'Remove selected (', n printString, ')' target: self selector: #removeSelectedMark.
			aMenu add: 'Clear all' target: self selector: #clearAllMarks]
		ifFalse: [
			aMenu add: 'Copy all to clipboard' target: self selector: #copyMarks.
			aMenu addLine.
			aMenu add: 'Clear all' target: self selector: #clearAllMarks].
	^ aMenu
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAPane >> marksListSelectionAt: index [
	"Is the Marks row at index part of the multi-selection?"
	| items |
	items := self marksListItems.
	(index between: 1 and: items size) ifFalse: [^ false].
	^ marksSelectedKeys notNil and: [marksSelectedKeys includes: (items at: index)]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> marksListSelectionAt: index put: aBoolean [
	"Add/remove the Marks row at index from the multi-selection (shift/ctrl-click)."
	| items key |
	items := self marksListItems.
	(index between: 1 and: items size) ifFalse: [^ self].
	marksSelectedKeys ifNil: [marksSelectedKeys := Set new].
	key := items at: index.
	aBoolean
		ifTrue: [marksSelectedKeys add: key. commentEditKey := key]
		ifFalse: [marksSelectedKeys remove: key ifAbsent: []].
	self updateCommentField
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:36'
}
SWAPane >> marksPrimaryIndex [
	"The primary-selection row index for the Marks list (drives the comment editor).
	0 = none."
	^ marksPrimaryIndex ifNil: [0]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:47'
}
SWAPane >> marksPrimaryIndex: anIndex shifted: shifted controlled: controlled [
	"Selection semantics for the Marks list (AlternatePluggableListMorphOfMany):
	 - PLAIN click: replace the selection with just this row.
	 - CTRL click: toggle this row in/out of the selection.
	 - SHIFT click: extend the selection as a range from the previous primary row.
	The clicked row becomes primary and its comment loads into the editor.

	Ctrl+click arrives here as #controlled:true because the global SWAMarksClickFilter
	rewrites the VM's emulated Ctrl+click (yellow button) back into a real Ctrl+Red
	left-click before dispatch (requires Morph metaMenuForAll to be OFF)."
	| items key |
	items := self marksListItems.
	marksSelectedKeys ifNil: [marksSelectedKeys := Set new].
	(anIndex between: 1 and: items size) ifFalse: [
		marksPrimaryIndex := 0. commentEditKey := nil.
		self updateCommentField. marksList ifNotNil: [marksList changed]. ^ self].
	key := items at: anIndex.
	shifted
		ifTrue: [self extendMarksSelectionTo: anIndex]
		ifFalse: [controlled
			ifTrue: [(marksSelectedKeys includes: key)
				ifTrue: [marksSelectedKeys remove: key ifAbsent: []]
				ifFalse: [marksSelectedKeys add: key]]
			ifFalse: [marksSelectedKeys := Set with: key]].
	marksPrimaryIndex := anIndex.
	commentEditKey := key.
	self updateCommentField.
	marksList ifNotNil: [marksList changed]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> metaInfoContents [
	"Meta-info string from the view, or nil if unsupported."
	^ (view respondsTo: #metaInfoString)
		ifTrue: [view metaInfoString]
		ifFalse: [nil]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:38'
}
SWAPane >> morphViewInto: aViewMorph [
	"Replace the panel's inner view with aViewMorph and rebuild the chrome around it,
	in place, keeping this panel (and its enclosing window) put. The previously
	displayed view is only REMOVED from the panel, not destroyed -- it lives on in
	structureViews for switching back.

	Detach the old view so clearing submorphs can't delete it; reset the lazily-built
	chrome ivars so #setView: builds a fresh set; then re-run #setView:."
	| oldView |
	oldView := view.
	oldView ifNotNil: [oldView delete].  "detach from this panel; morph object survives"
	self removeAllMorphs.
	"Drop references to the old chrome morphs so setView: rebuilds them cleanly."
	headerRow := breadcrumbMorph := selectionPathMorph := metaInfoMorph := runInfoMorph := nil.
	sourceMorph := detailsPane := detailsTitle := sourceRow := nil.
	coveringTestsPane := coveringTestsTitle := sourceSplitter := nil.
	depthButton := fullButton := tallyButton := nil.
	bodyRow := marksPanel := marksList := marksButton := nil.
	marksSplitter := commentField := nil.
	self setView: aViewMorph.
	self layoutChanged.
	aViewMorph changed
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:36'
}
SWAPane >> newCoveringTestsPane [
	"A titled list pane (right of the source pane) showing, for the selected method,
	the tests/TestCases that cover it -- or, for a selected test, the methods it
	covers -- or, for a container under a duplication dataset, the aggregated
	near-duplicates. Clicking an entry navigates / previews. The column WIDTH is
	resizable via the SWAListSplitter to its left (see #newSourceRow)."
	| column list |
	coveringTestsTitle := StringMorph new
		contents: 'Coverage';
		font: ((TextStyle default fontOfPointSize: 11) emphasized: 1);
		color: (Color gray: 0.9);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.
	list := PluggableListMorph
		on: self
		list: #provenanceList
		selected: #provenanceIndex
		changeSelected: #provenanceIndex:.
	list
		color: (Color gray: 0.1);
		textColor: (Color gray: 0.92);
		hResizing: #spaceFill; vResizing: #spaceFill.
	(list respondsTo: #highlightColor:) ifTrue: [list highlightColor: (Color h: 210 s: 0.6 v: 0.6)].
	coveringTestsPane := list.
	coveringTestsWidth ifNil: [coveringTestsWidth := 340].
	column := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #rigid; vResizing: #spaceFill;
		width: coveringTestsWidth;
		yourself.
	column addMorphBack: coveringTestsTitle; addMorphBack: list.
	coveringTestsColumn := column.
	^ column
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:59'
}
SWAPane >> newDetailsPane [
	"A titled, fixed-width box (left of the source pane in Show mode) showing the
	selected node's details -- the same info as the second header line, but laid out
	multi-line and WITHOUT the covered-methods/tests provenance (that has its own
	pane). Only meaningful for views answering #detailInfoString."
	| column box |
	detailsTitle := StringMorph new
		contents: 'Details';
		font: ((TextStyle default fontOfPointSize: 11) emphasized: 1);
		color: (Color gray: 0.9);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.
	box := TextMorph new
		contents: (self detailInfoContents ifNil: ['']);
		backgroundColor: (Color gray: 0.1);
		hResizing: #spaceFill; vResizing: #spaceFill;
		yourself.
	box textColor: (Color gray: 0.92).
	detailsPane := box.
	column := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #rigid; vResizing: #spaceFill;
		width: 260;
		yourself.
	column addMorphBack: detailsTitle; addMorphBack: box.
	^ column
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:39'
}
SWAPane >> newMarksPanel [
	"Build the left-hand Marks panel: a title, a Copy/Clear button row, a MULTI-SELECT
	list of the global mark keys (black-on-white), and -- beneath it -- a comment
	editor for the primary-selected mark. PLAIN click replaces the selection, SHIFT
	click ranges, and CTRL click toggles. Ctrl+click reaching the list is made
	possible by the global SWAMarksClickFilter, which rewrites this VM's emulated
	Ctrl+click (yellow button) back into a real Ctrl+left-click over a marks list.
	Comments are shown only in the editor (not inline) and persist in SWAMarkSet."
	| column title buttons commentTitle |
	marksSelectedKeys ifNil: [marksSelectedKeys := Set new].
	title := StringMorph new
		contents: 'Marks';
		font: ((TextStyle default fontOfPointSize: 11) emphasized: 1);
		color: (Color gray: 0.9);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.
	buttons := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellInset: 4;
		hResizing: #spaceFill; vResizing: #shrinkWrap;
		yourself.
	buttons
		addMorphBack: (self buttonLabelled: 'Copy' action: #copyMarks);
		addMorphBack: (self buttonLabelled: 'Clear' action: #clearMarks).
	marksList := SWAMarksListMorph
		on: self
		list: #marksListItems
		primarySelection: #marksPrimaryIndex
		changePrimarySelection: #marksPrimaryIndex:shifted:controlled:
		listSelection: #marksListSelectionAt:
		changeListSelection: #marksListSelectionAt:put:
		menu: #marksListMenu:
		keystroke: nil.
	marksList
		hResizing: #spaceFill; vResizing: #spaceFill;
		color: Color white;
		textColor: Color black.
	commentTitle := StringMorph new
		contents: 'Comment (Enter to save)';
		font: (TextStyle default fontOfPointSize: 10);
		color: (Color gray: 0.7);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.
	commentField := PluggableTextMorph
		on: self
		text: #commentFieldText
		accept: #acceptComment:.
	commentField
		hResizing: #spaceFill; vResizing: #rigid;
		height: 70.
	column := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		cellInset: 2;
		hResizing: #rigid; vResizing: #spaceFill;
		width: (marksWidth ifNil: [260]);
		yourself.
	column
		addMorphBack: title;
		addMorphBack: buttons;
		addMorphBack: marksList;
		addMorphBack: commentTitle;
		addMorphBack: commentField.
	^ column
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:19'
}
SWAPane >> newSearchField [
	"A fixed-size single-line text field for the header bar, WHITE so it reads as an
	editable field, sized to the same height as the header buttons, with a little
	top-left padding so the text isn't jammed against the corner. Typing filters the
	view's entity names live (see #runSearch:).

	Sizing a TextMorph is fiddly: while it is auto-fit it sizes to its CONTENT and
	ignores #extent:. So we FIRST make it rigid (isAutoFit -> false), THEN
	#contents:wrappedTo: to establish the wrap width and turn wrapping on, and only
	then can #extent: pin the exact box. The height is taken from a sample button so
	it always matches the current button chrome."
	| field w h |
	w := 260.
	h := (self buttonLabelled: 'Ag' action: #yourself) height.
	field := SWASearchFieldMorph new
		panel: self;
		backgroundColor: Color white;
		textColor: Color black;
		hResizing: #rigid; vResizing: #rigid;
		yourself.
	field contents: '' wrappedTo: w.
	field extent: w @ h.
	"Top-left text padding (left@top right@bottom)."
	field margins: (6 @ 4 corner: 4 @ 4).
	field setBalloonText: 'Filter entities by name (Esc clears)'.
	searchField := field.
	^ field
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAPane >> newSourceMorph [
	"A read-only, syntax-highlighted code pane. Its MODEL is the view morph, so the
	view's #aboutToStyle: drives Shout highlighting in the right class context."
	| tm |
	tm := PluggableTextMorphPlus on: view text: nil accept: nil.
	tm useDefaultStyler.
	tm
		hResizing: #spaceFill;
		vResizing: #rigid;
		height: 220;
		setText: 'select an item to see its source'.
	^ tm
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:22'
}
SWAPane >> newSourceRow [
	"The bottom (Show-mode) area: a left-to-right row. For the Code Map (which has
	the extra vertical room and a #detailInfoString) it is
	[details box | source pane (spaceFill) | SPLITTER | covering-tests pane]; other
	views get just the source pane (spaceFill). A vertical SWASplitter lets you widen
	the RIGHT-docked list (drag LEFT to grow it) to read long duplicate entries."
	| row |
	sourceMorph ifNil: [sourceMorph := self newSourceMorph].
	row := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #topLeft;
		cellInset: 4;
		hResizing: #spaceFill; vResizing: #rigid;
		height: 220;
		yourself.
	(view respondsTo: #detailInfoString) ifTrue: [
		row addMorphBack: self newDetailsPane].
	sourceMorph hResizing: #spaceFill; vResizing: #spaceFill.
	row addMorphBack: sourceMorph.
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		row addMorphBack: (SWASplitter vertical
			resizeAction: [:delta | self growCoveringTestsPaneBy: delta negated];
			yourself).
		row addMorphBack: self newCoveringTestsPane].
	^ row
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAPane >> peerPanels [
	"Other open nav panels whose view is a cross-referenceable treemap."
	^ (SWAPane openPanels)
		select: [:p | p ~~ self and: [p treemap notNil]]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:38'
}
SWAPane >> popUpColorMenu [
	"Header 'Color' button: pop up the same Color menu the right-click context menu
	uses (shared #colorMenuMorph on the overlay)."
	self treemapOverlay ifNotNil: [:o | o popUpColorMenu]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:55'
}
SWAPane >> popUpDataMenu [
	"Header 'Data' button: pop up the top-level Data menu (loaded datasets + open
	peers). Built by the PANEL so every tool -- not just the Code Map -- can pick a
	data source and cross-reference peers."
	| menu |
	menu := self dataMenuMorph.
	menu ifNil: [^ self treemapCoverageStatus: 'Data: load a dataset or open another treemap to cross-reference'].
	menu popUpInWorld: self world
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:17'
}
SWAPane >> popUpDecorationMenu [
	"Header 'Links' button: pop up the same Links (decoration) menu the right-click
	context menu uses (shared #decorationMenuMorph on the overlay)."
	self treemapOverlay ifNotNil: [:o |
		(o respondsTo: #popUpDecorationMenu) ifTrue: [o popUpDecorationMenu]]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWAPane >> popUpSizeMenu [
	"Header 'Size' button: pop up the same Size menu the right-click context menu
	uses (shared #sizeMenuMorph on the overlay). Always reachable, even on a
	collapsed/black canvas."
	self treemapOverlay ifNotNil: [:o | o popUpSizeMenu]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> popUpTreeMenu [
	"Header 'Tree' button: pop up the base-structure selector. If nothing else can
	be a structure yet, tell the user via the status line rather than nothing."
	| menu |
	menu := self treeMenuMorph.
	menu ifNil: [
		^ self treemapCoverageStatus:
			'Tree: load a space-tally node-tree JSON to switch structure'].
	menu popUpInWorld: self world
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAPane >> provenanceIndex [
	"List-model selection index for the covering-tests pane."
	^ provenanceIndex ifNil: [0]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 7/15/2026 11:08'
}
SWAPane >> provenanceIndex: anInteger [
	"List-model click handler for the side pane. The entry VALUE decides the action:
	 - nil (a '... N more' note) -> no-op;
	 - a topic id (SmallInteger) while a TOPIC dataset is active -> FOCUS that single
	   topic (weight-heat recolor) and show its top raw words in the Details box;
	 - a  fromKey -> partnerKey  Association (a CONTAINER's aggregated duplicate pair) ->
	   PREVIEW that pair's diff WITHOUT navigating, so the list stays and the clicked row
	   just highlights (keep #provenanceIndex);
	 - a plain String key -> the method-selection case: DIFF against the clicked partner
	   when a method is selected, else NAVIGATE (coverage / other provenance)."
	| assoc value |
	provenanceIndex := anInteger.
	(anInteger = 0 or: [provenanceEntries isNil]) ifTrue: [^ self].
	assoc := provenanceEntries at: anInteger ifAbsent: [^ self].
	value := assoc value.
	value ifNil: [^ self].   "non-navigating note"
	"Topic focus: entry value is a topic id while a topic dataset is active."
	((value isKindOf: Integer)
		and: [(view respondsTo: #isTopicProvenanceActive) and: [view isTopicProvenanceActive]]) ifTrue: [
			(view respondsTo: #focusTopic:) ifTrue: [view focusTopic: value].
			self refresh.
			^ self].
	"Container aggregated pair: preview the diff, keep the list + highlight."
	(value isKindOf: Association) ifTrue: [
		(view respondsTo: #previewDuplicatePairFrom:to:) ifTrue: [
			view previewDuplicatePairFrom: value key to: value value].
		^ self].
	"Method-selection case: diff if a method is selected, else navigate."
	((view respondsTo: #isDuplicationProvenanceActive) and: [view isDuplicationProvenanceActive]
		and: [view respondsTo: #dupDiffTarget:]
		and: [(view respondsTo: #selectionIsMethodForDiff) and: [view selectionIsMethodForDiff]]) ifTrue: [
			| node |
			node := (view respondsTo: #keyIndex)
				ifTrue: [view keyIndex at: value ifAbsent: [nil]]
				ifFalse: [nil].
			^ view dupDiffTarget: node].
	(view respondsTo: #selectNodeForKey:)
		ifTrue: [view selectNodeForKey: value]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAPane >> provenanceList [
	"List-model contents for the covering-tests pane: the display labels of the
	current selection's provenance entries."
	^ (provenanceEntries ifNil: [#()]) collect: [:assoc | assoc key]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:01'
}
SWAPane >> refresh [
	"Re-pull all label strings from the view and reload the source + details +
	covering-tests panes (if shown). The view calls this after any selection/zoom
	change. The info area is TWO lines: line 1 = generic whole-run info
	(#runInfoMorph), line 2 = current-selection info (#metaInfoMorph)."
	breadcrumbMorph ifNotNil: [breadcrumbMorph contents: self breadcrumbContents].
	selectionPathMorph ifNotNil: [selectionPathMorph contents: (self selectionPathContents ifNil: [''])].
	runInfoMorph ifNotNil: [runInfoMorph contents: (self runInfoContents ifNil: [''])].
	metaInfoMorph ifNotNil: [metaInfoMorph contents: (self selectionInfoContents ifNil: [''])].
	self updateSource.
	self updateDetails.
	self updateCoveringTests
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> removeSelectedMark [
	"Remove the currently multi-selected marks (globally). Falls back to the primary
	row if the multi-selection is empty."
	| picked |
	picked := (marksSelectedKeys notNil and: [marksSelectedKeys notEmpty])
		ifTrue: [marksSelectedKeys asArray]
		ifFalse: [
			| items idx |
			items := self marksListItems.
			idx := self marksPrimaryIndex.
			(idx between: 1 and: items size) ifTrue: [{ items at: idx }] ifFalse: [#()]].
	picked isEmpty ifTrue: [^ self].
	SWAMarkSet default removeAll: picked.
	marksSelectedKeys := Set new.
	marksPrimaryIndex := 0.
	commentEditKey := nil
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWAPane >> runInfoContents [
	"Line 1 of the info area: GENERIC, whole-run info (e.g. coverage status + the
	focused-subtree summary), independent of the current selection. Views opt in by
	implementing #runInfoString; otherwise we fall back to the legacy single
	#metaInfoString so non-split views keep working."
	(view respondsTo: #runInfoString) ifTrue: [^ view runInfoString ifNil: ['']].
	(view respondsTo: #metaInfoString) ifTrue: [^ view metaInfoString ifNil: ['']].
	^ ''
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:05'
}
SWAPane >> runSearch: aString [
	"Live name-filter driven by the header search field: dim every tile whose entity
	name doesn't contain aString (case-insensitive), keeping matches and their
	ancestors bright. Empty string clears the filter. Delegates to the view, which owns
	the match computation and redraw (see SWAView>>searchFor:)."
	view ifNil: [^ self].
	(view respondsTo: #searchFor:) ifTrue: [view searchFor: aString]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> selectedMarkKeys [
	"The mark keys the Copy/Clear actions operate on: the multi-selection if any rows
	are selected, otherwise ALL marks. Returned in mark order (not selection order)."
	| all |
	all := SWAMarkSet default keys.
	(marksSelectedKeys isNil or: [marksSelectedKeys isEmpty]) ifTrue: [^ all asArray].
	^ all select: [:k | marksSelectedKeys includes: k]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> selectedSourceContents [
	"Source text for the Show pane from the view, or nil if unsupported/none."
	^ (view respondsTo: #selectedSourceString)
		ifTrue: [view selectedSourceString]
		ifFalse: [nil]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWAPane >> selectionInfoContents [
	"Line 2 of the info area: info about the CURRENT SELECTION only (empty when
	nothing is selected). Views opt in by implementing #selectionInfoString; views
	that only support the legacy single-line #metaInfoString leave this line blank
	(their text already shows on line 1)."
	(view respondsTo: #selectionInfoString) ifTrue: [^ view selectionInfoString ifNil: ['']].
	^ ''
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> selectionPathContents [
	"Selection-path string from the view, or nil if unsupported."
	^ (view respondsTo: #selectionPathString)
		ifTrue: [view selectionPathString]
		ifFalse: [nil]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:55'
}
SWAPane >> setDataMode: aSymbol [
	"Data-menu action: make aSymbol the active data source on the wrapped view."
	| tm |
	tm := self treemap.
	(tm notNil and: [tm respondsTo: #setDataMode:]) ifTrue: [
		tm setDataMode: aSymbol.
		self refresh]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> setStructureMode: aKey [
	"Tree menu action: MORPH the panel's base view into the tree identified by aKey
	(#intrinsic = the Code Map; a dataset modeSymbol = that space tally's tree),
	reusing the SAME window/chrome. The other view is kept alive in structureViews
	so switching back is instant and lossless (the Code Map keeps its datasets, the
	tally keeps its layout). No-op if already active or unresolvable."
	| newView |
	aKey == self activeStructureKey ifTrue: [^ self].
	"Register the current intrinsic view before the first morph, so we can return."
	(self structureViews includesKey: #intrinsic)
		ifFalse: [(view respondsTo: #datasets) ifTrue: [structureViews at: #intrinsic put: view]].
	newView := self viewForStructureKey: aKey.
	newView ifNil: [^ self].
	activeStructureKey := aKey.
	self morphViewInto: newView.
	self updateStructureWindowLabel
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:59'
}
SWAPane >> setView: aViewMorph [
	"Build the panel chrome around aViewMorph: a WRAPPING button bar (Back/Browse/
	Deselect/Show/Marks + optional Data/Tree/Size/Color/Links + optional coverage
	controls + optional Depth + a name-SEARCH field), then a breadcrumb line carrying
	the fullscreen toggle at its right, then the selection-path line, a generic
	RUN-info line, a SELECTION-info line, then a BODY ROW holding the (initially
	hidden) Marks list panel on the LEFT and the view (spaceFill) on the right. The
	button bar wraps onto additional rows when the window is too narrow to fit every
	button. The source pane is created lazily by #toggleSource.

	The search field filters the view's entity NAMES live: typing dims every
	non-matching tile (see #runSearch: / SWAView>>searchFor:), Esc clears it.

	The Marks button toggles a left-hand list of the GLOBAL bookmarked nodes
	(SWAMarkSet), shared across every open panel; shift-click a tile to add/remove.

	Cross-referencing another open view is no longer a dedicated X-ref/Clear button
	pair: open peers appear as entries in the Data menu (pick one to color by it, pick
	None to clear), unifying 'which source colors this map' into one selector.

	Each optional button is gated on the overlay actually SUPPORTING it (non-empty
	Size/Color options, Data/Tree/Links protocols), so a view can opt into just the
	subset it implements -- e.g. the graph view exposes an overlay offering only Color."
	| crumbFont detailFont metaFont backButton browseButton showButton crumbRow ovl |
	view := aViewMorph.
	crumbFont := TextStyle default fontOfPointSize: 12.
	detailFont := (TextStyle default fontOfPointSize: 15) emphasized: 1.
	metaFont := TextStyle default fontOfPointSize: 11.

	self
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #spaceFill;
		vResizing: #spaceFill.

	backButton := self buttonLabelled: 'Back' action: #zoomOut.
	browseButton := self buttonLabelled: 'Browse' action: #browseSelected.
	showButton := self buttonLabelled: 'Show' action: #toggleSource.
	(view respondsTo: #leafKind:) ifTrue: [
		depthButton := self buttonLabelled: 'Depth: Full' action: #cycleLeafKind.
		self updateDepthLabel].
	fullButton := self iconButtonGraphic: MenuIcons smallFullscreenOnIcon action: #toggleFullScreen.

	breadcrumbMorph := StringMorph new
		contents: self breadcrumbContents;
		font: crumbFont;
		color: Color white;
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	headerRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		wrapDirection: #topToBottom;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	headerRow addMorphBack: backButton; addMorphBack: browseButton.
	"Deselect: clear the selection so the map shows everything again (drops the
	selected tile + its link/coverage filters + any duplicate diff)."
	(view respondsTo: #selectTileNode:) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'Deselect' action: #deselect)].
	headerRow addMorphBack: showButton.
	"Marks: toggle the left-hand list of globally bookmarked nodes."
	(view respondsTo: #markedNodes) ifTrue: [
		marksButton := self buttonLabelled: 'Marks' action: #toggleMarks.
		headerRow addMorphBack: marksButton].
	"Data / Tree / Size / Color / Links -- each gated on the overlay SUPPORTING it.
	Data leads (top-level source picker: loaded datasets AND open peers for
	cross-reference). Tree picks the base STRUCTURE. Size/Color are shown only when
	the overlay offers a non-empty option list, so a view can light up just Color
	(the graph) without a dead Size button."
	ovl := self treemapOverlay.
	ovl ifNotNil: [
		(view respondsTo: #selectDataset:) ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Data' action: #popUpDataMenu)].
		self showsTreeButton ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Tree' action: #popUpTreeMenu)].
		((ovl respondsTo: #sizeModeOptions) and: [ovl sizeModeOptions notEmpty]) ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Size' action: #popUpSizeMenu)].
		((ovl respondsTo: #colorModeOptions) and: [ovl colorModeOptions notEmpty]) ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Color' action: #popUpColorMenu)].
		(view respondsTo: #decorationMetric) ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Links' action: #popUpDecorationMenu)]].
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		tallyButton := self buttonLabelled: 'Tally' action: #coverageTally.
		headerRow addMorphBack: tallyButton.
		headerRow addMorphBack: (self buttonLabelled: 'Export' action: #exportCoverage).
		headerRow addMorphBack: (self buttonLabelled: 'Load' action: #importData).
		self updateTallyButton].
	depthButton ifNotNil: [headerRow addMorphBack: depthButton].
	"Live name-search: dims tiles whose entity name doesn't match what you type."
	(view respondsTo: #searchFor:) ifTrue: [
		headerRow addMorphBack: self newSearchField].

	crumbRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	crumbRow addMorphBack: breadcrumbMorph; addMorphBack: fullButton.

	selectionPathMorph := StringMorph new
		contents: (self selectionPathContents ifNil: ['']);
		font: detailFont;
		color: (Color gray: 0.95);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	runInfoMorph := StringMorph new
		contents: (self runInfoContents ifNil: ['']);
		font: metaFont;
		color: (Color gray: 0.6);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	metaInfoMorph := StringMorph new
		contents: (self selectionInfoContents ifNil: ['']);
		font: metaFont;
		color: (Color gray: 0.8);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	view hResizing: #spaceFill; vResizing: #spaceFill.

	"BODY ROW: [ (hidden) Marks panel | view ], laid out left-to-right so the Marks
	list docks on the left like the Show pane docks at the bottom."
	bodyRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #topLeft;
		hResizing: #spaceFill; vResizing: #spaceFill;
		yourself.
	bodyRow addMorphBack: view.

	self addMorphBack: headerRow;
		addMorphBack: crumbRow;
		addMorphBack: selectionPathMorph;
		addMorphBack: runInfoMorph;
		addMorphBack: metaInfoMorph;
		addMorphBack: bodyRow.

	(view respondsTo: #navPanel:) ifTrue: [view navPanel: self]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:54'
}
SWAPane >> showSelectionPath: aStringOrNil [
	"Directly set the selection-path line (used for live hover feedback, which is
	not driven by the persistent selection)."
	selectionPathMorph ifNotNil: [selectionPathMorph contents: (aStringOrNil ifNil: [''])]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:24'
}
SWAPane >> showsTreeButton [
	"Show the Tree (base-structure) button when structure switching is meaningful:
	on a Code Map (it can host loaded structure datasets, and the menu covers the
	'none loaded yet' case), or whenever we have already morphed away from intrinsic
	(so there is always a way back)."
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [^ true].
	^ self activeStructureKey ~~ #intrinsic
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> sourceMorph [
	"The embedded source pane, or nil if never shown. Owner is nil while hidden."
	^ sourceMorph
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWAPane >> startInvocationTally: aCodeRoot [
	"Install live invocation-counting wrappers on the shown packages (Ingalls-style,
	self-evicting on hot methods). They stay installed while you exercise the system.
	Press Tally again -> #collectInvocationTally to read counts and uninstall.
	The Tally button turns red; status shown in the meta line, no dialog."
	liveTally ifNotNil: [^ self collectInvocationTally].
	liveTally := SWACoverage new
		evictAt: 1000;
		methodsForPackages: aCodeRoot packageNames.
	liveTally instrumentTally.
	self updateTallyButton.
	self treemapCoverageStatus: 'Tallying ', liveTally methods size printString,
		' methods -- exercise, then press Tally to collect'
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:22'
}
SWAPane >> structureDatasets [
	"The retained datasets that can BE a base structure (have their own tree).
	Sourced from the intrinsic Code Map view, which owns the datasets regardless of
	which structure is currently displayed."
	| cm |
	cm := self codeMapView.
	(cm notNil and: [cm respondsTo: #datasets]) ifFalse: [^ #()].
	^ cm datasets select: [:ds | ds providesStructure]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> structureOptions [
	"{ key. label } pairs for the Tree selector: the intrinsic Code Map, plus one
	entry per retained structure-capable dataset (a space tally loaded from a node
	tree). Picking one MORPHS the view into that tree's tool in place."
	| opts |
	opts := OrderedCollection new.
	opts add: (Array with: #intrinsic with: 'Code map').
	self structureDatasets do: [:ds |
		opts add: (Array with: ds modeSymbol with: 'Space tally: ', (ds name ifNil: ['?']))].
	^ opts asArray
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:22'
}
SWAPane >> structureViews [
	"Cache of fully-wired view morphs keyed by a structure symbol (#intrinsic for
	the map first opened here, or a dataset's modeSymbol for a structure dataset).
	Keeping the morphs alive is what lets Tree switch back and forth WITHOUT losing
	the Code Map's loaded datasets or the tally's layout."
	^ structureViews ifNil: [structureViews := Dictionary new]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:21'
}
SWAPane >> toggleFullScreen [
	"Fullscreen toggle: cover the ENTIRE Display edge-to-edge, including the top
	docking/menu bar, or restore the previous frame. To hide the window's own title
	bar without touching its layout, we just push the window UP by its label height
	so the title bar sits above the visible Display and the panel fills the screen.
	The docking bar sits in the world's frontmost layer, so we insert the window at
	absolute submorph index 1 to draw over it; restoring re-adds it as a normal
	layered window. Unlike SystemWindow>>fullScreen this applies no insets."
	| window world top |
	window := self enclosingWindow ifNil: [^ Beeper beep].
	world := window world ifNil: [^ Beeper beep].
	savedWindowFrame
		ifNil: [
			savedWindowFrame := window bounds.
			world privateAddMorph: window atIndex: 1.
			"Offset up by the title-bar strip so it clips off the top of the Display."
			top := window labelHeight + window layoutInset + window borderWidth.
			window bounds: (Display boundingBox origin - (0 @ top)
				corner: Display boundingBox corner).
			fullButton ifNotNil: [fullButton labelGraphic: MenuIcons smallFullscreenOffIcon]]
		ifNotNil: [
			window bounds: savedWindowFrame.
			savedWindowFrame := nil.
			world addMorphFront: window.
			fullButton ifNotNil: [fullButton labelGraphic: MenuIcons smallFullscreenOnIcon]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 14:40'
}
SWAPane >> toggleMarks [
	"Marks button: show/hide the left-hand Marks panel -- a MULTI-SELECT list of the
	GLOBAL bookmarked nodes (SWAMarkSet) plus a comment editor, shared across every
	open panel. Hidden by default (like the bottom Show pane). A draggable vertical
	SWASplitter sits between the list and the main view so the column can be resized.
	Showing the panel installs the global SWAMarksClickFilter so Ctrl+click toggles
	selection despite the VM's single-button emulation."
	(marksPanel notNil and: [marksPanel owner notNil])
		ifTrue: [
			marksSplitter ifNotNil: [marksSplitter delete. marksSplitter := nil].
			marksPanel delete. marksPanel := nil. marksList := nil. commentField := nil]
		ifFalse: [
			SWAMarksClickFilter ensureInstalled.
			marksPanel := self newMarksPanel.
			marksSplitter := SWASplitter vertical
				resizeAction: [:delta | self growMarksPanelBy: delta];
				yourself.
			"Front-to-back: [marks list | splitter | view]."
			bodyRow addMorphFront: marksSplitter.
			bodyRow addMorphFront: marksPanel.
			self updateMarksList].
	self layoutChanged
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:22'
}
SWAPane >> toggleSource [
	"Show button: show/hide the bottom area at the bottom of the panel. The bottom
	area is a horizontal row holding -- for the Code Map -- a details box (left), the
	source pane (center), and a covering-tests list pane (right); other views get
	just the source pane. A draggable horizontal SWASplitter is inserted ABOVE the row
	so the user can resize it taller (e.g. to read an inline diff); dragging UP grows
	it. When shown, load the current selection's source, details, and provenance."
	(sourceRow notNil and: [sourceRow owner notNil])
		ifTrue: [
			sourceSplitter ifNotNil: [sourceSplitter delete].
			sourceRow delete]
		ifFalse: [
			sourceRow ifNil: [sourceRow := self newSourceRow].
			sourceSplitter ifNil: [
				sourceSplitter := SWASplitter horizontal
					resizeAction: [:delta | self growSourceRowBy: delta negated];
					yourself].
			self addMorphBack: sourceSplitter.
			self addMorphBack: sourceRow.
			self updateSource.
			self updateDetails.
			self updateCoveringTests].
	self layoutChanged
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> treeMenuMorph [
	"Build the Tree menu: pick which node tree is the base structure. 'Code map'
	plus one entry per structure-capable dataset; the active one is ticked. Answers
	nil when there is nothing to switch to (no structure datasets loaded)."
	| opts menu current |
	opts := self structureOptions.
	opts size <= 1 ifTrue: [^ nil].
	current := self activeStructureKey.
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | key label |
		key := pair first.
		label := current == key ifTrue: ['* ', pair second] ifFalse: ['   ', pair second].
		menu add: label selector: #setStructureMode: argument: key].
	^ menu
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:28'
}
SWAPane >> treemap [
	"The wrapped view, if it supports cross-referencing (treemap or flamegraph)."
	^ (view respondsTo: #keyIndex) ifTrue: [view] ifFalse: [nil]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWAPane >> treemapCoverageStatus: aString [
	"Set the coverage status line on the code map (no-op if not a code map)."
	| tm |
	tm := self treemap.
	(tm respondsTo: #coverageStatus:) ifTrue: [tm coverageStatus: aString]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWAPane >> treemapOverlay [
	"The wrapped view's event/menu overlay, or nil if it has none."
	^ (view respondsTo: #overlayMorph) ifTrue: [view overlayMorph] ifFalse: [nil]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:37'
}
SWAPane >> updateCommentField [
	"Reload the comment editor from the mark currently being edited."
	commentField ifNotNil: [commentField setText: self commentFieldText]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:32'
}
SWAPane >> updateCoveringTests [
	"If the covering-tests pane is showing, refill it from the view's current selection
	(tests covering the selected method, methods a test covers, or a container's
	aggregated duplicates) and update its title. PRESERVES the selected row when the
	list content is UNCHANGED -- so browsing a container's duplicate list (which
	previews a pair without changing the primary selection) keeps the clicked row
	highlighted instead of clearing it."
	| newEntries sameList |
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	coveringTestsPane ifNil: [^ self].
	newEntries := (view respondsTo: #provenanceListForSelection)
		ifTrue: [view provenanceListForSelection]
		ifFalse: [#()].
	sameList := provenanceEntries notNil
		and: [(provenanceEntries collect: [:a | a key]) = (newEntries collect: [:a | a key])].
	provenanceEntries := newEntries.
	sameList ifFalse: [provenanceIndex := 0].
	coveringTestsTitle ifNotNil: [
		coveringTestsTitle contents:
			((view respondsTo: #provenanceListTitle)
				ifTrue: [view provenanceListTitle]
				ifFalse: ['Coverage'])].
	coveringTestsPane updateList
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:25'
}
SWAPane >> updateDepthLabel [
	"Relabel the depth button to reflect the view's current render depth (leafKind).
	A view may supply its own friendlier text via #depthLabelString (e.g. the class
	diagram maps #class/#state/#method to Classes / +State / +Methods)."
	| kind text |
	depthButton ifNil: [^ self].
	(view respondsTo: #depthLabelString) ifTrue: [
		^ depthButton label: view depthLabelString].
	kind := (view respondsTo: #leafKind) ifTrue: [view leafKind] ifFalse: [nil].
	text := kind
		ifNil: ['Depth: Full']
		ifNotNil: ['Depth: ', (kind asString capitalized)].
	depthButton label: text
]

{
	#category : #updating,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:01'
}
SWAPane >> updateDetails [
	"If the Show-mode details box is showing, refill it from the current selection."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	detailsPane ifNotNil: [
		detailsPane contents: (self detailInfoContents ifNil: [''])]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 11:38'
}
SWAPane >> updateMarksList [
	"Refresh the Marks list contents (if shown), pruning selection/comment keys that
	no longer exist and reloading the comment editor."
	| live |
	live := SWAMarkSet default keys asSet.
	marksSelectedKeys ifNotNil: [
		marksSelectedKeys := marksSelectedKeys select: [:k | live includes: k]].
	(commentEditKey notNil and: [(live includes: commentEditKey) not])
		ifTrue: [commentEditKey := nil].
	marksList ifNotNil: [marksList updateList].
	self updateCommentField
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:58'
}
SWAPane >> updateSource [
	"If the bottom area is showing, reload the source pane from the current selection."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	sourceMorph ifNotNil: [
		sourceMorph setText: (self selectedSourceContents ifNil: [''])]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> updateStructureWindowLabel [
	"Reflect the active structure in the enclosing window title, if any."
	| win label |
	win := self enclosingWindow.
	win ifNil: [^ self].
	label := self activeStructureKey == #intrinsic
		ifTrue: ['Code Map']
		ifFalse: [| ds | ds := self structureDatasets detect: [:d | d modeSymbol == self activeStructureKey] ifNone: [nil].
			'Space Tally: ', (ds ifNotNil: [:d | d name] ifNil: ['?'])].
	win setLabel: label
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:14'
}
SWAPane >> updateTallyButton [
	"Tint the Tally button red while a tally is live (next press collects), normal
	grey when idle."
	tallyButton ifNil: [^ self].
	tallyButton color: (liveTally isNil
		ifTrue: [Color gray: 0.3]
		ifFalse: [Color r: 0.7 g: 0.15 b: 0.15])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWAPane >> view [
	"The wrapped view morph (treemap or flamegraph)."
	^ view
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:23'
}
SWAPane >> viewForStructureKey: aKey [
	"The (cached, fully-wired) view morph for a structure key. #intrinsic is the
	Code Map; a dataset modeSymbol builds -- once -- a Space Tally treemap on that
	dataset's retained structureRoot. Answers nil if the key can't be resolved."
	aKey == #intrinsic ifTrue: [^ self codeMapView].
	^ self structureViews at: aKey ifAbsentPut: [
		| ds tm |
		ds := self structureDatasets detect: [:d | d modeSymbol == aKey] ifNone: [nil].
		ds ifNil: [^ nil].
		tm := SWASpaceTallyTreemapMorph on: ds structureRoot.
		tm extent: view extent.
		self wireOverlayFor: tm.
		tm]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:22'
}
SWAPane >> wireOverlayFor: aTreemapMorph [
	"Attach the matching event/menu overlay to aTreemapMorph if it doesn't have one
	yet, mirroring the opener wiring (SWACodeNode>>openTreemapLeafKind: /
	SWASpaceTally>>openTreemap). The overlay class is the treemap's #overlayClass."
	| overlay |
	(aTreemapMorph respondsTo: #overlayMorph) ifFalse: [^ aTreemapMorph].
	aTreemapMorph overlayMorph ifNotNil: [^ aTreemapMorph].
	overlay := aTreemapMorph overlayClass new.
	overlay treemapMorph: aTreemapMorph.
	overlay extent: aTreemapMorph extent.
	aTreemapMorph overlayMorph: overlay.
	aTreemapMorph addMorph: overlay.
	^ aTreemapMorph
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWAPane >> zoomOut [
	"Back button: ask the view to zoom out, then refresh the chrome."
	(view respondsTo: #zoomOut) ifTrue: [view zoomOut].
	self refresh
]
