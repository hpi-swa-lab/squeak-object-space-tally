"
A SWACodeNode whose subject is a Class. Children are SWACodeCategoryNodes (one per method category). Class-side (metaclass) categories are included and flagged as UML 'static'. Owns source access so method nodes can delegate to it. Knows its superclass for inheritance-graph edges.
"
Class {
	#name : #SWACodeClassNode,
	#superclass : #SWACodeNode,
	#category : #'SWA-CodeMap',
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> kind [
	^ #class
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:22'
}
SWACodeClassNode >> recordFieldNodesShowState: showState showMethods: showMethods [
	"The SWACodeNode for each record field, by field index, matching the row order
	produced by #recordLabelColorMode:maxLoc:showState:showMethods:: index 0 = the
	class name row, then -- when showState is true -- one entry PER IVAR (the class
	itself -- selecting a state row selects the class, since an ivar is not a
	browsable node), then -- when showMethods is true -- one entry per method in
	#recordMethodNodes order. Used to resolve a clicked field index back to the node
	it represents."
	| out |
	out := OrderedCollection new.
	out add: self.                                            "0: name row"
	showState ifTrue: [self instVarNames do: [:v | out add: self]].  "ivar rows -> the class"
	showMethods ifTrue: [out addAll: self recordMethodNodes].        "method rows"
	^ out asArray
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:28'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc showState: showState showMethods: showMethods [
	"A Graphviz HTML-like label (UML class box) as a <table>: class name (bold) on
	top, then -- when showState is true -- a STATE compartment (one row per ivar),
	then -- when showMethods is true -- a METHODS compartment (one row per method).
	Compartments are separated by <hr/> rules; rows are borderless and left-aligned.
	Row order matches #recordFieldNodesShowState:showMethods:.

	The two flags give three meaningful granularities:
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
	showState ifTrue: [idx := self recordStateCompartmentOn: ws startingAt: idx].
	showMethods ifTrue: [
		idx := self recordMethodCompartmentOn: ws startingAt: idx colorMode: aColorMode maxLoc: aMaxLoc].
	ws nextPutAll: '</table>'.
	^ ws contents
]

{
	#category : #'as yet unclassified',
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:28'
}
SWACodeClassNode >> recordMethodCompartmentOn: ws startingAt: startIndex colorMode: aColorMode maxLoc: aMaxLoc [
	"Emit the METHODS compartment (one row per method, static methods prefixed '$'),
	preceded by an <hr/> rule, into ws. Ports continue from startIndex. In #loc mode
	each cell is tinted by its LOC on a green->red ramp scaled to aMaxLoc. Answer the
	next free port index. Emits nothing (and answers startIndex) when there are no
	methods."
	| idx locMode |
	idx := startIndex.
	self recordMethodNodes isEmpty ifTrue: [^ idx].
	locMode := aColorMode = #loc.
	ws nextPutAll: '<hr/>'.
	self recordMethodNodes do: [:m | | text cellBg |
		idx := idx + 1.
		text := m isStatic ifTrue: ['$', m name] ifFalse: [m name].
		cellBg := locMode ifTrue: [SWACodeNode locHeatColor: m loc max: aMaxLoc] ifFalse: [nil].
		self recordRowOn: ws port: idx bgColor: cellBg text: text].
	^ idx
]

{
	#category : #graphviz,
	#'squeak_changestamp' : 'MCPServer 7/13/2026 17:43'
}
SWACodeClassNode >> recordMethodNodes [
	"The method nodes as laid out in #recordLabel: instance methods first, then
	static (class-side) methods. This ordering defines the record's method field
	order (record field index = this index + 1; field 0 is the class name)."
	| inst stat |
	inst := self methodNodes reject: [:m | m isStatic].
	stat := self methodNodes select: [:m | m isStatic].
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
	#'squeak_changestamp' : 'MCPServer 7/14/2026 10:28'
}
SWACodeClassNode >> recordStateCompartmentOn: ws startingAt: startIndex [
	"Emit the STATE compartment (one row per instance variable), preceded by an <hr/>
	rule, into ws. Ports continue from startIndex. Answer the next free port index.
	Emits nothing (and answers startIndex) when there are no ivars."
	| idx |
	idx := startIndex.
	self instVarNames isEmpty ifTrue: [^ idx].
	ws nextPutAll: '<hr/>'.
	self instVarNames do: [:v |
		idx := idx + 1.
		self recordRowOn: ws port: idx bgColor: nil text: v].
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
