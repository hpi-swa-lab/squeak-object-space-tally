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
		'coverageKind'
	],
	#category : #'SWA-Treemap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> baseColorForNode: aNode [
	"Intrinsic fill color for a node, ignoring cross-ref highlight. Subclasses override."
	^ self subclassResponsibility
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
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 6/24/2026 14:33'
}
SWAView >> colorForNode: aNode [
	"Subclass's #baseColorForNode: with any active highlight on top. A tile lights
	up when it -- or any descendant -- matched; its weight is the MAX matching
	weight in its subtree, so a class tile is as hot as its hottest matching method.
	Non-matching tiles are dimmed. The matched-tile ramp depends on #highlightStyle
	(#heat for cross-ref, #coverage for SWACoverage data)."
	| base w |
	highlightWeights ifNil: [^ self baseColorForNode: aNode].
	base := self baseColorForNode: aNode.
	w := effectiveWeights ifNil: [nil] ifNotNil: [effectiveWeights at: aNode ifAbsent: [nil]].
	w ifNil: [^ (base alphaMixed: 0.25 with: (Color gray: 0.12))].
	^ self highlightColorForWeight: w base: base
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
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> coverageKind [
	"#boolean or #tally when a coverage overlay is active, else nil."
	^ coverageKind
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
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> crossReferenceFrom: aPeerView [
	"Highlight our tiles that also appear in aPeerView, weighting each by the peer
	node's totalSize (samples / bytes / loc). Pass nil to clear."
	| weights |
	aPeerView ifNil: [^ self highlightWeights: nil].
	weights := Dictionary new.
	aPeerView keyIndex keysAndValuesDo: [:k :node |
		weights at: k put: node totalSize].
	self highlightWeights: weights
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> effectiveWeightOf: aNode [
	"Memoised rolled-up highlight weight: the max of aNode's own direct match and
	its children's effective weights. Answers nil if nothing in the subtree matched."
	| key w |
	effectiveWeights at: aNode ifPresent: [:cached | ^ cached ].
	w := nil.
	key := aNode crossRefKey.
	(key notNil and: [highlightWeights includesKey: key])
		ifTrue: [w := highlightWeights at: key].
	aNode children do: [:c | | cw |
		cw := self effectiveWeightOf: c.
		cw ifNotNil: [w := w isNil ifTrue: [cw] ifFalse: [w max: cw]]].
	effectiveWeights at: aNode put: w.
	^ w
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
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel [
	^ navPanel
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> navPanel: aSWANavPanel [
	"The chrome panel that owns my breadcrumb/selection/meta labels + source pane."
	navPanel := aSWANavPanel
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
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rebuildKeyIndex [
	"(Re)build the crossRefKey -> node index by walking the whole tree. On key
	collisions keep the largest-totalSize node so lookups land on the most
	significant tile/frame."
	keyIndex := Dictionary new.
	rootNode ifNil: [^ keyIndex].
	rootNode withAllChildrenDo: [:n | | k existing |
		k := n crossRefKey.
		k ifNotNil: [
			existing := keyIndex at: k ifAbsent: [nil].
			(existing isNil or: [n totalSize > existing totalSize])
				ifTrue: [keyIndex at: k put: n]]].
	^ keyIndex
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 17:48'
}
SWAView >> rootNode [
	^ rootNode
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
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/24/2026 15:11'
}
SWAView >> showCoverage: aCoverage [
	"Overlay a SWACoverage result (its 'Class>>selector' -> value map) using the
	green coverage ramp, with the usual max class-rollup. Pass nil to clear."
	aCoverage ifNil: [coverageKind := nil. ^ self highlightWeights: nil].
	highlightStyle := #coverage.
	coverageKind := aCoverage kind.
	self highlightWeights: aCoverage resultMap
]
