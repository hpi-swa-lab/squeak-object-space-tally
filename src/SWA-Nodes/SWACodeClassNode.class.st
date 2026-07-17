"
A SWACodeNode whose subject is a Class. Children are SWACodeCategoryNodes (one per method category). Class-side (metaclass) categories are included and flagged as UML 'static'. Owns source access so method nodes can delegate to it. Knows its superclass for inheritance-graph edges.
"
Class {
	#name : #SWACodeClassNode,
	#superclass : #SWACodeNode,
	#instVars : [
		'methodFilter',
		'ivarFilter'
	],
	#category : #'SWA-Nodes',
	#'squeak_changestamp' : '<historical>'
}

{
	#category : #jump,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> browse [
	^ ToolSet browseClass: subject
]

{
	#category : #building,
	#'squeak_changestamp' : 'MCPServer 6/29/2026 16:49'
}
SWACodeClassNode >> buildChildren [
	"A SWACodeCommentNode for the class comment (when present), then one
	SWACodeCategoryNode per method category, instance side then class side.
	Class-side categories are flagged static (UML 'static')."
	| nodes comment |
	nodes := OrderedCollection new.
	comment := [subject organization classComment] on: Error do: [:e | nil].
	(comment notNil and: [comment asString withBlanksTrimmed notEmpty]) ifTrue: [
		nodes add: (SWACodeCommentNode on: subject parent: self)].
	subject organization categories do: [:cat |
		(subject organization listAtCategoryNamed: cat) isEmpty ifFalse: [
			nodes add: ((SWACodeCategoryNode on: cat parent: self)
				metaClass: subject;
				isStatic: false;
				yourself)]].
	subject class organization categories do: [:cat |
		(subject class organization listAtCategoryNamed: cat) isEmpty ifFalse: [
			nodes add: ((SWACodeCategoryNode on: cat parent: self)
				metaClass: subject class;
				isStatic: true;
				yourself)]].
	^ nodes
]

{
	#category : #tree,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> classNode [
	"I am the class node my method descendants delegate to."
	^ self
]

