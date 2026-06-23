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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:01'
}
SWACodeClassNode >> buildChildren [
	"One SWACodeCategoryNode per method category, instance side then class side.
	Class-side categories are flagged static (UML 'static')."
	| nodes |
	nodes := OrderedCollection new.
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
	#'squeak_changestamp' : 'MCPServer 6/19/2026 12:12'
}
SWACodeClassNode >> recordLabel [
	"A DOT record label (UML-style): class name on top, instance methods below,
	then a separated compartment of class-side (static) methods. Static methods
	are prefixed with '$' (UML static marker). Each method line ends with '\\l'
	so field text is LEFT-justified. The whole record is one node."
	| ws inst stat |
	inst := self methodNodes reject: [:m | m isStatic].
	stat := self methodNodes select: [:m | m isStatic].
	ws := WriteStream on: String new.
	ws nextPutAll: (SWACodeNode dotEscape: self name).
	inst do: [:m |
		ws nextPutAll: ' | '; nextPutAll: (SWACodeNode dotEscape: m name, '  (', m loc printString, ')'); nextPutAll: '\l'].
	stat isEmpty ifFalse: [
		ws nextPutAll: ' |'.   "blank separator compartment"
		stat do: [:m |
			ws nextPutAll: ' | '; nextPutAll: (SWACodeNode dotEscape: '$', m name, '  (', m loc printString, ')'); nextPutAll: '\l']].
	^ ws contents
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
