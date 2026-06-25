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
		'sourceMorph',
		'depthButton',
		'fullButton',
		'savedWindowFrame',
		'liveTally',
		'coverageCancel',
		'tallyButton',
		'sourceRow',
		'coveringTestsPane',
		'coveringTestsTitle',
		'provenanceEntries',
		'provenanceIndex'
	],
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

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
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:53'
}
SWANavPanel class >> openOnPackageNamed: aPackageName [
	"Open a code-structure treemap (package -> classes -> methods) wrapped in a
	SWANavPanel, rendered to full depth.

	(SWANavPanel openOnPackageNamed: 'Morphic-Kernel')"
	^ self openOnPackageNamed: aPackageName leafKind: nil
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:24'
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
	progress bar, and the panel chrome -- then sizes the window.

	(SWANavPanel openOnPackageNamed: 'Kernel' leafKind: nil)
	(SWANavPanel openOnPackageNamed: '*' leafKind: #class)"
	| root window |
	root := (SWACodeRootNode new)
		name: aPackageGlob;
		addPackages: aPackageGlob;
		yourself.
	window := root openTreemapLeafKind: aKindOrNil.
	window setLabel: 'Code Treemap: ', aPackageGlob.
	"Wider default to fit the full button row (X-ref/Coverage/Tally/...)."
	window extent: 1170 @ 650.
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:45'
}
SWANavPanel >> chooseCoverageFile [
	"Open a *.json file chooser and answer the chosen full path, or nil if cancelled.
	Falls back to a text path prompt if no file chooser is available (e.g. headless)."
	| result |
	(Smalltalk includesKey: #StandardFileMenu) ifTrue: [
		result := StandardFileMenu oldFileFrom: FileDirectory default withPattern: '*.json'.
		result ifNil: [^ nil].
		^ result directory fullNameFor: result name].
	"Fallback."
	^ (UIManager default request: 'Load coverage JSON from:' initialAnswer: '')
		ifNil: [nil] ifNotNil: [:s | s isEmpty ifTrue: [nil] ifFalse: [s withBlanksTrimmed]]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWANavPanel >> clearCoverage [
	"Remove the coverage overlay and its status line."
	| tm |
	tm := self treemap.
	tm ifNil: [^ self].
	tm showCoverage: nil.
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> collectInvocationTally [
	"Read invocation counts from the live tally, uninstall the wrappers, overlay
	the green tally ramp, and clear the live-tally state. Resets the Tally button.
	Status shown in the meta line, no dialog."
	| n |
	liveTally ifNil: [^ self].
	liveTally collectTally.
	liveTally uninstall.
	n := liveTally resultMap size.
	self treemap showCoverage: liveTally.
	self treemapCoverageStatus: 'Tally: ', n printString, ' methods invoked'.
	self refresh.
	liveTally := nil.
	self updateTallyButton
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:39'
}
SWANavPanel >> coverageScoped [
	"Cover button (code map only): run test coverage WITH provenance for the shown
	packages -- captures both coverage AND which tests cover each method -- under a
	forked, Stop-able panel, then overlay it (green by covering-test count; select a
	method to see its tests). Even on a broad selection like '*' this never wedges
	the image: hit STOP to abort and keep the partial result."
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
			tm showCoverageData: data.
			tm coverageStatus: 'Coverage: ', data coveredMethodCount printString,
				' methods, ', data testNames size printString, ' tests (select a method to see them)'.
			self refresh]
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
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:54'
}
SWANavPanel >> cycleLeafKind [
	"Depth button: cycle the view's render depth (leafKind) through
	Full -> Package -> Class -> Category -> Method -> Full. Only affects rendering;
	the tree and metric roll-ups are unchanged, so this is cheap to re-apply."
	| order current next |
	(view respondsTo: #leafKind:) ifFalse: [^ Beeper beep].
	order := { nil. #package. #class. #category. #method }.
	current := (view respondsTo: #leafKind) ifTrue: [view leafKind] ifFalse: [nil].
	next := order at: ((order indexOf: current) \\ order size) + 1.
	view leafKind: next.
	self updateDepthLabel.
	self refresh
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:45'
}
SWANavPanel >> importCoverageData [
	"Load button: open a file chooser for a reusable SWACoverageData JSON file
	(test<->method provenance) and overlay it -- works in any image, matched by
	'Class>>selector'."
	| path data |
	(self treemap isKindOf: SWACodeTreemapMorph) ifFalse: [^ self].
	path := self chooseCoverageFile.
	path ifNil: [^ self].
	[data := SWACoverageData fromFile: path]
		on: Error do: [:e | ^ self treemapCoverageStatus: 'Import failed: ', e messageText].
	self treemap showCoverageData: data.
	self treemapCoverageStatus: 'Coverage (loaded): ', data coveredMethodCount printString,
		' methods, ', data testNames size printString, ' tests'.
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
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:59'
}
SWANavPanel >> newSourceRow [
	"The bottom area: a left-to-right row with the source pane (spaceFill) and,
	for the Code Map (which has coverage provenance), the covering-tests pane
	(fixed width)."
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
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWANavPanel >> provenanceIndex [
	"List-model selection index for the covering-tests pane."
	^ provenanceIndex ifNil: [0]
]

{
	#category : #'covering tests pane',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWANavPanel >> provenanceIndex: anInteger [
	"List-model click handler for the covering-tests pane: navigate the treemap to
	the clicked test/method node (selecting it, which in turn re-fills this pane for
	the newly selected node)."
	| assoc |
	provenanceIndex := anInteger.
	(anInteger = 0 or: [provenanceEntries isNil]) ifTrue: [^ self].
	assoc := provenanceEntries at: anInteger ifAbsent: [^ self].
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
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:58'
}
SWANavPanel >> refresh [
	"Re-pull all label strings from the view and reload the source + covering-tests
	panes (if shown). The view calls this after any selection/zoom change."
	breadcrumbMorph ifNotNil: [breadcrumbMorph contents: self breadcrumbContents].
	selectionPathMorph ifNotNil: [selectionPathMorph contents: (self selectionPathContents ifNil: [''])].
	metaInfoMorph ifNotNil: [metaInfoMorph contents: (self metaInfoContents ifNil: [''])].
	self updateSource.
	self updateCoveringTests
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 18:40'
}
SWANavPanel >> setView: aViewMorph [
	"Build the panel chrome around aViewMorph: header (Back/Browse/Show + optional
	X-ref/Clear + optional coverage controls + optional Depth + breadcrumb + a
	top-right fullscreen toggle), selection-path line, meta-info line, then the view.
	The source pane is created lazily by #toggleSource."
	| crumbFont detailFont metaFont backButton browseButton showButton |
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

	headerRow := Morph new
		color: (Color gray: 0.15);
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		cellPositioning: #leftCenter;
		cellInset: 6;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	headerRow addMorphBack: backButton; addMorphBack: browseButton;
		addMorphBack: showButton.
	"Cross-reference controls, only for cross-referenceable treemap views."
	(view respondsTo: #keyIndex) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'X-ref' action: #crossReference).
		headerRow addMorphBack: (self buttonLabelled: 'Clear' action: #clearCrossReference)].
	"Coverage controls, only for the static Code Map. Cover runs the shown packages'
	related tests WITH provenance under a forked, Stop-able panel (covered green +
	per-method covering tests). Tally = live invocation counting. Export/Load persist
	the reusable JSON. The whole-image run is NOT here -- use
	SWACoverage class>>generateAllTestsToFile: from a Workspace/CLI."
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'Cover' action: #coverageScoped).
		tallyButton := self buttonLabelled: 'Tally' action: #coverageTally.
		headerRow addMorphBack: tallyButton.
		headerRow addMorphBack: (self buttonLabelled: 'Export' action: #exportCoverage).
		headerRow addMorphBack: (self buttonLabelled: 'Load' action: #importCoverageData).
		headerRow addMorphBack: (self buttonLabelled: 'Clear Cov' action: #clearCoverage).
		self updateTallyButton].
	depthButton ifNotNil: [headerRow addMorphBack: depthButton].
	"Breadcrumb spaceFills, pushing the fullscreen button to the right edge."
	headerRow addMorphBack: breadcrumbMorph.
	headerRow addMorphBack: fullButton.

	selectionPathMorph := StringMorph new
		contents: (self selectionPathContents ifNil: ['']);
		font: detailFont;
		color: (Color gray: 0.95);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	metaInfoMorph := StringMorph new
		contents: (self metaInfoContents ifNil: ['']);
		font: metaFont;
		color: (Color gray: 0.7);
		hResizing: #spaceFill; vResizing: #rigid;
		yourself.

	view hResizing: #spaceFill; vResizing: #spaceFill.

	self addMorphBack: headerRow;
		addMorphBack: selectionPathMorph;
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
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWANavPanel >> toggleSource [
	"Show button: show/hide the bottom area at the bottom of the panel. The bottom
	area is a horizontal row holding the source pane (left) and -- for views with
	coverage provenance -- a covering-tests list pane (right). When shown, load the
	current selection's source and provenance."
	(sourceRow notNil and: [sourceRow owner notNil])
		ifTrue: [sourceRow delete]
		ifFalse: [
			sourceRow ifNil: [sourceRow := self newSourceRow].
			self addMorphBack: sourceRow.
			self updateSource.
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
