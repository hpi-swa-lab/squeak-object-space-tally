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
	#superclass : #Object,
	#instVars : [
		'subject',
		'parent',
		'children'
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
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> depth [
	^ parent isNil ifTrue: [0] ifFalse: [parent depth + 1]
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
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> isLeaf [
	^ self children isEmpty
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> loc [
	"Lines of code. Default: sum over children (roll-up). Method leaves override."
	^ self children inject: 0 into: [:sum :c | sum + c loc]
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
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodeNode >> openContainmentGraph [
	"Open the Package -> Class -> Category -> Method containment graph."
	^ self
		openGraph: self containmentGraph
		engine: 'dot'
		label: 'Code Map: ', self name, '  (containment)'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:03'
}
SWACodeNode >> openGraph: aGraphTuple engine: engineString label: aLabel [
	"Open a GraphvizPane on a { dotString. ids. truncated } tuple, wiring node
	clicks to #browse on the corresponding SWACodeNode. 'ids' maps node -> dot-id;
	we invert it so a clicked dot-id finds its node."
	| dot ids gm pane win byDotId |
	dot := aGraphTuple first.
	ids := aGraphTuple second.
	byDotId := Dictionary new.
	ids keysAndValuesDo: [:node :dotId | byDotId at: dotId put: node].
	gm := GraphvizMorph new.
	gm engine: engineString.
	gm setDot: dot.
	pane := GraphvizPane new graph: gm.
	pane onNodeClick: [:dotId | | node |
		node := byDotId at: dotId ifAbsent: [nil].
		node ifNotNil: [
			Transcript showln: 'Browse: ', node name.
			WorldState addDeferredUIMessage: [node browse]]].
	pane extent: 820 @ 600.
	win := pane openInWindowLabeled: aLabel.
	win center: World center.
	^ win
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> parent [
	^ parent
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> parent: aNode [
	parent := aNode
]

{
	#category : #printing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> printOn: aStream [
	aStream nextPutAll: self class name; nextPut: $(; nextPutAll: self name; nextPut: $)
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
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:00'
}
SWACodeNode >> withAllChildrenDo: aBlock [
	"Evaluate aBlock with the receiver and every descendant (depth-first)."
	aBlock value: self.
	self children do: [:c | c withAllChildrenDo: aBlock]
]