{
	#category : #'cross-ref',
	#'squeak_changestamp' : 'MCPServer 6/23/2026 15:33'
}
SWACodeClassNode >> crossRefKey [
	"Classes are identified across views by their (unique) class name."
	^ subject name asString
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:25'
}
SWACodeClassNode >> instVarNames [
	"The receiver class's own instance-variable names (UML state / attributes),
	in definition order. Excludes inherited ivars."
	^ subject instVarNames
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWACodeClassNode >> ivarFilter: aBlockOrNil [
	"Set an optional one-arg predicate (SWACodeInstVarNode -> Boolean) that restricts which
	instance variables this class renders in the diagram's state compartment. nil = show
	all. Used by the class diagram's '+Selected' granularity to show only marked ivars.
	Returns self."
	ivarFilter := aBlockOrNil.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> kind [
	^ #class
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:37'
}
SWACodeClassNode >> methodFilter: aBlockOrNil [
	"Set an optional one-arg predicate (SWACodeMethodNode -> Boolean) that restricts which
	methods this class renders in the diagram's methods compartment. nil = show all. Used
	by the class diagram's 'classes + marked methods' granularity to show only marked
	methods. Returns self."
	methodFilter := aBlockOrNil.
	^ self
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:08'
}
SWACodeClassNode >> methodNodes [
	"All SWACodeMethodNodes of this class, flattened across categories,
	instance-side first then class-side (static)."
	| out |
	out := OrderedCollection new.
	self children do: [:cat | out addAll: cat children].
	^ out
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> name [
	^ subject name asString
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:52'
}
SWACodeClassNode >> recordEmptyRowOn: ws [
	"Emit a single borderless spacer row so an EMPTY but enabled compartment still renders
	as a (blank) UML section below its separator. Uses a non-breaking space so Graphviz
	lays out (and gives us a text baseline for) exactly one row -- keeping the field-rect /
	#recordFieldNodesShowState:showMethods: index alignment. No port -- it is not clickable
	as a member (its field maps back to the class)."
	ws nextPutAll: '<tr><td align="text">&nbsp;<br align="left"/></td></tr>'
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:14'
}
SWACodeClassNode >> recordFieldNodes [
	"Full field-node list (name + ivars + methods). See #recordFieldNodesShowMethods:."
	^ self recordFieldNodesShowMethods: true
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:23'
}
SWACodeClassNode >> recordFieldNodesShowMethods: showMethods [
	"State-always-on variant. See #recordFieldNodesShowState:showMethods:."
	^ self recordFieldNodesShowState: true showMethods: showMethods
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:52'
}
SWACodeClassNode >> recordFieldNodesShowState: showState showMethods: showMethods [
	"The SWACodeNode for each record field, by field index, matching the ROW order emitted
	by #recordLabelColorMode:maxLoc:showState:showMethods: EXACTLY -- including the blank
	spacer row an enabled-but-empty compartment emits (mapped to the class itself, since
	clicking blank space should select the whole class). Index 0 = the class name row; then
	the state rows (one SWACodeInstVarNode per visible ivar, or ONE placeholder = self when
	empty); then the method rows (one per visible method, or ONE placeholder = self when
	empty). Honors the ivar/method filters via #recordIvarNodes / #recordMethodNodes so
	this stays index-aligned with the emitted rows (each blank spacer produces one text
	baseline, hence one field slot). Used to resolve a clicked field index back to its
	node."
	| out ivars methods |
	out := OrderedCollection new.
	out add: self.                        "0: name row"
	showState ifTrue: [
		ivars := self recordIvarNodes.
		ivars isEmpty
			ifTrue: [out add: self]        "blank spacer row -> the class"
			ifFalse: [out addAll: ivars]].
	showMethods ifTrue: [
		methods := self recordMethodNodes.
		methods isEmpty
			ifTrue: [out add: self]        "blank spacer row -> the class"
			ifFalse: [out addAll: methods]].
	^ out asArray
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:44'
}
SWACodeClassNode >> recordIvarNodes [
	"The instance variables as SWACodeInstVarNodes, in definition order -- the state-row
	order for the class box. This is the markable/clickable counterpart to the raw
	#instVarNames strings. When an #ivarFilter is set (the '+Selected' granularity), only
	ivars satisfying it are returned, so the DOT label, the click field map, and the state
	compartment all agree (they all funnel through here)."
	| nodes |
	nodes := self instVarNames collect: [:v |
		(SWACodeInstVarNode on: subject parent: self) ivarName: v; yourself].
	ivarFilter isNil ifTrue: [^ nodes asArray].
	^ (nodes select: [:n | ivarFilter value: n]) asArray
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:40'
}
SWACodeClassNode >> recordLabel [
	"The default UML class box (flat fill by kind). See #recordLabelColorMode:maxLoc:."
	^ self recordLabelColorMode: #kind maxLoc: 0
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:14'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc [
	"The full UML class box (name + state + methods). See
	#recordLabelColorMode:maxLoc:showMethods: for the coarser (classes-only) variant."
	^ self recordLabelColorMode: aColorMode maxLoc: aMaxLoc showMethods: true
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:22'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc showMethods: showMethods [
	"State-always-on variant. See #recordLabelColorMode:maxLoc:showState:showMethods:
	for the three-way granularity (which can also hide the state compartment)."
	^ self
		recordLabelColorMode: aColorMode maxLoc: aMaxLoc
		showState: true showMethods: showMethods
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:51'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc showState: showState showMethods: showMethods [
	"A Graphviz HTML-like label (UML class box) as a <table>: class name (bold) on
	top, then -- when showState is true -- a STATE compartment (one row per ivar),
	then -- when showMethods is true -- a METHODS compartment (one row per method).
	Compartments are separated by <hr/> rules; rows are borderless and left-aligned.
	Row order matches #recordFieldNodesShowState:showMethods:.

	Per UML, an ENABLED compartment always draws its separator line even when it has no
	(visible) rows -- so an empty state/methods section shows as an empty box, and the
	'+Selected' depth (which may filter a compartment down to nothing) keeps the familiar
	three-section shape. The compartment methods emit rows only; the separator is drawn
	here.

	The two flags give the granularities:
	  showState=false, showMethods=false -- classes only (name box)
	  showState=true,  showMethods=false -- classes + state
	  showState=true,  showMethods=true  -- classes + state + methods

	aColorMode selects the fill: #kind (flat by-kind table background) or #loc
	(neutral background + per-method LOC heat tint, scaled to aMaxLoc). Meant to be
	emitted between < and > in the DOT node statement (an HTML label)."
	| ws idx |
	ws := WriteStream on: String new.
	ws nextPutAll: '<table border="1" cellborder="0" cellspacing="0" cellpadding="3" bgcolor="'.
	ws nextPutAll: (self recordTableBgColorMode: aColorMode); nextPutAll: '">'.
	self recordNameRowOn: ws.
	idx := 0.
	showState ifTrue: [
		ws nextPutAll: '<hr/>'.
		idx := self recordStateCompartmentOn: ws startingAt: idx].
	showMethods ifTrue: [
		ws nextPutAll: '<hr/>'.
		idx := self recordMethodCompartmentOn: ws startingAt: idx colorMode: aColorMode maxLoc: aMaxLoc].
	ws nextPutAll: '</table>'.
	^ ws contents
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:51'
}
SWACodeClassNode >> recordMethodCompartmentOn: ws startingAt: startIndex colorMode: aColorMode maxLoc: aMaxLoc [
	"Emit the METHODS compartment rows (one per method, static methods prefixed '$') into
	ws. Ports continue from startIndex. In #loc mode each cell is tinted by its LOC on a
	green->red ramp scaled to aMaxLoc. Answer the next free port index. When there are no
	(visible) methods a single blank spacer row is emitted so the enabled-but-empty section
	still renders below its separator (drawn by the caller). Honors #methodFilter (via
	#recordMethodNodes)."
	| idx locMode methods |
	idx := startIndex.
	locMode := aColorMode = #loc.
	methods := self recordMethodNodes.
	methods isEmpty ifTrue: [self recordEmptyRowOn: ws. ^ idx].
	methods do: [:m | | text cellBg |
		idx := idx + 1.
		text := m isStatic ifTrue: ['$', m name] ifFalse: [m name].
		cellBg := locMode ifTrue: [SWACodeNode locHeatColor: m loc max: aMaxLoc] ifFalse: [nil].
		self recordRowOn: ws port: idx bgColor: cellBg text: text].
	^ idx
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:37'
}
SWACodeClassNode >> recordMethodNodes [
	"The method nodes as laid out in #recordLabel: instance methods first, then
	static (class-side) methods. This ordering defines the record's method field
	order (record field index = this index + 1; field 0 is the class name). When a
	#methodFilter is set (e.g. the 'marked methods only' diagram granularity), only
	methods satisfying it are shown -- consistently across the DOT label, the click
	field map, and the compartment, since all three funnel through here."
	| inst stat all |
	all := methodFilter isNil
		ifTrue: [self methodNodes]
		ifFalse: [self methodNodes select: [:m | methodFilter value: m]].
	inst := all reject: [:m | m isStatic].
	stat := all select: [:m | m isStatic].
	^ inst asArray, stat asArray
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:27'
}
SWACodeClassNode >> recordNameRowOn: ws [
	"Emit the class-name compartment (bold, left-aligned) into ws."
	ws nextPutAll: '<tr><td align="text"><b>'.
	ws nextPutAll: (SWACodeNode htmlEscape: self name).
	ws nextPutAll: '</b><br align="left"/></td></tr>'
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:28'
}
SWACodeClassNode >> recordRowOn: ws port: portIndex bgColor: bgColorOrNil text: aString [
	"Emit one borderless, left-aligned table row into ws: a named port (for click
	geometry), an optional cell background (LOC tint), and the escaped text."
	ws nextPutAll: '<tr><td align="text" port="m', portIndex printString, '"'.
	bgColorOrNil ifNotNil: [:c |
		ws nextPutAll: ' bgcolor="'; nextPutAll: c; nextPutAll: '"'].
	ws nextPutAll: '>'.
	ws nextPutAll: (SWACodeNode htmlEscape: aString).
	ws nextPutAll: '<br align="left"/></td></tr>'
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/17/2026 13:51'
}
SWACodeClassNode >> recordStateCompartmentOn: ws startingAt: startIndex [
	"Emit the STATE compartment rows (one per instance variable) into ws. Ports continue
	from startIndex. Answer the next free port index. When there are no (visible) ivars a
	single blank spacer row is emitted so the enabled-but-empty section still renders below
	its separator (drawn by the caller). Honors #ivarFilter (via #recordIvarNodes)."
	| idx ivarNodes |
	idx := startIndex.
	ivarNodes := self recordIvarNodes.
	ivarNodes isEmpty ifTrue: [self recordEmptyRowOn: ws. ^ idx].
	ivarNodes do: [:n |
		idx := idx + 1.
		self recordRowOn: ws port: idx bgColor: nil text: n ivarName].
	^ idx
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:27'
}
SWACodeClassNode >> recordTableBgColorMode: aColorMode [
	"The <table> background color for a UML class box: a neutral gray in #loc mode
	(so per-method LOC tints read clearly), else the flat by-kind fill."
	^ aColorMode = #loc
		ifTrue: ['#f4f4f4']
		ifFalse: [self dotFillColor]
]

{
	#category : #inheritance,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> superclassName [
	"Name of the superclass, or nil for root classes (Object's superclass etc.)."
	^ subject superclass ifNotNil: [:sc | sc name asString]
]

{
	#category : #accessing,
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> theClass [
	"The live (instance-side) class this node represents."
	^ subject
]
