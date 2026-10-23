"
Abstract superclass for SWA tree visualisations (treemap, flamegraph).

Holds the structure (rootNode), navigation chrome link (navPanel), selection
and render cache shared by all views, and -- crucially -- the cross-reference
protocol that links independent views by SWANode>>crossRefKey:

- keyIndex: Dictionary crossRefKey -> node, built in #setRoot:, so peers can
  look us up in O(1).
- highlightWeights: foreign key -> weight map pushed in from another view.
- effectiveWeights: that map rolled up the tree (max of self + descendants) so
  ancestor tiles (class/package) light up when any descendant matched.

Subclasses must implement: setRoot: (call rebuildKeyIndex), children-walking via
the node tree, baseColorForNode:, and the actual rendering. They provide their
own layout-specific ivars.
"
Class {
	#name : #SWAView,
	#superclass : #Morph,
	#instVars : [
		'rootNode',
		'keyIndex',
		'highlightWeights',
		'effectiveWeights',
		'cachedForm',
		'history',
		'navPanel',
		'selectedNode',
		'highlightStyle',
		'coverageKind',
		'coverageData',
		'testKeys',
		'testFilterKeys',
		'coveringTestFilter',
		'secondarySelection',
		'datasets',
		'metricsByMode',
		'sizeMetric',
		'decorationMetric',
		'activeDataset',
		'searchQuery',
		'searchMatchSet',
		'markedNodesCache',
		'suppressMetricColor',
		'zoomBar',
		'scrollY',
		'contentHeight',
		'scrollThumbDragOffset',
		'crossRefDependents',
		'repositoryName',
		'fromCommit',
		'toCommit',
		'cachedGitHistory',
		'priorSources',
		'reviewScope',
		'gitChanges',
		'lastChanges',
		'liveRoot',
		'snapshotRoot',
		'rangeView',
		'rangeViewButtons',
		'gitStatusCache'
	],
	#classVars : [
		'CrossRefGeneration',
		'DatasetContainerTint'
	],
	#category : #'SWA-Base',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:42'
}
SWAView class >> crossReferenceGeneration [
	"Bumped whenever a dataset is added or dropped anywhere, so cached peer-link
	lists know they are stale."

	^ CrossRefGeneration ifNil: [CrossRefGeneration := 0]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:42'
}
SWAView class >> crossReferenceLinksChanged [
	CrossRefGeneration := self crossReferenceGeneration + 1.
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:24'
}
SWAView class >> datasetContainerTint [
	"How a container tile (one with child tiles drawn inside it) is coloured while a
	DATASET metric drives colour. Process-wide, so every SWA view agrees.

		#muted  -- (default) mean of the descendants, dimmed back toward the
			   background: the container reads as ground, its methods as figure
		#none   -- containers keep their intrinsic structural colour, MUTED to
			   #intrinsicMuteAlpha so it reads as context; only the leaves
			   carry the dataset reading
		#full   -- the historical behaviour: containers take the full rolled-up
			   value at full saturation (which, for an additive metric, saturates
			   every header at the hot end of the ramp)"
	^ DatasetContainerTint ifNil: [#muted]
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:32'
}
SWAView class >> datasetContainerTint: aSymbol [
	"#muted / #none / #full -- see #datasetContainerTint. Recolouring is instant, so
	callers only need to flush the cached Form of the views they care about."
	DatasetContainerTint := aSymbol
]

{
	#category : #preferences,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:24'
}
SWAView class >> datasetContainerTintOptions [
	^ #(
		(#muted 'Containers: muted average')
		(#none  'Containers: muted structural colour (leaves only)')
		(#full  'Containers: full rolled-up value')
	)
]

{
	#category : #colors,
	#'squeak_changestamp' : 'MCPServer 8/6/2026 11:23'
}
SWAView class >> intrinsicMuteAlpha [
	"How much of a tile's INTRINSIC (structural) colour survives while a dataset
	metric drives colour -- see #containerColorFor:metric:, mode #none. Large parts
	of a map often carry no data at all (an opencode session touched three packages;
	everything else is a neighbour it left alone), and at full strength the intrinsic
	hues of all those containers shout as loudly as the tiles the dataset actually
	says something about. Keeping 30% of the hue leaves the structure readable as
	ground while the measured tiles stay the figure."
	^ 0.3
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView class >> reviewHashOf: aString [
	"The first 12 hex digits of the SHA-1 of aString, with its line endings normalised."
	| hex |
	hex := (SecureHashAlgorithm new hashMessage: aString asString withSqueakLineEndings) printStringBase: 16.
	^ ((String new: 40 - hex size withAll: $0), hex) asLowercase first: 12
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:42'
}
SWAView class >> viewKindLabelFor: aSymbol [
	"Human-readable label for a #viewKind Symbol, for the Marks details pane. Falls back
	to a capitalised, de-camel-cased form of the symbol so a new kind still reads sensibly
	without a table entry."
	^ aSymbol caseOf: {
		[#codeMap] -> ['Code Map'].
		[#spaceTally] -> ['Space Tally'].
		[#messageTallyTreemap] -> ['Message Tally (treemap)'].
		[#messageTallyFlamegraph] -> ['Message Tally (flamegraph)'].
		[#changeMap] -> ['Change Map'].
		[#classDiagram] -> ['Class Diagram'].		[#codeBrowser] -> ['Code Browser'].		[#codeLinear] -> ['Linear Code']
	} otherwise: [aSymbol asString capitalized]
]

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:11'
}
SWAView >> aboutToStyle: aStyler [
	"Shout styling hook (this morph is the source pane's model). Give the styler the
	selected node's class context so ivars/selectors highlight correctly, then allow
	styling to proceed. The class is taken from #styleClassOrNil when the node
	supplies it (code/treemap nodes), else from #methodReference (flamegraph frames).
	Subclasses may override to suppress styling (e.g. while showing a diff)."
	| cls |
	cls := self styleClassForSelection.
	"NO CLASS, NO STYLING. Shout parses the text as a method either way, so without a
	class every instance variable is an undeclared name and gets painted RED -- in a
	method with a few ivars that is most of the text, and it reads as if the code were
	broken. Plain black is the honest rendering of 'I do not know what this text is';
	coloured-but-wrong is worse than uncoloured."
	cls ifNil: [^ false].
	(aStyler respondsTo: #classOrMetaClass:)
		ifTrue: [aStyler classOrMetaClass: cls].
	^ true
]

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAView >> aboutToStyle: aStyler requestor: anObject [
	"2-arg Shout hook the styler actually sends; delegates to the 1-arg
	#aboutToStyle:, mirroring Model>>aboutToStyle:requestor:. A SWAView is the
	source pane's Shout model (see SWAPane>>newSourceMorph), so every view
	needs this."
	^ self aboutToStyle: aStyler
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> acceptSource: aText notifying: aRequestor [
	"Cmd+S in the Source flap."
	^ self acceptSource: aText of: selectedNode shown: self sourceFlapText notifying: aRequestor
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> acceptSource: aText of: aNode shown: aShownText notifying: aRequestor [
	| key |
	(self canEditSourceOf: aNode shown: aShownText) ifFalse: [
		self reportProblem: (self showsGitRange
			ifTrue: ['Not saved: this is the text git has. Switch to Live image to edit.']
			ifFalse: ['Not saved: this text is not the source of the selection.']).
		^ false].
	key := self save: aText asString of: aNode notifying: aRequestor.
	key ifNil: [^ false].
	self sourceChangedUnder: aNode parent.
	self selectNodeForKey: key.
	^ true
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWAView >> activateCoverageProvenanceFrom: aSWACoverageData [
	"Wire up the test<->method PROVENANCE relation from aSWACoverageData -- WITHOUT the
	legacy green highlight overlay. This gives us the blue test tint (#isTestKey:) and
	the click filters (select a test -> its covered methods; select a covered method ->
	its covering tests), while the BASE tile color still comes from the active dataset
	METRIC. So coverage-as-a-dataset keeps its special provenance behavior.

	Sets #coverageData + #testKeys only; leaves #highlightWeights nil (the metric owns
	color) and does NOT push weights onto the root (size stays intrinsic). Pass the
	same data your active coverage metric wraps."
	aSWACoverageData ifNil: [^ self deactivateCoverageProvenance].
	coverageData := aSWACoverageData.
	testKeys := aSWACoverageData testKeySet , aSWACoverageData testClassNameSet.
	testFilterKeys := nil.
	coveringTestFilter := nil.
	self updateTestFilterForSelection.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> activeDataset [
	"The dataset last picked from the top-level Data selector (or nil). Used to tick
	the Data menu."
	^ activeDataset
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:05'
}
SWAView >> addCrossReferenceDependent: aView [
	"aView colours by my data, so it has to hear when my data changes. WEAK on
	purpose: a pane closed without deregistering must not be kept alive by me."

	crossRefDependents ifNil: [crossRefDependents := WeakSet new].
	crossRefDependents add: aView.
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:04'
}
SWAView >> addDataset: aSWADataset [
	"Retain a named dataset and register ITS METRICS. Each metric gets a UNIQUE minted
	symbol so it becomes its own Color/Size menu entry, tagged with the dataset name --
	and loading the same kind twice yields distinct, coexisting entries you switch
	between with no reload. Answers the dataset. Does NOT change the current color/size
	mode."
	| n base |
	n := (self datasets count: [:d | d kind == aSWADataset kind]) + 1.
	aSWADataset modeSymbol: (aSWADataset kind, '_', n printString) asSymbol.
	base := aSWADataset kind, '_', n printString.
	self datasets addLast: aSWADataset.
	"A peer dataset is a live link to another view: register so it can push changes."
	aSWADataset kind == #peer ifTrue: [
		aSWADataset source peerView ifNotNil: [:view |
			view addCrossReferenceDependent: self]].
	aSWADataset metrics do: [:metric | | sym |
		sym := (base, '_', metric id) asSymbol.
		metric modeSymbol: sym.
		self metricsByMode at: sym put: metric].
	^ aSWADataset
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> addLastChange: aDictionary toReviewOf: aNode [
	| key provenance |
	key := self reviewKeyFor: aNode.
	(key notNil and: [SWAMarkSet reviewed includes: key]) ifFalse: [^ self].
	provenance := (SWAMarkSet reviewed provenanceAt: key) ifNil: [Dictionary new] ifNotNil: [:each | each copy].
	provenance addAll: aDictionary.
	SWAMarkSet reviewed provenanceAt: key put: provenance.
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:54'
}
SWAView >> adoptDatasetsFrom: anotherView [
	"Take over another view's retained datasets (and its active one) so morphing
	between two drawings of the same tree does not silently drop the overlay you
	loaded. Metrics are re-minted onto this view's own colour menu by #addDataset:."
	(anotherView respondsTo: #datasets) ifFalse: [^ self].
	anotherView datasets do: [:ds | self addDataset: ds].
	(anotherView respondsTo: #activeDataset) ifTrue: [
		anotherView activeDataset ifNotNil: [:ds | self selectDataset: ds]]
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:54'
}
SWAView >> alternateStructures [
	"SWAStructures offering ANOTHER WAY TO DRAW THIS SAME TREE, for the Tree menu.

	Distinct from a dataset's #structures, which supply a different TREE. Here the
	root node is unchanged and only the viewClass differs -- the flamegraph/treemap
	relationship, generalised. Empty by default."
	^ #()
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:57'
}
SWAView >> applyColorMetricSymbol: aSymbolOrNil [
	"Bind the COLOR axis to a minted dataset-metric symbol, or (nil) restore the
	view's intrinsic default color mode. The one axis MOST SWA views support. Views
	without a switchable color mode (e.g. the flamegraph, which colors intrinsically
	per frame) simply can't be a color TARGET -- they no-op here but can still be a
	cross-ref SOURCE (peer) for others."
	(self respondsTo: #colorMode:) ifFalse: [^ self].
	aSymbolOrNil
		ifNotNil: [self colorMode: aSymbolOrNil]
		ifNil: [self colorMode: self intrinsicColorMode]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> baseColorForNode: aNode [
	"Intrinsic fill color for a node, ignoring cross-ref highlight. Subclasses override."
	^ self subclassResponsibility
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:54'
}
SWAView >> branchChoices [
	^ (self gitHistory ifNil: [#()] ifNotNil: [:history |
		(history localBranchNames collect: [:each | each -> (each, ' (branch tip)')]),
		(history remoteBranchNames collect: [:each | each -> (each, ' (remote branch tip)')])])
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:42'
}
SWAView >> bumpKey: aCoverageClass dim: aBoolean [
	"The proportions-Dictionary key for a leaf of the given coverage class
	(#green/#red/#blue), choosing the dimmed variant when aBoolean. nil for #none."
	aCoverageClass == #green ifTrue: [^ aBoolean ifTrue: [#greenDim] ifFalse: [#green]].
	aCoverageClass == #red ifTrue: [^ aBoolean ifTrue: [#redDim] ifFalse: [#red]].
	aCoverageClass == #blue ifTrue: [^ aBoolean ifTrue: [#blueDim] ifFalse: [#blue]].
	^ nil
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> canEditSourceOf: aNode [
	^ self canEditSourceOf: aNode shown: self sourceFlapText
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> canEditSourceOf: aNode shown: aShownText [
	"Only members of the image, and only while their own text is shown rather than a
	description or a diff."
	aNode ifNil: [^ false].
	self showsGitRange ifTrue: [^ false].
	((aNode isKindOf: SWACodeMethodNode) or: [aNode isKindOf: SWACodeClassNode]) ifFalse: [^ false].
	((aNode subject isKindOf: SWASnapshotMethod) or: [aNode subject isKindOf: SWASnapshotBehavior])
		ifTrue: [^ false].
	^ aShownText asString = (self currentTextFor: aNode)
]

{
	#category : #navigation,
	#'squeak_changestamp' : 'MCPServer 7/21/2026 14:55'
}
SWAView >> canZoomOut [
	"Whether #zoomOut would actually navigate to a previous focus, i.e. this view still
	has zoom history to unwind. When false, the enclosing SWAPane's Back button falls
	through to reverting a structure morph (returning to the tree we came from)."
	^ history notNil and: [history notEmpty]
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> changeLabel: aString for: aNode [
	"aString in the colour of aNode's change on a shown range: struck out when removed,
	italic once signed off."
	| text kind reviewed |
	text := aString asText.
	self showsGitRange ifFalse: [^ text].
	kind := self gitStatusOf: aNode.
	kind ifNil: [^ text].
	reviewed := self isReviewedChange: aNode.
	text addAttribute: (TextColor color: (self colorForChange: kind reviewed: reviewed)).
	(self gitKindOf: aNode) == #removed ifTrue: [text addAttribute: TextEmphasis struckOut].
	reviewed ifTrue: [text addAttribute: TextEmphasis italic].
	^ text
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> clearCrossReference [
	"Remove any active cross-reference highlight."
	self highlightWeights: nil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> clearTestFilters [
	"Drop both the green (test-selected) and blue (method-selected) filters and
	restore the full coverage overlay."
	coveringTestFilter := nil.
	self filterToTestKey: nil
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWAView >> codeChanged [
	self rebuildKeyIndex.
	self flushCache.
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:41'
}
SWAView >> codeRunInfoString [
	self showsGitRange ifFalse: [^ 'live image'].
	^ self gitRangeLabel, (self showsChangesOnly ifTrue: [', changes only'] ifFalse: [', full picture'])
]

{
	#category : #chrome,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> codeSelectionInfoString [
	| status |
	selectedNode ifNil: [^ ''].
	status := (self showsGitRange and: [(self gitStatusOf: selectedNode) notNil])
		ifTrue: ['   ', (self gitStatusOf: selectedNode),
			((self isReviewedChange: selectedNode) ifTrue: [', signed off'] ifFalse: [''])]
		ifFalse: [''].
	^ selectedNode kind asString, ': ', selectedNode name,
		'   ', selectedNode loc printString, ' LOC', status,
		(self lastChangeInfoFor: selectedNode)
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> codeViewKey [
	"#codeMap or #classDiagram for the two views the pane switches between, else nil."
	^ nil
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> colorForChange: aKind reviewed: aBoolean [
	"The Code Map's change colours, darkened for a light background. Signed-off
	changes fade."
	| tint |
	tint := aKind caseOf: {
		[#added] -> [Color h: 120 s: 0.8 v: 0.55].
		[#modified] -> [Color h: 30 s: 0.9 v: 0.85].
		[#removed] -> [Color h: 0 s: 0.8 v: 0.75] }.
	^ aBoolean
		ifTrue: [tint alphaMixed: 0.4 with: Color gray]
		ifFalse: [tint]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:04'
}
SWAView >> colorForNode: aNode [
	"Tile color, with the name-SEARCH overlay applied last: compute the intrinsic color
	(metric / coverage / highlight compositing -- see #intrinsicColorForNode:) then, if
	a name-search is running and aNode is neither a match nor an ancestor of one, DIM it
	toward near-black so the matching tiles (and the path down to them) stand out."
	| base |
	base := self intrinsicColorForNode: aNode.
	(self isSearchDimmed: aNode)
		ifTrue: [^ base alphaMixed: 0.16 with: (Color gray: 0.1)].
	^ base
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMenuMorph [
	"Build the Color (instant recolor) menu from #colorModeOptions, ticking the
	current #colorMode. Generic mechanism shared by every SWAView: the context menu
	and the header 'Color' button. Answers nil when the view offers no color options.
	Selecting an item sends #colorMode: to the view."
	| opts current menu |
	opts := self colorModeOptions.
	opts isEmpty ifTrue: [^ nil].
	current := self colorMode.
	menu := MenuMorph new defaultTarget: self.
	opts do: [:pair | | mode label |
		mode := pair first.
		label := current == mode
			ifTrue: ['* ', pair second]
			ifFalse: ['   ', pair second].
		menu add: label selector: #colorMode: argument: mode].
	^ menu
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMode [
	"The active color mode symbol (from #colorModeOptions), or nil if the view has
	no switchable coloring. Subclasses that recolor override this with an ivar."
	^ nil
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorMode: aSymbol [
	"Set the active color mode and recolor. Default: no-op (view has no switchable
	coloring). Subclasses override to store the mode and re-render."
	^ self
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:32'
}
SWAView >> colorModeOptions [
	"{ colorModeSymbol. menuLabel } pairs offered by the Color menu. Default: none
	(no Color menu). Subclasses that support recoloring override this."
	^ #()
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> commitLabelFor: aCommitName [
	"'aae5930  the subject line', short enough to sit in a field."
	| repoHistory commit |
	aCommitName ifNil: [^ ''].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ aCommitName].
	commit := repoHistory commitNamed: aCommitName.
	commit ifNil: [^ aCommitName].
	^ aCommitName, '  ', ((repoHistory summaryOf: commit) truncateWithElipsisTo: 30)
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> computeGitStateOf: aNode [
	| kinds reviewed |
	kinds := Set new.
	reviewed := true.
	(self gitKindOf: aNode) ifNotNil: [:kind |
		kinds add: kind.
		(self isNodeReviewed: aNode) ifFalse: [reviewed := false]].
	aNode children ifNotNil: [:kids |
		kids do: [:each |
			(self gitStateOf: each) ifNotNil: [:state |
				kinds add: state first.
				state second ifFalse: [reviewed := false]]]].
	kinds isEmpty ifTrue: [^ nil].
	^ { #(#modified #added #removed) detect: [:each | kinds includes: each]. reviewed }
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:40'
}
SWAView >> containerColorFor: aNode metric: aMetric [
	"Tint for a tile that has child tiles drawn inside it, under the class-wide
	#datasetContainerTint setting. Answers nil to mean 'the metric says nothing',
	which the caller turns into the neutral base."
	| mode |
	"A container with its OWN value in the dataset is DATA, not context: the tint
	modes exist to keep a ROLLUP from burying the children, and a class the dataset
	names directly would otherwise be the one tile that never lights up."
	(aMetric rawValueForKey: aNode crossRefKey)
		ifNotNil: [^ aMetric colorForNode: aNode].
	mode := self class datasetContainerTint.
	mode == #full ifTrue: [^ aMetric colorForNode: aNode].
	mode == #none ifTrue: [
		"The subclass overrides all check #metricForMode: first, so a plain
		#baseColorForNode: here would just hand back the metric colour again.
		MUTED to #intrinsicMuteAlpha: the structural hue is context, not the
		reading, so it must not compete with the dataset-coloured tiles."
		^ (self withoutMetricColorDo: [self baseColorForNode: aNode])
			alphaMixed: self class intrinsicMuteAlpha with: (Color gray: 0.16)].
	^ aMetric containerColorForNode: aNode
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:27'
}
SWAView >> contentHeight [
	"Total height of the scrollable content in content coordinates, or nil for a view
	that does not scroll. Set by #ensureLayout in the views that do."
	^ contentHeight
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:39'
}
SWAView >> coverageClassOfNode: aNode [
	"Classify a single (leaf) node under the active provenance overlay, mirroring the
	priority in #colorForNode::
	  #blue  -- an executed test method / TestCase class,
	  #red   -- a method evicted during the run,
	  #green -- a covered method,
	  #none  -- not covered / not relevant.
	Keyed by crossRefKey against the loaded SWACoverageData (node-identity-independent),
	so it works while walking descendants. Used to build the proportional
	green/red/blue bar on aggregate tiles."
	| key |
	key := aNode crossRefKey.
	(self isTestKey: key) ifTrue: [^ #blue].
	coverageData ifNil: [^ #none].
	(coverageData isEvicted: key) ifTrue: [^ #red].
	(coverageData isCovered: key) ifTrue: [^ #green].
	^ #none
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> coverageColorForWeight: aWeight base: baseColor [
	"Coverage ramp. For boolean coverage every matched weight is 1, so all covered
	tiles are solid green and everything unmatched is dimmed by #colorForNode:.
	For invocation tallies, busier methods go from pale to saturated green on a log
	scale (hue 120), so hot paths read darker-green."
	| maxW frac |
	maxW := self highlightMaxWeight.
	(aWeight isNil or: [aWeight <= 0]) ifTrue: [^ Color gray: 0.2].
	maxW <= 1 ifTrue: [^ Color h: 120.0 s: 0.75 v: 0.85].   "boolean: flat green"
	frac := ((aWeight + 1) ln) / ((maxW + 1) ln).
	frac := (frac max: 0.0) min: 1.0.
	"Pale green (low) -> vivid green (hot): raise saturation + drop brightness."
	^ Color h: 120.0 s: (0.35 + (0.55 * frac)) v: (0.95 - (0.2 * frac))
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 16:47'
}
SWAView >> coverageData [
	"The SWACoverageData behind a provenance overlay (test<->method relation), or
	nil. Lets the meta line show a method's covering tests."
	^ coverageData
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> coverageKind [
	"#boolean or #tally when a coverage overlay is active, else nil."
	^ coverageKind
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:42'
}
SWAView >> coverageProportionsForNode: aNode [
	"For an AGGREGATE (non-leaf) tile under a loaded SWACoverageData overlay, answer
	the leaf-method counts per coverage class, split into BRIGHT (matching the active
	selection filter) and DIM (filtered out), as a Dictionary:
	  #green #greenDim #red #redDim #blue #blueDim #total.
	'total' is ALL leaf descendants, so uncovered methods leave empty (background)
	space in the bar. With no filter active everything is bright (the *Dim entries
	are 0). Answers nil for leaf tiles or when no coverage overlay is active (let
	#colorForNode: paint solid)."
	| counts |
	(coverageData isNil and: [testKeys isNil]) ifTrue: [^ nil].
	aNode children isEmpty ifTrue: [^ nil].
	counts := Dictionary new.
	#(green greenDim red redDim blue blueDim total) do: [:k | counts at: k put: 0].
	self leavesUnder: aNode do: [:leaf | | class dim |
		counts at: #total put: (counts at: #total) + 1.
		class := self coverageClassOfNode: leaf.
		class ~~ #none ifTrue: [
			dim := self isFilteredOut: leaf.
			(self bumpKey: class dim: dim) ifNotNil: [:k | counts at: k put: (counts at: k) + 1]]].
	^ counts
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> coverageValueForNode: aNode [
	"The rolled-up coverage/tally value for aNode (max over its subtree), or nil if
	no overlay is active or nothing in its subtree matched. For a method node this
	is its own value; for a class/package node it is the hottest descendant's."
	(highlightStyle == #coverage and: [effectiveWeights notNil]) ifFalse: [^ nil].
	^ effectiveWeights at: aNode ifAbsent: [nil]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:41'
}
SWAView >> coveringTestFilter [
	"The set of test/TestCase crossRefKeys currently highlighted because a covered
	method is selected (the tests that covered it), or nil for none."
	^ coveringTestFilter
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:06'
}
SWAView >> crossReferenceDependents [
	"The registered views still on screen. A closed pane that failed to deregister
	drops out here rather than being notified."

	| live |
	live := OrderedCollection new.
	crossRefDependents ifNil: [^ live].
	"A WeakSet slot reads as nil once its view is collected, so test for that before
	asking anything of it."
	crossRefDependents do: [:view |
		(view notNil and: [view world notNil]) ifTrue: [live add: view]].
	^ live
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAView >> crossReferenceFrom: aPeerView [
	"Highlight our tiles that also appear in aPeerView, weighting each by the peer
	node's totalSize (samples / bytes / loc). Pass nil to clear. Asks the peer what it
	shows rather than reading its key index: a view may hold context nodes it does not
	draw (see SWAClassDiagram>>peerWeightForKey:)."
	| weights |
	aPeerView ifNil: [^ self highlightWeights: nil].
	weights := Dictionary new.
	aPeerView peerWeightKeys do: [:key |
		(aPeerView peerWeightForKey: key) ifNotNil: [:w | weights at: key put: w]].
	self highlightWeights: weights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:04'
}
SWAView >> crossReferenceLinkedViews [
	"Views joined to me by a #peer dataset, in EITHER direction: the data flows one
	way, but two tools showing the same code should share a selection both ways."

	| linked |
	linked := OrderedCollection withAll: self crossReferenceDependents.
	self crossReferenceSources do: [:view |
		(linked includes: view) ifFalse: [linked add: view]].
	^ linked
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:05'
}
SWAView >> crossReferenceSources [
	"The views MY #peer datasets read. Known from the datasets themselves, so this
	direction needs no registry and no search."

	| sources |
	sources := OrderedCollection new.
	self datasets do: [:ds |
		ds kind == #peer ifTrue: [
			ds source peerView ifNotNil: [:view |
				(view world notNil and: [(sources includes: view) not])
					ifTrue: [sources add: view]]]].
	^ sources
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAView >> currentFocus [
	"The zoom position as #focusForNode: answers it."
	^ nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:41'
}
SWAView >> currentTextFor: aNode [
	"What aNode reads as at the To end. A class reads as its definition, in the form
	its prior source is kept in."
	(aNode isKindOf: SWACodeClassNode) ifTrue: [^ self definitionTextOf: aNode theClass].
	^ aNode sourceString asString
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> dataPanelExtrasFor: aPane [
	"Further controls a view adds to its Data flap, after the range fields."
	^ #()
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> dataPanelFor: aPane [
	"The Data flap's contents: the commit range this view is a picture of. Each
	field is typeable as well as pickable -- a hash under review is usually pasted
	from a mail or a pull request, not one of the recent ones -- and each shows the
	commit's subject line, so the range reads as what it is rather than as two hashes.

	From also takes PARENT: with that set, stepping To down the log walks the history
	one commit at a time. Accepting any field re-diffs (see #reloadFromGit); Reload
	re-runs the same range, for after a commit.

	Wraps like the header bar, so a narrow pane stacks the fields instead of
	overflowing its window."
	| row reload |
	row := Morph new
		color: Color transparent;
		layoutPolicy: TableLayout new;
		listDirection: #leftToRight;
		wrapDirection: #topToBottom;
		cellPositioning: #leftCenter;
		cellInset: 8;
		hResizing: #spaceFill;
		vResizing: #shrinkWrap;
		yourself.
	reload := (aPane buttonLabelled: 'Reload' action: #reloadFromGit)
		target: self;
		yourself.
	reload setBalloonText: 'Diff this range again, picking up new commits'.
	row
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #repositoryName set: #repositoryName:
			choices: #repositoryChoices label: 'Repository' width: 170);
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #fromCommitLabel set: #fromCommit:
			choices: #fromCommitChoices label: 'From' width: 210);
		addMorphBack: (SWAComboFieldMorph new
			on: self get: #toCommitLabel set: #toCommit:
			choices: #toCommitChoices label: 'To' width: 210);
		addMorphBack: reload.
	(self dataPanelExtrasFor: aPane) do: [:each | row addMorphBack: each].
	^ row
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> datasetForDataMode: aSymbol [
	"Resolve a Data-menu symbol to its dataset; #none clears the active dataset."
	aSymbol == #none ifTrue: [^ nil].
	^ self datasets detect: [:d | d modeSymbol == aSymbol] ifNone: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> datasets [
	"The retained, named analysis overlays loaded into this view (SWADataset), in
	load order. Shared across all SWA views so any tool -- Code Map, Space Tally,
	flamegraph -- can host datasets and cross-reference peers uniformly. Lazily
	initialized."
	^ datasets ifNil: [datasets := OrderedCollection new]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:26'
}
SWAView >> deactivateCoverageProvenance [
	"Drop the coverage provenance relation (blue tests + click filters). Used when the
	active color leaves a coverage-provenance metric."
	coverageData := nil.
	testKeys := nil.
	testFilterKeys := nil.
	coveringTestFilter := nil.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> definitionTextOf: aClass [
	"Monticello's form for live classes too, so a class reviewed in the image and in
	git hashes the same."
	^ [(aClass isKindOf: SWASnapshotBehavior)
		ifTrue: [aClass definition definitionString]
		ifFalse: [aClass asClassDefinition definitionString]]
			on: Error do: [:e | '']
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> drawScrollIndicatorOn: aCanvas [
	"A thumb on the right edge. Not a ScrollPane: these views own their own y mapping
	(zoom, virtualisation, lane bands), and wrapping one in a ScrollPane would mean
	maintaining the same arithmetic in two places."
	| thumb |
	thumb := self thumbRect ifNil: [^ self].
	aCanvas fillRectangle: self scrollBarTrackRect color: (Color gray: 0.18).
	aCanvas
		fillRectangle: (thumb insetBy: 2)
		color: (self isDraggingScrollThumb ifTrue: [Color gray: 0.75] ifFalse: [Color gray: 0.5])
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> effectiveWeightOf: aNode [
	"Memoised rolled-up highlight weight: the max of aNode's own direct match and
	its children's effective weights. Answers nil if nothing in the subtree matched.
	When a test filter is active (a test/TestCase is selected), a method only counts
	as a direct match if it is one of that test's covered methods."
	| key w |
	effectiveWeights at: aNode ifPresent: [:cached | ^ cached ].
	w := nil.
	key := aNode crossRefKey.
	(key notNil
		and: [highlightWeights includesKey: key]
		and: [testFilterKeys isNil or: [testFilterKeys includes: key]])
		ifTrue: [w := highlightWeights at: key].
	aNode children do: [:c | | cw |
		cw := self effectiveWeightOf: c.
		cw ifNotNil: [w := w isNil ifTrue: [cw] ifFalse: [w max: cw]]].
	effectiveWeights at: aNode put: w.
	^ w
]

{
	#category : #layout,
	#'squeak_changestamp' : 'MCPServer 9/17/2026 10:55'
}
SWAView >> ensureLayout [
	"Bring #contentHeight and any cached layout up to date. Subclasses that lay
	themselves out override this; #isScrollable sends it to every view, so the
	default has to exist even for views that have no layout to compute."
]

{
	#category : #'zoom bar',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:22'
}
SWAView >> ensureZoomBar [
	"A floating control strip, kept in the top-right corner. Built once from
	#zoomBarSpecs, which is where a subclass says what its buttons do; a view that
	answers none gets no bar, and pays nothing for having the option.

	Repositioned from #drawOn: rather than from a resize hook, for exactly the reason
	the layout is validated there too: SWAPane resizes its view through a layout policy
	that never sends #extent:, so there is no resize hook to trust.

	Called from the subclass's #drawOn:, not from here, because SWAView does not own
	that method -- every view draws itself its own way."
	| target specs |
	zoomBar ifNil: [
		specs := self zoomBarSpecs.
		specs isEmpty ifTrue: [^ self].
		zoomBar := AlignmentMorph newRow
			color: (Color gray: 0.2);
			borderWidth: 1;
			borderColor: (Color gray: 0.35);
			cellInset: 2;
			layoutInset: 3;
			hResizing: #shrinkWrap;
			vResizing: #shrinkWrap;
			yourself.
		specs do: [:spec |
			| b |
			b := PluggableButtonMorphPlus on: self getState: nil action: spec second.
			b label: spec first; setBalloonText: spec third.
			zoomBar addMorphBack: b].
		self addMorphFront: zoomBar].
	target := (self right - self zoomBarRightInset - zoomBar width - 4)
		@ (self top + 4).
	zoomBar position = target ifFalse: [zoomBar position: target]
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:41'
}
SWAView >> equivalentOf: aNode [
	"The node standing for aNode in the current tree, else for its nearest ancestor."
	| node |
	node := aNode.
	[node notNil] whileTrue: [
		(self nodeEquivalentTo: node) ifNotNil: [:found | ^ found].
		node := node parent].
	^ nil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:51'
}
SWAView >> filterToCoveredMethodKey: aMethodKey [
	"Restrict the blue test highlight to just the tests (and their TestCase classes)
	that covered the given application method. Pass nil to remove the filter.
	No-op unless a SWACoverageData provenance overlay is active."
	coverageData ifNil: [^ self].
	coveringTestFilter := aMethodKey
		ifNil: [nil]
		ifNotNil: [:key | coverageData testKeysForMethod: key].
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:51'
}
SWAView >> filterToTestKey: aTestOrClassKey [
	"Restrict the green coverage highlight to just the methods covered by the given
	test method or TestCase class. Pass nil to remove the filter (show all covered
	methods again). No-op unless a SWACoverageData provenance overlay is active."
	coverageData ifNil: [^ self].
	aTestOrClassKey
		ifNil: [testFilterKeys := nil]
		ifNotNil: [:key |
			testFilterKeys := (coverageData methodsForTestOrClass: key) asSet].
	self rebuildEffectiveWeights.
	self flushCacheKeepingSelection.
	self changed
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:27'
}
SWAView >> flushCache [
	"Drop only the rendered pixels -- whatever layout the view keeps survives."

	cachedForm := nil.
	self changed.
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:57'
}
SWAView >> flushMarksCache [
	"Drop the cached set of marked nodes so it is rebuilt from the global mark set
	on next draw. Called when the shared SWAMarkSet changes."
	markedNodesCache := nil
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAView >> focusForNode: aNode [
	"Where aNode is, in terms both code views understand whatever tree they hold: a
	system category or a class, by name. nil for the whole tree."
	aNode ifNil: [^ nil].
	(aNode isKindOf: SWACodeSubpackageNode) ifTrue: [^ #category -> aNode fullCategory].
	(aNode isKindOf: SWACodePackageNode) ifTrue: [^ #category -> aNode subject systemCategoryPrefix asString].
	((aNode respondsTo: #classNode) and: [aNode classNode notNil])
		ifTrue: [^ #class -> aNode classNode name].
	^ nil
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAView >> focusOn: aFocus [
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> forgetDataset: aDataset [
	self datasets remove: aDataset ifAbsent: [^ self].
	aDataset metrics do: [:metric | self metricsByMode removeKey: metric modeSymbol ifAbsent: []].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> fromCommit [
	^ fromCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> fromCommit: aString [
	| value |
	value := self normalizeCommitInput: aString.
	value = fromCommit ifTrue: [^ self].
	self tryRange: [fromCommit := value]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> fromCommitChoices [
	"PARENT leads the list: with From on PARENT, stepping To down the log shows what
	each commit changed, one at a time. The branches let a range span two of them;
	any other commit can be typed as a hash."
	^ (OrderedCollection with: 'PARENT' -> 'PARENT (just what To changed)'),
		self branchChoices, self recentCommits
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> fromCommitLabel [
	"What the From field shows: the keyword as chosen, or the commit's subject line so
	the field says what it points at rather than just where."
	self isParentFrom ifTrue: [^ 'PARENT'].
	^ self commitLabelFor: fromCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> gitChanges [
	^ gitChanges
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 18:05'
}
SWAView >> gitDiffFor: aNode [
	"aNode's change over the loaded range as a styled diff, or nil when there is nothing
	it was changed from. Definitions and comments are diffed word by word, so a renamed
	instance variable shows as one word, not as two whole lines."
	| prior current builder |
	prior := self priorSourceFor: aNode.
	prior ifNil: [^ nil].
	current := (self gitKindAt: aNode crossRefKey) == #removed
		ifTrue: ['']
		ifFalse: [self currentTextFor: aNode].
	builder := ((aNode isKindOf: SWACodeClassNode) or: [aNode isKindOf: SWACodeCommentNode])
		ifTrue: [ClassDiffBuilder]
		ifFalse: [TextDiffBuilder].
	^ [builder
		buildDisplayPatchFrom: prior
		to: current
		inClass: (self styleClassForDiffOf: aNode)
		prettyDiffs: false]
			on: Error do: [:e | nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> gitDiffForSelection [
	^ self gitDiffFor: selectedNode
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> gitHistory [
	"A history on the named repository, or nil when there is no such working copy.
	Kept across calls: it holds the walked commit list, which a fresh history per
	call would throw away."
	repositoryName isNil ifTrue: [^ nil].
	(cachedGitHistory notNil
		and: [([cachedGitHistory workingCopy name] on: Error do: [:e | nil]) = repositoryName])
		ifTrue: [^ cachedGitHistory].
	^ cachedGitHistory := [SWAGitHistory onWorkingCopyNamed: repositoryName]
		on: Error do: [:e | nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:06'
}
SWAView >> gitKindAt: aKey [
	gitChanges ifNil: [^ nil].
	^ (gitChanges at: #kinds) at: aKey ifAbsent: [nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> gitKindOf: aNode [
	"#added or #modified for a member the range changed. A class counts as modified
	when only its definition changed."
	| key |
	gitChanges ifNil: [^ nil].
	key := aNode crossRefKey.
	key ifNil: [^ nil].
	^ (gitChanges at: #kinds) at: key ifAbsent: [
		(aNode kind == #class and: [(gitChanges at: #marks) includes: key])
			ifTrue: [#modified]
			ifFalse: [nil]]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> gitRangeLabel [
	"'mysqueak aae5930..a1f8091' -- names the range for the window title and, more
	importantly, for the review marks: a sign-off is only meaningful together with the
	version it was given to, so both ends are the RESOLVED hashes. PARENT and HEAD
	would each mean something different tomorrow."
	| from to |
	repositoryName ifNil: [^ self viewKindLabel].
	from := self resolvedFromCommit.
	from ifNil: [^ repositoryName].
	to := self resolvedToCommit ifNil: ['HEAD'].
	^ repositoryName, ' ',
		(from first: (from size min: 7)), '..', (to first: (to size min: 7))
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:44'
}
SWAView >> gitRangePackageNames [
	"The packages a range is loaded for, nil for all code packages of the repository."
	^ liveRoot ifNotNil: [:root | root packageNames asArray]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> gitRangeState [
	^ { repositoryName. fromCommit. toCommit. gitChanges. priorSources. reviewScope }
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> gitRangeState: anArray [
	repositoryName := anArray first.
	fromCommit := anArray second.
	toCommit := anArray third.
	gitChanges := anArray fourth.
	priorSources := anArray fifth.
	reviewScope := anArray sixth.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> gitStateOf: aNode [
	"{ kind. allReviewed } rolled up over the subtree, nil when nothing in it changed.
	The kind is #modified over #added over #removed."
	gitChanges ifNil: [^ nil].
	gitStatusCache ifNil: [gitStatusCache := IdentityDictionary new].
	^ gitStatusCache
		at: aNode
		ifAbsent: [gitStatusCache at: aNode put: (self computeGitStateOf: aNode)]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> gitStatusOf: aNode [
	"#added, #modified or #removed, rolled up; nil when nothing in the subtree changed."
	^ (self gitStateOf: aNode) ifNotNil: [:state | state first]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAView >> handleScrollMouseDown: evt [
	"Consume a click in the scrollbar gutter: grab the thumb, or page toward a click on
	the track. Answers whether it was consumed, so a subclass's #mouseDown: can open
	with 'ifTrue: [^ self]' and otherwise carry on exactly as before."
	| thumb |
	self isScrollable ifFalse: [^ false].
	(self scrollBarTrackRect containsPoint: evt position) ifFalse: [^ false].
	thumb := self thumbRect.
	(thumb notNil and: [thumb containsPoint: evt position])
		ifTrue: [scrollThumbDragOffset := evt position y - thumb top]
		ifFalse: [
			scrollThumbDragOffset := nil.
			self scrollBy: (evt position y < (thumb ifNil: [self bounds]) top
				ifTrue: [self scrollViewportHeight negated]
				ifFalse: [self scrollViewportHeight])].
	self changed.
	^ true
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAView >> handleScrollMouseMove: evt [
	"Continue a thumb drag. Answers whether it was consumed."
	scrollThumbDragOffset ifNil: [^ false].
	self scrollToThumbTop: evt position y - scrollThumbDragOffset.
	^ true
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAView >> handleScrollMouseUp: evt [
	"End a thumb drag. Answers whether it was consumed."
	scrollThumbDragOffset ifNil: [^ false].
	scrollThumbDragOffset := nil.
	self changed.
	^ true
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAView >> handlesKeyboard: evt [
	"Accept keystrokes so the Ctrl+F search shortcut works while the map has focus
	(the view grabs keyboard focus on mouseDown -- see #mouseDown: in subclasses /
	#takeKeyboardFocusFrom:)."
	^ true
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> handlesMouseWheel: evt [
	"Only when there is something to scroll -- a view that never sets #contentHeight
	should not swallow the wheel from whatever is underneath it. Subclasses that also
	use the wheel for zooming override this to answer true unconditionally."
	^ self isScrollable
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:38'
}
SWAView >> hasRangeViews [
	"Whether the view offers Full picture / Changes only / Live image."
	^ false
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:30'
}
SWAView >> hasRenderedChildren: aNode [
	"Does aNode have CHILD TILES drawn inside it in the current layout? Views that
	cannot answer say false, which keeps the historical 'tint every node' behaviour.
	SWATreemapMorph overrides with the real answer (see #computeLayout)."
	^ false
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> hashOf: aCommitName [
	"The short hash of a branch or hash prefix, on any branch; nil when it names none."
	^ (self gitHistory ifNotNil: [:history | history commitNamed: aCommitName])
		ifNotNil: [:commit | [commit hexHash first: 7] on: Error do: [:e | nil]]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> heatColorForWeight: aWeight base: baseColor [
	"Map aWeight onto a log-scaled cold->hot ramp (blue -> red). Log scale spreads
	the long tail of small values."
	| maxW frac |
	maxW := self highlightMaxWeight.
	(aWeight isNil or: [aWeight <= 0 or: [maxW <= 0]])
		ifTrue: [^ Color h: 220.0 s: 0.7 v: 0.85].
	frac := ((aWeight + 1) ln) / ((maxW + 1) ln).
	frac := (frac max: 0.0) min: 1.0.
	^ Color h: (220.0 * (1.0 - frac)) s: 0.85 v: 0.95
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightColorForWeight: aWeight base: baseColor [
	"Dispatch a matched tile's colour on the active highlight style."
	^ self highlightStyle == #coverage
		ifTrue: [self coverageColorForWeight: aWeight base: baseColor]
		ifFalse: [self heatColorForWeight: aWeight base: baseColor]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightMaxWeight [
	"Largest weight in the active cross-reference map (0 if none)."
	highlightWeights ifNil: [^ 0].
	highlightWeights isEmpty ifTrue: [^ 0].
	^ highlightWeights values inject: 0 into: [:mx :w | mx max: w]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightStyle [
	"How a matched tile is coloured: #heat (cross-ref blue->red, default) or
	#coverage (covered green -> uncovered red, for SWACoverage data)."
	^ highlightStyle ifNil: [#heat]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> highlightStyle: aSymbol [
	"#heat or #coverage. Redraws."
	highlightStyle := aSymbol.
	self flushCache.
	self changed
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightWeights [
	"Dictionary crossRefKey -> Number pushed in from a peer view, or nil when no
	cross-reference is active. Drives the cross-ref heat colouring."
	^ highlightWeights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> highlightWeights: aDictionaryOrNil [
	"Set (or clear, with nil) the foreign weight map, roll it up the tree (max of
	self + descendants) so ancestor tiles also light up, and redraw."
	highlightWeights := aDictionaryOrNil.
	self rebuildEffectiveWeights.
	self flushCache.
	self changed
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> installRoot: aRootNode [
	aRootNode == rootNode ifTrue: [^ self].
	self setRoot: aRootNode.
	navPanel ifNotNil: [:panel | panel refresh].
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 18:02'
}
SWAView >> intensityColorFor: aValue max: aMax [
	"GitHub-style single-hue intensity ramp: a dark empty cell, then four steps of
	green. Log-normalised against aMax, because these counts are heavily skewed.

	Lives here rather than on SWATemporalView because SWAOpenCodeTreemapMorph's
	#writes and #reads colour modes also send it -- and did not inherit it, so both
	modes raised doesNotUnderstand: on every draw."
	| t |
	aValue <= 0 ifTrue: [^ Color gray: 0.17].
	t := aMax <= 1
		ifTrue: [1.0]
		ifFalse: [(((aValue max: 1) ln / aMax ln) min: 1.0) max: 0.0].
	^ Color h: 135 s: 0.35 + (t * 0.45) v: 0.32 + (t * 0.58)
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:32'
}
SWAView >> intrinsicColorForNode: aNode [
	"Tile color IGNORING the name-search overlay (see #colorForNode:, which dims this
	result for nodes filtered out by an active search). LAYERED-DATASETS: when the
	active color mode is a dataset METRIC, that metric owns the BASE tint. But a
	COVERAGE-provenance metric ALSO keeps the special behavior: executed tests /
	TestCase classes are tinted BLUE, and when a selection filter is active (select a
	test -> its covered methods; select a covered method -> its covering tests)
	non-matching tiles DIM. So we layer blue + filter-dim on top of the metric's color.

	Without a metric active, this falls back to the legacy provenance/highlight
	compositing (blue tests, red eviction, gray aggregate base, cross-ref heat).

	Metric dispatch needs BOTH #metricForMode: and a switchable #colorMode (a view
	without a colorMode -- e.g. the flamegraph -- colors intrinsically and can't be a
	metric color TARGET, so it skips straight to its own baseColorForNode:)."
	| metric base w red |
	((self respondsTo: #metricForMode:) and: [self respondsTo: #colorMode]) ifTrue: [
		metric := self metricForMode: self colorMode].
	metric ifNotNil: [
		"Blue tint for executed test / TestCase tiles (needs provenance wired up)."
		(metric isCoverageProvenance and: [self isTestKey: aNode crossRefKey])
			ifTrue: [^ self testColorForNode: aNode].
		"Base tint from the metric; dim it if an active provenance filter excludes it.
		A tile with child tiles drawn INSIDE it is a container: painting it with the
		same saturated ramp as its children buries the reading it is supposed to
		frame (and, for an additive metric, saturates it past the scale's top). See
		#datasetContainerTint / SWADatasetMetric>>containerColorForNode:."
		base := ((self hasRenderedChildren: aNode)
			ifTrue: [self containerColorFor: aNode metric: metric]
			ifFalse: [metric colorForNode: aNode]) ifNil: [Color gray: 0.22].
		(metric isCoverageProvenance and: [aNode isLeaf and: [self isFilteredOut: aNode]])
			ifTrue: [^ base alphaMixed: 0.25 with: (Color gray: 0.12)].
		^ base].
	(self isTestKey: aNode crossRefKey) ifTrue: [^ self testColorForNode: aNode].
	(coverageData notNil and: [coverageData isEvicted: aNode crossRefKey]) ifTrue: [
		red := Color h: 0.0 s: 0.8 v: 0.85.
		^ (self isFilteredOut: aNode)
			ifTrue: [red alphaMixed: 0.25 with: (Color gray: 0.12)]
			ifFalse: [red]].
	(coverageData notNil and: [aNode children notEmpty])
		ifTrue: [^ Color gray: 0.25].   "aggregate base under coverage overlay; bar drawn on top"
	highlightWeights ifNil: [^ self baseColorForNode: aNode].
	base := self baseColorForNode: aNode.
	w := effectiveWeights ifNil: [nil] ifNotNil: [effectiveWeights at: aNode ifAbsent: [nil]].
	(w notNil and: [aNode isLeaf and: [self isFilteredOut: aNode]]) ifTrue: [w := nil].
	w ifNil: [^ (base alphaMixed: 0.25 with: (Color gray: 0.12))].
	^ self highlightColorForWeight: w base: base
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> intrinsicColorMode [
	"The view's own default color mode, restored when a dataset color binding is
	cleared. Subclasses override with their native default (#codeKind, #class, ...)."
	^ #class
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> isDraggingScrollThumb [
	"Whether the thumb is currently being dragged, for the highlight in
	#drawScrollIndicatorOn:. The flow tracks this in its own drag-mode state machine
	and overrides."
	^ scrollThumbDragOffset notNil
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:37'
}
SWAView >> isFilteredOut: aNode [
	"True if an active provenance filter excludes aNode (so its tile should dim).
	 - test selected (testFilterKeys): a method not among the selected test's
	   covered methods is out;
	 - covered method selected (coveringTestFilter): only the selected method itself
	   stays bright;
	 - no filter: nothing is filtered out."
	testFilterKeys notNil ifTrue: [
		^ (testFilterKeys includes: aNode crossRefKey) not].
	coveringTestFilter notNil ifTrue: [
		^ aNode crossRefKey ~= (selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey])].
	^ false
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> isLiveCodeRoot: aNode [
	^ (aNode isKindOf: SWACodeRootNode)
		and: [(aNode isKindOf: SWACodeSnapshotRootNode) not
		and: [(aNode isKindOf: SWACodeMarkSetRootNode) not]]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:57'
}
SWAView >> isNodeMarked: aNode [
	"Is aNode currently marked in the global mark set?"
	^ aNode notNil and: [SWAMarkSet default includes: aNode markKey]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> isNodeReviewed: aNode [
	| key |
	key := self reviewKeyFor: aNode.
	key ifNil: [^ false].
	^ SWAMarkSet reviewed includes: key
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:41'
}
SWAView >> isPackageNode: aNode [
	^ (aNode isKindOf: SWACodePackageNode) or: [aNode isKindOf: SWACodeSubpackageNode]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> isParentFrom [
	"Whether the From end is the symbolic PARENT rather than a hash."
	^ fromCommit notNil and: [fromCommit asUppercase = 'PARENT']
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView >> isReviewKey: aCharacter event: anEvent [
	^ aCharacter = $r
		and: [(anEvent commandKeyPressed or: [anEvent controlKeyPressed]) not]
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> isReviewedChange: aNode [
	"Whether every change at or under aNode is signed off."
	^ (self gitStateOf: aNode) ifNil: [false] ifNotNil: [:state | state second]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> isScrollable [
	"True when there is more content than viewport. Answers false for every view that
	never sets #contentHeight, which is how the treemaps opt out of all of this without
	knowing it exists."
	self ensureLayout.
	^ (contentHeight ifNil: [0]) > self scrollViewportHeight
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> isSearchDimmed: aNode [
	"True when a name-search is active and aNode is neither a match nor an ancestor of
	a match, so its tile should be dimmed out. Answers false when no search is running
	(the common case), so callers can guard cheaply."
	searchQuery ifNil: [^ false].
	^ (searchMatchSet notNil and: [searchMatchSet includes: aNode]) not
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> isTestKey: aKey [
	"True if aKey identifies an executed test method or TestCase class under the
	active provenance coverage overlay (drives blue tinting)."
	(testKeys isNil or: [aKey isNil]) ifTrue: [^ false].
	^ testKeys includes: aKey
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> keyIndex [
	"Dictionary crossRefKey -> node for this view, built in #setRoot: (lazily on
	first access if missing). Lets other panels cross-reference us in O(1)."
	keyIndex ifNil: [self rebuildKeyIndex].
	^ keyIndex
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView >> keyStroke: evt [
	"Ctrl+F (Cmd+F on Mac) focuses the header search field, r toggles the selection's
	review sign-off. Ctrl+F may arrive either as the letter $f with
	the control/command modifier set, or -- on some platforms -- as control-code 6."
	| isFindKey |
	isFindKey := (evt keyValue = 6)
		or: [(evt commandKeyPressed or: [evt controlKeyPressed])
			and: [evt keyCharacter asLowercase = $f]].
	isFindKey ifTrue: [
		navPanel ifNotNil: [navPanel focusSearchField: evt].
		^ self].
	((self isReviewKey: evt keyCharacter event: evt) and: [selectedNode notNil])
		ifTrue: [^ self toggleReviewedUnder: selectedNode].
	^ super keyStroke: evt
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> lastChangeInfoFor: aNode [
	"For the selection's info line."
	(self gitKindAt: (aNode markKey ifNil: [^ ''])) ifNil: [^ ''].
	^ (self lastChangeOf: aNode)
		ifNil: [(self lastChanges at: aNode markKey ifAbsent: [nil]) == #pending
			ifTrue: ['   last change: looking...']
			ifFalse: ['']]
		ifNotNil: [:info |
			'   last change ', (info at: 'lastChangeCommit'), ' ', (info at: 'lastChangeDate'),
				' ', (info at: 'lastChangeAuthor'), ': ', (info at: 'lastChangeSummary')]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> lastChangeOf: aNode [
	"The last-change info of a changed member: a Dictionary once known, nil while it
	is being looked for or when there is none. The first ask starts the search in the
	background; finding it repaints, and adds it to a sign-off made in the meantime."
	| key snapshot path to |
	key := aNode markKey ifNil: [^ nil].
	(self gitKindAt: key) ifNil: [^ nil].
	(self lastChanges at: key ifAbsent: [nil]) ifNotNil: [:known |
		^ known == #none | (known == #pending) ifTrue: [nil] ifFalse: [known]].
	snapshot := gitChanges at: #snapshot ifAbsent: [^ nil].
	path := snapshot classFilePathFor: key.
	to := self gitHistory ifNotNil: [:history | history commitNamed: self resolvedToCommit].
	(path isNil or: [to isNil]) ifTrue: [^ nil].
	self lastChanges at: key put: #pending.
	[ | history info |
	  history := self gitHistory.
	  info := [(history lastChangeOfMember: key inFile: path from: to)
			ifNotNil: [:commit | history changeInfoOf: commit]]
		on: Error do: [:e | nil].
	  WorldState addDeferredUIMessage: [
		self lastChanges at: key put: (info ifNil: [#none]).
		info ifNotNil: [self addLastChange: info toReviewOf: aNode].
		navPanel ifNotNil: [:panel | panel refresh]] ]
		forkAt: Processor userBackgroundPriority.
	^ nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> lastChanges [
	^ lastChanges ifNil: [lastChanges := Dictionary new]
]

{
	#category : #drawing,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 15:17'
}
SWAView >> layoutProgress: aBlockOrNil [
	"SWAPane>>rebuildCodeMap sends this to whatever view it wraps, and the Tree button
	can put any view there, so the default has to exist. Only the treemap lays out
	tile by tile and has progress to report."
	^ self
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 13:39'
}
SWAView >> leavesUnder: aNode do: aBlock [
	"Evaluate aBlock with every LEAF node in aNode's subtree (depth-first). A leaf is
	a node with no children (a method node on the code map)."
	aNode children isEmpty
		ifTrue: [aBlock value: aNode]
		ifFalse: [aNode children do: [:c | self leavesUnder: c do: aBlock]]
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> liveRoot [
	^ liveRoot
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView >> loadGitRange [
	"Load the range and hand it to #showGitChanges:. Answers whether it loaded.

	Works on the RESOLVED ends: the fields may say PARENT or HEAD, which are positions
	rather than commits, and a review sign-off has to name the commit it was given to.
	An end that will not resolve is REPORTED -- answering false quietly would look
	exactly like a range that changed nothing."
	| from to result |
	(repositoryName isNil or: [fromCommit isNil]) ifTrue: [^ false].
	to := self resolvedToCommit.
	from := self resolvedFromCommit.
	(toCommit notNil and: [to isNil]) ifTrue: [
		self reportProblem: 'no commit or branch ', toCommit, ' in ', repositoryName.
		^ false].
	from ifNil: [
		self reportProblem: (self isParentFrom
			ifTrue: ['no commit starting ', (toCommit ifNil: ['HEAD']), ' to take the parent of']
			ifFalse: ['no commit or branch ', fromCommit, ' in ', repositoryName]).
		^ false].
	result := [(SWACodeSnapshot
			repository: repositoryName from: from to: to packages: self gitRangePackageNames) changes]
		on: Error
		do: [:e | self reportProblem: e messageText. nil].
	result ifNil: [^ false].
	gitChanges := result.
	lastChanges := nil.
	self priorSources: (result at: #priorSources).
	self reviewScope: self gitRangeLabel.
	self showGitChanges: result.
	self reportReviewedChanges.
	^ true
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:01'
}
SWAView >> markProvenance [
	"A SERIALIZABLE snapshot (String->String Dictionary) describing where a mark made in
	this view came from AND enough to best-effort re-open it: the KIND of visualization
	(#viewKind Symbol, stored as a String -- the thing we dispatch on), a human label,
	the view class, the active dataset (name/kind), and the root SCOPE. For code views the
	respawn argument is the package GLOB the root was built from (SWACodeRootNode
	displayName -- e.g. 'Kernel', 'Morphic*', '*'); we store that as 'scopeGlob' and the
	pretty root label as 'rootScope'. NO object references are stored -- every value is a
	String -- so this round-trips through JSON with the mark set. Recorded once when a
	mark is first made (see SWAMarkSet>>add:from:)."
	| dict ds root |
	dict := Dictionary new.
	dict at: 'viewKind' put: self viewKind asString.
	dict at: 'viewLabel' put: self viewKindLabel asString.
	dict at: 'viewClass' put: self class name asString.
	ds := (self respondsTo: #activeDataset) ifTrue: [self activeDataset] ifFalse: [nil].
	ds ifNotNil: [
		ds name ifNotNil: [:n | dict at: 'datasetName' put: n asString].
		ds kind ifNotNil: [:k | dict at: 'datasetKind' put: k asString]].
	root := self rootNode.
	root ifNotNil: [
		dict at: 'rootScope' put: root name asString.
		(root respondsTo: #displayName)
			ifTrue: [dict at: 'scopeGlob' put: root displayName asString].
		(root respondsTo: #pathString) ifTrue: [dict at: 'rootPath' put: root pathString asString]].
	^ dict
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/16/2026 09:57'
}
SWAView >> markedNodes [
	"The nodes in THIS view whose #markKey is in the global SWAMarkSet -- i.e. the
	marked tiles to draw a green border around. Resolved from the shared key set so
	a mark set in any view lights up here too. Cached (rebuilt on #flushMarksCache,
	which the pane calls when the global marks change) because the overlay asks for
	this every frame."
	markedNodesCache ifNotNil: [^ markedNodesCache].
	markedNodesCache := IdentitySet new.
	rootNode ifNil: [^ markedNodesCache].
	SWAMarkSet default isEmpty ifTrue: [^ markedNodesCache].
	rootNode withAllChildrenDo: [:n |
		(SWAMarkSet default includes: n markKey)
			ifTrue: [markedNodesCache add: n]].
	^ markedNodesCache
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:34'
}
SWAView >> metricForMode: aSymbol [
	"The dataset METRIC a minted color/size symbol refers to, or nil if aSymbol is an
	intrinsic mode (#loc, #class, ...)."
	"#withoutMetricColorDo: switches this off for the duration of one call, which is
	how a caller asks a subclass's #baseColorForNode: for the INTRINSIC (structural)
	colour: every override consults this single lookup point first, so suppressing it
	here makes them all fall through to their legacy modes without duplicating a
	'ignore the dataset' branch in each."
	suppressMetricColor == true ifTrue: [^ nil].
	^ self metricsByMode at: aSymbol ifAbsent: [nil]
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:52'
}
SWAView >> metricsByMode [
	"Map of minted menu symbol (e.g. #coverage_1_call) -> SWADatasetMetric. One entry
	per metric of every loaded dataset; the symbol-based color/size machinery
	dispatches through this."
	^ metricsByMode ifNil: [metricsByMode := Dictionary new]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAView >> mouseWheel: evt [
	"Wheel scrolls; CTRL-wheel (or CMD) zooms -- the convention everywhere else, and it
	keeps the two gestures from fighting. What zooming MEANS is the subclass's business
	(#wheelZoomBy:at:); by default it means nothing and the wheel just scrolls."
	| localY step up |
	(evt isWheelUp or: [evt isWheelDown]) ifFalse: [^ self].
	up := evt isWheelUp.
	localY := evt position y - self top.
	"EITHER modifier zooms. This VM's Alt/Ctrl/Command mapping is tangled (Alt arrives
	as command + blue button; see the 2026-07-23b journal), so insisting on control
	alone means the gesture silently does nothing on some keyboards. The zoom buttons
	exist for the same reason -- a modifier should never be the only way to reach a
	function."
	(evt controlKeyPressed or: [evt commandKeyPressed]) ifTrue: [
		^ self wheelZoomBy: (up ifTrue: [1.25] ifFalse: [0.8]) at: localY].
	"#verticalScrollDelta: converts the platform's scroll units into an increment for
	the notch size we ask for, and always answers a POSITIVE magnitude -- the direction
	comes from #isWheelUp. That is what makes a trackpad's fine-grained scrolling and a
	notched wheel both feel right."
	step := evt verticalScrollDelta: 60.
	self scrollBy: (up ifTrue: [step negated] ifFalse: [step])
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel [
	^ navPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAView >> navPanel: aSWAPane [
	"The chrome panel that owns my breadcrumb/selection/meta labels + source pane."
	navPanel := aSWAPane
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:41'
}
SWAView >> nodeEquivalentTo: aNode [
	aNode crossRefKey ifNotNil: [:key | ^ self keyIndex at: key ifAbsent: [nil]].
	(aNode isKindOf: SWACodeCategoryNode) ifTrue: [
		^ (self nodeEquivalentTo: aNode parent) ifNotNil: [:classNode |
			classNode children
				detect: [:each | (each isKindOf: SWACodeCategoryNode) and: [each name = aNode name]]
				ifNone: [nil]]].
	(self isPackageNode: aNode) ifTrue: [^ self nodeForFocus: (self focusForNode: aNode)].
	^ nil
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:41'
}
SWAView >> nodeForFocus: aFocus [
	aFocus key == #class ifTrue: [^ self keyIndex at: aFocus value ifAbsent: [nil]].
	rootNode withAllChildrenDo: [:each |
		((each isKindOf: SWACodePackageNode) or: [each isKindOf: SWACodeSubpackageNode])
			ifTrue: [(self focusForNode: each) = aFocus ifTrue: [^ each]]].
	^ nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> normalizeCommitInput: aString [
	"The fields show 'aae5930  the subject line', so an accepted value may be a whole
	label, a bare hash, or a keyword. Everything up to the first blank is the value."
	| text |
	text := aString ifNil: [''] ifNotNil: [:s | s asString withBlanksTrimmed].
	text isEmpty ifTrue: [^ nil].
	text := (text findTokens: ' ') first.
	text asUppercase = 'PARENT' ifTrue: [^ 'PARENT'].
	text asUppercase = 'HEAD' ifTrue: [^ 'HEAD'].
	^ text
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:04'
}
SWAView >> notifyCrossReferenceDependents [
	"A #peer dataset reads its weights live out of MY keyIndex, so every view
	registered against me is showing stale colours the moment my tree changes."

	| label |
	label := self navPanel ifNotNil: [:panel | panel crossRefMenuLabel].
	self crossReferenceDependents do: [:view |
		(view peerDatasetsOn: self) do: [:ds |
			ds refreshScales.
			label ifNotNil: [:text | ds name: text]].
		view flushCache].
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:39'
}
SWAView >> notifyCrossReferenceSelection [
	"Mirror my selection into the views cross-referenced with me, as THEIR secondary
	selection, so the same method is findable in both tools."

	| key |
	key := selectedNode ifNotNil: [:node | node crossRefKey].
	self crossReferenceLinkedViews do: [:view | view showForeignSelectionKey: key]
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWAView >> okToChange [
	"Unsaved edits in the Source flap: ask before the selection moves away from them."
	| source |
	source := navPanel ifNotNil: [:panel | panel sourceMorph].
	(source isNil or: [source canDiscardEdits]) ifTrue: [^ true].
	source promptForCancel: false.
	^ source canDiscardEdits
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:41'
}
SWAView >> opensSourceFlap [
	^ false
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:27'
}
SWAView >> peerDatasetsOn: aView [
	"My datasets that cross-reference aView."

	^ self datasets select: [:ds | ds kind == #peer and: [ds source peerView == aView]]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAView >> peerWeightForKey: aCrossRefKey [
	"What a view cross-referencing me reads for aCrossRefKey: my node's weight, or nil
	when I say nothing about it. Everything in my key index counts, because a view
	normally shows its whole tree; one that holds nodes it does NOT draw narrows this."

	aCrossRefKey ifNil: [^ nil].
	^ (self keyIndex at: aCrossRefKey ifAbsent: [nil])
		ifNotNil: [:node | node totalSize]
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:36'
}
SWAView >> peerWeightKeys [
	"The keys a peer may read from me -- see #peerWeightForKey:."

	^ self keyIndex keys
]

{
	#category : #coloring,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWAView >> popUpColorMenu [
	"Pop up the Color menu standalone (header 'Color' button). No-op if the view
	offers no color options."
	| menu |
	menu := self colorMenuMorph.
	self popUpMenu: menu
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWAView >> popUpMenu: aMenu [
	"Pop up aMenu at the hand position, as a CHILD -- never in the world.
	See SWAPane class>>popUp:at:in: for why."
	^ self popUpMenu: aMenu at: self currentHand position
]

{
	#category : #menus,
	#'squeak_changestamp' : 'MCPServer 7/31/2026 16:36'
}
SWAView >> popUpMenu: aMenu at: aPoint [
	"Route the pop-up through the owning pane, so it is hosted by whatever that pane
	declares as its #dialogHost and gets the XR panel refresh. Falls back to this
	view itself when the view is used bare, without a pane around it."
	^ navPanel
		ifNil: [SWAPane popUp: aMenu at: aPoint in: self]
		ifNotNil: [:pane | pane popUpMenu: aMenu at: aPoint]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> priorSourceFor: aNode [
	"aNode's source as it was before the range being shown, or nil. The live image shows
	source, not a diff, so it can be edited."
	| key |
	(priorSources isNil or: [aNode isNil]) ifTrue: [^ nil].
	self showsGitRange ifFalse: [^ nil].
	key := [aNode crossRefKey] on: Error do: [:e | nil].
	key ifNil: [^ nil].
	^ priorSources at: key ifAbsent: [nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> priorSourceForSelection [
	^ self priorSourceFor: selectedNode
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> priorSources: aDictionary [
	"crossRefKey -> the source as it was before the range being shown. Makes the Show
	pane display a diff rather than just the current source."

	priorSources := aDictionary
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> provenanceListForSelection [
	"For the covering-tests side pane. Returns an Array of associations
	displayLabel -> crossRefKey describing the current selection's provenance under
	a SWACoverageData overlay:
	 - a covered application method -> the tests (and TestCase classes) that cover it;
	 - a test method / TestCase class -> the methods it covers;
	 - otherwise -> empty.
	The key lets the panel navigate the treemap to the clicked entry."
	| key |
	coverageData ifNil: [^ #()].
	selectedNode ifNil: [^ #()].
	key := selectedNode crossRefKey.
	key ifNil: [^ #()].
	(self isTestKey: key) ifTrue: [
		^ (coverageData methodsForTestOrClass: key) asSortedCollection asArray
			collect: [:m | m -> m]].
	(selectedNode kind == #method and: [coverageData isCovered: key]) ifTrue: [
		| tests classes entries |
		tests := coverageData testsForMethod: key.
		classes := coverageData testClassesForMethod: key.
		entries := OrderedCollection new.
		classes asSortedCollection do: [:c | entries add: ('[', c, ']') -> c].
		tests asSortedCollection do: [:t | entries add: ('   ', t) -> t].
		^ entries asArray].
	^ #()
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> provenanceListTitle [
	"A short heading for the covering-tests side pane describing what it lists for
	the current selection."
	| key |
	(coverageData isNil or: [selectedNode isNil]) ifTrue: [^ 'Coverage'].
	key := selectedNode crossRefKey.
	key ifNil: [^ 'Coverage'].
	(self isTestKey: key) ifTrue: [
		^ 'Covers ', (coverageData methodsForTestOrClass: key) size printString, ' methods'].
	(selectedNode kind == #method and: [coverageData isCovered: key]) ifTrue: [
		^ 'Covered by ', (coverageData coveringTestCountFor: key) printString, ' tests'].
	^ 'Coverage'
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> rangeView [
	^ rangeView ifNil: [#live]
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> rangeView: aSymbol [
	"#full and #changes show the loaded range on the tree built from git, #live the image."
	(aSymbol ~~ #live and: [snapshotRoot isNil]) ifTrue: [^ self].
	rangeView := aSymbol.
	gitStatusCache := nil.
	self installRoot: (aSymbol == #live
		ifTrue: [liveRoot ifNil: [rootNode]]
		ifFalse: [snapshotRoot]).
	self rangeViewChanged.
	self updateRangeViewButtons.
	self updateWindowLabel.
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> rangeViewButtonsFor: aPane [
	| buttons |
	rangeViewButtons := Dictionary new.
	buttons := #(#(#full 'Full picture') #(#changes 'Changes only') #(#live 'Live image'))
		collect: [:pair | | button |
			button := (aPane buttonLabelled: pair second action: #rangeView:)
				target: self;
				arguments: {pair first};
				yourself.
			rangeViewButtons at: pair first put: button.
			button].
	self updateRangeViewButtons.
	^ buttons
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> rangeViewChanged [
	self flushCache.
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rebuildEffectiveWeights [
	"Roll the foreign highlightWeights up the tree so a class/package tile lights
	up when any contained method matched. Each node's effective weight is the MAX
	of its own match and its children's effective weights."
	effectiveWeights := IdentityDictionary new.
	(highlightWeights isNil or: [rootNode isNil]) ifTrue: [^ effectiveWeights].
	self effectiveWeightOf: rootNode.
	^ effectiveWeights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:27'
}
SWAView >> rebuildKeyIndex [
	"(Re)build the crossRefKey -> node index by walking the whole tree. On key
	collisions keep the largest-totalSize node so lookups land on the most
	significant tile/frame.

	Only a REbuild notifies the views cross-referencing me: #keyIndex builds the
	index lazily, and notifying from there would flush a peer's pixels in the middle
	of the very draw that asked for the weights."
	| wasBuilt |
	wasBuilt := keyIndex notNil.
	keyIndex := Dictionary new.
	rootNode ifNil: [
		wasBuilt ifTrue: [self notifyCrossReferenceDependents].
		^ keyIndex].
	rootNode withAllChildrenDo: [:n | | k existing |
		k := n crossRefKey.
		k ifNotNil: [
			existing := keyIndex at: k ifAbsent: [nil].
			(existing isNil or: [n totalSize > existing totalSize])
				ifTrue: [keyIndex at: k put: n]]].
	wasBuilt ifTrue: [self notifyCrossReferenceDependents].
	^ keyIndex
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> rebuildSearchMatches [
	"Build the IdentitySet of nodes to keep BRIGHT for the current searchQuery: every
	node whose #name contains the query (case-insensitive), plus all of that node's
	ancestors up to the root, so a container tile stays lit when anything inside it
	matches and the path down to a leaf hit is never dimmed."
	searchMatchSet := IdentitySet new.
	(searchQuery isNil or: [rootNode isNil]) ifTrue: [^ searchMatchSet].
	rootNode withAllChildrenDo: [:n | | nm |
		nm := n name ifNil: [''].
		(nm asLowercase includesSubstring: searchQuery) ifTrue: [
			| a |
			a := n.
			[a notNil and: [(searchMatchSet includes: a) not]] whileTrue: [
				searchMatchSet add: a.
				a := a parent]]].
	^ searchMatchSet
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> recentCommits [
	"The newest commits of the current repository as value -> menu label: short hash
	-> the git log --oneline line. Capped, since this feeds a pop-up menu."
	| repoHistory ancestry |
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ #()].
	ancestry := [repoHistory newestCommits: SWAGitHistory defaultMaxCommits] on: Error do: [:e | #()].
	ancestry ifNil: [^ #()].

	^ ancestry collect: [:commit |
		([commit hexHash first: 7] on: Error do: [:e | '???????'])
			-> (repoHistory commitLabelFor: commit)]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> refreshDataPanel [
	"Reload the Data flap's fields from me, after I changed them myself."
	navPanel ifNotNil: [:panel | panel refreshDataPanel]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> reloadFromGit [
	"Re-diff and rebuild, answering whether it loaded. A range that does not resolve
	leaves the current diagram standing: the fields are edited live, so a half-typed
	hash must not wipe the screen."
	self loadGitRange ifFalse: [^ false].
	self updateWindowLabel.
	^ true
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:05'
}
SWAView >> removeCrossReferenceDependent: aView [
	crossRefDependents ifNil: [^ self].
	crossRefDependents remove: aView ifAbsent: [].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> reportProblem: aString [
	"Say why the range did not load, without a modal dialog -- the fields are edited
	live, and a dialog would block the pane that owns them."
	navPanel
		ifNil: [Transcript cr; show: self viewKindLabel, ': ', aString]
		ifNotNil: [:panel | panel showMessage: aString]
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView >> reportReviewedChanges [
	"Sign-offs follow the text, so a range can arrive partly reviewed already."
	| changed reviewed |
	changed := 0.
	reviewed := 0.
	(gitChanges at: #kinds) keysDo: [:key |
		(self keyIndex at: key ifAbsent: [nil]) ifNotNil: [:node |
			changed := changed + 1.
			(self isNodeReviewed: node) ifTrue: [reviewed := reviewed + 1]]].
	navPanel ifNotNil: [:panel |
		panel showMessage: reviewed printString, ' of ', changed printString, ' changes already reviewed'].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> repositoryChoices [
	"value -> menu label for the Repository drop-down: every git working copy the
	image has open."
	^ SWAGitHistory workingCopies collect: [:wc |
		| name |
		name := [wc name] on: Error do: [:e | '?'].
		name -> name]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> repositoryName [
	^ repositoryName
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> repositoryName: aString [
	"Switching repository invalidates the range: hashes are repository-local, so the
	old ones would not resolve. The new range defaults to what the newest commit
	changed."
	| name |
	name := aString ifNil: [''] ifNotNil: [:s | s asString withBlanksTrimmed].
	name = repositoryName ifTrue: [^ self].
	self tryRange: [
		repositoryName := name.
		self resetRangeToNewestCommit]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> resetRangeToNewestCommit [
	"Point the range at what the newest commit changed. Said symbolically, so it needs
	no git walk here and stays right as the branch grows."
	fromCommit := 'PARENT'.
	toCommit := nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> resolvedFromCommit [
	"The hash the range starts at. PARENT means the first parent of the TO end, which
	is what makes stepping To down the log show one commit at a time."
	| repoHistory target |
	fromCommit ifNil: [^ nil].
	self isParentFrom ifFalse: [^ self hashOf: fromCommit].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ nil].
	target := toCommit
		ifNil: [[repoHistory workingCopy headCommit] on: Error do: [:e | nil]]
		ifNotNil: [:name | repoHistory commitNamed: name].
	target ifNil: [^ nil].
	^ [target firstParent hexHash first: 7] on: Error do: [:e | nil]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> resolvedToCommit [
	"The hash the range ends at. The field may say HEAD or a branch, which move."
	| repoHistory |
	toCommit ifNotNil: [^ self hashOf: toCommit].
	repoHistory := self gitHistory.
	repoHistory ifNil: [^ nil].
	^ [repoHistory workingCopy headCommit hexHash first: 7] on: Error do: [:e | nil]
]

{
	#category : #selection,
	#'squeak_changestamp' : 'MCPServer 9/22/2026 15:21'
}
SWAView >> revealPackageNode: aNode [
	"A row in the pane's Packages list was clicked. What that should do is the view's
	business -- the treemap drills in, a diagram or a graph may have nowhere to go --
	so the default is to do nothing."
	^ self
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:18'
}
SWAView >> reviewHashFor: aNode [
	^ self class reviewHashOf: (self reviewTextFor: aNode)
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> reviewKeyFor: aNode [
	"A sign-off belongs to what was read: the member plus a hash of its text. It holds
	in any range, on any branch and in the image wherever the member reads the same,
	and lapses when it changes."
	| key |
	aNode ifNil: [^ nil].
	key := aNode markKey.
	key ifNil: [^ nil].
	^ key, ' @', (self reviewHashFor: aNode)
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> reviewScope [
	^ reviewScope
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> reviewScope: aStringOrNil [
	"Names the commit range this diagram shows, e.g. 'SqueakXRNative 2269a69..399beef'.
	A review mark is only meaningful together with the version reviewed, so the scope
	becomes part of the reviewed key. nil switches the review badges off."
	reviewScope := aStringOrNil.
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> reviewTextFor: aNode [
	"The member as this view shows it. A removal is reviewed as the text that went."
	| key |
	key := aNode markKey.
	(self gitKindAt: key) == #removed ifTrue: [
		^ '(removed) ', (priorSources ifNil: [''] ifNotNil: [:sources | sources at: key ifAbsent: ['']])].
	(aNode isKindOf: SWACodeMethodNode) ifTrue: [^ aNode source].
	(aNode isKindOf: SWACodeClassNode) ifTrue: [^ self definitionTextOf: aNode theClass].
	^ ''
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rootNode [
	^ rootNode
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWAView >> save: aString of: aNode notifying: aRequestor [
	"Answer the crossRefKey of what was saved, nil when it did not compile."
	| class selector |
	(aNode isKindOf: SWACodeCommentNode) ifTrue: [
		aNode subject theNonMetaClass classComment: aString stamp: Utilities changeStamp.
		^ aNode crossRefKey].
	(aNode isKindOf: SWACodeClassNode) ifTrue: [
		class := Compiler evaluate: aString notifying: aRequestor logged: true.
		^ (class isKindOf: Behavior) ifTrue: [class name asString] ifFalse: [nil]].
	class := aNode subject actualClass.
	selector := class compile: aString classified: aNode subject category notifying: aRequestor.
	^ selector ifNotNil: [class name asString, '>>', selector]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollBarTrackRect [
	"The scrollbar gutter, in GLOBAL coordinates, spanning the scrollable area only."
	^ (self right - self scrollBarWidth) @ self scrollViewportTop
		corner: self right @ (self scrollViewportTop + self scrollViewportHeight)
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollBarWidth [
	"Wide enough to hit. The 4px indicator this replaced was undraggable in practice
	even before it was undraggable in principle."
	^ 12
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollBy: aNumber [
	self scrollTo: (scrollY ifNil: [0]) + aNumber
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollChanged [
	"Hook: the scroll position moved. Views that draw straight to the canvas (the flow)
	need nothing; views that blit a CACHED FORM (the temporal ones) must drop it, or
	they scroll by redrawing the same picture."
	^ self
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollHome [
	self scrollTo: 0
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollTo: aNumber [
	| max |
	self ensureLayout.
	max := (contentHeight ifNil: [0]) - self scrollViewportHeight max: 0.
	"ROUNDED: the thumb maps a pixel to a Fraction of the content, and letting that
	through makes scrollY a Fraction that then propagates into every row rectangle --
	exact, slower, and pointless when the destination is a pixel grid."
	scrollY := ((aNumber max: 0) min: max) rounded.
	self scrollChanged.
	self changed
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollToThumbTop: aGlobalY [
	"Inverse of #thumbRect: given where the thumb's TOP should be, answer the scroll
	position that puts it there."
	| track h span |
	self isScrollable ifFalse: [^ self].
	track := self scrollBarTrackRect.
	h := ((track height * self scrollViewportHeight / contentHeight) max: 24) min: track height.
	span := contentHeight - self scrollViewportHeight.
	(track height - h) <= 0 ifTrue: [^ self scrollTo: 0].
	self scrollTo: (aGlobalY - track top) * span / (track height - h)
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollViewportHeight [
	"Height of the scrollable area -- what #contentHeight is compared against and what
	one page means. My whole height, unless a subclass pins chrome above or below it."
	^ self height
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> scrollViewportTop [
	"GLOBAL y of the top of the scrollable area. My whole top edge, unless a subclass
	keeps something pinned up there -- SWATraceMorph's continuous bands do not scroll."
	^ self top
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> searchFor: aStringOrNil [
	"Set the name-search filter. A node MATCHES when aString (case-insensitive) is a
	substring of its #name; matching nodes AND all their ancestors stay bright, every
	other tile dims (see #searchMatches:). Empty/nil clears the filter. Recomputes the
	kept-node set, flushes the render cache and redraws."
	| q |
	q := (aStringOrNil ifNil: ['']) asString withBlanksTrimmed.
	q isEmpty
		ifTrue: [searchQuery := nil. searchMatchSet := nil]
		ifFalse: [searchQuery := q asLowercase. self rebuildSearchMatches].
	self flushCache.
	self changed
]

{
	#category : #search,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:03'
}
SWAView >> searchQuery [
	"The active lowercase name-search string, or nil when no search is running."
	^ searchQuery
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWAView >> secondarySelection [
	"A SECONDARY selection node (or nil), distinct from the primary #selectedNode.
	Drawn with a RED border (vs the primary's white). General mechanism: a view can
	use it for any 'compare against' / 'related-to' relationship -- the duplication
	view uses it for the near-duplicate currently being diffed against the primary
	selection."
	^ secondarySelection
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 12:59'
}
SWAView >> secondarySelection: aNodeOrNil [
	"Set the secondary selection and refresh chrome so its red border and any
	dependent panes update."
	secondarySelection := aNodeOrNil.
	self refreshChrome
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> selectDataset: aSWADatasetOrNil [
	"Top-level Data pick (exclusive): make aSWADataset the active data source and bind
	the COLOR axis to its fitting default color metric (or restore intrinsic color when
	nil). This base version handles only color -- the axis every SWA view has. Tools
	with size/decoration axes (the Code Map) override to also apply those, calling
	super for the color + activeDataset bookkeeping."
	| colorMetric |
	activeDataset := aSWADatasetOrNil.
	aSWADatasetOrNil isNil ifTrue: [^ self applyColorMetricSymbol: nil].
	colorMetric := aSWADatasetOrNil defaultBindings at: #color ifAbsent: [nil].
	self applyColorMetricSymbol: (colorMetric ifNotNil: [:m | m modeSymbol])
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 13:57'
}
SWAView >> selectNodeForKey: aCrossRefKey [
	"Navigate to and select the node with the given crossRefKey (from the covering-
	tests pane). No-op if not found. Zooms out to a node that contains it if it is
	not under the current focus, so the tile becomes visible."
	| node |
	aCrossRefKey ifNil: [^ self].
	node := self keyIndex at: aCrossRefKey ifAbsent: [^ self].
	self selectedNode: node
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> selectedNode [
	"The currently selected node (single-click), or nil."
	^ selectedNode
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:42'
}
SWAView >> selectedNode: aNodeOrNil [
	"Set the selected node and refresh the chrome.

	This lived only on SWATreemapMorph, but #selectNodeForKey: -- the cross-view
	navigation every view is supposed to answer -- sends it unconditionally. So
	cross-referencing INTO a flamegraph, timeline, calendar or trace raised a DNU
	instead of selecting anything (visible in the image as
	'MessageNotUnderstood: SWATimelineMorph>>selectedNode:'). The generic behaviour
	belongs here; the treemap's override adds its provenance-filter side effect on
	top."
	selectedNode := aNodeOrNil.
	self flushCache.
	self refreshChrome.
	self notifyCrossReferenceSelection
]

{
	#category : #datasets,
	#'squeak_changestamp' : 'MCPServer 7/3/2026 11:53'
}
SWAView >> setDataMode: aSymbol [
	"Data-menu entry point: pick the active data source by its symbol (#none clears),
	applying its fitting defaults across the axes."
	self selectDataset: (self datasetForDataMode: aSymbol)
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> setRepository: aRepositoryName from: aHexPrefix to: aHexPrefixOrNil [
	"Install the range WITHOUT loading -- the individual setters each reload, which is
	right when a field is edited and wrong while all three are being installed."
	repositoryName := aRepositoryName.
	fromCommit := aHexPrefix.
	toCommit := aHexPrefixOrNil
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> shareDatasetsOf: aView [
	"The same dataset objects, under the same mode symbols: re-minting a symbol would
	change it under aView too, whose colour menu still names the old one. A dataset
	generated here for a symbol aView also uses gives way to aView's."
	aView datasets do: [:each |
		(self datasets includes: each) ifFalse: [
			(self datasets select: [:own |
				own metrics anySatisfy: [:metric |
					each metrics anySatisfy: [:theirs | theirs modeSymbol == metric modeSymbol]]])
				do: [:own | self forgetDataset: own].
			self datasets addLast: each.
			each metrics do: [:metric | self metricsByMode at: metric modeSymbol put: metric]]].
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:40'
}
SWAView >> showCoverage: aCoverage [
	"Overlay a SWACoverage result (its 'Class>>selector' -> value map) using the
	green coverage ramp, with the usual max class-rollup. Pass nil to clear.
	This overlay has no test<->method provenance, so no blue test tinting."
	testKeys := nil. testFilterKeys := nil. coveringTestFilter := nil.
	aCoverage ifNil: [coverageKind := nil. coverageData := nil. ^ self highlightWeights: nil].
	highlightStyle := #coverage.
	coverageData := nil.
	coverageKind := aCoverage kind.
	self highlightWeights: aCoverage resultMap
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:02'
}
SWAView >> showCoverageData: aCoverageData [
	"Overlay a SWACoverageData graded by COVERING-TEST count (the default metric).
	See #showCoverageData:weightMode: for the invocation-count metric."
	^ self showCoverageData: aCoverageData weightMode: #tests
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:22'
}
SWAView >> showCoverageData: aCoverageData weightMode: aWeightMode [
	"Overlay a SWACoverageData: covered application methods are tinted green graded
	by the chosen metric -- #tests (covering-test count) or #invocations (raw call
	count) -- and executed test methods / TestCase classes are tinted BLUE. So the
	overlay VALUES (tint + the coverage-value shown in the header/details) match the
	tile SIZING when the view is coverage-weighted. #invocations silently falls back
	to test count if the data carries no invocation counts. Pass nil data to clear.

	Also pushes the data onto the ROOT NODE (when it understands #coverageData:), so
	the #invocations/#tests SIZE metrics actually have weights to lay out -- without
	this the 'Load' path tinted tiles but every coverage weight rolled up to 0,
	collapsing those size metrics to an empty map."
	| useInvocations |
	testFilterKeys := nil. coveringTestFilter := nil.
	aCoverageData ifNil: [
		coverageData := nil. coverageKind := nil. testKeys := nil.
		(rootNode respondsTo: #coverageData:) ifTrue: [rootNode coverageData: nil].
		^ self highlightWeights: nil].
	coverageData := aCoverageData.
	coverageKind := #tally.   "graded green by the chosen count"
	highlightStyle := #coverage.
	testKeys := aCoverageData testKeySet , aCoverageData testClassNameSet.
	(rootNode respondsTo: #coverageData:) ifTrue: [
		rootNode coverageData: aCoverageData.
		(rootNode respondsTo: #coverageWeightMode:) ifTrue: [
			rootNode coverageWeightMode: aWeightMode]].
	useInvocations := aWeightMode == #invocations and: [aCoverageData hasInvocationData].
	self highlightWeights: (useInvocations
		ifTrue: [aCoverageData invocationMap]
		ifFalse: [aCoverageData resultMap])
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 18:39'
}
SWAView >> showForeignSelectionKey: aCrossRefKeyOrNil [
	"Show what a cross-referenced view has selected, using this view's secondary
	(red) selection. A key I have no node for CLEARS the mark rather than leaving a
	stale one pointing at the previous selection."

	| node |
	node := aCrossRefKeyOrNil ifNotNil: [:key | self keyIndex at: key ifAbsent: [nil]].
	node == self secondarySelection ifTrue: [^ self].
	self secondarySelection: node.
	self changed.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> showGitChanges: aDictionary [
	"Show a loaded range, see #changesForRepository:from:to: for the keys. The prior
	sources and the review scope are already in place."
	self subclassResponsibility.
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> showRangeTree: aDictionary [
	"The range gets a tree of its own, built from git, so it can show what the image
	no longer has. The image's tree is kept for #live."
	(rootNode notNil and: [self rangeView == #live]) ifTrue: [liveRoot := rootNode].
	liveRoot ifNil: [liveRoot := rootNode].
	(snapshotRoot isNil or: [snapshotRoot snapshot ~~ (aDictionary at: #snapshot)]) ifTrue: [
		snapshotRoot := SWACodeSnapshotRootNode new
			snapshot: (aDictionary at: #snapshot);
			name: liveRoot displayName;
			addPackages: liveRoot packageNames;
			yourself.
		snapshotRoot children isEmpty ifTrue: [
			self reportProblem: 'none of this view''s packages are in ', repositoryName]].
	self rangeView: (self rangeView == #live ifTrue: [#full] ifFalse: [self rangeView]).
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> showsChangesOnly [
	^ self rangeView == #changes
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> showsGitRange [
	^ gitChanges notNil and: [self rangeView ~~ #live]
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> snapshotRoot [
	^ snapshotRoot
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWAView >> sourceChangedUnder: aNode [
	"Rebuild aNode's children from the image, so a new selector gets a node, and drop
	the sizes cached above them."
	| node |
	aNode ifNil: [^ self].
	aNode forgetChildren.
	node := aNode.
	[node notNil] whileTrue: [
		(node respondsTo: #flushAllRollups) ifTrue: [node flushAllRollups].
		node := node parent].
	self codeChanged.
	navPanel ifNotNil: [:panel | panel codeChangedBy: self].
]

{
	#category : #editing,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:59'
}
SWAView >> sourceFlapText [
	^ ((self respondsTo: #selectedSourceString) ifTrue: [self selectedSourceString]) ifNil: ['']
]

{
	#category : #structure,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 15:54'
}
SWAView >> structureLabel [
	"Name for THIS view in the Tree menu / window title. Overridden per view; the
	default keeps the historical 'Code map' wording for the code treemap."
	^ 'Code map'
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> styleClassForDiff [
	^ self styleClassForDiffOf: selectedNode
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> styleClassForDiffOf: aNode [
	^ [aNode styleClassOrNil ifNotNil: [:class |
		(class respondsTo: #liveClass) ifTrue: [class liveClass] ifFalse: [class]]]
			on: Error do: [:e | nil]
]

{
	#category : #styling,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:05'
}
SWAView >> styleClassForSelection [
	"The class/metaclass context for Shout styling of the selected node's source,
	or nil. Prefers #styleClassOrNil (code + treemap nodes); falls back to the first
	element of #methodReference (sampling-tally flamegraph frames)."
	selectedNode ifNil: [^ nil].
	"No class while a diff is on show: Shout restyles the whole pane from the source
	text and would overwrite the insert/remove attributes TextDiffBuilder put there."
	self priorSourceForSelection ifNotNil: [^ nil].
	(selectedNode respondsTo: #styleClassOrNil)
		ifTrue: [^ selectedNode styleClassOrNil ifNotNil: [:class |
			(class respondsTo: #liveClass) ifTrue: [class liveClass] ifFalse: [class]]].
	(selectedNode respondsTo: #methodReference)
		ifTrue: [^ selectedNode methodReference ifNotNil: [:ref | ref first]].
	^ nil
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> supportsGitRange [
	^ false
]

{
	#category : #'event handling',
	#'squeak_changestamp' : 'MCPServer 7/3/2026 14:18'
}
SWAView >> takeKeyboardFocusFrom: evt [
	"Grab keyboard focus so the Ctrl+F search shortcut reaches this view. Called from
	subclass #mouseDown: (clicking the map is a natural point to take focus)."
	evt hand newKeyboardFocus: self
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAView >> takeOverFrom: aView [
	"Show what aView showed: its commit range and review scope, its root and zoom, its
	datasets, its colour layer when that is a shared dataset, and its selection."
	self gitRangeState: aView gitRangeState.
	self takeOverRootFrom: aView.
	self focusOn: aView currentFocus.
	self shareDatasetsOf: aView.
	(aView colorMode notNil and: [(self metricForMode: aView colorMode) notNil])
		ifTrue: [self colorMode: aView colorMode].
	aView selectedNode ifNotNil: [:node | self selectNodeForKey: node crossRefKey].
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> takeOverRangeRootsFrom: aView [
	"A package root from aView becomes the live tree. A diagram of a range has none, so
	a view made from it gets one over the packages the range was loaded for. A tree
	aView built from the same commits is shared, and so is how it was shown."
	(self isLiveCodeRoot: aView unfocusedRoot) ifTrue: [
		liveRoot := aView unfocusedRoot.
		self rangeView == #live ifTrue: [self installRoot: liveRoot]].
	aView liveRoot ifNotNil: [:root | liveRoot := root].
	liveRoot ifNil: [
		liveRoot := (aView showsGitRange and: [aView gitChanges notNil])
			ifTrue: [SWACodeRootNode new
				name: repositoryName;
				addPackages: ((aView gitChanges at: #snapshot) packages collect: [:each | each packageName]);
				yourself]
			ifFalse: [aView unfocusedRoot]].
	aView showsGitRange ifFalse: [^ self rangeView: #live].
	(aView snapshotRoot notNil and: [aView snapshotRoot snapshot == (gitChanges at: #snapshot)])
		ifTrue: [snapshotRoot := aView snapshotRoot].
	aView rangeView == #live ifFalse: [rangeView := aView rangeView].
	self showRangeTree: gitChanges.
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:41'
}
SWAView >> takeOverRootFrom: aView [
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> testColorForNode: aNode [
	"Blue tint for an executed test method or TestCase class tile.
	 - With a test selected (testFilterKeys set): the selected test/class is bright,
	   the others dimmed.
	 - With a covered application method selected (coveringTestFilter set): tests
	   that covered it are bright, the others dimmed.
	 - Otherwise: plain blue."
	| key selectedKey |
	key := aNode crossRefKey.
	coveringTestFilter notNil ifTrue: [
		^ (coveringTestFilter includes: key)
			ifTrue: [Color h: 210.0 s: 0.85 v: 0.95]
			ifFalse: [Color h: 210.0 s: 0.35 v: 0.45]].
	selectedKey := selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey].
	(testFilterKeys notNil and: [key = selectedKey])
		ifTrue: [^ Color h: 210.0 s: 0.85 v: 0.95].
	testFilterKeys notNil ifTrue: [^ Color h: 210.0 s: 0.35 v: 0.45].
	^ Color h: 210.0 s: 0.6 v: 0.85
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:23'
}
SWAView >> testFilterKeys [
	"The set of method crossRefKeys the green highlight is currently restricted to
	(because a test/TestCase is selected), or nil for 'show all covered methods'."
	^ testFilterKeys
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:24'
}
SWAView >> thumbRect [
	"Thumb geometry, in GLOBAL coordinates, and the single source of truth for both
	drawing and hit testing -- drawing one rectangle and hit-testing another is how a
	scrollbar ends up looking right and feeling wrong."
	| track h span top |
	self isScrollable ifFalse: [^ nil].
	track := self scrollBarTrackRect.
	"Integer arithmetic throughout, for the same reason as the rows: a Fraction
	rectangle does not blit."
	h := ((track height * self scrollViewportHeight // contentHeight) max: 24) min: track height.
	span := contentHeight - self scrollViewportHeight.
	top := track top + ((track height - h) * (scrollY ifNil: [0]) // span).
	^ track left @ top extent: track width @ h
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> toCommit [
	"nil means the head commit."
	^ toCommit
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> toCommit: aString [
	"HEAD is a position, not a commit: the diff API spells it nil."
	| value |
	value := self normalizeCommitInput: aString.
	(value notNil and: [value = 'HEAD']) ifTrue: [value := nil].
	value = toCommit ifTrue: [^ self].
	self tryRange: [toCommit := value]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:03'
}
SWAView >> toCommitChoices [
	"HEAD leads the list: reviewing up to the tip is the common case, and it stays
	right as the branch grows."
	^ (OrderedCollection with: 'HEAD' -> 'HEAD (checked-out tip)'),
		self branchChoices, self recentCommits
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> toCommitLabel [
	"What the To field shows. The head commit has a name rather than a blank."
	toCommit ifNil: [^ 'HEAD'].
	^ self commitLabelFor: toCommit
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:10'
}
SWAView >> toggleMark: aNode [
	"Toggle aNode in/out of the global mark set (shift-click / menu). No-op for
	unmarkable nodes (markKey nil). When a mark is newly ADDED, a serializable provenance
	snapshot is recorded: the VIEW context (#markProvenance) plus the NODE kind
	(#nodeKind -- class / package / method / space-tally node / ...) so the mark
	remembers what its markKey points at. The mark set notifies all open panes, which
	flush this view's marks cache and repaint."
	| prov |
	aNode ifNil: [^ self].
	aNode markKey ifNil: [^ self].
	prov := self markProvenance.
	prov at: 'nodeKind' put: aNode nodeKind asString.
	SWAMarkSet default toggle: aNode markKey from: prov
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> toggleReviewed: aNode [
	"Sign aNode off, or take the sign-off back."
	| key provenance |
	key := self reviewKeyFor: aNode.
	key ifNil: [^ self].
	provenance := self markProvenance.
	provenance at: 'nodeKind' put: aNode nodeKind asString.
	provenance at: 'reviewedAt' put: DateAndTime now printString.
	reviewScope ifNotNil: [provenance at: 'reviewScope' put: reviewScope].
	(self lastChangeOf: aNode) ifNotNil: [:info | provenance addAll: info].
	SWAMarkSet reviewed toggle: key from: provenance.
	self updateReviewMarkers.
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> toggleReviewedAllUnder: aNode [
	"Sign off every change under aNode, or take them all back once all are signed off."
	| changed reviewing |
	changed := OrderedCollection new.
	aNode withAllChildrenDo: [:each |
		(self gitKindOf: each) ifNotNil: [:kind | changed add: each]].
	reviewing := changed anySatisfy: [:each | (self isNodeReviewed: each) not].
	changed do: [:each |
		(self isNodeReviewed: each) = reviewing ifFalse: [self toggleReviewed: each]].
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> toggleReviewedShownUnder: aNode [
	"What is shown for aNode when that changed itself, else every change under it."
	(self gitKindOf: aNode) ifNotNil: [:kind | ^ self toggleReviewed: aNode].
	self toggleReviewedAllUnder: aNode.
]

{
	#category : #review,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 14:17'
}
SWAView >> toggleReviewedUnder: aNode [
	self toggleReviewed: aNode.
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:49'
}
SWAView >> tryRange: aBlock [
	"Apply a range change, undoing it when the new range does not load. The fields have
	to describe the picture on screen, and a hash that resolves to nothing would
	otherwise leave them claiming a range the view is not of."
	| snapshot |
	snapshot := { repositoryName. fromCommit. toCommit }.
	aBlock value.
	self reloadFromGit ifFalse: [
		repositoryName := snapshot first.
		fromCommit := snapshot second.
		toCommit := snapshot third].
	self refreshDataPanel
]

{
	#category : #switching,
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 13:50'
}
SWAView >> unfocusedRoot [
	^ rootNode
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/22/2026 19:05'
}
SWAView >> unregisterCrossReferenceLinks [
	"Drop out of every source I read. Sent when my pane closes: the registry is weak,
	but a source should not carry a dead view until the next garbage collect."

	self crossReferenceSources do: [:view | view removeCrossReferenceDependent: self].
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> updateRangeViewButtons [
	rangeViewButtons ifNil: [^ self].
	rangeViewButtons keysAndValuesDo: [:view :button |
		button color: (view == self rangeView
			ifTrue: [Color h: 210 s: 0.6 v: 0.7]
			ifFalse: [Color gray: 0.3])].
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 15:39'
}
SWAView >> updateReviewMarkers [
	gitStatusCache := nil.
	self flushCache.
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/25/2026 12:27'
}
SWAView >> updateTestFilterForSelection [
	"Called after the selection changes (no-op without a provenance overlay):
	 - select a test / TestCase -> green-filter to the methods it covers;
	 - select a covered application method -> blue-filter to the tests that
	   covered it (and their TestCase classes);
	 - select anything else -> drop both filters."
	| key |
	coverageData ifNil: [^ self].
	key := selectedNode ifNil: [nil] ifNotNil: [:n | n crossRefKey].
	(self isTestKey: key) ifTrue: [
		coveringTestFilter := nil.
		^ self filterToTestKey: key].
	(key notNil and: [selectedNode kind == #method and: [coverageData isCovered: key]]) ifTrue: [
		testFilterKeys := nil.
		^ self filterToCoveredMethodKey: key].
	(testFilterKeys notNil or: [coveringTestFilter notNil]) ifTrue: [
		self clearTestFilters]
]

{
	#category : #'git range',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 12:48'
}
SWAView >> updateWindowLabel [
	"Keep the window title on the range actually shown."
	navPanel ifNil: [^ self].
	navPanel enclosingWindow ifNotNil: [:window | window setLabel: self gitRangeLabel]
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:00'
}
SWAView >> viewKind [
	"A machine-readable Symbol identifying THIS kind of visualization -- the thing we
	dispatch on (respawn, pane matching, filtering). E.g. #codeMap, #spaceTally,
	#classDiagram. Subclasses override. The default derives one from the class name by
	stripping the 'SWA' prefix and 'Morph' suffix and lowercasing the first letter, so an
	un-overridden view still has a stable non-nil kind. Kept distinct from the display
	string #viewKindLabel."
	| n |
	n := self class name asString.
	(n beginsWith: 'SWA') ifTrue: [n := n allButFirst: 3].
	(n endsWith: 'Morph') ifTrue: [n := n allButLast: 5].
	n isEmpty ifTrue: [^ #view].
	^ (n first asLowercase asString, n allButFirst) asSymbol
]

{
	#category : #marks,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:00'
}
SWAView >> viewKindLabel [
	"A short, human-readable name for THIS kind of visualization, shown in the Marks
	details pane (e.g. 'Code Map', 'Space Tally', 'Duplication'). Derived from #viewKind
	via #viewKindLabelFor: so the machine-readable symbol stays the single source of
	truth; override #viewKind (not this) in subclasses."
	^ self class viewKindLabelFor: self viewKind
]

{
	#category : #'range view',
	#'squeak_changestamp' : 'MCPServer (MCPServer) 10/23/2026 16:40'
}
SWAView >> visibleChildrenOf: aNode [
	"Changes only keeps what the range changed, a search what matches it."
	^ (aNode children ifNil: [#()]) select: [:each |
		(self showsChangesOnly not or: [(self gitStatusOf: each) notNil])
			and: [(self isSearchDimmed: each) not]]
]

{
	#category : #scrolling,
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:25'
}
SWAView >> wheelZoomBy: aFactor at: localY [
	"CTRL-wheel. No-op unless a subclass has something to zoom."
	^ self
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 8/4/2026 11:34'
}
SWAView >> withoutMetricColorDo: aBlock [
	"Evaluate aBlock with dataset-metric colour lookup disabled, so
	#baseColorForNode: answers the view's own structural colour. Re-entrant-safe via
	save/restore, and #ensure:d so an error cannot strand the flag and leave every
	tile permanently intrinsic."
	| saved |
	saved := suppressMetricColor.
	suppressMetricColor := true.
	^ aBlock ensure: [suppressMetricColor := saved]
]

{
	#category : #'zoom bar',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 19:28'
}
SWAView >> zoomBarRightInset [
	"Pixels to keep clear at my right edge when parking the zoom bar: the scrollbar
	gutter, when there is one. Asked of #isScrollable rather than hardcoded per view,
	so a view that only sometimes scrolls does not permanently reserve the space."
	^ self isScrollable ifTrue: [self scrollBarWidth] ifFalse: [0]
]

{
	#category : #'zoom bar',
	#'squeak_changestamp' : 'MCPServer 8/5/2026 18:22'
}
SWAView >> zoomBarSpecs [
	"{ label. selector. balloon } per button, left to right. Empty here: a view opts IN
	to the floating zoom bar by overriding this. The selectors are sent to the view
	itself, so they are the same ones its context menu uses -- the bar is a shortcut for
	the menu, never a second implementation of it."
	^ #()
]
