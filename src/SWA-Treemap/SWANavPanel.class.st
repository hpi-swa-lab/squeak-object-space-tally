"
Shared window chrome for the SWA navigable visualizations (treemap, flamegraph).

A SWANavPanel is a top-to-bottom panel that wraps a ""view"" morph (e.g. a
SWATreemapMorph or SWAStSpyFlamegraphMorph) and supplies the common UI:

  - a header row with Back / Browse / Show buttons + a breadcrumb label
  - a selection-path line (the currently selected/zoomed item)
  - a meta-info line (per-view summary: pid/duration, package/LOC, etc.)
  - an optional, toggleable, Shout-highlighted read-only source pane at the bottom

It exists so this chrome is defined once instead of being copy-pasted into
each open* method.

View protocol (duck-typed; the view must understand):
  breadcrumbString            -> String for the breadcrumb
  selectionPathString         -> String for the selection-path line (or nil)
  metaInfoString              -> String for the meta-info line (or nil)
  selectedSourceString        -> source text for the Show pane (or nil)
  zoomOut                      -> Back button action
  browseSelected               -> Browse button action
  navPanel: aSWANavPanel       -> back-reference so the view can ask us to refresh

The view also drives Shout styling for the source pane: the pane's model is the
VIEW morph, so the view must implement aboutToStyle:(requestor:).

