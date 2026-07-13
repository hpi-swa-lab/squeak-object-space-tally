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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 18:26'
}
SWACodeClassNode >> recordFieldNodes [
	"The SWACodeNode for each record field, by field index, matching the row order
	produced by #recordLabel: index 0 = the class name row, then one entry PER IVAR
	(the class itself -- selecting a state row selects the class, since an ivar is
	not a browsable node), then one entry per method in #recordMethodNodes order.
	Used to resolve a clicked field index back to the node it represents."
	| out |
	out := OrderedCollection new.
	out add: self.                                   "0: name row"
	self instVarNames do: [:v | out add: self].      "ivar rows -> the class"
	out addAll: self recordMethodNodes.              "method rows"
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
	#'squeak_changestamp' : 'MCPServer 7/13/2026 19:01'
}
SWACodeClassNode >> recordLabelColorMode: aColorMode maxLoc: aMaxLoc [
	"A Graphviz HTML-like label (UML class box) as a <table>: class name (bold) on
	top, a STATE compartment (one row per ivar), then a METHODS compartment (one row
	per method). Compartments are separated by <hr/> rules; rows are borderless and
	left-aligned. Row order matches #recordFieldNodes. Static methods are prefixed
	with '$' (UML static marker).

	aColorMode selects the fill:
	  #kind -- flat pastel table background per node kind (the default).
	  #loc  -- neutral table background, and each METHOD cell is tinted by its LOC on
	           a green->red heat ramp scaled to aMaxLoc (the max method LOC in the
	           whole diagram, so colors are comparable across classes).

	Meant to be emitted between < and > in the DOT node statement (an HTML label)."
	| ws bg ivars idx locMode |
	locMode := aColorMode = #loc.
	bg := locMode ifTrue: ['#f4f4f4'] ifFalse: [self dotFillColor].
	ivars := self instVarNames.
	ws := WriteStream on: String new.
	ws nextPutAll: '<table border="1" cellborder="0" cellspacing="0" cellpadding="3" bgcolor="'.
	ws nextPutAll: bg; nextPutAll: '">'.
	"Name compartment."
	ws nextPutAll: '<tr><td align="text"><b>'.
	ws nextPutAll: (SWACodeNode htmlEscape: self name).
	ws nextPutAll: '</b><br align="left"/></td></tr>'.
	"State compartment."
	idx := 0.
	ivars isEmpty ifFalse: [
		ws nextPutAll: '<hr/>'.
		ivars do: [:v |
			idx := idx + 1.
			ws nextPutAll: '<tr><td align="text" port="m', idx printString, '">'.
			ws nextPutAll: (SWACodeNode htmlEscape: v).
			ws nextPutAll: '<br align="left"/></td></tr>']].
	"Methods compartment (per-cell LOC tint in #loc mode)."
	self recordMethodNodes isEmpty ifFalse: [
		ws nextPutAll: '<hr/>'.
		self recordMethodNodes do: [:m | | text cellBg |
			idx := idx + 1.
			text := m isStatic ifTrue: ['$', m name] ifFalse: [m name].
			ws nextPutAll: '<tr><td align="text" port="m', idx printString, '"'.
			locMode ifTrue: [
				cellBg := SWACodeNode locHeatColor: m loc max: aMaxLoc.
				ws nextPutAll: ' bgcolor="'; nextPutAll: cellBg; nextPutAll: '"'].
			ws nextPutAll: '>'.
			ws nextPutAll: (SWACodeNode htmlEscape: text).
			ws nextPutAll: '<br align="left"/></td></tr>']].
	ws nextPutAll: '</table>'.
	^ ws contents
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
