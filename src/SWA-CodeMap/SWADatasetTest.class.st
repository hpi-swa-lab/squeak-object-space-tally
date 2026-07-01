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
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> nodeForKey: aKey [
	"A minimal leaf-like node answering just what a dataset needs: crossRefKey +
	children. Reuses SWADuplicationPartnerStub, which already provides both."
	^ SWADuplicationPartnerStub new crossRefKey: aKey loc: 3
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testBothCoveragesAppearInColorMenu [
	"Both loaded datasets show up as distinct entries in the Code Map Color menu,
	each carrying its minted symbol and its display name."
	| tm ov modes labels |
	tm := SWACodeTreemapMorph new.
	tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'first.json').
	tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'second.json').
	ov := SWACodeTreemapOverlay new.
	ov treemapMorph: tm.
	modes := ov colorModeOptions collect: [:pair | pair first].
	labels := ov colorModeOptions collect: [:pair | pair second].
	self assert: (modes includes: #coverage_1).
	self assert: (modes includes: #coverage_2).
	self assert: (labels anySatisfy: [:l | l includesSubstring: 'first.json']).
	self assert: (labels anySatisfy: [:l | l includesSubstring: 'second.json'])
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:18'
}
SWADatasetTest >> testColorForNodeSwitchesAtViewLevel [
	"Regression for the 'first coverage's colors stay' bug: tiles call
	SWAView>>colorForNode:, NOT #baseColorForNode:. When the active mode is a
	dataset, colorForNode: must defer to that dataset and switch with the mode --
	the legacy coverageData short-circuit must not win."
	| tm dsCovered dsUncovered node cCovered cUncovered |
	tm := SWACodeTreemapMorph new.
	dsCovered := tm addDataset: (SWADataset
		coverageFrom: (self coverageWithCovered: 'Bar>>baz' uncovered: 'x') named: 'covered').
	dsUncovered := tm addDataset: (SWADataset
		coverageFrom: SWACoverageData new named: 'uncovered').
	node := self nodeForKey: 'Bar>>baz'.

	tm colorMode: dsCovered modeSymbol.
	cCovered := tm colorForNode: node.
	tm colorMode: dsUncovered modeSymbol.
	cUncovered := tm colorForNode: node.
	self deny: cCovered equals: cUncovered.

	tm colorMode: dsCovered modeSymbol.
	self assert: (tm colorForNode: node) equals: cCovered
]

{
	#category : #'tests - value',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testColorForNodeUsesScale [
	"Covered vs uncovered nodes get different colors via the kind-specific default
	scale; the value drives the color (raw-value + scale)."
	| cov ds covered uncovered |
	cov := self coverageWithCovered: 'Bar>>baz' uncovered: 'Bar>>qux'.
	ds := SWADataset coverageFrom: cov named: 'cov'.
	covered := ds colorForNode: (self nodeForKey: 'Bar>>baz').
	uncovered := ds colorForNode: (self nodeForKey: 'Bar>>qux').
	self deny: covered equals: uncovered.
	"a custom scale must override the default"
	ds scale: [:v | Color black].
	self assert: (ds colorForNode: (self nodeForKey: 'Bar>>baz')) equals: Color black
]

{
	#category : #'tests - loading',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:14'
}
SWADatasetTest >> testDatasetNameForPath [
	"The Load button derives a dataset's display name from the file's base name.
	Regression: #substrings: is not understood in this image (was a live DNU in
	#datasetNameFor:) -- this pins the actual parsing across separators and nil."
	| p |
	p := SWANavPanel new.
	self assert: (p datasetNameFor: '/home/jens/first.json') equals: 'first.json'.
	self assert: (p datasetNameFor: 'C:\d\second.json') equals: 'second.json'.
	self assert: (p datasetNameFor: 'bare.json') equals: 'bare.json'.
	self assert: (p datasetNameFor: nil) equals: 'loaded'
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testDuplicationDatasetSymbolIndependentOfCoverage [
	"Mixing kinds: coverage and duplication mint symbols from independent counters,
	so both coexist and neither steals the other's numbering."
	| tm cov dup |
	tm := SWACodeTreemapMorph new.
	cov := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'c').
	dup := tm addDataset: (SWADataset duplicationFrom: SWADuplicationData new named: 'd').
	self assert: cov modeSymbol equals: #coverage_1.
	self assert: dup modeSymbol equals: #duplication_1.
	self assert: tm datasets size equals: 2
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testRemoveDatasetFallsBackWhenActive [
	"Unloading the active dataset drops it from the registry and falls back to an
	intrinsic mode; unloading a non-active one leaves the current mode alone."
	| tm ds1 ds2 |
	tm := SWACodeTreemapMorph new.
	ds1 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'a').
	ds2 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'b').
	tm colorMode: ds2 modeSymbol.
	tm removeDataset: ds1.
	self assert: tm colorMode equals: ds2 modeSymbol.
	self assert: tm datasets size equals: 1.
	tm removeDataset: ds2.
	self assert: tm colorMode equals: #codeKind.
	self assert: (tm datasetForMode: ds2 modeSymbol) isNil
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testSwitchBetweenCoveragesWithoutReload [
	"THE acceptance test: two coverage datasets differing on one method's status;
	flipping colorMode between their two symbols recolors that node instantly, with
	no reload / no recompute -- and flipping back returns the original color."
	| tm dsCovered dsUncovered node cCovered cUncovered |
	tm := SWACodeTreemapMorph new.
	dsCovered := tm addDataset: (SWADataset
		coverageFrom: (self coverageWithCovered: 'Bar>>baz' uncovered: 'x') named: 'covered').
	dsUncovered := tm addDataset: (SWADataset
		coverageFrom: SWACoverageData new named: 'uncovered').
	node := self nodeForKey: 'Bar>>baz'.

	tm colorMode: dsCovered modeSymbol.
	cCovered := tm baseColorForNode: node.
	tm colorMode: dsUncovered modeSymbol.
	cUncovered := tm baseColorForNode: node.
	self deny: cCovered equals: cUncovered.

	"switch back -- same color as before, purely from the retained dataset"
	tm colorMode: dsCovered modeSymbol.
	self assert: (tm baseColorForNode: node) equals: cCovered
]

{
	#category : #'tests - registration',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testTwoCoveragesAreDistinctAndRetained [
	"Loading coverage twice yields two DISTINCT retained datasets with unique minted
	mode symbols -- neither clobbers the other."
	| tm ds1 ds2 |
	tm := SWACodeTreemapMorph new.
	ds1 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'first').
	ds2 := tm addDataset: (SWADataset coverageFrom: SWACoverageData new named: 'second').
	self assert: tm datasets size equals: 2.
	self assert: (tm datasets includes: ds1).
	self assert: (tm datasets includes: ds2).
	self assert: ds1 modeSymbol equals: #coverage_1.
	self assert: ds2 modeSymbol equals: #coverage_2.
	self deny: ds1 modeSymbol equals: ds2 modeSymbol.
	self assert: (tm datasetForMode: #coverage_1) equals: ds1.
	self assert: (tm datasetForMode: #coverage_2) equals: ds2
]

{
	#category : #'tests - value',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:09'
}
SWADatasetTest >> testValueForNodeReadsCoverage [
	"A coverage dataset answers the covering-test count for a node, keyed by its
	crossRefKey."
	| cov ds |
	cov := self coverageWithCovered: 'Bar>>baz' uncovered: 'Bar>>qux'.
	ds := SWADataset coverageFrom: cov named: 'cov'.
	self assert: (ds valueForNode: (self nodeForKey: 'Bar>>baz')) equals: 1.
	self assert: (ds valueForNode: (self nodeForKey: 'Bar>>qux')) equals: 0
]