The view calls #refresh on its panel after selection/zoom changes to update all
labels (and the source pane if shown).
"
Class {
	#name : #SWANavPanel,
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
		'sourceSplitter'
	],
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:49'
}
SWANavPanel class >> defaultWindowBounds [
	"Preferred opening bounds for a Code Map window: wide enough for the full button
	bar on one row and tall enough that the wrapped header + info lines + map all
	fit without the visualization overflowing the bottom edge. Clamped up to the
	button-bar minimum width by #enforceMinimumWidthOn:."
	^ 568 @ 205 corner: 1935 @ 1264
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:46'
}
SWANavPanel class >> enforceMinimumWidthOn: aWindow [
	"Find the SWANavPanel inside aWindow and have it set the window's minimum width
	to the button bar's natural one-row width (widening the window to it if the
	requested default was narrower). Keeps every opener's explicit #extent: as a
	PREFERRED size that is then clamped up to fit the buttons."
	aWindow allMorphs
		detect: [:m | m isKindOf: SWANavPanel]
		ifFound: [:p | p enforceMinimumWindowWidth]
		ifNone: []
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:52'
}
SWANavPanel class >> initialize [
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
SWANavPanel class >> on: aViewMorph [
	"Build a navigation panel wrapping aViewMorph (a treemap/flamegraph morph)."
	^ self new setView: aViewMorph
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:51'
}
SWANavPanel class >> open [
	"Apps-menu action: open the whole-image code map (all packages, classes as leaves)."
	^ self openOnPackageNamed: '*' leafKind: #class
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:36'
}
SWANavPanel class >> openByteCompositionOnPackageNamed: aPackageGlob [
	"Byte-composition treemap rendered down to methods (leafKind nil) so the
	per-method doc/string/code bar is visible. See
	#openByteCompositionOnPackageNamed:leafKind:.

	(SWANavPanel openByteCompositionOnPackageNamed: 'Morphic*')"
	^ self openByteCompositionOnPackageNamed: aPackageGlob leafKind: nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:50'
}
SWANavPanel class >> openByteCompositionOnPackageNamed: aPackageGlob leafKind: aKindOrNil [
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

	(SWANavPanel openByteCompositionOnPackageNamed: 'Kernel' leafKind: nil)
	(SWANavPanel openByteCompositionOnPackageNamed: '*' leafKind: nil)"
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:22'
}
SWANavPanel class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob [
	"Open a coverage-WEIGHTED code treemap: same package -> class -> category ->
	method structure as #openOnPackageNamed:, but tiles are sized by the actual
	covered counts (covering-test count per method, rolled up) instead of LOC.
	Uncovered methods collapse to nothing, so the layout shows -- proportionally --
	what the tests in aCoverageFileName actually exercised, with the usual green/
	blue tint and proportional coverage bars on aggregate tiles.

	aCoverageFileName is a SWACoverageData JSON file (Class>>selector keyed, image-
	independent). aPackageGlob is a String>>match: glob over package names.

	(SWANavPanel openCoverage: 'morphic-coverage.json' onPackageNamed: '*')
	(SWANavPanel openCoverage: 'squeak-coverage.json' onPackageNamed: 'Morphic*')"
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:37'
}
SWANavPanel class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: aKindOrNil [
	"See #openCoverage:onPackageNamed:. Sizes tiles by covering-TEST count. aKindOrNil
	stops RENDERING at that #kind (roll-ups still build over the full tree); nil
	renders down to methods."
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob
		leafKind: aKindOrNil weightMode: #tests
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:50'
}
SWANavPanel class >> openCoverage: aCoverageFileName onPackageNamed: aPackageGlob leafKind: aKindOrNil weightMode: aWeightMode [
	"Coverage-WEIGHTED code treemap. aWeightMode selects the tile-size metric:
	  #tests       -- distinct covering-test count per method (default), or
	  #invocations -- raw call count (how many times each method actually ran).
	#invocations requires data generated by an invocation-counting runner; if the
	file has none (old JSON), we fall back to #tests and say so in the status line.
	aKindOrNil stops RENDERING at that #kind; nil renders down to methods.

	The mode is set as the live #weightMetric (the 'Size' menu shows it ticked), so
	the user can switch among Structure / Methods / LOC / Bytes / call count /
	covering tests in place.

	(SWANavPanel openCoverage: 'morphic-coverage.json' onPackageNamed: '*'
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
		detect: [:m | m isKindOf: SWANavPanel]
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:38'
}
SWANavPanel class >> openInvocations: aCoverageFileName onPackageNamed: aPackageGlob [
	"Open a coverage treemap sized by RAW INVOCATION COUNT -- how many times each
	method was actually called during the run -- instead of covering-test count.
	Requires data generated by an invocation-counting runner (falls back to test
	count, with a note, for older JSON files).

	(SWANavPanel openInvocations: 'morphic-coverage.json' onPackageNamed: '*')"
	^ self openCoverage: aCoverageFileName onPackageNamed: aPackageGlob
		leafKind: nil weightMode: #invocations
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:55'
}
SWANavPanel class >> openOnPackageNamed: aPackageName [
	"Open a code-structure treemap (package -> classes -> categories -> methods)
	wrapped in a SWANavPanel. Defaults to #class render depth (Full/nil is omitted
	from the depth cycle -- it tiles the whole tree at once, which is unwieldy on a
	broad glob); cycle deeper/shallower with the Depth button.

	(SWANavPanel openOnPackageNamed: 'Morphic-Kernel')"
	^ self openOnPackageNamed: aPackageName leafKind: #class
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:49'
}
SWANavPanel class >> openOnPackageNamed: aPackageGlob leafKind: aKindOrNil [
	"Open a code-structure treemap (root -> packages -> classes -> categories ->
	methods) wrapped in a SWANavPanel, with Back/Browse/Show/Depth/Full chrome.

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

	(SWANavPanel openOnPackageNamed: 'Kernel' leafKind: nil)
	(SWANavPanel openOnPackageNamed: '*' leafKind: #class)"
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
SWANavPanel class >> openPanels [
	"All nav panels currently live in the world (still owned by a window/world).
	Discovered live rather than via a registry so closed panels drop out
	automatically."
	^ self allInstances select: [:p | p world notNil]
]

{
	#category : #'class initialization',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:52'
}
SWANavPanel class >> unload [
	"Remove the Apps-menu entry."
	(TheWorldMenu respondsTo: #unregisterOpenCommandWithReceiver:)
		ifTrue: [TheWorldMenu unregisterOpenCommandWithReceiver: self]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:24'
}
SWANavPanel >> acquireTestCoverageThenColor [
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
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWANavPanel >> breadcrumbContents [
	"Breadcrumb string from the view (empty if unsupported)."
	^ (view respondsTo: #breadcrumbString)
		ifTrue: [view breadcrumbString ifNil: ['']]
		ifFalse: ['']
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> browseSelected [
	"Browse button: delegate to the view (it knows what 'selected' means)."
	(view respondsTo: #browseSelected)
		ifTrue: [view browseSelected]
		ifFalse: [Beeper beep]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWANavPanel >> buttonLabelled: aString action: aSelector [
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
SWANavPanel >> chooseJsonFilePrompt: aPromptString [
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
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:23'
}
SWANavPanel >> clearCoverage [
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
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWANavPanel >> clearCrossReference [
	"Remove any cross-reference highlight from this view."
	| mine |
	mine := self treemap.
	mine ifNil: [^ self].
	mine clearCrossReference.
	self refresh
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:38'
}
SWANavPanel >> codeRoot [
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
	#'squeak_changestamp' : 'MCPServer 6/30/2026 18:24'
}
SWANavPanel >> collectInvocationTally [
	"Read invocation counts from the live tally, uninstall the wrappers, overlay
	the green tally ramp, and clear the live-tally state. Resets the Tally button.
	Status shown in the meta line, no dialog."
	| n tm |
	liveTally ifNil: [^ self].
	liveTally collectTally.
	liveTally uninstall.
	n := liveTally resultMap size.
	tm := self treemap.
	tm showCoverage: liveTally.
	(tm respondsTo: #noteColorMode:) ifTrue: [tm noteColorMode: #tally].
	self treemapCoverageStatus: 'Tally: ', n printString, ' methods invoked'.
	self refresh.
	liveTally := nil.
	self updateTallyButton
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> coverageTally [
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
SWANavPanel >> crossRefMenuLabel [
	"Human-readable label for this panel in a cross-reference chooser:
	the enclosing window's title, else the view's class name."
	| win |
	win := self enclosingWindow.
	(win notNil and: [win label notNil]) ifTrue: [^ win label].
	^ view class name
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWANavPanel >> crossReference [
	"X-ref button: highlight this view's tiles that also appear in another open
	panel, weighted (log heat ramp) by that panel's metric. With one peer, link
	to it directly; with several, ask which. With none, beep."
	| mine peers chosen |
	mine := self treemap.
	mine ifNil: [^ Beeper beep].
	peers := self peerPanels.
	peers isEmpty ifTrue: [^ self inform: 'No other treemap panel is open to cross-reference.'].
	peers size = 1 ifTrue: [^ self crossReferenceWith: peers first].
	"Several candidates: let the user pick by window label."
	chosen := UIManager default
		chooseFrom: (peers collect: [:p | p crossRefMenuLabel])
		values: peers
		title: 'Cross-reference against which panel?'.
	chosen ifNotNil: [self crossReferenceWith: chosen]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWANavPanel >> crossReferenceWith: aPeerPanel [
	"Push aPeerPanel's key index onto our treemap as a highlight overlay."
	| mine peer |
	mine := self treemap.
	peer := aPeerPanel treemap.
	(mine isNil or: [peer isNil]) ifTrue: [^ Beeper beep].
	mine crossReferenceFrom: peer.
	self refresh
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:55'
}
SWANavPanel >> cycleLeafKind [
	"Depth button: cycle the view's render depth (leafKind) through
	Package -> Class -> Category -> Method -> Package. (Full/nil is omitted -- it
	renders the whole tree at once, which doesn't make sense here.) Only affects
	rendering; the tree and metric roll-ups are unchanged, so this is cheap to
	re-apply. If the view is currently at Full (nil), the first press goes to Package."
	| order current next |
	(view respondsTo: #leafKind:) ifFalse: [^ Beeper beep].
	order := { #package. #class. #category. #method }.
	current := (view respondsTo: #leafKind) ifTrue: [view leafKind] ifFalse: [nil].
	next := order at: ((order indexOf: current) \\ order size) + 1.
	view leafKind: next.
	self updateDepthLabel.
	self refresh
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:13'
}
SWANavPanel >> datasetNameFor: aPath [
	"A short display name for a dataset loaded from aPath: the file's base name."
	| segs |
	aPath ifNil: [^ 'loaded'].
	segs := (aPath asString copyReplaceAll: '\' with: '/') findTokens: '/'.
	^ segs isEmpty ifTrue: [aPath asString] ifFalse: [segs last]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:59'
}
SWANavPanel >> detailInfoContents [
	"Multi-line details for the Show-mode details box (beside the source). Views opt
	in by implementing #detailInfoString; otherwise '' (no box content)."
	(view respondsTo: #detailInfoString) ifTrue: [^ view detailInfoString ifNil: ['']].
	^ ''
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:07'
}
SWANavPanel >> enclosingWindow [
	"The SystemWindow that contains this panel, or nil if opened bare in the world."
	^ self ownerThatIsA: SystemWindow
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:45'
}
SWANavPanel >> enforceMinimumWindowWidth [
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
SWANavPanel >> exportCoverage [
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
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWANavPanel >> growSourceRowBy: deltaPixels [
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
SWANavPanel >> headerNaturalWidth [
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
SWANavPanel >> iconButtonGraphic: aForm action: aSelector [
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
SWANavPanel >> importCoverage [
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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:07'
}
SWANavPanel >> importData [
	"Unified Load button for the Code Map: open a *.json file chooser and overlay
	whatever kind of analysis data it holds, switching the view's color mode to
	match. Dispatch is by the JSON #format marker, so one button handles both:
	  'SWACoverageData/1'    -> coverage overlay (green covered + blue tests)
	  'SWADuplicationData/1' -> duplication overlay (#duplication color mode)
	Both are image-independent ('Class>>selector'-keyed) and may be generated
	offline (SWACoverage / SWADuplicationData generatePackages:toFile:).

	Every load is ALSO retained as a named SWADataset (see #loadCoverageJson:name:),
	so loading twice gives two coexisting, switchable Color-menu entries."
	| tm path contents json format |
	tm := self treemap.
	(tm isKindOf: SWACodeTreemapMorph) ifFalse: [^ self].
	path := self chooseJsonFilePrompt: 'Load analysis JSON from:'.
	path ifNil: [^ self].
	[contents := (FileStream readOnlyFileNamed: path) contentsOfEntireFile.
	 json := Json readFrom: contents readStream]
		on: Error do: [:e | ^ self treemapCoverageStatus: 'Load failed: ', e messageText].
	format := (json at: 'format' ifAbsent: ['']) asString.
	(format beginsWith: 'SWADuplicationData')
		ifTrue: [^ self loadDuplicationJson: json name: (self datasetNameFor: path)].
	"Default / 'SWACoverageData...' / legacy files with no marker -> coverage."
	self loadCoverageJson: json name: (self datasetNameFor: path)
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:07'
}
SWANavPanel >> loadCoverageJson: json [
	"Legacy entry: overlay coverage without a dataset name (keeps old callers working)."
	^ self loadCoverageJson: json name: 'coverage'
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:53'
}
SWANavPanel >> loadCoverageJson: json name: aName [
	"Overlay an already-parsed SWACoverageData JSON object (see #importData) as a
	retained, named SWADataset so its metrics ('By coverage', and 'By call' when the
	file has invocation data) stay selectable in the Color/Size menus. Loading twice
	yields distinct metric entries you switch between instantly, no reload. Selects
	the dataset's first color metric.

	Deliberately does NOT touch the legacy single-ivar coverage overlay -- that
	clobbers on every load and holds only ONE coverage, which the dataset replaces."
	| data tm ds first |
	data := SWACoverageData new.
	data loadFromJson: json.
	tm := self treemap.
	ds := tm addDataset: (SWADataset coverageFrom: data named: aName).
	first := ds metrics detect: [:m | m supportsColor] ifNone: [nil].
	first ifNotNil: [tm colorMode: first modeSymbol].
	self treemapCoverageStatus: 'Coverage (', ds name, '): ', data coveredMethodCount printString,
		' methods, ', data testNames size printString, ' tests',
		(data hasInvocationData ifTrue: [' (+call counts)'] ifFalse: ['']).
	self refresh
]

{
	#category : #duplication,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:07'
}
SWANavPanel >> loadDuplicationJson: json [
	"Legacy entry: overlay duplication without a dataset name."
	^ self loadDuplicationJson: json name: 'duplication'
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:12'
}
SWANavPanel >> loadDuplicationJson: json name: aName [
	"Overlay an already-parsed SWADuplicationData JSON object as a retained, named
	SWADataset. Applies the dataset's fitting DEFAULTS across aspects: its color
	metric drives tint AND its links metric drives decorations (the clone lines).
	Purely a dataset -- does NOT touch the legacy dupScores overlay."
	| data tm ds colorMetric linkMetric |
	tm := self treemap.
	data := SWADuplicationData new.
	data loadFromJson: json.
	ds := tm addDataset: (SWADataset duplicationFrom: data named: aName).
	colorMetric := ds metrics detect: [:m | m supportsColor] ifNone: [nil].
	colorMetric ifNotNil: [tm colorMode: colorMetric modeSymbol].
	linkMetric := ds metrics detect: [:m | m supportsLinks] ifNone: [nil].
	linkMetric ifNotNil: [tm decorationMetric: linkMetric].
	self treemapCoverageStatus: 'Duplication (', ds name, '): ', data matchedMethodCount printString,
		' methods with near-duplicates of ', data methodNames size printString, ' analysed'.
	self refresh
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWANavPanel >> metaInfoContents [
	"Meta-info string from the view, or nil if unsupported."
	^ (view respondsTo: #metaInfoString)
		ifTrue: [view metaInfoString]
		ifFalse: [nil]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 14:31'
}
SWANavPanel >> newCoveringTestsPane [
	"A titled list pane (right of the source pane) showing, for the selected method,
	the tests/TestCases that cover it -- or, for a selected test, the methods it
	covers. Clicking an entry navigates the treemap to that node."
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
	column := Morph new
		color: (Color gray: 0.12);
		layoutPolicy: TableLayout new;
		listDirection: #topToBottom;
		cellPositioning: #topLeft;
		hResizing: #rigid; vResizing: #spaceFill;
		width: 340;
		yourself.
	column addMorphBack: coveringTestsTitle; addMorphBack: list.
	^ column
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:59'
}
SWANavPanel >> newDetailsPane [
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
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> newSourceMorph [
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
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:01'
}
SWANavPanel >> newSourceRow [
	"The bottom (Show-mode) area: a left-to-right row. For the Code Map (which has
	the extra vertical room and a #detailInfoString) it is
	[details box | source pane (spaceFill) | covering-tests pane]; other views get
	just the source pane (spaceFill)."
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
		row addMorphBack: self newCoveringTestsPane].
	^ row
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:37'
}
SWANavPanel >> peerPanels [
	"Other open nav panels whose view is a cross-referenceable treemap."
	^ (SWANavPanel openPanels)
		select: [:p | p ~~ self and: [p treemap notNil]]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWANavPanel >> popUpColorMenu [
	"Header 'Color' button: pop up the same Color menu the right-click context menu
	uses (shared #colorMenuMorph on the overlay)."
	self treemapOverlay ifNotNil: [:o | o popUpColorMenu]
]

{
	#category : #'code map - datasets',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:17'
}
SWANavPanel >> popUpDecorationMenu [
	"Header 'Links' button: pop up the same Links (decoration) menu the right-click
	context menu uses (shared #decorationMenuMorph on the overlay)."
	self treemapOverlay ifNotNil: [:o |
		(o respondsTo: #popUpDecorationMenu) ifTrue: [o popUpDecorationMenu]]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWANavPanel >> popUpSizeMenu [
	"Header 'Size' button: pop up the same Size menu the right-click context menu
	uses (shared #sizeMenuMorph on the overlay). Always reachable, even on a
	collapsed/black canvas."
	self treemapOverlay ifNotNil: [:o | o popUpSizeMenu]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWANavPanel >> provenanceIndex [
	"List-model selection index for the covering-tests pane."
	^ provenanceIndex ifNil: [0]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:06'
}
SWANavPanel >> provenanceIndex: anInteger [
	"List-model click handler for the side pane. Normally navigates the treemap to
	the clicked test/method node. In #duplication mode, instead of navigating away
	we DIFF the current selection against the clicked near-duplicate (set it as the
	view's diff target, which re-renders the source pane as an inline diff)."
	| assoc |
	provenanceIndex := anInteger.
	(anInteger = 0 or: [provenanceEntries isNil]) ifTrue: [^ self].
	assoc := provenanceEntries at: anInteger ifAbsent: [^ self].
	((view respondsTo: #colorMode) and: [view colorMode == #duplication]
		and: [view respondsTo: #dupDiffTarget:]) ifTrue: [
			| node |
			node := (view respondsTo: #keyIndex)
				ifTrue: [view keyIndex at: assoc value ifAbsent: [nil]]
				ifFalse: [nil].
			^ view dupDiffTarget: node].
	(view respondsTo: #selectNodeForKey:)
		ifTrue: [view selectNodeForKey: assoc value]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWANavPanel >> provenanceList [
	"List-model contents for the covering-tests pane: the display labels of the
	current selection's provenance entries."
	^ (provenanceEntries ifNil: [#()]) collect: [:assoc | assoc key]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:01'
}
SWANavPanel >> refresh [
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
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWANavPanel >> runInfoContents [
	"Line 1 of the info area: GENERIC, whole-run info (e.g. coverage status + the
	focused-subtree summary), independent of the current selection. Views opt in by
	implementing #runInfoString; otherwise we fall back to the legacy single
	#metaInfoString so non-split views keep working."
	(view respondsTo: #runInfoString) ifTrue: [^ view runInfoString ifNil: ['']].
	(view respondsTo: #metaInfoString) ifTrue: [^ view metaInfoString ifNil: ['']].
	^ ''
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWANavPanel >> selectedSourceContents [
	"Source text for the Show pane from the view, or nil if unsupported/none."
	^ (view respondsTo: #selectedSourceString)
		ifTrue: [view selectedSourceString]
		ifFalse: [nil]
]

{
	#category : #content,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:51'
}
SWANavPanel >> selectionInfoContents [
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
SWANavPanel >> selectionPathContents [
	"Selection-path string from the view, or nil if unsupported."
	^ (view respondsTo: #selectionPathString)
		ifTrue: [view selectionPathString]
		ifFalse: [nil]
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:18'
}
SWANavPanel >> setView: aViewMorph [
	"Build the panel chrome around aViewMorph: a WRAPPING button bar (Back/Browse/
	Show + optional Size/Color/Links + optional X-ref/Clear + optional coverage
	controls + optional Depth), then a breadcrumb line carrying the fullscreen toggle
	at its right, then the selection-path line, a generic RUN-info line, a
	SELECTION-info line, then the view. The button bar wraps onto additional rows when
	the window is too narrow to fit every button. The source pane is created lazily by
	#toggleSource."
	| crumbFont detailFont metaFont backButton browseButton showButton crumbRow |
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
	"Depth (render-level) control, only for views that support a leafKind cutoff."
	(view respondsTo: #leafKind:) ifTrue: [
		depthButton := self buttonLabelled: 'Depth: Full' action: #cycleLeafKind.
		self updateDepthLabel].
	"Fullscreen toggle: uses the docking bar's fullscreen icon, pinned top-right."
	fullButton := self iconButtonGraphic: MenuIcons smallFullscreenOnIcon action: #toggleFullScreen.

	breadcrumbMorph := StringMorph new
		contents: self breadcrumbContents;
		font: crumbFont;
		color: Color white;
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	"Button bar -- a left-to-right row that WRAPS onto new rows (wrapDirection
	#topToBottom) when it is wider than the window, so buttons never overflow."
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
	headerRow addMorphBack: backButton; addMorphBack: browseButton;
		addMorphBack: showButton.
	"Size / Color / Links menu buttons -- same menus as the right-click context menu
	(shared #sizeMenuMorph / #colorMenuMorph / #decorationMenuMorph on the overlay).
	Always reachable from the header, even when a size metric collapses the layout to
	an empty canvas where the tile-based right-click menu would be unreachable."
	(view respondsTo: #overlayMorph) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'Size' action: #popUpSizeMenu).
		headerRow addMorphBack: (self buttonLabelled: 'Color' action: #popUpColorMenu).
		"Links (decoration axis): only for views carrying a decoration binding (Code Map)."
		(view respondsTo: #decorationMetric) ifTrue: [
			headerRow addMorphBack: (self buttonLabelled: 'Links' action: #popUpDecorationMenu)]].
	"Cross-reference controls, only for cross-referenceable treemap views."
	(view respondsTo: #keyIndex) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'X-ref' action: #crossReference).
		headerRow addMorphBack: (self buttonLabelled: 'Clear' action: #clearCrossReference)].
	"Code Map data controls. Test coverage and duplication are picked from the COLOR
	menu (they acquire their data lazily on first pick). Tally STAYS a button: an
	interactive 2-press toggle. Export saves the current coverage to reusable JSON;
	Load reads any coverage- or duplication-JSON back (dispatched by its #format)."
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		tallyButton := self buttonLabelled: 'Tally' action: #coverageTally.
		headerRow addMorphBack: tallyButton.
		headerRow addMorphBack: (self buttonLabelled: 'Export' action: #exportCoverage).
		headerRow addMorphBack: (self buttonLabelled: 'Load' action: #importData).
		self updateTallyButton].
	depthButton ifNotNil: [headerRow addMorphBack: depthButton].

	"Breadcrumb line: the path spaceFills, pushing the fullscreen toggle to the right
	edge. Kept on its own row so it never competes with the wrapping button bar."
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

	"Line 1: generic, whole-RUN info (coverage status + focused-subtree summary)."
	runInfoMorph := StringMorph new
		contents: (self runInfoContents ifNil: ['']);
		font: metaFont;
		color: (Color gray: 0.6);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	"Line 2: info about the current SELECTION (empty when nothing is selected)."
	metaInfoMorph := StringMorph new
		contents: (self selectionInfoContents ifNil: ['']);
		font: metaFont;
		color: (Color gray: 0.8);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	view hResizing: #spaceFill; vResizing: #spaceFill.

	self addMorphBack: headerRow;
		addMorphBack: crumbRow;
		addMorphBack: selectionPathMorph;
		addMorphBack: runInfoMorph;
		addMorphBack: metaInfoMorph;
		addMorphBack: view.

	"Tell the view about us so it can drive label/breadcrumb refresh and the source pane."
	(view respondsTo: #navPanel:) ifTrue: [view navPanel: self]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:54'
}
SWANavPanel >> showSelectionPath: aStringOrNil [
	"Directly set the selection-path line (used for live hover feedback, which is
	not driven by the persistent selection)."
	selectionPathMorph ifNotNil: [selectionPathMorph contents: (aStringOrNil ifNil: [''])]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:50'
}
SWANavPanel >> sourceMorph [
	"The embedded source pane, or nil if never shown. Owner is nil while hidden."
	^ sourceMorph
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> startInvocationTally: aCodeRoot [
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
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:21'
}
SWANavPanel >> toggleFullScreen [
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
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:11'
}
SWANavPanel >> toggleSource [
	"Show button: show/hide the bottom area at the bottom of the panel. The bottom
	area is a horizontal row holding -- for the Code Map -- a details box (left), the
	source pane (center), and a covering-tests list pane (right); other views get
	just the source pane. A draggable splitter handle is inserted ABOVE the row so
	the user can resize it taller (e.g. to read an inline diff). When shown, load the
	current selection's source, details, and provenance."
	(sourceRow notNil and: [sourceRow owner notNil])
		ifTrue: [
			sourceSplitter ifNotNil: [sourceSplitter delete].
			sourceRow delete]
		ifFalse: [
			sourceRow ifNil: [sourceRow := self newSourceRow].
			sourceSplitter ifNil: [
				sourceSplitter := SWASourceSplitter new panel: self; yourself].
			self addMorphBack: sourceSplitter.
			self addMorphBack: sourceRow.
			self updateSource.
			self updateDetails.
			self updateCoveringTests].
	self layoutChanged
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:28'
}
SWANavPanel >> treemap [
	"The wrapped view, if it supports cross-referencing (treemap or flamegraph)."
	^ (view respondsTo: #keyIndex) ifTrue: [view] ifFalse: [nil]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> treemapCoverageStatus: aString [
	"Set the coverage status line on the code map (no-op if not a code map)."
	| tm |
	tm := self treemap.
	(tm respondsTo: #coverageStatus:) ifTrue: [tm coverageStatus: aString]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:20'
}
SWANavPanel >> treemapOverlay [
	"The wrapped view's event/menu overlay, or nil if it has none."
	^ (view respondsTo: #overlayMorph) ifTrue: [view overlayMorph] ifFalse: [nil]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:58'
}
SWANavPanel >> updateCoveringTests [
	"If the covering-tests pane is showing, refill it from the view's current
	selection (tests covering the selected method, or methods a selected test
	covers) and update its title."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	coveringTestsPane ifNil: [^ self].
	provenanceEntries := (view respondsTo: #provenanceListForSelection)
		ifTrue: [view provenanceListForSelection]
		ifFalse: [#()].
	provenanceIndex := 0.
	coveringTestsTitle ifNotNil: [
		coveringTestsTitle contents:
			((view respondsTo: #provenanceListTitle)
				ifTrue: [view provenanceListTitle]
				ifFalse: ['Coverage'])].
	coveringTestsPane updateList
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:54'
}
SWANavPanel >> updateDepthLabel [
	"Relabel the depth button to reflect the view's current render depth (leafKind)."
	| kind text |
	depthButton ifNil: [^ self].
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
SWANavPanel >> updateDetails [
	"If the Show-mode details box is showing, refill it from the current selection."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	detailsPane ifNotNil: [
		detailsPane contents: (self detailInfoContents ifNil: [''])]
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:58'
}
SWANavPanel >> updateSource [
	"If the bottom area is showing, reload the source pane from the current selection."
	(sourceRow isNil or: [sourceRow owner isNil]) ifTrue: [^ self].
	sourceMorph ifNotNil: [
		sourceMorph setText: (self selectedSourceContents ifNil: [''])]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:14'
}
SWANavPanel >> updateTallyButton [
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
SWANavPanel >> view [
	"The wrapped view morph (treemap or flamegraph)."
	^ view
]

{
	#category : #actions,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> zoomOut [
	"Back button: ask the view to zoom out, then refresh the chrome."
	(view respondsTo: #zoomOut) ifTrue: [view zoomOut].
	self refresh
]
