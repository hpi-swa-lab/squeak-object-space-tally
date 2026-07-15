"
Treemap view of a time-bucketed changes tree (SWAChangeNode).

Tiles are sized by rolled-up lines of code, so busier days/saves and larger
methods get bigger tiles. The default color mode (#changeKind) tints the temporal
container levels (year/month/week/day/save) on a cool depth ramp, and the leaf
change tiles by change type: methods green, doIts blue, class definitions purple,
comments teal, removals red.

Clicking a tile selects it (source shown in the Show pane); clicking the selected
tile zooms in. Leaves' source is their change text; containers show a summary.
"
Class {
	#name : #SWAChangeTreemapMorph,
	#superclass : #AnObsoleteSWATreemapMorph,
	#category : #'SWA-ChangeMap',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:06'
}
SWAChangeTreemapMorph >> aboutToStyle: aStyler [
	"Suppress Shout syntax styling while an inline DIFF is shown (otherwise the
	styler would repaint over TextDiffBuilder's removed/inserted-line colors).
	A diff is shown for a selected method-change leaf that has a diff baseline.
	Otherwise behave exactly like the superclass (highlight source in class context)."
	(selectedNode notNil
		and: [selectedNode respondsTo: #hasDiffBaseline]
		and: [selectedNode hasDiffBaseline]) ifTrue: [^ false].
	^ super aboutToStyle: aStyler
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapMorph >> balloonStringFor: aNode [
	^ String streamContents: [:s |
		s nextPutAll: aNode name; cr.
		s nextPutAll: 'level: '; nextPutAll: aNode kind asString; cr.
		aNode kind == #change
			ifTrue: [s nextPutAll: 'type:  '; nextPutAll: aNode changeType asString; cr.
				s nextPutAll: 'status: '; nextPutAll: (aNode statusSymbol ifNil: ['-']) asString; cr.
				aNode author ifNotNil: [:a | s nextPutAll: 'author: '; nextPutAll: a; cr].
				s nextPutAll: 'LOC:   '; print: aNode loc; cr]
			ifFalse: [s print: aNode changeCount; nextPutAll: ' changes, ';
				print: aNode totalLoc; nextPutAll: ' LOC'; cr.
				aNode dominantAuthor ifNotNil: [:a |
					s nextPutAll: 'top author: '; nextPutAll: a; cr]].
		aNode timeStamp ifNotNil: [:t |
			s nextPutAll: 'when:  '; nextPutAll: t printString; cr].
		s nextPutAll: 'path:  '; nextPutAll: aNode pathString]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapMorph >> baseColorForNode: aNode [
	"Cross-ref/dataset metrics win when active; otherwise the intrinsic modes."
	(self metricForMode: colorMode) ifNotNil: [:metric |
		^ (metric colorForNode: aNode) ifNil: [Color gray: 0.22]].
	colorMode == #recency ifTrue: [^ self colorByRecency: aNode].
	colorMode == #author ifTrue: [^ self colorByAuthor: aNode].
	colorMode == #status ifTrue: [^ self colorByStatus: aNode].
	^ self colorByChangeKind: aNode
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapMorph >> colorByAuthor: aNode [
	"Stable per-author hue (containers use their dominant author). Unknown = gray."
	| a |
	a := aNode dominantAuthor.
	a ifNil: [^ Color gray: 0.3].
	^ Color h: (a hash \\ 360) s: 0.55 v: 0.82
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 15:06'
}
SWAChangeTreemapMorph >> colorByChangeKind: aNode [
	"Leaf changes by change type; package/class grouping in warm structural hues;
	temporal containers on a cool depth ramp."
	| depth |
	aNode kind == #change ifTrue: [
		^ aNode changeType caseOf: {
			[#method] -> [Color h: 130 s: 0.5 v: 0.80].
			[#doIt] -> [Color h: 210 s: 0.5 v: 0.82].
			[#classDefinition] -> [Color h: 280 s: 0.45 v: 0.82].
			[#classComment] -> [Color h: 190 s: 0.5 v: 0.80].
			[#methodRemoval] -> [Color h: 0 s: 0.6 v: 0.82].
		} otherwise: [Color gray: 0.6]].
	aNode kind == #package ifTrue: [^ Color h: 45 s: 0.5 v: 0.80].
	aNode kind == #class ifTrue: [^ Color h: 90 s: 0.4 v: 0.78].
	depth := aNode depth.
	^ (Color h: 220 s: 0.30 v: 0.72) adjustBrightness: depth \\ 5 * -0.05
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:55'
}
SWAChangeTreemapMorph >> colorByRecency: aNode [
	"Heat by how recently the node's change happened within the tree's span:
	older = blue, newer = red."
	| ts span now oldest frac |
	ts := aNode timeStamp.
	ts ifNil: [^ Color gray: 0.3].
	now := TimeStamp now asSeconds.
	oldest := rootNode timeStamp
		ifNil: [now - (30 * 24 * 60 * 60)]
		ifNotNil: [:t | t asSeconds].
	span := (now - oldest) max: 1.
	frac := ((ts asSeconds - oldest) / span) min: 1.0 max: 0.0.
	^ Color h: 240 - (frac * 240) s: 0.6 v: 0.85
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapMorph >> colorByStatus: aNode [
	"Provenance status color. Leaves use their #statusSymbol; containers use the
	status of their most salient descendant (highest-priority present)."
	| s |
	s := aNode isLeaf
		ifTrue: [aNode statusSymbol]
		ifFalse: [self dominantStatusOf: aNode].
	^ s caseOf: {
		[#current]    -> [Color h: 130 s: 0.55 v: 0.80].   "green: matches live method"
		[#superseded] -> [Color h: 40 s: 0.65 v: 0.85].    "amber: older version exists"
		[#inHistory]  -> [Color h: 200 s: 0.5 v: 0.82].    "blue: in version history"
		[#gone]       -> [Color h: 0 s: 0.6 v: 0.80].       "red: class/selector removed"
		[#other]      -> [Color h: 280 s: 0.4 v: 0.80].     "purple: differs, not in history"
		[#doIt]       -> [Color gray: 0.45].
	} otherwise: [Color gray: 0.3]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:26'
}
SWAChangeTreemapMorph >> detailContainerInfo: n on: s [
	"Detail lines specific to a CONTAINER node (year/month/week/day/save/pkg/class)."
	s nextPutAll: 'changes: '; print: n changeCount; cr.
	s nextPutAll: 'diff size: '; print: n totalLoc; nextPutAll: ' lines'; cr.
	n dominantAuthor ifNotNil: [:a |
		s nextPutAll: 'top author: '; nextPutAll: a; cr]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAChangeTreemapMorph >> detailInfoString [
	"Multi-line details for the Show-mode Details box (bottom-left), one
	'label: value' per line, like the Code Map. Describes the selected node:
	change leaves get type/status/author/when/diff-size/baseline; containers get
	change count, rolled-up diff size, and top author. '' when nothing is selected.
	(SWAPane content protocol.)"
	| n |
	n := selectedNode ifNil: [^ ''].
	^ String streamContents: [:s |
		s nextPutAll: n kind asString; nextPutAll: ': '; nextPutAll: n name; cr.
		n isLeaf
			ifTrue: [self detailLeafInfo: n on: s]
			ifFalse: [self detailContainerInfo: n on: s].
		n timeStamp ifNotNil: [:t |
			s nextPutAll: 'when: '; nextPutAll: t asDate printString;
				nextPutAll: ' '; nextPutAll: t asTime print24; cr].
		s nextPutAll: 'path:'; cr.
		s nextPutAll: '  '; nextPutAll: (n pathString copyReplaceAll: ' / ' with: String cr, '  ')]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:26'
}
SWAChangeTreemapMorph >> detailLeafInfo: n on: s [
	"Detail lines specific to a change LEAF."
	s nextPutAll: 'type: '; nextPutAll: n changeType asString; cr.
	s nextPutAll: 'status: '; nextPutAll: (n statusSymbol ifNil: ['-']) asString; cr.
	s nextPutAll: 'author: '; nextPutAll: (n author ifNil: ['?']); cr.
	n hasDiffBaseline
		ifTrue: [
			s nextPutAll: 'diff: '; print: n diffLines; nextPutAll: ' changed lines'; cr.
			s nextPutAll: 'baseline: '; nextPutAll: (n changeType == #methodRemoval
				ifTrue: ['removed body']
				ifFalse: [n prevInScope ifNil: ['image version'] ifNotNil: [:p | 'previous in view']]); cr]
		ifFalse: [
			s nextPutAll: 'lines: '; print: n loc; cr]
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 17:38'
}
SWAChangeTreemapMorph >> dominantStatusOf: aNode [
	"The most salient leaf status under aNode, so trouble spots surface on
	container tiles: #gone > #other > #superseded > #inHistory > #current > #doIt."
	| order best bestRank |
	order := #(#gone #other #superseded #inHistory #current #doIt).
	best := nil. bestRank := 999.
	aNode withAllChildrenDo: [:n | | r |
		n isLeaf ifTrue: [
			r := order indexOf: n statusSymbol ifAbsent: [999].
			r < bestRank ifTrue: [bestRank := r. best := n statusSymbol]]].
	^ best
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:55'
}
SWAChangeTreemapMorph >> formatWeight: aNumber [
	^ aNumber printString, ' LOC'
]

{
	#category : #initialization,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 14:55'
}
SWAChangeTreemapMorph >> initialize [
	super initialize.
	colorMode := #changeKind
]

{
	#category : #rendering,
	#'squeak_changestamp' : 'MCPServer 7/9/2026 18:21'
}
SWAChangeTreemapMorph >> selectedSourceString [
	"Show pane content. For a selected method change with a baseline, show the
	INLINE DIFF styled by TextDiffBuilder, like the versions browser:
	 - definition: baseline (previous in view, else image version) -> this change
	 - removal:    the removed method body -> empty  (all lines removed)
	Otherwise plain source (which Shout then highlights)."
	| node origin |
	node := selectedNode.
	(node notNil and: [node respondsTo: #hasDiffBaseline]) ifFalse: [
		^ super selectedSourceString].
	node hasDiffBaseline ifTrue: [
		origin := node changeType == #methodRemoval
			ifTrue: ['REMOVED  (', (node crossRefKey ifNil: ['?']), ')']
			ifFalse: [(node prevInScope ifNil: ['diff vs image version'] ifNotNil: [:p | 'diff vs previous in view']),
				'  ->  this change  (', (node crossRefKey ifNil: ['?']), ')'].
		^ (('"', origin, '"', String cr, String cr) asText),
		  (TextDiffBuilder buildDisplayPatchFrom: node diffFromSource to: node diffToSource)].
	^ super selectedSourceString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 11:01'
}
SWAChangeTreemapMorph >> selectionInfoString [
	"Line 2 of the panel info area: a one-line summary of the current selection,
	or '' when nothing is selected. (SWAPane content protocol.)"
	| n |
	n := selectedNode ifNil: [^ ''].
	^ String streamContents: [:s |
		s nextPutAll: n name.
		n isLeaf
			ifTrue: [
				s nextPutAll: '   ['; nextPutAll: (n statusSymbol ifNil: ['-']) asString; nextPut: $].
				n author ifNotNil: [:a | s nextPutAll: '   '; nextPutAll: a].
				n hasDiffBaseline ifTrue: [
					s nextPutAll: '   '; print: n diffLines; nextPutAll: ' diff lines']]
			ifFalse: [
				s nextPutAll: '   '; print: n changeCount; nextPutAll: ' changes, ';
					print: n totalLoc; nextPutAll: ' diff lines']]
]
