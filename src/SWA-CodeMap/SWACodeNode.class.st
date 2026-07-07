"
A lightweight node wrapping a live code element for visualization (Graphviz, later TreeView).

The 'subject' is the live thing itself -- a PackageInfo, a Class, a method category Symbol, or a MethodReference. We are in a live image, so we just hold the reference; no mirror layer.

Subclasses, one per level:
  SWACodePackageNode   subject = PackageInfo
  SWACodeClassNode     subject = a Class (owns source access; class-side methods treated as UML 'static')
  SWACodeCategoryNode  subject = a category Symbol
  SWACodeMethodNode    subject = a MethodReference (leaf)

Metrics (loc, commentLines, lastChanged, changeCount) default to 0/nil here and roll up from children; leaf method nodes compute the real values (delegating source access up to their class node).

Graph output mirrors SWASpaceTallyNode: graph-builder methods return { dotString. ids. truncated } where 'ids' is an IdentityDictionary node -> dot-id for click mapping in GraphvizPane.
"
Class {
	#name : #SWACodeNode,
	#superclass : #SWANode,
	#instVars : [
		'subject',
		'rollupLoc',
		'rollupMethodCount',
		'coverageData',
		'rollupCoverage',
		'coverageWeightMode',
		'weightMetric',
		'rollupBytes',
		'sizeMetric',
		'rollupDataset',
		'topicData',
		'rollupTopic'
	],
	#classVars : [
		'TestWeightFloorInvocations',
		'TestWeightFloorTests'
	],
	#category : #'SWA-CodeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeNode class >> dotEscape: aString [
	"Escape a string for use inside a DOT double-quoted label."
	| ws |
	ws := WriteStream on: String new.
	aString asString do: [:ch |
		(ch = $" or: [ch = $\]) ifTrue: [ws nextPut: $\].
		ch = Character lf
			ifTrue: [ws nextPutAll: '\n']
			ifFalse: [ws nextPut: ch]].
	^ ws contents
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode class >> on: aSubject [
	^ self new subject: aSubject; yourself
]

{
	#category : #'instance creation',
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode class >> on: aSubject parent: aNode [
	^ self new subject: aSubject; parent: aNode; yourself
]

{
	#category : #'test-weight floor',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeNode class >> testWeightFloorInvocations [
	"Minimum weight a test method gets in #invocations-weighted maps so tests stay
	visible (default 300)."
	^ TestWeightFloorInvocations ifNil: [300]
]

{
	#category : #'test-weight floor',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeNode class >> testWeightFloorInvocations: anInteger [
	TestWeightFloorInvocations := anInteger
]

{
	#category : #'test-weight floor',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeNode class >> testWeightFloorTests [
	"Minimum weight a test method gets in #tests-weighted maps so tests stay visible
	(default 20)."
	^ TestWeightFloorTests ifNil: [20]
]

{
	#category : #'test-weight floor',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeNode class >> testWeightFloorTests: anInteger [
	TestWeightFloorTests := anInteger
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:41'
}
SWACodeNode >> avgChangeCount [
	"Average number of recorded versions per method over this subtree (rolled-up
	changeCount / method count). On class/package nodes a raw total just tracks size,
	so the average is the meaningful 'churn per method' signal. 0 if no methods."
	| n |
	n := self methodCount.
	^ n = 0 ifTrue: [0] ifFalse: [self changeCount / n]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
}
SWACodeNode >> avgLoc [
	"Average lines of code per method over this subtree (rolled-up LOC / method count).
	Most meaningful for class/category/package nodes. 0 if there are no methods."
	| n |
	n := self methodCount.
	^ n = 0 ifTrue: [0] ifFalse: [self loc / n]
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> browse [
	"Open a system browser on this node's subject. Subclasses refine."
	^ self subclassResponsibility
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> buildChildren [
	"Answer an OrderedCollection of child SWACodeNodes. Subclasses override.
	Leaf nodes answer an empty collection."
	^ OrderedCollection new
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:35'
}
SWACodeNode >> byteComposition [
	"Rolled-up { docBytes. stringBytes. codeBytes } over this subtree, summing the
	leaves. Used to paint the composition bar on aggregate tiles. Recomputed each
	call (cheap relative to drawing); method leaves override with their own analysis."
	| doc str code |
	doc := str := code := 0.
	self children do: [:c | | comp |
		comp := c byteComposition.
		doc := doc + comp first.
		str := str + (comp at: 2).
		code := code + comp last].
	^ { doc. str. code }
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:34'
}
SWACodeNode >> byteWeight [
	"Treemap weight for byte-composition layout: rolled-up source byte size over the
	subtree. Sum over children (cached), so a class/package tile is sized by the
	total source bytes of all its methods. Method leaves override with their own
	byteSize."
	^ rollupBytes ifNil: [
		rollupBytes := self children inject: 0 into: [:sum :c | sum + c byteWeight]]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> changeCount [
	"Number of recorded changes. Default: sum over children. Method leaves override."
	^ self children inject: 0 into: [:sum :c | sum + c changeCount]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> children [
	"Lazily build child nodes the first time they are asked for."
	children ifNil: [children := self buildChildren].
	^ children
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:04'
}
SWACodeNode >> className [
	"Used by the treemap's label/color strategies. We answer nil so it falls back
	to #name; the code treemap brings its own coloring anyway."
	^ nil
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> classNode [
	"Answer the nearest enclosing SWACodeClassNode, or nil. Method nodes use this
	to delegate source access up to the owning class node."
	^ parent ifNil: [nil] ifNotNil: [parent classNode]
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> commentLines [
	"Comment lines. Default: sum over children. Method leaves override."
	^ self children inject: 0 into: [:sum :c | sum + c commentLines]
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodeNode >> containmentGraph [
	"Build a Graphviz DOT graph of this subtree as a containment tree
	(Package -> Class -> Category -> Method). Answer { dotString. ids. truncated }
	where ids is an IdentityDictionary node -> dot-id string for click mapping,
	matching the tuple shape used by GraphvizPane. 'truncated' is always false here."
	| dot ids |
	dot := WriteStream on: String new.
	ids := IdentityDictionary new.
	dot nextPutAll: 'digraph code {'; nextPut: Character lf.
	dot nextPutAll: '  rankdir=LR;'; nextPut: Character lf.
	dot nextPutAll: '  node [fontname="Helvetica", fontsize=10];'; nextPut: Character lf.
	self withAllChildrenDo: [:node |
		ids at: node put: node dotId.
		node dotNodeStatementOn: dot].
	self withAllChildrenDo: [:node |
		node children do: [:child |
			dot
				nextPutAll: '  '; nextPutAll: node dotId;
				nextPutAll: ' -> '; nextPutAll: child dotId;
				nextPutAll: ';'; nextPut: Character lf]].
	dot nextPutAll: '}'; nextPut: Character lf.
	^ { dot contents. ids. false }
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:22'
}
SWACodeNode >> coverageData [
	"The SWACoverageData driving coverage-WEIGHTED layout (tiles sized by covering-
	test count instead of LOC), or nil for the normal LOC view. Set on the root by
	SWANavPanel class>>openCoverage:onPackageNamed:; children inherit it by walking
	up the parent chain, so lazily-built nodes see it without per-node wiring."
	coverageData ifNotNil: [^ coverageData].
	^ parent ifNil: [nil] ifNotNil: [parent coverageData]
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:22'
}
SWACodeNode >> coverageData: aCoverageDataOrNil [
	"Set the coverage data that drives coverage-weighted layout for this subtree.
	Normally set only on the root node. Clears any cached coverage roll-up."
	coverageData := aCoverageDataOrNil.
	rollupCoverage := nil
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:22'
}
SWACodeNode >> coverageWeight [
	"Treemap weight for coverage-weighted layout: rolled-up covering-test COUNT over
	the subtree. Sum over children (cached), so a class/package tile is sized by the
	total covered counts of all its methods. Method leaves override with their own
	count. Uncovered methods contribute 0, so they vanish from the layout."
	^ rollupCoverage ifNil: [
		rollupCoverage := self children inject: 0 into: [:sum :c | sum + c coverageWeight]]
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:37'
}
SWACodeNode >> coverageWeightMode [
	"Which coverage metric drives tile size: #tests (distinct covering-test count,
	the default) or #invocations (raw call count). Resolves up the parent chain like
	#coverageData, so it need only be set on the root."
	coverageWeightMode ifNotNil: [^ coverageWeightMode].
	parent ifNotNil: [:p | ^ p coverageWeightMode].
	^ #tests
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 14:37'
}
SWACodeNode >> coverageWeightMode: aSymbolOrNil [
	"#tests (covering-test count) or #invocations (raw call count). Normally set only
	on the root. Clears the cached coverage roll-up so the new metric takes effect."
	coverageWeightMode := aSymbolOrNil.
	rollupCoverage := nil
]

{
	#category : #'dataset-weight',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:51'
}
SWACodeNode >> datasetWeight [
	"Rolled-up SIZE weight from the active dataset #sizeMetric: a method leaf uses its
	own raw metric value; a container sums its children (cached). Nodes the metric
	ignores contribute 0, so uncovered/unmatched subtrees collapse -- exactly like
	#coverageWeight, but for an arbitrary loaded metric. 0 when no metric is active."
	| metric |
	metric := self sizeMetric.
	metric ifNil: [^ 0].
	^ rollupDataset ifNil: [
		rollupDataset := self isLeaf
			ifTrue: [(metric weightForNode: self) ]
			ifFalse: [self children inject: 0 into: [:sum :c | sum + c datasetWeight]]]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeNode >> dominantTopic [
	"The argmax topic id (0-based) over this subtree's rolled-up distribution, or nil
	if no topic data / no covered methods below."
	| dist best bestT |
	dist := self topicDistribution.
	dist isEmpty ifTrue: [^ nil].
	best := -1.0. bestT := nil.
	dist keysAndValuesDo: [:topic :wgt | wgt > best ifTrue: [best := wgt. bestT := topic]].
	^ bestT
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeNode >> dotFillColor [
	"A pastel fill per kind, so the four levels are visually distinct.
	(Metric-driven heat coloring will be a later option.)"
	self kind = #package ifTrue: [^ '#cfe2ff'].
	self kind = #class ifTrue: [^ '#cde8cd'].
	self kind = #category ifTrue: [^ '#fff2cc'].
	self kind = #method ifTrue: [^ self isStatic ifTrue: ['#e6d5f5'] ifFalse: ['#ffffff']].
	^ '#eeeeee'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeNode >> dotId [
	"A stable DOT node id for the receiver (based on identity)."
	^ 'n', self identityHash printString
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodeNode >> dotLabel [
	"Multi-line node label: name plus a metric summary. Subclasses may refine.
	Uses real LF separators; dotEscape: turns them into DOT's \\n."
	| s |
	s := self name.
	self loc > 0 ifTrue: [s := s, String lf, self loc printString, ' LOC'].
	^ SWACodeNode dotEscape: s
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeNode >> dotNodeStatementOn: aStream [
	"Write one DOT node statement for the receiver."
	aStream
		nextPutAll: '  '; nextPutAll: self dotId;
		nextPutAll: ' [label="'; nextPutAll: self dotLabel;
		nextPutAll: '", shape='; nextPutAll: self dotShape;
		nextPutAll: ', style="filled'.
	self isStatic ifTrue: [aStream nextPutAll: ',bold'].
	aStream
		nextPutAll: '", fillcolor="'; nextPutAll: self dotFillColor;
		nextPutAll: '"];'; nextPut: Character lf
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:02'
}
SWACodeNode >> dotShape [
	"Box for everything; subclasses may override (e.g. methods rounded)."
	^ 'box'
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:05'
}
SWACodeNode >> edgeLabel [
	"No edge labels in the code treemap."
	^ nil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:31'
}
SWACodeNode >> estimatedNodeCount [
	"A cheap up-front estimate of how many nodes the full subtree will have, used
	to scale a build progress bar. For a package this is classes + their methods
	(+ category nodes), computed WITHOUT forcing source/LOC. Subclasses refine;
	default falls back to counting already-built children."
	^ 1 + (self children inject: 0 into: [:s :c | s + c estimatedNodeCount])
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeNode >> flushSizeRollups [
	"Drop the metric-dependent roll-up caches (#rollupBytes, #rollupCoverage,
	#rollupDataset). The #rollupLoc and #rollupMethodCount caches are metric-stable,
	so they are kept."
	rollupBytes := nil.
	rollupCoverage := nil.
	rollupDataset := nil
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeNode >> hueFamily [
	"The hue family index (0-based) for this node's dominant topic, or nil."
	| td topic |
	td := self topicData.
	td ifNil: [^ nil].
	topic := self dominantTopic.
	topic ifNil: [^ nil].
	^ td hueFamilyForTopic: topic
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> isStatic [
	"True for class-side (UML 'static') elements. Default false."
	^ false
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> kind [
	"A symbol naming this node's level. Subclasses override."
	^ #node
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:29'
}
SWACodeNode >> lastAuthor [
	"Author initials of the most recently changed leaf over the subtree, or nil.
	Tracks lastChanged so author color and recency color agree. Method leaves override."
	| best bestAuthor |
	best := nil.
	bestAuthor := nil.
	self children do: [:c | | t |
		t := c lastChanged.
		(t notNil and: [best isNil or: [t > best]])
			ifTrue: [best := t. bestAuthor := c lastAuthor]].
	^ bestAuthor
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> lastChanged [
	"Most recent change DateAndTime over the subtree, or nil. Method leaves override."
	| best |
	best := nil.
	self children do: [:c | | t |
		t := c lastChanged.
		(t notNil and: [best isNil or: [t > best]]) ifTrue: [best := t]].
	^ best
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/23/2026 11:45'
}
SWACodeNode >> loc [
	"Lines of code. Default: sum over children (roll-up), cached so repeated layout
	passes don't re-walk the subtree. Method leaves override with their own count."
	^ rollupLoc ifNil: [
		rollupLoc := self children inject: 0 into: [:sum :c | sum + c loc]]
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 12:37'
}
SWACodeNode >> methodCount [
	"Number of method leaves in this subtree (cached). Method leaves override with 1."
	^ rollupMethodCount ifNil: [
		rollupMethodCount := self children inject: 0 into: [:sum :c | sum + c methodCount]]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> name [
	"Display name. Subclasses override."
	^ subject printString
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:04'
}
SWACodeNode >> openClassTreemap [
	"Open a treemap that stops at the CLASS level: packages and classes sized by
	their total LOC, with no method/category tiles. Metrics (LOC, recency, author)
	still roll up from the real methods underneath."
	^ self openTreemapLeafKind: #class
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:37'
}
SWACodeNode >> openContainmentGraph [
	"Open the Package -> Class -> Category -> Method containment graph."
	^ self
		openGraph: [self containmentGraph]
		engine: 'dot'
		label: 'Code Map: ', self name, '  (containment)'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:37'
}
SWACodeNode >> openGraph: aTupleOrBlock engine: engineString label: aLabel [
	"Open a GraphvizPane on a { dotString. ids. truncated } tuple. The first arg
	may be the tuple itself or a 0-arg block that produces it (preferred, so the
	potentially slow DOT generation runs inside the progress region). Node clicks
	-> #browse on the matching SWACodeNode. The DOT-build and the external layout
	run are wrapped in a progress bar whose label reflects the current phase."
	| tuple dot ids gm pane win byDotId |
	gm := GraphvizMorph new.
	gm engine: engineString.
	pane := nil.
	('Code map: ', self name)
		displayProgressFrom: 0 to: 3 during: [:bar |
			bar value: 'Generating DOT...'.
			tuple := aTupleOrBlock isBlock
				ifTrue: [aTupleOrBlock value]
				ifFalse: [aTupleOrBlock].
			bar value: 1.
			dot := tuple first.
			ids := tuple second.
			byDotId := Dictionary new.
			ids keysAndValuesDo: [:node :dotId | byDotId at: dotId put: node].
			bar value: 'Running ', engineString, ' layout (', byDotId size printString, ' nodes)...'.
			gm setDot: dot.
			bar value: 2.
			bar value: 'Building window...'.
			pane := GraphvizPane new graph: gm.
			pane onNodeClick: [:dotId | | node |
				node := byDotId at: dotId ifAbsent: [nil].
				node ifNotNil: [
					Transcript showln: 'Browse: ', node name.
					WorldState addDeferredUIMessage: [node browse]]].
			pane extent: 820 @ 600.
			bar value: 3].
	win := pane openInWindowLabeled: aLabel.
	win center: World center.
	^ win
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 18:04'
}
SWACodeNode >> openTreemap [
	"Open a squarified treemap of the full subtree (down to methods)."
	^ self openTreemapLeafKind: nil
]

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:49'
}
SWACodeNode >> openTreemapLeafKind: aLeafKindOrNil [
	"Open a squarified treemap of this code subtree (tiles sized by LOC). The full
	tree is built so LOC/recency/author roll up from real methods, but layout stops
	at aLeafKindOrNil (e.g. #class to show packages+classes but no methods); nil
	lays out the full tree down to methods. The shared SWANavPanel supplies the
	window chrome. A single progress bar covers the build + layout phases."
	| treemap overlay panel window total label bounds |
	total := (self estimatedNodeCount max: 1) * 2.   "build pass + layout pass"
	treemap := SWACodeTreemapMorph on: self.
	treemap leafKind: aLeafKindOrNil.
	treemap extent: (Display extent * 0.7) rounded - (0 @ 60).
	('Code map: ', self name)
		displayProgressFrom: 0 to: total during: [:bar |
			| done |
			bar value: 'Building nodes + counting LOC...'.
			done := 0.
			self prewarmDo: [:n |
				done := done + 1.
				(done \\ 64 = 0) ifTrue: [bar value: done]].
			bar value: 'Laying out treemap...'.
			treemap layoutProgress: [:n |
				done := done + 1.
				(done \\ 64 = 0) ifTrue: [bar value: (done min: total)]].
			treemap ensureLayout.
			treemap layoutProgress: nil.
			bar value: total].

	overlay := SWACodeTreemapOverlay new.
	overlay treemapMorph: treemap.
	overlay extent: treemap extent.
	treemap overlayMorph: overlay.
	treemap addMorph: overlay.

	panel := SWANavPanel on: treemap.

	label := aLeafKindOrNil
		ifNil: ['Code Treemap: ', self name, '  (LOC)']
		ifNotNil: [:k | 'Code Treemap: ', self name, '  (LOC, to ', k, ')'].
	window := panel openInWindow.
	window setLabel: label.
	"Default bounds: sized so the wrapped header + info lines + map fit without the
	visualization overflowing the bottom. Clipped to the screen if smaller."
	bounds := SWANavPanel defaultWindowBounds intersect: (0 @ 0 corner: Display extent).
	window bounds: bounds.
	"Stop the window from shrinking narrower than one full button row (the bar
	wraps above that floor); does not force it WIDER than the default."
	panel enforceMinimumWindowWidth.
	^ window
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:20'
}
SWACodeNode >> otherParents [
	"Code nodes form a strict tree (single parent), so there are no 'other parents'
	the way the SpaceTally object-graph treemap has. The treemap overlay guards on
	nil, so answering nil disables that decoration."
	^ nil
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:31'
}
SWACodeNode >> prewarmDo: aBlock [
	"Depth-first walk that forces each node's children to be built and its LOC to
	be computed (the expensive source-fetching step), evaluating aBlock once per
	node visited. Use this to drive a progress bar before layout."
	self loc.
	aBlock value: self.
	self children do: [:c | c prewarmDo: aBlock]
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> printOn: aStream [
	aStream nextPutAll: self class name; nextPut: $(; nextPutAll: self name; nextPut: $)
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/30/2026 10:00'
}
SWACodeNode >> root [
	"Walk the parent chain to the top SWACodeRootNode (its parent is nil)."
	^ parent isNil ifTrue: [self] ifFalse: [parent root]
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 13:04'
}
SWACodeNode >> selfSize [
	"LOC owned directly by this node (non-leaf nodes own none; method leaves own
	their lines)."
	^ self isLeaf ifTrue: [self loc] ifFalse: [0]
]

{
	#category : #'dataset-weight',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeNode >> setSizeMetric: aSWADatasetMetric [
	"Bind tile SIZE to a loaded dataset metric on this (root) node and flush the size
	roll-up caches over the whole subtree so the new weights lay out next pass.
	Counterpart to #setWeightMetric: for the intrinsic metrics."
	sizeMetric := aSWADatasetMetric.
	self withAllChildrenDo: [:n | n flushSizeRollups]
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeNode >> setWeightMetric: aSymbol [
	"Set an INTRINSIC size metric on this (root) node, clearing any active dataset
	size metric, AND flush the size roll-up caches over the WHOLE built subtree so a
	live switch takes effect on the next layout. LOC and method-count caches are
	metric-stable and kept."
	weightMetric := aSymbol.
	sizeMetric := nil.
	self withAllChildrenDo: [:n | n flushSizeRollups]
]

{
	#category : #'dataset-weight',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:51'
}
SWACodeNode >> sizeMetric [
	"The active SWADatasetMetric driving tile SIZE, or nil for an intrinsic metric.
	Resolves up the parent chain like #weightMetric, so it need only be set on root."
	sizeMetric ifNotNil: [^ sizeMetric].
	parent ifNotNil: [:p | ^ p sizeMetric].
	^ nil
]

{
	#category : #'dataset-weight',
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:51'
}
SWACodeNode >> sizeMetric: aSWADatasetMetricOrNil [
	"Set the dataset metric driving tile SIZE (nil = back to intrinsic #weightMetric).
	Set on the root; #totalSize consults it via #datasetWeight."
	sizeMetric := aSWADatasetMetricOrNil
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:43'
}
SWACodeNode >> sourceString [
	"Text to show in the embedded source pane. Non-method nodes have no single
	source, so describe the node instead. Method leaves override with real source."
	^ self kind asString, ': ', self name, String cr, String cr,
		'(', self loc printString, ' lines of code over the subtree)'
]

{
	#category : #metrics,
	#'squeak_changestamp' : 'MCPServer 6/22/2026 16:43'
}
SWACodeNode >> styleClassOrNil [
	"Class (or metaclass) to use as Shout styling context for the source pane,
	or nil when not applicable. Method leaves override."
	^ nil
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> subject [
	^ subject
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> subject: anObject [
	subject := anObject
]

{
	#category : #'coverage-weight',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 15:17'
}
SWACodeNode >> testWeightFloor [
	"Minimum coverage weight for a test method, so tests stay visible on the
	coverage-weighted map (their real coverage weight is 0). Configurable per mode
	via the class-side accessors."
	^ self coverageWeightMode == #invocations
		ifTrue: [self class testWeightFloorInvocations]
		ifFalse: [self class testWeightFloorTests]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeNode >> topicData [
	"The SWATopicData driving #topic coloring, or nil. Set on the root; children
	inherit it up the parent chain (like #coverageData), so lazily-built nodes see
	it without per-node wiring."
	topicData ifNotNil: [^ topicData].
	^ parent ifNil: [nil] ifNotNil: [parent topicData]
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeNode >> topicData: aTopicDataOrNil [
	"Set the SWATopicData that drives #topic coloring for this subtree. Normally set
	only on the root node; children inherit it by walking up the parent chain (see
	#topicData). Clears any cached dominant-topic roll-up."
	topicData := aTopicDataOrNil.
	rollupTopic := nil
]

{
	#category : #topic,
	#'squeak_changestamp' : 'MCPServer 7/7/2026 11:41'
}
SWACodeNode >> topicDistribution [
	"A Dictionary topicId -> summed weight over this subtree's method leaves, using
	the inherited SWATopicData. Aggregate tiles roll up their children; method leaves
	answer their own single distribution. Cached in rollupTopic. Empty if no data."
	| td |
	rollupTopic ifNotNil: [^ rollupTopic].
	td := self topicData.
	td ifNil: [^ rollupTopic := Dictionary new].
	rollupTopic := Dictionary new.
	self children do: [:c |
		(c topicDistribution) keysAndValuesDo: [:topic :wgt |
			rollupTopic at: topic put: (rollupTopic at: topic ifAbsent: [0.0]) + wgt]].
	^ rollupTopic
]

{
	#category : #treemap,
	#'squeak_changestamp' : 'MCPServer 7/1/2026 10:52'
}
SWACodeNode >> totalSize [
	"Treemap weight, selected by #weightMetric (the live 'Size' menu):
	  #methods      -- number of method leaves in the subtree,
	  #loc          -- rolled-up lines of code (the default),
	  #bytes        -- rolled-up source byte size (doc/string/code bar),
	  #invocations  -- rolled-up dynamic CALL count (needs profile/coverage data),
	  #tests        -- rolled-up distinct covering-test count (needs coverage data).
	OR, when a loaded DATASET metric drives size (#sizeMetric set), the rolled-up
	value of that metric (#datasetWeight); like the legacy dynamic metrics it floors
	at 0, so a subtree the metric ignores collapses to no width.
	The static metrics floor at 1 so a tile never vanishes for lack of code."
	| metric |
	self sizeMetric ifNotNil: [^ self datasetWeight].
	metric := self weightMetric.
	(metric == #invocations or: [metric == #tests]) ifTrue: [^ self coverageWeight].
	metric == #methods ifTrue: [^ self methodCount max: 1].
	metric == #bytes ifTrue: [^ self byteWeight max: 1].
	^ self loc max: 1
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:34'
}
SWACodeNode >> weightMetric [
	"Which metric sizes the treemap tiles: nil/#loc (lines of code, the default and
	historical behaviour) or #bytes (source-text byte size, with the
	doc/string/code composition bar). Resolves up the parent chain like
	#coverageData, so it need only be set on the root. Coverage weighting, when a
	SWACoverageData is present, takes priority over this in #totalSize."
	weightMetric ifNotNil: [^ weightMetric].
	parent ifNotNil: [:p | ^ p weightMetric].
	^ #loc
]

{
	#category : #'byte-metrics',
	#'squeak_changestamp' : 'MCPServer 6/29/2026 17:02'
}
SWACodeNode >> weightMetric: aSymbolOrNil [
	"Set the active size metric (#structure/#methods/#loc/#bytes/#invocations/#tests).
	Normally set on the root; resolves down via #weightMetric. Clears the byte and
	coverage roll-up caches so a switch between #invocations and #tests (or in/out of
	#bytes) recomputes."
	weightMetric := aSymbolOrNil.
	rollupBytes := nil.
	rollupCoverage := nil
]
