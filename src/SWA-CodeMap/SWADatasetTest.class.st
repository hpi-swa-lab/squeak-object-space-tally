"
Tests for the additive layered-datasets layer of the Code Map (see journal
2026-06-30 and the follow-up). Focus is the NON-UI behavior of SWADataset and its
registration on SWACodeTreemapMorph:

	- a dataset answers a RAW value per node (keyed by crossRefKey) and a Color via
	  its kind-specific default scale;
	- loading the same kind twice yields two DISTINCT, retained datasets with unique
	  minted mode symbols (#coverage_1, #coverage_2);
	- both appear as distinct entries in the Color menu (colorModeOptions);
	- switching the active color mode between them recolors instantly, with NO reload
	  and NO recompute (the acceptance test Jens asked for).

These tests target the NEW dataset API deliberately -- they do not lock in the
legacy colorMode/coverageData/dupScores machinery, which the datasets will absorb
piece-meal later.
"
Class {
	#name : #SWADatasetTest,
	#superclass : #TestCase,
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:53'
}
SWADatasetTest >> colorMetricSymbolOf: aDataset [
	"The minted menu symbol of aDataset's first color-capable metric (after it has
	been added to a treemap, so modeSymbols are minted)."
	^ (aDataset metrics detect: [:m | m supportsColor]) modeSymbol
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> coverageWithCovered: coveredKey uncovered: uncoveredKey [
	"A tiny in-memory SWACoverageData where coveredKey has one covering test and
	uncoveredKey is merely mentioned (records nothing, so it stays count 0)."
	| cov |
	cov := SWACoverageData new.
	cov recordTest: 'TFixture>>testA' covers: coveredKey.
	^ cov
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:18'
}
SWADatasetTest >> coverageWithInvocations [
	"Coverage data carrying both covering-test and invocation counts."
	| cov |
	cov := SWACoverageData new.
	cov recordTest: 'T>>t' covers: 'Bar>>baz'.
	cov recordInvocationCount: 12 for: 'Bar>>baz'.
	^ cov
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWADatasetTest >> duplicationWithMatchKey: aKey partner: partnerKey score: aScore locA: locA locB: locB [
	"A tiny SWADuplicationData with one symmetric near-clone pair."
	| dup |
	dup := SWADuplicationData new.
	dup recordMatchesForKey: aKey loc: locA matches: (Array with: (aScore -> partnerKey)).
	dup recordMatchesForKey: partnerKey loc: locB matches: (Array with: (aScore -> aKey)).
	^ dup
]

{
	#category : #fixtures,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> nodeForKey: aKey [
	"A minimal leaf-like node answering just what a dataset needs: crossRefKey +
	children. Reuses SWADuplicationPartnerStub, which already provides both."
	^ SWADuplicationPartnerStub new crossRefKey: aKey loc: 3
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testBothCoveragesAppearInColorMenu [
	"Both loaded datasets show up as distinct entries in the Code Map Color menu,
	each carrying its minted metric symbol and a 'By <metric> [<name>]' label."
	| tm ov modes labels |
	tm := SWACodeTreemapMorph new.
	tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'first.json').
	tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'second.json').
	ov := SWACodeTreemapOverlay new.
	ov treemapMorph: tm.
	modes := ov colorModeOptions collect: [:pair | pair first].
	labels := ov colorModeOptions collect: [:pair | pair second].
	self assert: (modes includes: #coverage_1_coverage).
	self assert: (modes includes: #coverage_2_coverage).
	self assert: (labels includes: 'By coverage [first.json]').
	self assert: (labels includes: 'By coverage [second.json]')
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testColorForNodeSwitchesAtViewLevel [
	"Regression for the 'first coverage's colors stay' bug: tiles call
	SWAView>>colorForNode:, NOT #baseColorForNode:. When the active mode is a dataset
	metric, colorForNode: must defer to it and switch with the mode -- the legacy
	coverageData short-circuit must not win."
	| tm dsCovered dsUncovered node sCov sUncov cCovered cUncovered |
	tm := SWACodeTreemapMorph new.
	dsCovered := tm addDataset: (SWADataset
		coverageFrom: (self coverageWithCovered: 'Bar>>baz' uncovered: 'x') named: 'covered').
	dsUncovered := tm addDataset: (SWADataset
		coverageFrom: SWACoverageData new named: 'uncovered').
	node := self nodeForKey: 'Bar>>baz'.
	sCov := self colorMetricSymbolOf: dsCovered.
	sUncov := self colorMetricSymbolOf: dsUncovered.

	tm colorMode: sCov.
	cCovered := tm colorForNode: node.
	tm colorMode: sUncov.
	cUncovered := tm colorForNode: node.
	self deny: cCovered equals: cUncovered.

	tm colorMode: sCov.
	self assert: (tm colorForNode: node) equals: cCovered
]

{
	#category : #'tests - value',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:53'
}
SWADatasetTest >> testColorForNodeUsesScale [
	"Covered vs uncovered nodes get different colors via the metric's scale; the
	value drives the color (raw-value + scale). A custom scale overrides the default."
	| cov ds metric covered uncovered |
	cov := self coverageWithCovered: 'Bar>>baz' uncovered: 'Bar>>qux'.
	ds := SWADataset coverageFrom: cov named: 'cov'.
	metric := ds metrics detect: [:m | m id == #coverage].
	covered := metric colorForNode: (self nodeForKey: 'Bar>>baz').
	uncovered := metric colorForNode: (self nodeForKey: 'Bar>>qux').
	self deny: covered equals: uncovered.
	metric scale: [:v | Color black].
	self assert: (metric colorForNode: (self nodeForKey: 'Bar>>baz')) equals: Color black
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:33'
}
SWADatasetTest >> testContainerDuplicateBrowsePreservesList [
	"Browsing a container's aggregated duplicates: each entry carries BOTH keys
	(fromKey -> partnerKey), and previewing a pair shows its diff WITHOUT changing the
	primary selection -- so the container stays selected and the list survives (you can
	step through it)."
	| tm root dup ds pkg list entry |
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm := SWACodeTreemapMorph on: root. tm ensureLayout.
	dup := SWADuplicationData new.
	dup buildFromMethodNodes: (SWADuplicationData methodNodesForPackages: #('Regex-Tests-Core')) asArray
		similarity: SWACodeSimilarity new floor: 0.3 minLoc: 3 progress: nil.
	ds := tm addDataset: (SWADataset duplicationFrom: dup named: 'dup').
	tm selectDataset: ds.
	pkg := root children detect: [:c | c isKindOf: SWACodePackageNode].
	tm selectTileNode: pkg.
	list := tm provenanceListForSelection.
	entry := list first.

	"entry value is a fromKey -> partnerKey association"
	self assert: (entry value isKindOf: Association).
	self assert: (entry value key isKindOf: String).
	self assert: (entry value value isKindOf: String).

	"preview the pair -> primary selection unchanged, list intact, diff shown"
	tm previewDuplicatePairFrom: entry value key to: entry value value.
	self assert: tm selectedNode == pkg.
	self assert: tm provenanceListForSelection size equals: list size.
	self assert: tm dupDiffFrom notNil.
	self assert: tm dupDiffTarget notNil.
	self assert: (tm selectedSourceString asString includesSubstring: 'vs ').

	"selecting a different primary node clears the browse diff"
	tm selectTileNode: (tm keyIndex at: entry value key).
	self assert: tm dupDiffFrom isNil
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:28'
}
SWADatasetTest >> testContainerDuplicatesAggregation [
	"Selecting ANY container -- category, CLASS, or PACKAGE -- aggregates the
	near-duplicates of all DESCENDANT methods into the side pane. Split is by node KIND,
	so a class (which has a crossRefKey) is still treated as a container, not a method."
	| tm root dup ds metric leaves category classNode pkg |
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm := SWACodeTreemapMorph on: root. tm ensureLayout.
	dup := SWADuplicationData new.
	dup buildFromMethodNodes: (SWADuplicationData methodNodesForPackages: #('Regex-Tests-Core')) asArray
		similarity: SWACodeSimilarity new floor: 0.3 minLoc: 3 progress: nil.
	ds := tm addDataset: (SWADataset duplicationFrom: dup named: 'dup').
	tm selectDataset: ds.
	metric := ds metrics first.
	leaves := OrderedCollection new. tm collectMethodLeavesFrom: root into: leaves.
	category := (leaves detect: [:m | m crossRefKey notNil
		and: [(metric linksForKey: m crossRefKey) notEmpty]]) parent.
	classNode := category parent.
	pkg := root children detect: [:c | c isKindOf: SWACodePackageNode].

	"class: has a crossRefKey but MUST aggregate (not be treated as a method)"
	self assert: classNode crossRefKey notNil.
	self assert: (classNode isKindOf: SWACodeClassNode).
	tm selectTileNode: classNode.
	self deny: tm provenanceListForSelection isEmpty.
	self assert: (tm provenanceListTitle includesSubstring: 'in subtree').
	self assert: (tm provenanceListForSelection first key includesSubstring: ' <-> ').

	"package: aggregates the whole tree, >= any single class"
	tm selectTileNode: pkg.
	self deny: tm provenanceListForSelection isEmpty.
	self assert: (tm containerDuplicatePairCountFor: pkg metric: metric)
		>= (tm containerDuplicatePairCountFor: classNode metric: metric).

	"a click on a container entry is NOT a diff (selection is not a method)"
	self deny: tm selectionIsMethodForDiff
]

{
	#category : #'tests - metrics',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testCoverageExposesCallMetricWhenInvocationDataPresent [
	"One coverage file carrying invocation data yields TWO metrics -- 'By coverage'
	and 'By call' -- each color- and size-capable, with distinct minted symbols and
	'[name]'-tagged labels. Without invocation data, only 'By coverage' is offered."
	| cov ds ids callMetric coverageOnly |
	cov := SWACoverageData new.
	cov recordTest: 'T>>t' covers: 'Bar>>baz'.
	cov recordInvocationCount: 42 for: 'Bar>>baz'.
	ds := SWADataset coverageFrom: cov named: 'squeak-coverage.json'.
	ids := ds metrics collect: [:m | m id].
	self assert: (ids includes: #coverage).
	self assert: (ids includes: #call).
	callMetric := ds metrics detect: [:m | m id == #call].
	self assert: (callMetric valueForNode: (self nodeForKey: 'Bar>>baz')) equals: 42.
	self assert: callMetric supportsColor.
	self assert: callMetric supportsSize.
	self assert: callMetric menuLabel equals: 'By call [squeak-coverage.json]'.
	"no invocation data -> no call metric"
	coverageOnly := SWADataset coverageFrom: (self coverageWithCovered: 'A>>m' uncovered: 'x') named: 'c'.
	self deny: ((coverageOnly metrics collect: [:m | m id]) includes: #call)
]

{
	#category : #'tests - coverage provenance',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:29'
}
SWADatasetTest >> testCoverageProvenanceBlueTestsAndFilters [
	"Selecting a coverage dataset keeps the SPECIAL provenance behavior even though base
	color comes from the metric: test tiles are BLUE, and the click filters work --
	select a test -> its covered methods bright, others dim; select a covered method ->
	its covering tests filter. Uses real tree nodes so crossRefKeys resolve."
	| tm root leaves methods testM appM cov covDs testNode appNode otherNode |
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm := SWACodeTreemapMorph on: root. tm ensureLayout.
	leaves := OrderedCollection new. tm collectMethodLeavesFrom: root into: leaves.
	methods := leaves select: [:m | m crossRefKey notNil and: [m kind == #method]].
	testM := (methods detect: [:m | m crossRefKey includesSubstring: 'test']) crossRefKey.
	appM := (methods detect: [:m | m crossRefKey ~= testM]) crossRefKey.
	cov := SWACoverageData new. cov recordTest: testM covers: appM.
	covDs := tm addDataset: (SWADataset coverageFrom: cov named: 'cov').
	tm selectDataset: covDs.

	"provenance wired from the dataset"
	self assert: tm coverageData notNil.
	self assert: (tm isTestKey: testM).

	testNode := methods detect: [:m | m crossRefKey = testM].
	appNode := methods detect: [:m | m crossRefKey = appM].
	otherNode := methods detect: [:m | (m crossRefKey ~= testM) and: [m crossRefKey ~= appM]].

	"test tile is blue"
	self assert: (tm colorForNode: testNode) equals: (tm testColorForNode: testNode).

	"select the test -> covered method bright, unrelated dim"
	tm selectTileNode: testNode.
	self deny: (tm isFilteredOut: appNode).
	self assert: (tm isFilteredOut: otherNode).

	"select the covered method -> covering-tests filter set"
	tm selectTileNode: appNode.
	self assert: (tm instVarNamed: 'coveringTestFilter') notNil.

	"leaving coverage (pick duplication or none) drops provenance"
	tm selectDataset: nil.
	self assert: tm coverageData isNil.
	self deny: (tm isTestKey: testM)
]

{
	#category : #'tests - data selector',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:18'
}
SWADatasetTest >> testDataMenuListsDatasets [
	"The Data menu offers 'None' plus one entry per retained dataset, ticking the
	active one; suppressed (nil) when nothing is loaded."
	| tm ov modes emptyOv |
	tm := SWACodeTreemapMorph new.
	tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'a.json').
	tm addDataset: (SWADataset duplicationFrom: SWADuplicationData new named: 'b.json').
	ov := SWACodeTreemapOverlay new. ov treemapMorph: tm.
	modes := ov dataModeOptions collect: [:p | p first].
	self assert: (modes includes: #none).
	self assert: (modes includes: (tm datasets first modeSymbol)).
	self assert: (modes includes: (tm datasets last modeSymbol)).
	self assert: ov dataMenuMorph notNil.
	"empty map -> only 'None' -> menu suppressed"
	emptyOv := SWACodeTreemapOverlay new. emptyOv treemapMorph: SWACodeTreemapMorph new.
	self assert: emptyOv dataModeOptions size equals: 1.
	self assert: emptyOv dataMenuMorph isNil
]

{
	#category : #'tests - data selector',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:18'
}
SWADatasetTest >> testDataSelectorOverridesPersistUntilNextPick [
	"After a Data pick sets defaults, a single-axis override sticks (and the dataset
	stays active) until the next Data pick; #none clears everything back to intrinsic."
	| tm dupDs |
	tm := SWACodeTreemapMorph new.
	dupDs := tm addDataset: (SWADataset duplicationFrom:
		(self duplicationWithMatchKey: 'A>>m' partner: 'B>>n' score: 0.9 locA: 8 locB: 8) named: 'dup').
	tm selectDataset: dupDs.
	"override color to an intrinsic mode -- decoration + active dataset persist"
	tm colorMode: #loc.
	self assert: tm colorMode equals: #loc.
	self assert: tm decorationMetric supportsLinks.
	self assert: tm activeDataset equals: dupDs.
	"clear via #none -> everything intrinsic"
	tm selectDataset: nil.
	self assert: tm activeDataset isNil.
	self assert: tm colorMode equals: #codeKind.
	self assert: tm weightMetric equals: #loc.
	self assert: tm decorationMetric isNil
]

{
	#category : #'tests - loading',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWADatasetTest >> testDatasetNameForPath [
	"The Load button derives a dataset's display name from the file's base name.
	Regression: #substrings: is not understood in this image (was a live DNU in
	#datasetNameFor:) -- this pins the actual parsing across separators and nil."
	| p |
	p := SWAPane new.
	self assert: (p datasetNameFor: '/home/jens/first.json') equals: 'first.json'.
	self assert: (p datasetNameFor: 'C:\d\second.json') equals: 'second.json'.
	self assert: (p datasetNameFor: 'bare.json') equals: 'bare.json'.
	self assert: (p datasetNameFor: nil) equals: 'loaded'
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:14'
}
SWADatasetTest >> testDecorationBindingIndependentOfColor [
	"The decoration (links) axis binds independently of color: I can color by a
	coverage metric while duplication links stay bound to the decoration axis, and
	clearing color does not clear decorations."
	| tm dup cov dupDs covDs linkMetric covMetric |
	tm := SWACodeTreemapMorph new.
	cov := self coverageWithCovered: 'A>>m' uncovered: 'x'.
	dup := self duplicationWithMatchKey: 'A>>m' partner: 'B>>n' score: 0.8 locA: 10 locB: 20.
	covDs := tm addDataset: (SWADataset coverageFrom: cov named: 'cov').
	dupDs := tm addDataset: (SWADataset duplicationFrom: dup named: 'dup').
	linkMetric := dupDs metrics detect: [:m | m supportsLinks].
	covMetric := covDs metrics detect: [:m | m supportsColor].
	"bind decoration to dup links, color to coverage"
	tm decorationMetric: linkMetric.
	tm colorMode: covMetric modeSymbol.
	self assert: tm decorationMetric equals: linkMetric.
	self assert: tm colorMode equals: covMetric modeSymbol.
	"switching color to an intrinsic mode leaves decorations intact"
	tm colorMode: #loc.
	self assert: tm decorationMetric equals: linkMetric.
	"clearing decorations does not touch color"
	tm setDecorationMode: #none.
	self assert: tm decorationMetric isNil.
	self assert: tm colorMode equals: #loc
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:14'
}
SWADatasetTest >> testDecorationMenuListsLinkMetrics [
	"The Links (decoration) menu offers 'None' plus one entry per link-capable metric;
	a coverage-only map offers no link entries (menu suppressed)."
	| tm ov dup modes covOnlyOv covTm |
	tm := SWACodeTreemapMorph new.
	dup := self duplicationWithMatchKey: 'A>>m' partner: 'B>>n' score: 0.8 locA: 10 locB: 20.
	tm addDataset: (SWADataset duplicationFrom: dup named: 'dup.json').
	ov := SWACodeTreemapOverlay new. ov treemapMorph: tm.
	modes := ov decorationModeOptions collect: [:p | p first].
	self assert: (modes includes: #none).
	self assert: (modes includes: #duplication_1_duplication).
	self assert: (ov decorationMenuMorph notNil).
	"coverage-only: only 'None' -> menu suppressed"
	covTm := SWACodeTreemapMorph new.
	covTm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'c').
	covOnlyOv := SWACodeTreemapOverlay new. covOnlyOv treemapMorph: covTm.
	self assert: covOnlyOv decorationModeOptions size equals: 1.
	self assert: covOnlyOv decorationMenuMorph isNil
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testDuplicationDatasetSymbolIndependentOfCoverage [
	"Mixing kinds: coverage and duplication mint metric symbols from independent
	dataset counters, so both coexist and neither steals the other's numbering."
	| tm cov dup |
	tm := SWACodeTreemapMorph new.
	cov := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'c').
	dup := tm addDataset: (SWADataset duplicationFrom: SWADuplicationData new named: 'd').
	self assert: (self colorMetricSymbolOf: cov) equals: #coverage_1_coverage.
	self assert: (self colorMetricSymbolOf: dup) equals: #duplication_1_duplication.
	self assert: tm datasets size equals: 2
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:13'
}
SWADatasetTest >> testDuplicationMetricProvidesLinks [
	"The duplication metric supports the #links (decoration) axis and answers a
	method's partner links keyed by crossRefKey, plus the shared-LOC impact for width."
	| dup ds metric |
	dup := self duplicationWithMatchKey: 'A>>m' partner: 'B>>n' score: 0.8 locA: 10 locB: 20.
	ds := SWADataset duplicationFrom: dup named: 'd'.
	metric := ds metrics detect: [:m | m id == #duplication].
	self assert: metric supportsLinks.
	self assert: (metric linksForKey: 'A>>m') first value equals: 'B>>n'.
	self assert: (metric linksForKey: 'A>>m') first key equals: 0.8.
	"shared LOC = score * min(locA, locB) = 0.8 * 10 = 8"
	self assert: (metric sharedLocForKey: 'A>>m' score: 0.8 partnerKey: 'B>>n') equals: 8.
	"a non-link metric offers no links"
	self deny: (SWADataset coverageFrom: SWACoverageData new named: 'c')
		metrics anyOne supportsLinks
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 14:04'
}
SWADatasetTest >> testDuplicationProvenanceListAndDiffTarget [
	"With a duplication dataset active, the side pane lists the selected method's
	near-duplicates (keyed by crossRefKey, clickable), and picking one resolves to the
	partner node so it can become the diff target. Uses a real tree so keys resolve."
	| tm root dup ds leaves node partnerKey resolved |
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm := SWACodeTreemapMorph on: root. tm ensureLayout.
	dup := SWADuplicationData new.
	dup buildFromMethodNodes: (SWADuplicationData methodNodesForPackages: #('Regex-Tests-Core')) asArray
		similarity: SWACodeSimilarity new floor: 0.3 minLoc: 3 progress: nil.
	ds := tm addDataset: (SWADataset duplicationFrom: dup named: 'dup').
	tm selectDataset: ds.
	self assert: tm isDuplicationProvenanceActive.

	leaves := OrderedCollection new. tm collectMethodLeavesFrom: root into: leaves.
	node := leaves detect: [:m | m crossRefKey notNil
		and: [(ds metrics first linksForKey: m crossRefKey) notEmpty]].
	tm selectTileNode: node.

	"list is non-empty and keyed by partner crossRefKey"
	self deny: tm provenanceListForSelection isEmpty.
	self assert: (tm provenanceListTitle includesSubstring: 'near-duplicate').
	partnerKey := tm provenanceListForSelection first value.
	self assert: ((tm provenanceListForSelection first key) includesSubstring: partnerKey).

	"picking it resolves to the partner node -> diff target (secondary selection)"
	resolved := tm keyIndex at: partnerKey ifAbsent: [nil].
	self assert: resolved notNil.
	tm dupDiffTarget: resolved.
	self assert: tm secondarySelection equals: resolved
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:23'
}
SWADatasetTest >> testLeafKeySetUnderRealTree [
	"leafKeySetUnder: collects the method crossRefKeys of a subtree (the general
	selection-restriction set). A class node yields its methods' keys; a single
	method yields just its own key."
	| tm root classNode methodNode classKeys |
	tm := SWACodeTreemapMorph new.
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm setRoot: root.
	classNode := nil.
	root withAllChildrenDo: [:n |
		(classNode isNil and: [(n isKindOf: SWACodeClassNode)
			and: [n children anySatisfy: [:c | c isKindOf: SWACodeMethodNode]]])
				ifTrue: [classNode := n]].
	self assert: classNode notNil.
	classKeys := tm leafKeySetUnder: classNode.
	"every method child's key is in the set"
	classNode children do: [:m |
		(m isKindOf: SWACodeMethodNode) ifTrue: [
			self assert: (classKeys includes: m crossRefKey)]].
	"a single method -> singleton of its own key"
	methodNode := classNode children detect: [:c | c isKindOf: SWACodeMethodNode].
	self assert: (tm leafKeySetUnder: methodNode) equals: (Set with: methodNode crossRefKey)
]

{
	#category : #'tests - decoration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 11:23'
}
SWADatasetTest >> testLinkRestrictionPredicate [
	"The general decoration selection-filter: nil restriction shows every link; a
	restriction set shows a link when AT LEAST ONE endpoint is inside it (so an
	outgoing clone from the selection still shows)."
	| tm restrict |
	tm := SWACodeTreemapMorph new.
	"no restriction -> everything shows"
	self assert: (tm link: ('A>>m' -> 'B>>n') connectsRestriction: nil).
	restrict := Set withAll: #('A>>m' 'A>>k').
	"both endpoints in -> show"
	self assert: (tm link: ('A>>m' -> 'A>>k') connectsRestriction: restrict).
	"one endpoint in (outgoing) -> show"
	self assert: (tm link: ('A>>m' -> 'Z>>z') connectsRestriction: restrict).
	self assert: (tm link: ('Z>>z' -> 'A>>m') connectsRestriction: restrict).
	"neither endpoint in -> hide"
	self deny: (tm link: ('Y>>y' -> 'Z>>z') connectsRestriction: restrict)
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testRemoveDatasetFallsBackWhenActive [
	"Unloading the active dataset drops its metrics from the registry and falls back
	to an intrinsic mode; unloading a non-active one leaves the current mode alone."
	| tm ds1 ds2 s2 |
	tm := SWACodeTreemapMorph new.
	ds1 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'a').
	ds2 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'b').
	s2 := self colorMetricSymbolOf: ds2.
	tm colorMode: s2.
	tm removeDataset: ds1.
	self assert: tm colorMode equals: s2.
	self assert: tm datasets size equals: 1.
	tm removeDataset: ds2.
	self assert: tm colorMode equals: #codeKind.
	self assert: (tm metricForMode: s2) isNil
]

{
	#category : #'tests - data selector',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 13:24'
}
SWADatasetTest >> testSelectDatasetAppliesDefaultsAcrossAxes [
	"Picking a data source applies its fitting defaults across the axes: coverage ->
	color by a coverage metric, size LEFT INTRINSIC (LOC -- sizing by coverage collapses
	uncovered code), no decoration; duplication -> color heat + decoration links, size
	intrinsic. Uses a real root so the size axis (which routes through the root node)
	actually binds."
	| tm root covDs dupDs |
	root := SWACodeRootNode new addPackages: 'Regex-Tests-Core'; yourself.
	tm := SWACodeTreemapMorph on: root.
	tm ensureLayout.
	covDs := tm addDataset: (SWADataset coverageFrom: self coverageWithInvocations named: 'cov').
	dupDs := tm addDataset: (SWADataset duplicationFrom:
		(self duplicationWithMatchKey: 'A>>m' partner: 'B>>n' score: 0.9 locA: 8 locB: 8) named: 'dup').

	tm selectDataset: covDs.
	self assert: tm activeDataset equals: covDs.
	self assert: (tm metricForMode: tm colorMode) dataset equals: covDs.
	self assert: (tm metricForMode: tm colorMode) supportsColor.
	self assert: tm weightMetric equals: #loc.   "size stays intrinsic, not coverage"
	self assert: tm decorationMetric isNil.

	tm selectDataset: dupDs.
	self assert: tm activeDataset equals: dupDs.
	self assert: (tm metricForMode: tm colorMode) id equals: #duplication.
	self assert: tm weightMetric equals: #loc.
	self assert: tm decorationMetric supportsLinks
]

{
	#category : #'tests - metrics',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testSizeMetricSumsAcrossChildren [
	"A size-capable metric with #sum rollup aggregates its children additively, so a
	container is sized by the total of its leaves' values (weightForNode:)."
	| cov ds callMetric leafA leafB container |
	cov := SWACoverageData new.
	cov recordInvocationCount: 10 for: 'C>>a'.
	cov recordInvocationCount: 25 for: 'C>>b'.
	ds := SWADataset coverageFrom: cov named: 'c'.
	callMetric := ds metrics detect: [:m | m id == #call].
	leafA := self nodeForKey: 'C>>a'.
	leafB := self nodeForKey: 'C>>b'.
	"a container node with no crossRefKey and two leaf children"
	container := SWADatasetTestContainer new childrenColl: (Array with: leafA with: leafB).
	self assert: (callMetric weightForNode: leafA) equals: 10.
	self assert: (callMetric weightForNode: container) equals: 35
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:54'
}
SWADatasetTest >> testSwitchBetweenCoveragesWithoutReload [
	"THE acceptance test: two coverage datasets differing on one method's status;
	flipping colorMode between their two metric symbols recolors that node instantly,
	no reload -- and flipping back returns the original color."
	| tm dsCovered dsUncovered node sCov sUncov cCovered cUncovered |
	tm := SWACodeTreemapMorph new.
	dsCovered := tm addDataset: (SWADataset
		coverageFrom: (self coverageWithCovered: 'Bar>>baz' uncovered: 'x') named: 'covered').
	dsUncovered := tm addDataset: (SWADataset
		coverageFrom: SWACoverageData new named: 'uncovered').
	node := self nodeForKey: 'Bar>>baz'.
	sCov := self colorMetricSymbolOf: dsCovered.
	sUncov := self colorMetricSymbolOf: dsUncovered.

	tm colorMode: sCov.
	cCovered := tm baseColorForNode: node.
	tm colorMode: sUncov.
	cUncovered := tm baseColorForNode: node.
	self deny: cCovered equals: cUncovered.

	tm colorMode: sCov.
	self assert: (tm baseColorForNode: node) equals: cCovered
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:53'
}
SWADatasetTest >> testTwoCoveragesAreDistinctAndRetained [
	"Loading coverage twice yields two DISTINCT retained datasets whose metrics get
	unique minted symbols -- neither clobbers the other."
	| tm ds1 ds2 s1 s2 |
	tm := SWACodeTreemapMorph new.
	ds1 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'first').
	ds2 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'second').
	self assert: tm datasets size equals: 2.
	self assert: (tm datasets includes: ds1).
	self assert: (tm datasets includes: ds2).
	s1 := self colorMetricSymbolOf: ds1.
	s2 := self colorMetricSymbolOf: ds2.
	self assert: s1 equals: #coverage_1_coverage.
	self assert: s2 equals: #coverage_2_coverage.
	self deny: s1 equals: s2.
	self assert: (tm metricForMode: s1) id equals: #coverage.
	self assert: (tm metricForMode: s1) dataset equals: ds1.
	self assert: (tm metricForMode: s2) dataset equals: ds2
]

{
	#category : #'tests - value',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:53'
}
SWADatasetTest >> testValueForNodeReadsCoverage [
	"A coverage dataset's 'By coverage' metric answers the covering-test count for a
	node, keyed by its crossRefKey."
	| cov ds metric |
	cov := self coverageWithCovered: 'Bar>>baz' uncovered: 'Bar>>qux'.
	ds := SWADataset coverageFrom: cov named: 'cov'.
	metric := ds metrics detect: [:m | m id == #coverage].
	self assert: (metric valueForNode: (self nodeForKey: 'Bar>>baz')) equals: 1.
	self assert: (metric valueForNode: (self nodeForKey: 'Bar>>qux')) equals: 0
]
