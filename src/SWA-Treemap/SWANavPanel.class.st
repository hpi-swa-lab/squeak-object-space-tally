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
		'tallyButton'
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> coverageAll [
	"Button action: test coverage of the shown packages, run by ALL tests (slow)."
	| root |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Coverage: only on a Code Map'].
	self runAllTestCoverage: root
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:15'
}
SWANavPanel >> coverageScoped [
	"Button action: test coverage of the shown packages, run by their related tests."
	| root |
	root := self codeRoot.
	root ifNil: [^ self treemapCoverageStatus: 'Coverage: only on a Code Map'].
	self runScopedTestCoverage: root
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:55'
}
SWANavPanel >> coverageStatusString: aCoverage ran: done of: total cancelled: wasCancelled [
	"Build the meta-line status for a boolean coverage pass."
	| covered watched |
	covered := aCoverage resultMap size.
	watched := aCoverage methods size max: 1.
	^ String streamContents: [:s |
		s nextPutAll: 'Coverage: '.
		done < total ifTrue: [
			s nextPutAll: (wasCancelled ifTrue: ['stopped '] ifFalse: ['running ']);
			print: done; nextPut: $/; print: total; nextPutAll: ' classes -- '].
		s print: covered; nextPut: $/; print: watched; nextPutAll: ' methods (';
			print: ((covered * 100) // watched); nextPutAll: '%)']
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:55'
}
SWANavPanel >> escapePressed [
	"True if ESC is currently down -- used to abort a modal coverage run."
	^ Sensor peekKeyboard = Character escape
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> refresh [
	"Re-pull all label strings from the view and reload the source pane (if shown).
	The view calls this after any selection/zoom change."
	breadcrumbMorph ifNotNil: [breadcrumbMorph contents: self breadcrumbContents].
	selectionPathMorph ifNotNil: [selectionPathMorph contents: (self selectionPathContents ifNil: [''])].
	metaInfoMorph ifNotNil: [metaInfoMorph contents: (self metaInfoContents ifNil: [''])].
	self updateSource
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWANavPanel >> repaintNow [
	"Force a synchronous redraw of the treemap (and its overlay) plus the meta line,
	so coverage results appear live mid-run even under a modal progress bar."
	| tm |
	tm := self treemap.
	tm ifNotNil: [tm flushCache; changed].
	self world ifNotNil: [:w | w displayWorld]
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> runAllTestCoverage: aCodeRoot [
	"Whole-image test coverage: instrument the shown packages, run EVERY test in
	the image. Slow and memory-heavy -- the progress bar shows it, ESC stops it.
	No confirm dialog."
	| cov testClasses |
	cov := SWACoverage new methodsForPackages: aCodeRoot packageNames.
	testClasses := (TestCase allSubclasses select: [:tc |
		tc isAbstract not and: [tc testSelectors notEmpty]]) asArray.
	self runCoverage: cov testClasses: testClasses label: 'Test coverage (all tests)'
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:55'
}
SWANavPanel >> runCoverage: aCoverage testClasses: testClasses label: aLabel [
	"Drive a boolean test-coverage pass over testClasses with a modal progress bar,
	repainting the treemap with partial results every few classes. Press ESC to
	stop early (the bar is modal, so the Stop button can't be clicked during it);
	whatever ran so far is kept. Wrappers are always uninstalled (ensure:)."
	| tm n |
	tm := self treemap.
	n := testClasses size max: 1.
	coverageCancel := false.
	tm coverageStatus: 'starting...'.
	aCoverage installTestCoverage.
	[aLabel
		displayProgressFrom: 0 to: n
		during: [:bar | | done |
			done := 0.
			testClasses do: [:tc |
				(coverageCancel or: [self escapePressed]) ifTrue: [coverageCancel := true].
				coverageCancel ifFalse: [
					[tc suite run] on: Error, Halt do: [:e | e return: nil].
					done := done + 1.
					bar value: done.
					(done \\ 5 = 0 or: [done = testClasses size]) ifTrue: [
						aCoverage refreshBooleanResult.
						tm showCoverage: aCoverage.
						tm coverageStatus: (self coverageStatusString: aCoverage
							ran: done of: testClasses size cancelled: false).
						self repaintNow]]]]]
		ensure: [aCoverage uninstallTestCoverage].
	aCoverage refreshBooleanResult.
	tm showCoverage: aCoverage.
	tm coverageStatus: (self coverageStatusString: aCoverage
		ran: testClasses size of: testClasses size cancelled: coverageCancel).
	self refresh
]

{
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:16'
}
SWANavPanel >> runScopedTestCoverage: aCodeRoot [
	"Boolean test coverage of the shown packages, exercised by their related
	TestCase classes (category = or starts-with a shown package name). Modal
	progress bar with live partial repaint; ESC to stop. Feedback goes to the
	status line, not a dialog."
	| names cov testClasses |
	names := aCodeRoot packageNames.
	cov := SWACoverage new methodsForPackages: names.
	testClasses := (TestCase allSubclasses select: [:tc | | cat |
		cat := tc category ifNil: [''].
		tc isAbstract not and: [tc testSelectors notEmpty and: [
			names anySatisfy: [:nm | cat = nm or: [cat beginsWith: nm] ]]]]) asArray.
	testClasses isEmpty ifTrue: [
		^ self treemapCoverageStatus: 'Coverage: no related test classes found'].
	self runCoverage: cov testClasses: testClasses label: 'Test coverage'
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:14'
}
SWANavPanel >> setView: aViewMorph [
	"Build the panel chrome around aViewMorph: header (Back/Browse/Show + optional
	X-ref/Clear + optional Cover/All/Tally/Clear Cov + optional Depth + breadcrumb
	+ a top-right fullscreen toggle), selection-path line, meta-info line, then the
	view. The source pane is created lazily by #toggleSource."
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
	"Coverage controls, only for the static Code Map: one button per measurement.
	The Tally button is kept so its label/colour can reflect the live-tally state."
	(view isKindOf: SWACodeTreemapMorph) ifTrue: [
		headerRow addMorphBack: (self buttonLabelled: 'Cover' action: #coverageScoped).
		headerRow addMorphBack: (self buttonLabelled: 'Cover All' action: #coverageAll).
		tallyButton := self buttonLabelled: 'Tally' action: #coverageTally.
		headerRow addMorphBack: tallyButton.
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
	#category : #coverage,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:54'
}
SWANavPanel >> stopCoverage [
	"Stop button: request cancellation of a running coverage pass (the run loop
	checks this each step, restores wrappers, and keeps partial results)."
	coverageCancel := true
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> toggleSource [
	"Show button: show/hide the source pane at the bottom of the panel. When shown,
	load the view's currently selected source."
	(sourceMorph notNil and: [sourceMorph owner notNil])
		ifTrue: [sourceMorph delete]
		ifFalse: [
			sourceMorph ifNil: [sourceMorph := self newSourceMorph].
			self addMorphBack: sourceMorph.
			self updateSource].
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
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:51'
}
SWANavPanel >> updateSource [
	"If the source pane is showing, reload it from the view's current selection."
	(sourceMorph isNil or: [sourceMorph owner isNil]) ifTrue: [^ self].
	sourceMorph setText: (self selectedSourceContents ifNil: [''])
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
