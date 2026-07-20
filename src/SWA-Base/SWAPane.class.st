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
		'tallyStopPanel',
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
		'commentEditKey',
		'marksTab',
		'marksCollapseTab',
		'sourceTab',
		'sourceCollapseTab',
		'marksDetailsMorph'
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
	#category : #'marks-show',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:44'
}
SWAPane class >> openPanes [
	"All SWAPane instances that are currently in a live world (open windows)."
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
	#category : #'marks-show',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:01'
}
SWAPane class >> paneMatchingProvenance: aProvenanceDict [
	"An already-open SWAPane whose view KIND and root scope match the given provenance
	Dictionary (String->String, or nil), or nil if none. Matches on #viewKind (the
	machine-readable Symbol, compared as a String; falls back to viewClass for older
	records that predate viewKind) and, when present, the scope glob."
	| wantKind wantClass wantScope |
	aProvenanceDict ifNil: [^ nil].
	wantKind := aProvenanceDict at: 'viewKind' ifAbsent: [nil].
	wantClass := aProvenanceDict at: 'viewClass' ifAbsent: [nil].
	wantScope := aProvenanceDict at: 'scopeGlob' ifAbsent: [nil].
	^ self openPanes
		detect: [:p | | v root kindOk |
			v := p view.
			kindOk := wantKind notNil
				ifTrue: [(v respondsTo: #viewKind) and: [v viewKind asString = wantKind]]
				ifFalse: [wantClass isNil or: [v class name asString = wantClass]].
			kindOk
				and: [wantScope isNil
					or: [root := (v respondsTo: #rootNode) ifTrue: [v rootNode] ifFalse: [nil].
						root notNil
							and: [(root respondsTo: #displayName)
								and: [root displayName asString = wantScope]]]]]
		ifNone: [nil]
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
	#category : #'marks-show',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:45'
}
SWAPane class >> showMarkKey: aMarkKey [
	"Reveal aMarkKey in a real view: reuse an already-open pane of the recorded kind+scope
	if there is one, otherwise best-effort spawn a fresh one from the mark's provenance.
	Then bring its window to the front and select the node (if the view contains it, via
	crossRefKey). Answers the pane, or nil if nothing could be opened."
	| prov pane window |
	aMarkKey ifNil: [^ nil].
	prov := SWAMarkSet default provenanceAt: aMarkKey.
	pane := self paneMatchingProvenance: prov.
	pane ifNil: [
		window := self spawnFromProvenance: prov.
		window ifNil: [^ nil].
		pane := window allMorphs detect: [:m | m isKindOf: SWAPane] ifNone: [nil]].
	pane ifNil: [^ nil].
	pane enclosingWindow ifNotNil: [:w | w activate; comeToFront].
	pane revealMarkKey: aMarkKey.
	^ pane
]

{
	#category : #'marks-show',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:45'
}
SWAPane class >> spawnFromProvenance: aProvenanceDict [
	"BEST-EFFORT open a fresh SWAPane matching the recorded provenance and answer its
	window (or nil if we cannot). We only reliably know the code-structure scope (the
	package glob), so we open a plain code treemap on that glob. Dataset-backed overlays
	(coverage/topic/duplication) can't be rebuilt -- their source file isn't recorded --
	so those degrade to the same structural map, which still contains the marked node.
	Answers the opened window."
	| glob |
	aProvenanceDict ifNil: [^ nil].
	glob := aProvenanceDict at: 'scopeGlob' ifAbsent: [nil].
	glob ifNil: [^ nil].
	^ self openOnPackageNamed: glob leafKind: nil
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
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:56'
}
SWAPane >> abandonInvocationTally [
	"Tear down a live invocation tally WITHOUT collecting or touching the treemap/UI.
	Safe to call during window teardown (#delete) or from error recovery. Uninstalls
	the wrappers, closes the STOP window, then sweeps ALL strays (layer-aware) as a
	belt-and-braces guarantee that no instrumentation lingers to corrupt unrelated
	tools (the Git-tool DNU). Idempotent."
	liveTally ifNotNil: [
		[liveTally uninstall] on: Error do: [:e | "swept below regardless"].
		liveTally := nil].
	self closeTallyStopWindow.
	SWAMethodWrapper uninstallAllStrayWrappers
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:25'
}
SWAPane >> buildBodyRow [
	"Build the body row into bodyRow: laid out left-to-right so the Marks flap can dock
	on the LEFT while the view fills the rest on the right. By default BOTH flaps are
	COLLAPSED, shown as floating tabs over the view edges: a vertical 'Marks' tab on
	the LEFT (#showMarksTab -> #openMarks) and a horizontal 'Source' tab on the BOTTOM
	(#showSourceTab -> #openSource). Answers bodyRow."
	bodyRow := self newChromeRow
		cellPositioning: #topLeft;
		vResizing: #spaceFill;
		yourself.
	view hResizing: #spaceFill; vResizing: #spaceFill.
	bodyRow addMorphBack: view.
	self showMarksTab.
	self showSourceTab.
	^ bodyRow
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:54'
}
SWAPane >> buildCrumbRow [
	"Build the breadcrumb line: the (width-filling) breadcrumb label plus the
	fullscreen toggle pinned at its right. Sets breadcrumbMorph and fullButton.
	Answers the row (this row does NOT wrap, so the right-pinned fullButton stays
	put)."
	| crumbRow |
	breadcrumbMorph := self
		newInfoLine: self breadcrumbContents
		font: (TextStyle default fontOfPointSize: 12)
		color: Color white.
	fullButton := self iconButtonGraphic: MenuIcons smallFullscreenOnIcon action: #toggleFullScreen.
	crumbRow := self newChromeRow.
	crumbRow addMorphBack: breadcrumbMorph; addMorphBack: fullButton.
	^ crumbRow
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:56'
}
SWAPane >> buildHeaderRow [
	"Build the wrapping button bar into headerRow: a generic pane HAMBURGER menu
	(far left; overflow home for growing actions like Export/Load), then Back/Browse/
	optional Deselect, then the overlay-gated Data/Tree/Size/Color/Links, then
	optional Depth and the name-search field. (Marks and Source are NO LONGER header
	buttons -- each is a floating flap tab over the body: Marks vertical on the LEFT,
	Source horizontal on the BOTTOM; see #buildBodyRow.) Each optional control is
	gated on the view/overlay actually SUPPORTING it, so a view opts into just the
	subset it implements. Answers headerRow.

	Call Tally is no longer a header button: it is a Data-menu generator that pops up
	a STOP window (see #generateCallTallyDataset / #openTallyStopWindow)."
	| menuButton ovl |
	headerRow := self newChromeRow
		wrapDirection: #topToBottom;
		vResizing: #shrinkWrap;
		yourself.
	"Generic pane menu leads the bar (far left)."
	menuButton := self iconButtonGraphic: MenuIcons smallJustifiedIcon action: #openPaneMenu.
	menuButton setBalloonText: 'Pane menu'.
	headerRow addMorphBack: menuButton.
	headerRow
		addMorphBack: (self buttonLabelled: 'Back' action: #zoomOut);
		addMorphBack: (self buttonLabelled: 'Browse' action: #browseSelected).
	"Deselect: clear the selection so the map shows everything again."
	(view respondsTo: #selectTileNode:) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'Deselect' action: #deselect)].
	"Data / Tree / Size / Color / Links -- each gated on the overlay SUPPORTING it."
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
	"Depth: cycle how deep tiles are drawn (only where the view supports leafKind:)."
	(view respondsTo: #leafKind:) ifTrue: [
		depthButton := self buttonLabelled: 'Depth: Full' action: #cycleLeafKind.
		self updateDepthLabel.
		headerRow addMorphBack: depthButton].
	"Live name-search: dims tiles whose entity name doesn't match what you type."
	(view respondsTo: #searchFor:) ifTrue: [
		headerRow addMorphBack: self newSearchField].
	^ headerRow
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:54'
}
SWAPane >> buildInfoLines [
	"Create the three stacked info StringMorphs -- the selection PATH line (big), the
	generic RUN-info line, and the SELECTION-info line -- setting selectionPathMorph,
	runInfoMorph and metaInfoMorph. They are added to the panel by the caller."
	| detailFont metaFont |
	detailFont := (TextStyle default fontOfPointSize: 15) emphasized: 1.
	metaFont := TextStyle default fontOfPointSize: 11.
	selectionPathMorph := self
		newInfoLine: self selectionPathContents
		font: detailFont
		color: (Color gray: 0.95).
	runInfoMorph := self
		newInfoLine: self runInfoContents
		font: metaFont
		color: (Color gray: 0.6).
	metaInfoMorph := self
		newInfoLine: self selectionInfoContents
		font: metaFont
		color: (Color gray: 0.8)
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
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:56'
}
SWAPane >> cleanupAllWrappers [
	"MANUAL SAFETY: forcibly remove EVERY instrumentation wrapper still installed in
	the image (layer-aware -- peels stacked wrappers to the real method), drop any live
	tally state, close the STOP window, and report how many were swept. For recovering
	after a crash/snapshot or an abandoned run left wrappers behind (which crash the
	image on the next tally)."
	| n |
	liveTally := nil.
	tallyAsDataset := false.
	self closeTallyStopWindow.
	n := SWAMethodWrapper uninstallAllStrayWrappers.
	self treemapCoverageStatus: 'Removed ', n printString, ' instrumentation wrapper(s)'.
	self inform: 'Removed ', n printString, ' instrumentation wrapper(s).'
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
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 13:17'
}
SWAPane >> closeTallyStopWindow [
	"Close and forget the call-tally STOP window, if open. Clears onClose first so a
	deliberate close after collecting does not re-fire the abandon path. Idempotent."
	tallyStopPanel ifNotNil: [
		tallyStopPanel onClose: nil.
		tallyStopPanel closeWindow.
		tallyStopPanel := nil]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:57'
}
SWAPane >> codeMapGeneratorEntries [
	"{ menuLabel. generatorSelector } pairs for the async, on-the-fly dataset
	GENERATORS offered -- in italic -- under the Data menu. Each is the async twin of
	the 'Load' button: picking it computes data for the shown packages and retains it
	as a named SWADataset (so it then appears in the Color/Size menus like any loaded
	file). Empty unless the wrapped view is a Code Map.

	Call Tally is TWO-PHASE (instrument -> exercise -> collect): picking it instruments
	and pops up a STOP window; pressing STOP there collects. The label reflects whether
	a tally is currently live."
	| entries |
	(self treemap isKindOf: SWACodeTreemapMorph) ifFalse: [^ #()].
	entries := OrderedCollection new.
	entries add: { 'Generate: duplication (clone heat)'. #generateDuplicationDataset }.
	entries add: { 'Generate: test coverage (run related tests)'. #generateCoverageDataset }.
	liveTally isNil
		ifTrue: [entries add: { 'Generate: call tally (instrument + exercise, then Stop)'. #generateCallTallyDataset }]
		ifFalse: [entries add: { 'Generate: call tally -- COLLECT now'. #generateCallTallyDataset }].
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
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:07'
}
SWAPane >> collapseMarks [
	"Collapse the Marks flap: remove the panel + splitter (and its floating collapse
	tab) and restore the vertical tab over the view's left edge. Called by the panel's
	tab. No-op if not open."
	(marksPanel isNil or: [marksPanel owner isNil]) ifTrue: [^ self].
	marksSplitter ifNotNil: [marksSplitter delete. marksSplitter := nil].
	marksPanel delete. marksPanel := nil. marksList := nil. commentField := nil.
	marksCollapseTab := nil.
	self showMarksTab.
	self layoutChanged
]

{
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> collapseSource [
	"Collapse the Source flap: remove the row + splitter (and its floating collapse
	tab) and restore the bottom 'Source' tab. No-op if not open."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	sourceSplitter ifNotNil: [sourceSplitter delete].
	sourceRow delete.
	sourceCollapseTab ifNotNil: [sourceCollapseTab delete. sourceCollapseTab := nil].
	self showSourceTab.
	self layoutChanged
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:55'
}
SWAPane >> collectInvocationTally [
	"Read invocation counts from the live tally, uninstall the wrappers, close the STOP
	window, and retain the result as a #call-metric DATASET (the normal Data-menu
	path). A legacy fallback still overlays the green tally ramp directly if a tally
	was somehow started with tallyAsDataset false. Either way the wrappers are
	UNINSTALLED first so instrumentation never lingers.

	The collect+uninstall is wrapped in ensure: with a FULL layer-aware stray-sweep,
	so even if the overlay/UI work fails -- or the tally had layered over an earlier
	leaked run -- NOTHING is left instrumented (the Git-tool DNU came from orphaned
	wrappers)."
	| n tm cov |
	liveTally ifNil: [^ self].
	cov := liveTally.
	[cov collectTally.
	 cov uninstall]
		ensure: [SWAMethodWrapper uninstallAllStrayWrappers].
	self closeTallyStopWindow.
	n := cov resultMap size.
	tm := self treemap.
	tallyAsDataset == true
		ifTrue: [
			tallyAsDataset := false.
			liveTally := nil.
			^ self addCallTallyDataset: cov name: 'Call Tally (generated)'].
	tm showCoverage: cov.
	(tm respondsTo: #noteColorMode:) ifTrue: [tm noteColorMode: #tally].
	self treemapCoverageStatus: 'Tally: ', n printString, ' methods invoked'.
	self refresh.
	liveTally := nil
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:58'
}
SWAPane >> coverageTally [
	"BACKWARD COMPAT: the Tally header button was removed in favour of the Data-menu
	'Generate: call tally' + STOP window. Old panels built before that change still
	carry a Tally button wired here; route it to the new flow so it never DNUs
	(#generateCallTallyDataset installs + opens the STOP window, or collects if live)."
	^ self generateCallTallyDataset
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
	#category : #'marks - persistence',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:22'
}
SWAPane >> defaultMarksFileName [
	"The suggested file name for Save/Load, in the image directory."
	^ FileDirectory default fullNameFor: 'swa-marks.json'
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 11:23'
}
SWAPane >> delete [
	"Closing the pane/window MUST tear down any live invocation tally, otherwise the
	installed wrappers are orphaned (their owning liveTally is dropped) and linger in
	every method dictionary -- silently corrupting unrelated tools (seen as the Git
	tool's ByteSymbol>>refTreeRoots DNU). Uninstall first, then proceed with normal
	morph deletion."
	liveTally ifNotNil: [self abandonInvocationTally].
	super delete
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
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:55'
}
SWAPane >> generateCallTallyDataset [
	"Data-menu GENERATE (async twin of Load): a live CALL TALLY as a dataset. This is
	inherently TWO-PHASE and must be driven carefully -- instrumenting every shown
	method installs self-evicting wrappers that stay live until collected:
	  1st pick -- instrument the shown packages (wrappers installed) AND pop up a small
	              STOP window;
	  2nd phase -- press STOP in that window to collect the counts, UNINSTALL the
	               wrappers, and retain the result as a named SWADataset whose #call
	               metric colours the map.
	Between the two, EXERCISE the system so calls are counted. If a tally is already
	live, this just collects (idempotent with the Stop button)."
	| root |
	liveTally ifNotNil: [^ self collectInvocationTally].
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Call Tally: only on a Code Map'].
	tallyAsDataset := true.
	self startInvocationTally: root.
	self openTallyStopWindow
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
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 11:09'
}
SWAPane >> hideMarksTab [
	"Remove the vertical Marks tab from the body row (called when the flap opens)."
	marksTab ifNotNil: [marksTab delete. marksTab := nil]
]

{
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> hideSourceTab [
	"Remove the collapsed 'Source' flap tab (called when the source row opens)."
	sourceTab ifNotNil: [sourceTab delete. sourceTab := nil]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:52'
}
SWAPane >> iconButtonGraphic: aForm action: aSelector [
	"A header button showing aForm as its icon that sends aSelector to THIS panel.
	Sized (via border padding) to match the height of a text #buttonLabelled: button
	so icon and text buttons line up in the header row."
	| button refHeight |
	button := IconicButton new
		labelGraphic: aForm;
		color: (Color gray: 0.3);
		borderWidth: 0;
		target: self;
		actionSelector: aSelector;
		hResizing: #rigid; vResizing: #rigid;
		yourself.
	"Pad top/bottom so the button matches a text button's height."
	refHeight := (self buttonLabelled: 'X' action: nil) fullBounds height.
	button extent: (button fullBounds extent max: (button fullBounds width @ refHeight)).
	^ button
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
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:25'
}
SWAPane >> layoutChanged [
	"After the pane relays out, re-pin every floating flap tab -- none is a layout
	participant, so each must be repositioned explicitly:
	  Marks (left):   collapsed tab over the view, open collapse tab over the panel;
	  Source (bottom): collapsed tab over the view, open collapse tab over the row."
	super layoutChanged.
	self positionMarksTab.
	self positionMarksCollapseTab.
	self positionSourceTab.
	self positionSourceCollapseTab
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
	#category : #'marks - persistence',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:34'
}
SWAPane >> loadMarks [
	"Prompt for a JSON marks file and REPLACE the current marks + comments with it.
	Clears the local selection since the keys change; all panes refresh via notifyPanes.
	The pattern is a String (';'/CR/LF-separated globs), NOT an Array."
	| name n |
	name := UIManager default
		chooseFileMatching: '*.json'
		label: 'Load marks from file'.
	(name isNil or: [name isEmpty]) ifTrue: [^ self].
	n := SWAMarkSet default loadFromFile: name.
	marksSelectedKeys := Set new.
	marksPrimaryIndex := 0.
	commentEditKey := nil.
	self flashMarksMessage: 'Loaded ', n printString,
		' mark(s) from ', (FileDirectory localNameFor: name)
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
	#category : #'marks - persistence',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:14'
}
SWAPane >> marksBurgerMenu: aMenu [
	"The 'burger' menu that replaces the Copy/Clear button row. Bundles the
	clipboard/clear actions together with Save/Load to a JSON sidecar file and
	'Class diagram of marks' (a live diagram of the marked classes)."
	| n |
	n := (marksSelectedKeys ifNil: [Set new]) size.
	aMenu addTitle: 'Marks'.
	n > 0
		ifTrue: [aMenu add: 'Copy selected (', n printString, ')' target: self selector: #copyMarks]
		ifFalse: [aMenu add: 'Copy all' target: self selector: #copyMarks].
	aMenu add: 'Clear' target: self selector: #clearMarks.
	aMenu addLine.
	aMenu add: 'Class diagram of marks (live)' target: self selector: #openMarksClassDiagram.
	aMenu addLine.
	aMenu add: 'Save to file...' target: self selector: #saveMarks.
	aMenu add: 'Load from file...' target: self selector: #loadMarks.
	^ aMenu
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:10'
}
SWAPane >> marksDetailsText [
	"Read-only details for the mark currently being edited (primary/last-clicked row):
	its key, what KIND of node it is (class/package/method/space-tally/...), plus the
	recorded provenance (kind of visualization, dataset, root scope). Shown in the small
	pane above the comment editor."
	| prov |
	commentEditKey ifNil: [^ 'Select a mark to see where it was made.' asText].
	prov := SWAMarkSet default provenanceAt: commentEditKey.
	prov ifNil: [^ (commentEditKey, String cr, '(no provenance recorded)') asText].
	^ (String streamContents: [:s |
		s nextPutAll: commentEditKey; cr.
		(prov at: 'nodeKind' ifAbsent: [nil]) ifNotNil: [:v |
			s nextPutAll: 'Kind: '; nextPutAll: v; cr].
		(prov at: 'viewLabel' ifAbsent: [nil]) ifNotNil: [:v |
			s nextPutAll: 'View: '; nextPutAll: v; cr].
		(prov at: 'datasetName' ifAbsent: [nil]) ifNotNil: [:v |
			s nextPutAll: 'Dataset: '; nextPutAll: v.
			(prov at: 'datasetKind' ifAbsent: [nil]) ifNotNil: [:k |
				s nextPutAll: ' ('; nextPutAll: k; nextPut: $)].
			s cr].
		(prov at: 'rootScope' ifAbsent: [nil]) ifNotNil: [:v |
			s nextPutAll: 'Root scope: '; nextPutAll: v; cr]]) asText
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:45'
}
SWAPane >> marksListMenu: aMenu [
	"Right-click context menu for the Marks list. Copy and Remove act on the current
	multi-selection when there is one, otherwise on all marks; the labels say which.
	'Show' reveals the primary (last-clicked) mark in a real view -- reusing an open pane
	of the recorded kind+scope or best-effort spawning one -- and selects the node there."
	| n |
	n := (marksSelectedKeys ifNil: [Set new]) size.
	aMenu addTitle: 'Marks'.
	commentEditKey ifNotNil: [
		aMenu add: 'Show in a view' target: self selector: #showSelectedMark.
		aMenu addLine].
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:46'
}
SWAPane >> marksPrimaryIndex: anIndex shifted: shifted controlled: controlled [
	"Selection semantics for the Marks list (AlternatePluggableListMorphOfMany):
	 - PLAIN click: replace the selection with just this row.
	 - CTRL click: toggle this row in/out of the selection.
	 - SHIFT click: extend the selection as a range from the previous primary row.
	The clicked row becomes primary and its comment loads into the editor. On a PLAIN
	click we also try to REVEAL the mark in an already-open view of its recorded kind+scope
	(select the node so its source shows) -- like clicking the node itself. We never spawn
	a new window here; that is reserved for the explicit 'Show in a view' menu entry.

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
	(shifted not and: [controlled not]) ifTrue: [self revealMarkInOpenView: key].
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
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:56'
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
	depthButton := fullButton := nil.
	bodyRow := marksPanel := marksList := marksButton := nil.
	marksSplitter := commentField := nil.
	self setView: aViewMorph.
	self layoutChanged.
	aViewMorph changed
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:53'
}
SWAPane >> newChromeRow [
	"An empty left-to-right, width-filling, shrink-wrap-height row used for the
	header button bar, the breadcrumb line, and the body row (callers tweak wrapping
	/ direction as needed)."
	^ Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> newFlapTabLabelled: aLabelString on: anActionSelector balloon: aBalloonString edge: anEdge [
	"Build a compact, half-transparent flap 'pull-tab' bearing aLabelString that sends
	anActionSelector to the pane when clicked. Shared by every flap (Marks/Details, in
	both their collapsed and open states). Orientation follows anEdge:
	  #left / #right  -> text rotated 270 degrees (reads bottom-to-top, the vertical
	                     left-edge convention),
	  #top / #bottom  -> text horizontal.
	The tab is sized to its (rotated) label so the word is fully shown. Positioning is
	done separately by #positionFlapTab:onEdge:of:."
	| label content tab |
	label := StringMorph new
		contents: aLabelString;
		font: ((TextStyle default fontOfPointSize: 11) emphasized: 1);
		color: (Color gray: 0.9);
		yourself.
	content := (anEdge = #left or: [anEdge = #right])
		ifTrue: [(TransformationMorph new asFlexOf: label) rotationDegrees: 270; yourself]
		ifFalse: [label].
	tab := Morph new
		color: ((Color gray: 0.22) alpha: 0.5);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		listCentering: #center;
		wrapCentering: #center;
		cellPositioning: #center;
		cellInset: 0;
		hResizing: #rigid; vResizing: #rigid;
		extent: content fullBounds extent + (anEdge = #bottom ifTrue: [8 @ 4] ifFalse: [0 @ 0]);
		disableTableLayout: true;
		yourself.
	tab addMorphBack: content.
	tab setBalloonText: aBalloonString.
	tab on: #mouseUp send: anActionSelector to: self.
	^ tab
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:53'
}
SWAPane >> newInfoLine: aString font: aFont color: aColor [
	"A single-line, width-filling StringMorph used for the breadcrumb / path / info
	rows in the chrome. aString nil is treated as empty."
	^ StringMorph new
		contents: (aString ifNil: ['']);
		font: aFont;
		color: aColor;
		hResizing: #spaceFill; vResizing: #rigid;
		yourself
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> newMarksCollapseButton [
	"The OPEN panel's collapse control: the SAME vertical 'Marks' tab as the collapsed
	floater. It floats over the panel content's left edge (positioned by
	#positionMarksCollapseTab) and collapses the flap on click (#collapseMarks)."
	^ self newVerticalMarksTabOn: #collapseMarks balloon: 'Hide Marks'
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:48'
}
SWAPane >> newMarksPanel [
	"Build the left-hand Marks panel. The content column (burger-menu row, then a
	MULTI-SELECT list of the global mark keys, then a comment editor) fills the WHOLE
	panel width; the vertical 'Marks' collapse tab (#newMarksCollapseButton) FLOATS
	over the content's left edge, overlapping into the list rather than taking its own
	column, and is centred vertically by #positionMarksCollapseTab. Clicking the tab
	collapses the flap. PLAIN click on a row replaces the selection, SHIFT ranges, CTRL
	toggles (via the global SWAMarksClickFilter). The burger menu bundles Copy/Clear +
	Save/Load to a JSON sidecar file. Comments persist in SWAMarkSet."
	| panel column burgerRow burger commentTitle detailsTitle |
	marksSelectedKeys ifNil: [marksSelectedKeys := Set new].
	burger := self iconButtonGraphic: MenuIcons smallJustifiedIcon action: #openMarksBurgerMenu.
	burger setBalloonText: 'Marks menu: Copy, Clear, Save, Load'.
	burgerRow := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		vResizing: #shrinkWrap; hResizing: #spaceFill;
		cellInset: 4;
		wrapCentering: #center; cellPositioning: #rightCenter;
		yourself.
	burgerRow addMorphBack: burger.
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
	detailsTitle := StringMorph new
		contents: 'Origin';
		font: (TextStyle default fontOfPointSize: 10);
		color: (Color gray: 0.7);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.
	marksDetailsMorph := PluggableTextMorph
		on: self
		text: #marksDetailsText
		accept: nil.
	marksDetailsMorph
		hResizing: #spaceFill; vResizing: #rigid;
		height: 66;
		askBeforeDiscardingEdits: false.
	marksDetailsMorph textMorph readOnly: true.
	commentTitle := StringMorph new
		contents: 'Comment (Cmd+S to save)';
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
		hResizing: #spaceFill; vResizing: #spaceFill;
		yourself.
	column
		addMorphBack: burgerRow;
		addMorphBack: marksList;
		addMorphBack: detailsTitle;
		addMorphBack: marksDetailsMorph;
		addMorphBack: commentTitle;
		addMorphBack: commentField.
	panel := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #topLeft;
		cellInset: 0;
		hResizing: #rigid; vResizing: #spaceFill;
		width: (marksWidth ifNil: [260]);
		yourself.
	"Content fills the whole panel; the collapse tab floats over its left edge."
	panel addMorphBack: column.
	marksCollapseTab := self newMarksCollapseButton.
	panel addMorphFront: marksCollapseTab.
	^ panel
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> newMarksTab [
	"The COLLAPSED-state floating Marks tab: the shared vertical 'Marks' tab that OPENS
	the flap. Floating flags (#disableTableLayout: true, #rigid) are set by the generic
	builder; it is positioned by #positionMarksTab over the treemap's left edge."
	^ self newVerticalMarksTabOn: #openMarks balloon: 'Show Marks'
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
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> newVerticalMarksTabOn: anActionSelector balloon: aString [
	"The Marks flap's vertical (#left-edge) tab: a thin wrapper over the generic
	#newFlapTabLabelled:on:balloon:edge:. Shared by the COLLAPSED floating tab
	(#newMarksTab -> #openMarks) and the OPEN panel's collapse tab
	(#newMarksCollapseButton -> #collapseMarks) so both read identically."
	^ self newFlapTabLabelled: 'Marks' on: anActionSelector balloon: aString edge: #left
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 11:09'
}
SWAPane >> openMarks [
	"Open the Marks flap: hide the vertical tab and slide the full Marks panel in at
	the LEFT of the body row, with a draggable SWASplitter between it and the view.
	No-op if already open. The panel's title acts as the collapse control (#collapseMarks)."
	(marksPanel notNil and: [marksPanel owner notNil]) ifTrue: [^ self].
	self hideMarksTab.
	marksPanel := self newMarksPanel.
	marksSplitter := SWASplitter vertical
		resizeAction: [:delta | self growMarksPanelBy: delta];
		yourself.
	"Front-to-back: [marks panel | splitter | view]."
	bodyRow addMorphFront: marksSplitter.
	bodyRow addMorphFront: marksPanel.
	self updateMarksList.
	self layoutChanged
]

{
	#category : #'marks - persistence',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:22'
}
SWAPane >> openMarksBurgerMenu [
	"Pop up the Marks burger menu (Copy/Clear/Save/Load)."
	| menu |
	menu := MenuMorph new.
	self marksBurgerMenu: menu.
	menu popUpInWorld: self world
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:14'
}
SWAPane >> openMarksClassDiagram [
	"Open a live class diagram of the classes currently in the global mark set. It stays
	synced -- marking/unmarking classes anywhere updates it."
	^ SWAClassDiagram openOnMarks
]

{
	#category : #'pane menu',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:49'
}
SWAPane >> openPaneMenu [
	"Pop up the generic per-pane menu (the header-row hamburger)."
	| menu |
	menu := MenuMorph new.
	self paneMenu: menu.
	menu popUpInWorld: self world
]

{
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> openSource [
	"Open the Source flap: hide the bottom tab and dock the source row at the BOTTOM of
	the pane, with a draggable horizontal SWASplitter above it (drag UP to grow). A
	'Source' collapse tab floats over the row's TOP edge (#collapseSource). No-op if
	already open. Loads the current selection's source, details and provenance."
	(sourceRow notNil and: [sourceRow owner notNil]) ifTrue: [^ self].
	self hideSourceTab.
	sourceRow ifNil: [sourceRow := self newSourceRow].
	sourceSplitter ifNil: [
		sourceSplitter := SWASplitter horizontal
			resizeAction: [:delta | self growSourceRowBy: delta negated];
			yourself].
	self addMorphBack: sourceSplitter.
	self addMorphBack: sourceRow.
	sourceCollapseTab := self newFlapTabLabelled: 'Source' on: #collapseSource balloon: 'Hide source' edge: #bottom.
	self addMorphFront: sourceCollapseTab.
	self updateSource.
	self updateDetails.
	self updateCoveringTests.
	self layoutChanged
]

{
	#category : #tally,
	#'squeak_changestamp' : 'MCPServer 7/20/2026 13:17'
}
SWAPane >> openTallyStopWindow [
	"Pop up a small window with a single STOP button that collects the live call tally.
	STOP -> #collectInvocationTally; closing without stopping -> #abandonInvocationTally.
	Retained so #collectInvocationTally can close it."
	liveTally ifNil: [^ self].
	tallyStopPanel := SWACoverageRunPanel new
		onStop: [self collectInvocationTally];
		onClose: [self abandonInvocationTally];
		openInWindowTitled: 'Call Tally -- exercise, then Stop';
		yourself.
	tallyStopPanel status: 'Tallying ', liveTally methods size printString,
		' methods. Exercise the system, then press STOP to collect.'
]

{
	#category : #'pane menu',
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:28'
}
SWAPane >> paneMenu: aMenu [
	"The generic per-pane overflow menu, opened from the hamburger icon at the FAR
	LEFT of the header row. This is the catch-all home for less-frequent / growing
	actions so they don't each need a button. Items may be gated on the view type:
	Export / Load are Code-Map-only (they read/write analysis JSON overlays)."
	aMenu addTitle: 'Pane'.
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		aMenu add: 'Export...' target: self selector: #exportCoverage.
		aMenu add: 'Load...' target: self selector: #importData].
	aMenu addLine.
	aMenu add: 'Remove all instrumentation wrappers'
		target: self selector: #cleanupAllWrappers.
	^ aMenu
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
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> positionFlapTab: aTab onEdge: anEdge of: aReferenceMorph [
	"Pin the floating flap tab aTab to the given edge of aReferenceMorph, CENTRED along
	that edge, so it overlaps the content and steals no layout width/height. Forces the
	PANE's layout current first (#fullBounds on self): right after a pane is added or
	removed the pane's TableLayout hasn't repositioned the reference morph yet, so its
	bounds would be stale. No-op unless the tab is live."
	| b |
	(aTab isNil or: [aTab owner isNil]) ifTrue: [^ self].
	self fullBounds.
	b := aReferenceMorph bounds.
	anEdge caseOf: {
		[#left]   -> [aTab position: (b left @ (b center y - (aTab height // 2)))].
		[#right]  -> [aTab position: ((b right - aTab width) @ (b center y - (aTab height // 2)))].
		[#top]    -> [aTab position: ((b center x - (aTab width // 2)) @ b top)].
		[#bottom] -> [aTab position: ((b center x - (aTab width // 2)) @ (b bottom - aTab height))] }
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:30'
}
SWAPane >> positionMarksCollapseTab [
	"Pin the OPEN panel's Marks collapse tab, centred on the RIGHT edge of the panel --
	beside the splitter/slider, mirroring the divider side -- rather than on the left
	where it would cover the list rows. Delegates to #positionFlapTab:onEdge:of:."
	marksPanel ifNil: [^ self].
	self positionFlapTab: marksCollapseTab onEdge: #right of: marksPanel
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:18'
}
SWAPane >> positionMarksTab [
	"Pin the collapsed Marks floating tab, centred on the LEFT edge of the view.
	Delegates to the generic #positionFlapTab:onEdge:of:."
	self positionFlapTab: marksTab onEdge: #left of: view
]

{
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> positionSourceCollapseTab [
	"Pin the OPEN row's 'Source' collapse tab, centred on the TOP edge of the source
	row, so it overlaps the row content. Delegates to #positionFlapTab:onEdge:of:."
	sourceRow ifNil: [^ self].
	self positionFlapTab: sourceCollapseTab onEdge: #top of: sourceRow
]

{
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> positionSourceTab [
	"Pin the collapsed 'Source' flap tab, centred on the BOTTOM edge of the view.
	Delegates to the generic #positionFlapTab:onEdge:of:."
	self positionFlapTab: sourceTab onEdge: #bottom of: view
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
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:47'
}
SWAPane >> revealMarkInOpenView: aMarkKey [
	"If a view of aMarkKey's recorded kind+scope is ALREADY open, select the node there
	(like clicking it), so its source/details appear. Does NOT spawn a window -- silent
	no-op when no matching pane is open (use 'Show in a view' to force one). Prefers a
	matching pane but falls back to THIS pane if it happens to contain the node."
	| prov pane |
	aMarkKey ifNil: [^ self].
	prov := SWAMarkSet default provenanceAt: aMarkKey.
	pane := SWAPane paneMatchingProvenance: prov.
	pane ifNil: [
		((view respondsTo: #keyIndex) and: [view keyIndex includesKey: aMarkKey])
			ifTrue: [pane := self]].
	pane ifNil: [^ self].
	pane revealMarkKey: aMarkKey
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:45'
}
SWAPane >> revealMarkKey: aMarkKey [
	"Select the node identified by aMarkKey in this pane's view, as if the user had
	clicked it: the view finds the node by crossRefKey, selects it (zooming so the tile is
	visible) and refreshes the chrome, so the source/details appear. No-op if the view has
	no such node. (markKey == crossRefKey for classes and methods, which is where marks
	most often point.)"
	aMarkKey ifNil: [^ self].
	(view respondsTo: #selectNodeForKey:) ifTrue: [view selectNodeForKey: aMarkKey]
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
	#category : #'marks - persistence',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:22'
}
SWAPane >> saveMarks [
	"Prompt for a file name and write ALL marks + comments as JSON. Save always
	acts on the whole set (selection is a view concern, not persistence)."
	| name |
	name := UIManager default
		saveFilenameRequest: 'Save marks to file'
		initialAnswer: self defaultMarksFileName.
	(name isNil or: [name isEmpty]) ifTrue: [^ self].
	SWAMarkSet default saveToFile: name.
	self flashMarksMessage: 'Saved ', SWAMarkSet default keys size printString,
		' mark(s) to ', (FileDirectory localNameFor: name)
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 10:54'
}
SWAPane >> setView: aViewMorph [
	"Build the panel chrome around aViewMorph, top to bottom:
	  1. headerRow    -- wrapping button bar led by a generic pane hamburger menu
	                     (#buildHeaderRow),
	  2. crumbRow     -- breadcrumb line with the fullscreen toggle at its right
	                     (#buildCrumbRow),
	  3. info lines   -- selection PATH, RUN-info, SELECTION-info (#buildInfoLines),
	  4. bodyRow      -- the (initially hidden) left Marks panel + the view
	                     (#buildBodyRow).
	The source pane is created lazily by #toggleSource; the Marks panel by
	#toggleMarks. Each optional control is gated on the view/overlay SUPPORTING it
	(see #buildHeaderRow)."
	view := aViewMorph.
	self
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #spaceFill;
		vResizing: #spaceFill.
	self buildHeaderRow.
	self buildInfoLines.
	self
		addMorphBack: headerRow;
		addMorphBack: self buildCrumbRow;
		addMorphBack: selectionPathMorph;
		addMorphBack: runInfoMorph;
		addMorphBack: metaInfoMorph;
		addMorphBack: self buildBodyRow.
	(view respondsTo: #navPanel:) ifTrue: [view navPanel: self]
]

{
	#category : #'marks - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 11:21'
}
SWAPane >> showMarksTab [
	"Show the collapsed-state vertical Marks tab as a FLOATING, absolutely-positioned
	morph that overlays the LEFT edge of the treemap (it is NOT in bodyRow's layout,
	so it doesn't steal width from the rendering). Parented on the pane itself and
	placed by #positionMarksTab. Only for views that support marks."
	(view respondsTo: #markedNodes) ifFalse: [^ self].
	(marksPanel notNil and: [marksPanel owner notNil]) ifTrue: [^ self].
	(marksTab notNil and: [marksTab owner notNil]) ifTrue: [^ self].
	marksTab := self newMarksTab.
	self addMorphFront: marksTab.
	self positionMarksTab
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:45'
}
SWAPane >> showSelectedMark [
	"Reveal the primary (last-clicked) mark in a real view via SWAPane>>showMarkKey:,
	which reuses an open pane of the recorded kind+scope or best-effort spawns one, then
	selects the node. Flashes a message if the mark has no usable provenance."
	commentEditKey ifNil: [^ self].
	(SWAPane showMarkKey: commentEditKey)
		ifNil: [self flashMarksMessage: 'No view to show this mark (missing scope).']
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
	#category : #'source - flap',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> showSourceTab [
	"Show the collapsed-state horizontal 'Source' flap tab, floating over the BOTTOM
	edge of the view, centred. Parented on the pane; placed by #positionSourceTab.
	No-op if the source row is open or the tab is already up."
	(sourceRow notNil and: [sourceRow owner notNil]) ifTrue: [^ self].
	(sourceTab notNil and: [sourceTab owner notNil]) ifTrue: [^ self].
	sourceTab := self newFlapTabLabelled: 'Source' on: #openSource balloon: 'Show source' edge: #bottom.
	self addMorphFront: sourceTab.
	self positionSourceTab
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
	#'squeak_changestamp' : 'MCPServer 7/20/2026 12:55'
}
SWAPane >> startInvocationTally: aCodeRoot [
	"Install live invocation-counting wrappers on the shown packages (Ingalls-style,
	self-evicting on hot methods). They stay installed while you exercise the system;
	a STOP window (see #openTallyStopWindow) collects them.

	CRITICAL: sweep any STRAY wrappers FIRST. If a prior run's wrappers are still
	installed (crash + snapshot restore, abandoned run, GC'd owner), installing on top
	LAYERS wrappers -- the new wrapper's originalMethod becomes the old wrapper, so
	collecting the new layer restores the OLD wrapper and strands it forever (this is
	the recurring Git-tool corruption). Starting from a clean slate makes each tally
	self-contained."
	liveTally ifNotNil: [^ self collectInvocationTally].
	SWAMethodWrapper uninstallAllStrayWrappers.
	liveTally := SWACoverage new
		evictAt: 1000;
		methodsForPackages: aCodeRoot packageNames.
	liveTally instrumentTally.
	self treemapCoverageStatus: 'Tallying ', liveTally methods size printString,
		' methods -- exercise, then press STOP to collect'
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 11:10'
}
SWAPane >> toggleMarks [
	"Toggle the Marks flap open/collapsed. Kept for any external/keyboard callers;
	the primary UI is now the vertical tab (#openMarks) and the panel-title collapse
	button (#collapseMarks)."
	(marksPanel notNil and: [marksPanel owner notNil])
		ifTrue: [self collapseMarks]
		ifFalse: [self openMarks]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:24'
}
SWAPane >> toggleSource [
	"Toggle the Source flap open/collapsed. Kept for any external/keyboard callers; the
	primary UI is now the bottom 'Source' flap tab (#openSource) and the row-top
	collapse tab (#collapseSource)."
	(sourceRow notNil and: [sourceRow owner notNil])
		ifTrue: [self collapseSource]
		ifFalse: [self openSource]
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
	#'squeak_changestamp' : 'MCPServer 7/17/2026 12:41'
}
SWAPane >> updateCommentField [
	"Reload the comment editor and the read-only provenance details from the mark
	currently being edited."
	commentField ifNotNil: [commentField setText: self commentFieldText].
	marksDetailsMorph ifNotNil: [marksDetailsMorph setText: self marksDetailsText]
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
